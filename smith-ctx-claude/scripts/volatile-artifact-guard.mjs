#!/usr/bin/env node
import { readFileSync, createReadStream } from "node:fs";
import { createInterface } from "node:readline";
import { homedir } from "node:os";

const WRITE_VERB = /(^|\s|\|)(>>?|cp|mv|tee|dd|install|rsync)\b|>>?\s*['"]?\S/;
const COMMAND_TOKEN_SEPARATORS = /[\s'";|&()<>]+/;

function volatileWritePathPrefixes() {
  const prefixes = ["/tmp/", "/private/tmp/", `${homedir()}/Downloads/`];
  const jobDir = process.env.CLAUDE_JOB_DIR;
  if (jobDir) prefixes.push(`${jobDir.replace(/\/+$/, "")}/tmp/`);
  return prefixes;
}

function volatileCommandPrefixes() {
  const prefixes = [
    ...volatileWritePathPrefixes(),
    "~/Downloads/",
    "$HOME/Downloads/",
    "${HOME}/Downloads/",
  ];
  if (process.env.CLAUDE_JOB_DIR) {
    prefixes.push("$CLAUDE_JOB_DIR/tmp/", "${CLAUDE_JOB_DIR}/tmp/");
  }
  return prefixes;
}

function startsWithAny(value, prefixes) {
  return prefixes.some((prefix) => value.startsWith(prefix));
}

function volatileTargetsInCommand(command, prefixes) {
  if (!WRITE_VERB.test(command)) return [];
  const targets = [];
  for (const token of command.split(COMMAND_TOKEN_SEPARATORS)) {
    if (token && startsWithAny(token, prefixes)) targets.push(token);
  }
  return targets;
}

function collectVolatileWrites(line, writePrefixes, commandPrefixes, found) {
  let event;
  try {
    event = JSON.parse(line);
  } catch {
    return;
  }
  const content = event && event.message && event.message.content;
  if (!Array.isArray(content)) return;
  for (const block of content) {
    if (!block || block.type !== "tool_use" || !block.input) continue;
    if (block.name === "Write" || block.name === "NotebookEdit") {
      const target = block.input.file_path || block.input.notebook_path;
      if (typeof target === "string" && startsWithAny(target, writePrefixes)) {
        found.add(target);
      }
    } else if (block.name === "Bash" && typeof block.input.command === "string") {
      for (const target of volatileTargetsInCommand(block.input.command, commandPrefixes)) {
        found.add(target);
      }
    }
  }
}

function advisoryOutput(found) {
  return (
    JSON.stringify({
      systemMessage:
        `volatile-artifact-guard: this session wrote ${found.size} file(s) ` +
        `under volatile prefixes (/tmp, ~/Downloads, $CLAUDE_JOB_DIR/tmp): ` +
        `${[...found].join(", ")}. These are deleted without warning. Move ` +
        `anything durable to a persistent path, or run /smith-checkpoint, ` +
        `before you stop.`,
    }) + "\n"
  );
}

async function main() {
  let input;
  try {
    input = JSON.parse(readFileSync(0, "utf-8"));
  } catch {
    return;
  }
  const transcriptPath = input.transcript_path;
  if (typeof transcriptPath !== "string") return;

  const writePrefixes = volatileWritePathPrefixes();
  const commandPrefixes = volatileCommandPrefixes();
  const found = new Set();

  try {
    const lines = createInterface({
      input: createReadStream(transcriptPath, { encoding: "utf-8" }),
      crlfDelay: Infinity,
    });
    for await (const line of lines) {
      if (line.trim()) {
        collectVolatileWrites(line, writePrefixes, commandPrefixes, found);
      }
    }
  } catch {
    return;
  }

  if (found.size > 0) process.stdout.write(advisoryOutput(found));
}

main().catch(() => {});
