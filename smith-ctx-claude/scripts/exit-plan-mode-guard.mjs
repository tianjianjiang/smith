#!/usr/bin/env node
import { readFileSync, writeSync } from "node:fs";
import {
  hasBlockType,
  isGenuineNewUserTurn,
  readTranscriptEvents,
  toolUseNames,
} from "./lib/transcript-turns.mjs";

const MIN_ELABORATION_CHARS = 80;

function hasSubstantialText(content) {
  if (!Array.isArray(content)) return false;
  let total = 0;
  for (const block of content) {
    if (block && block.type === "text" && typeof block.text === "string") {
      total += block.text.trim().length;
    }
  }
  return total >= MIN_ELABORATION_CHARS;
}

async function priorElaborationFound(transcriptPath) {
  let found = false;
  let pendingReset = false;
  for await (const event of readTranscriptEvents(transcriptPath)) {
    if (!event || event.isSidechain === true) continue;

    if (pendingReset) {
      found = false;
      pendingReset = false;
    }

    if (event.type === "user") {
      if (isGenuineNewUserTurn(event)) found = false;
      continue;
    }

    const content = event.message && event.message.content;
    if (toolUseNames(content).includes("ExitPlanMode")) {
      if (hasSubstantialText(content)) {
        found = false;
      } else {
        pendingReset = true;
      }
      continue;
    }
    if (!hasBlockType(content, "tool_use") && hasSubstantialText(content)) {
      found = true;
    }
  }
  return found;
}

function blockAndExit() {
  writeSync(
    2,
    [
      "Blocked: ExitPlanMode was called with no prior turn of plain-text " +
        "elaboration since the last real user message or ExitPlanMode " +
        "attempt. Send the explanation as its own turn (text only, no tool " +
        "call) first.",
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

  const transcriptPath = input.transcript_path;
  if (typeof transcriptPath !== "string") return;

  let found;
  try {
    found = await priorElaborationFound(transcriptPath);
  } catch {
    return;
  }

  if (!found) blockAndExit();
}

main().catch(() => {});
