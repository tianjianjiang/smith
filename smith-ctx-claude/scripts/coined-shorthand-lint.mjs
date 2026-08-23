#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const CONFIG_PATH = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "coined-shorthand-config.json",
);
const DEFAULT_CONFIG = { minDistinctTokens: 2, allowlist: [] };
const COINED_LABEL = /\b[A-Z][0-9]{1,2}\b/g;

function addedContent(input) {
  const toolInput = input.tool_input || {};
  if (input.tool_name === "Write") return toolInput.content;
  if (input.tool_name === "Edit") return toolInput.new_string;
  if (input.tool_name === "NotebookEdit") return toolInput.new_source;
  return undefined;
}

function loadConfig() {
  try {
    const config = JSON.parse(readFileSync(CONFIG_PATH, "utf-8"));
    return {
      minDistinctTokens: Number.isFinite(config.minDistinctTokens)
        ? config.minDistinctTokens
        : DEFAULT_CONFIG.minDistinctTokens,
      allowlist: Array.isArray(config.allowlist)
        ? config.allowlist
        : DEFAULT_CONFIG.allowlist,
    };
  } catch {
    return DEFAULT_CONFIG;
  }
}

function coinedLabels(content, allowlist) {
  const allowed = new Set(allowlist);
  const found = new Set();
  const matches = content.match(COINED_LABEL);
  if (matches) {
    for (const token of matches) if (!allowed.has(token)) found.add(token);
  }
  return [...found];
}

function reminder(tokens) {
  return (
    `coined-shorthand-lint: this edit introduces meaningless coined label(s) ` +
    `${tokens.join(", ")}. @smith-standards: replace internal index codes / ` +
    `coined shorthand with descriptive names (e.g. a fixture var 'T1' -> ` +
    `'write_to_tmp'). Add genuinely-standard tokens to the allowlist in ` +
    `coined-shorthand-config.json.`
  );
}

function main() {
  let input;
  try {
    input = JSON.parse(readFileSync(0, "utf-8"));
  } catch {
    return;
  }
  if (!input || typeof input !== "object") return;

  const content = addedContent(input);
  if (typeof content !== "string" || !content) return;

  const { minDistinctTokens, allowlist } = loadConfig();
  const tokens = coinedLabels(content, allowlist);
  if (tokens.length < minDistinctTokens) return;

  const message = reminder(tokens);
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
