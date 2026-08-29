#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { UNWRAP_DEPTH_EXCEEDED, unwrappedCommandSegments } from "./lib/git-command-tokenizer.mjs";

const HELP_FLAGS = new Set(["--help", "-h", "-V", "--version"]);
const CODERABBIT_COMMANDS = new Set(["coderabbit", "cr"]);

function flagName(token) {
  if (token.startsWith("--") && token.includes("=")) return token.slice(0, token.indexOf("="));
  return token;
}

function isHelpInvocation(tokens) {
  return tokens.slice(1).some((token) => HELP_FLAGS.has(flagName(token)));
}

function hasAgentFlag(tokens) {
  return tokens.some((token) => flagName(token) === "--agent");
}

function isCodeRabbitReviewAgent(command) {
  const segments = unwrappedCommandSegments(command);
  if (segments[UNWRAP_DEPTH_EXCEEDED]) return false;
  for (const tokens of segments) {
    if (!CODERABBIT_COMMANDS.has(tokens[0])) continue;
    if (isHelpInvocation(tokens)) continue;
    if (tokens[1] !== "review") continue;
    if (!hasAgentFlag(tokens)) continue;
    return true;
  }
  return false;
}

function advisory() {
  return (
    "coderabbit-status-check: a `coderabbit review --agent` just ran. " +
    "BEFORE treating the output as a valid review, verify both: " +
    '(1) `"status":"review_completed"` is present, and ' +
    "(2) `reviewedFiles` is a non-empty array. " +
    'A rate-limit refusal (`"errorType":"rate_limit"`) exits 0 and prints ' +
    '`"findings":0`, which reads like a clean pass but is NOT a review. ' +
    "Likewise `\"status\":\"review_skipped\"` with `\"findings\":0` is not a " +
    "pass. See @smith-gh-pr \"CodeRabbit fails OPEN\"."
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
  if (input.tool_name !== "Bash") return;

  const command = input.tool_input && input.tool_input.command;
  if (typeof command !== "string") return;

  let matches;
  try {
    matches = isCodeRabbitReviewAgent(command);
  } catch {
    return;
  }
  if (!matches) return;

  const message = advisory();
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: message,
      },
      systemMessage: message,
    }) + "\n",
  );
}

main();
