#!/usr/bin/env node

import { readFileSync } from "node:fs";

const TOKEN_THRESHOLD = 5000;
const CHARS_PER_TOKEN = 4;

function readStdin() {
  try {
    return readFileSync(0, "utf-8");
  } catch {
    return "";
  }
}

function estimateTokens(text) {
  return Math.ceil(text.length / CHARS_PER_TOKEN);
}

function main() {
  const raw = readStdin();
  if (!raw.trim()) return;

  let hookData;
  try {
    hookData = JSON.parse(raw);
  } catch {
    return;
  }

  const toolResult = hookData?.tool_result;
  if (!toolResult || typeof toolResult !== "string") return;

  const estimatedTokens = estimateTokens(toolResult);

  if (estimatedTokens > TOKEN_THRESHOLD) {
    const reminder = `Tool output ~${estimatedTokens.toLocaleString()} tokens. ` +
      `Summarize key findings and reference file:line instead of keeping full output in context.`;

    const output = {
      hookSpecificOutput: {
        additionalContext: reminder
      }
    };

    console.log(JSON.stringify(output));
  }
}

main();
