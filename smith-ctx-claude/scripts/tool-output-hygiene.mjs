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

function extractOutputText(toolName, toolResponse) {
  if (toolResponse == null) return "";
  if (typeof toolResponse === "string") return toolResponse;
  if (toolName === "Bash") {
    const stdout = typeof toolResponse.stdout === "string" ? toolResponse.stdout : "";
    const stderr = typeof toolResponse.stderr === "string" ? toolResponse.stderr : "";
    return stdout + stderr;
  }
  try {
    return JSON.stringify(toolResponse);
  } catch {
    return "";
  }
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

  if (typeof hookData !== "object" || hookData === null) return;

  const outputText = extractOutputText(hookData.tool_name, hookData.tool_response);
  if (!outputText) return;

  const estimatedTokens = estimateTokens(outputText);

  if (estimatedTokens > TOKEN_THRESHOLD) {
    const reminder =
      `tool-output-hygiene: tool output ~${estimatedTokens.toLocaleString()} tokens. ` +
      "Summarize key findings and reference file:line instead of keeping full output in context.";

    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "PostToolUse",
          additionalContext: reminder,
        },
        systemMessage: reminder,
      }),
    );
  }
}

main();
