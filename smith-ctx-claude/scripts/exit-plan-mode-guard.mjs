#!/usr/bin/env node
import { readFileSync, createReadStream, writeSync } from "node:fs";
import { createInterface } from "node:readline";

const MIN_ELABORATION_CHARS = 80;

function textLength(content) {
  if (!Array.isArray(content)) return 0;
  let total = 0;
  for (const block of content) {
    if (block && block.type === "text" && typeof block.text === "string") {
      total += block.text.trim().length;
    }
  }
  return total;
}

function hasToolUse(content) {
  return Array.isArray(content) && content.some((block) => block && block.type === "tool_use");
}

async function priorElaborationFound(transcriptPath) {
  let found = false;
  const lines = createInterface({
    input: createReadStream(transcriptPath, { encoding: "utf-8" }),
    crlfDelay: Infinity,
  });
  for await (const line of lines) {
    if (!line.trim()) continue;
    let event;
    try {
      event = JSON.parse(line);
    } catch {
      continue;
    }
    if (event && event.type === "user") {
      const blocks = event.message && event.message.content;
      const carriesToolResult =
        Array.isArray(blocks) && blocks.some((block) => block && block.type === "tool_result");
      if (!carriesToolResult) found = false;
      continue;
    }
    const content = event && event.message && event.message.content;
    if (!content) continue;
    if (!hasToolUse(content) && textLength(content) >= MIN_ELABORATION_CHARS) {
      found = true;
    }
  }
  return found;
}

function emitBlock(reason) {
  writeSync(
    2,
    [
      `Blocked: ExitPlanMode ${reason}`,
      "Per smith-plan-claude/SKILL.md §Explain Before ExitPlanMode: " +
        "deliver the explanation as plain text in its own turn first, " +
        "then call ExitPlanMode in a separate, later turn.",
    ].join(" ") + "\n",
  );
  process.exit(2);
}

async function main() {
  let input;
  try {
    input = JSON.parse(readFileSync(0, "utf-8"));
  } catch {
    return;
  }
  if (!input || typeof input !== "object") return;

  const lastMessage =
    typeof input.last_assistant_message === "string" ? input.last_assistant_message.trim() : "";
  if (lastMessage.length > 0) {
    emitBlock(
      "was called with explanatory text in the same message. The approval " +
        "modal hides text that shares a turn with the tool call.",
    );
    return;
  }

  const transcriptPath = input.transcript_path;
  if (typeof transcriptPath !== "string") return;

  let found;
  try {
    found = await priorElaborationFound(transcriptPath);
  } catch {
    return;
  }

  if (!found) {
    emitBlock(
      "was called with no prior turn of plain-text elaboration in this " +
        "exchange. Send the explanation as its own turn (text only, no " +
        "tool call) first.",
    );
  }
}

main().catch(() => {});
