#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const CONFIG_PATH = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "review-orchestration-config.json",
);
const DEFAULT_ORCHESTRATED_PREFIXES = ["pr-review-toolkit:"];
const SUBAGENT_SPAWN_TOOLS = new Set(["Agent", "Task"]);

function orchestratedPrefixes() {
  try {
    const config = JSON.parse(readFileSync(CONFIG_PATH, "utf-8"));
    const prefixes = config.orchestratedSubagentPrefixes;
    return Array.isArray(prefixes) && prefixes.length
      ? prefixes
      : DEFAULT_ORCHESTRATED_PREFIXES;
  } catch {
    return DEFAULT_ORCHESTRATED_PREFIXES;
  }
}

function reminder(subagentType) {
  return (
    `review-orchestration-guard: you are spawning '${subagentType}' directly. ` +
    `Invoke its orchestrator instead - /review-pr (pr-review-toolkit), or ` +
    `/smith-review which marshals it - so the FULL applicable agent set runs. ` +
    `Hand-picking individual agents repeatedly misses some (silent-failure-hunter, ` +
    `pr-test-analyzer, comment-analyzer, ...). @smith-review step 2 runs the ` +
    `/review-pr multi-agent pass.`
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
  if (!SUBAGENT_SPAWN_TOOLS.has(input.tool_name)) return;

  const subagentType = input.tool_input && input.tool_input.subagent_type;
  if (typeof subagentType !== "string") return;
  if (!orchestratedPrefixes().some((prefix) => subagentType.startsWith(prefix))) {
    return;
  }

  const message = reminder(subagentType);
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
