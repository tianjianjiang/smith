#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { readHookInput } from "../../smith-git/scripts/lib/hook-utils.mjs";

const CONFIG_PATH = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "gh-stack-config.json",
);
const DEFAULT_NATIVE_STACK_MARKERS = ["gh-stack"];
const SUBPROCESS_OPTIONS = {
  stdio: ["ignore", "pipe", "ignore"],
  encoding: "utf-8",
  timeout: 5000,
  killSignal: "SIGKILL",
};
const COMMAND_SEGMENT_SEPARATORS = /[;&|\n\r\f\v]+/;
const WHITESPACE = /\s+/;
const ENV_ASSIGNMENT = /^[A-Za-z_][A-Za-z0-9_]*=/;
const HAND_ROLLED_STACK_HINT = /--onto|pr\s+create/;

function stripSurroundingQuotes(token) {
  return token.replace(/^(['"])(.*)\1$/, "$2");
}

function withoutLeadingEnvAssignments(tokens) {
  let index = 0;
  while (index < tokens.length && ENV_ASSIGNMENT.test(tokens[index])) index += 1;
  return tokens.slice(index);
}

function commandSegments(command) {
  return command.split(COMMAND_SEGMENT_SEPARATORS).map((segment) =>
    withoutLeadingEnvAssignments(
      segment.trim().split(WHITESPACE).filter(Boolean).map(stripSurroundingQuotes),
    ),
  );
}

function rebasesOnto(tokens) {
  return (
    tokens[0] === "git" && tokens.includes("rebase") && tokens.includes("--onto")
  );
}

function stackedCreateBase(tokens) {
  if (tokens[0] !== "gh") return null;
  let createIndex = -1;
  for (let i = 1; i < tokens.length - 1; i += 1) {
    if (tokens[i] === "pr" && tokens[i + 1] === "create") {
      createIndex = i + 1;
      break;
    }
  }
  if (createIndex === -1) return null;
  for (let i = createIndex + 1; i < tokens.length; i += 1) {
    const token = tokens[i];
    if (token === "--base" || token === "-B") return tokens[i + 1] ?? "";
    if (token.startsWith("--base=")) return token.slice("--base=".length);
  }
  return null;
}

function defaultBranch(cwd) {
  const probes = [
    ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
    ["rev-parse", "--abbrev-ref", "origin/HEAD"],
  ];
  for (const args of probes) {
    try {
      const ref = execFileSync(
        "git",
        ["-C", cwd, ...args],
        SUBPROCESS_OPTIONS,
      ).trim();
      if (ref) return ref.replace(/^origin\//, "");
    } catch {
      continue;
    }
  }
  return "";
}

function handRollsStack(command, cwd) {
  let resolvedDefaultBranch;
  for (const tokens of commandSegments(command)) {
    if (rebasesOnto(tokens)) return true;
    const base = stackedCreateBase(tokens);
    if (base === null) continue;
    if (resolvedDefaultBranch === undefined) {
      resolvedDefaultBranch = defaultBranch(cwd);
    }
    if (resolvedDefaultBranch && base !== resolvedDefaultBranch) return true;
  }
  return false;
}

function nativeStackMarkers() {
  try {
    const config = JSON.parse(readFileSync(CONFIG_PATH, "utf-8"));
    const markers = config.nativeStackMarkers;
    return Array.isArray(markers) && markers.length
      ? markers
      : DEFAULT_NATIVE_STACK_MARKERS;
  } catch {
    return DEFAULT_NATIVE_STACK_MARKERS;
  }
}

function nativeStackInstalled(markers) {
  try {
    const listing = execFileSync("gh", ["extension", "list"], SUBPROCESS_OPTIONS);
    return markers.some((marker) => listing.includes(marker));
  } catch {
    return false;
  }
}

function reminder() {
  return (
    "gh-stack-guard: this command hand-builds a stacked pull " +
    "request (gh pr create with a non-default --base, or git rebase --onto), " +
    "but the gh stack extension (github/gh-stack) is installed. Prefer gh stack " +
    "(init / add / submit / push / sync / rebase / merge) over hand-rolling the " +
    "base-retarget and rebase cascade. Verify tools with `gh extension list`; do " +
    "not assume a native tool is absent. Per @smith-gh-pr Stacked PRs."
  );
}

function main() {
  const input = readHookInput();
  if (!input || typeof input !== "object") return;
  if (input.tool_name !== "Bash") return;

  const command = input.tool_input && input.tool_input.command;
  if (typeof command !== "string") return;
  if (!HAND_ROLLED_STACK_HINT.test(command)) return;

  const cwd = input.cwd || process.cwd();
  if (!handRollsStack(command, cwd)) return;
  if (!nativeStackInstalled(nativeStackMarkers())) return;

  const message = reminder();
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: message,
      },
      systemMessage: message,
    }) + "\n",
  );
}

main();
