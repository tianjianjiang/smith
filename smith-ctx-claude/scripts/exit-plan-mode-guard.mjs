#!/usr/bin/env node
import { writeSync } from "node:fs";
import { readHookInput, blockWithError } from "../../smith-git/scripts/lib/hook-utils.mjs";
import {
  hasBlockType,
  isGenuineNewUserTurn,
  isLocalCommandEcho,
  readTranscriptTurns,
  toolUseNames,
  userTurnText,
} from "../../smith-git/scripts/lib/transcript-turns.mjs";
import { classify, isClassifierReentry } from "./lib/approval-classifier.mjs";

const MIN_ELABORATION_CHARS = 80;
const CLASSIFIER_SYSTEM_PROMPT = [
  "You classify one message from a software engineering chat session.",
  "The assistant has just presented a plan and is about to submit it for approval.",
  "Decide whether the message is the user approving that plan so the work can proceed as it stands.",
  "A message that adds instructions, asks a question, requests a change, or raises a doubt is not an approval,",
  "even when it opens with an affirmative word.",
  "A short go-ahead in any language is an approval.",
  "Answer with exactly one lowercase word and nothing else: approval, or elaboration.",
  'Examples: "go" -> approval; "ok" -> approval; "yes" -> approval; "lgtm" -> approval;',
  '"好" -> approval; "可以" -> approval; "go, but rename the file first" -> elaboration;',
  '"why not use a regex?" -> elaboration.',
].join(" ");

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

function isCurrentExitPlanModeCall(content, currentToolUseId) {
  if (!currentToolUseId || !Array.isArray(content)) return false;
  return content.some(
    (block) =>
      block &&
      block.type === "tool_use" &&
      block.name === "ExitPlanMode" &&
      block.id === currentToolUseId,
  );
}

async function scanTranscript(transcriptPath, currentToolUseId) {
  let elaborationFound = false;
  let pendingReset = false;
  let lastUserText = "";
  for await (const event of readTranscriptTurns(transcriptPath)) {
    if (!event || event.isSidechain === true) continue;

    if (pendingReset) {
      elaborationFound = false;
      pendingReset = false;
    }

    if (event.type === "user") {
      if (isGenuineNewUserTurn(event)) {
        elaborationFound = false;
        const text = userTurnText(event);
        if (text && !isLocalCommandEcho(text)) lastUserText = text;
      }
      continue;
    }
    if (event.type !== "assistant") continue;

    const content = event.message && event.message.content;
    if (toolUseNames(content).includes("ExitPlanMode")) {
      if (hasSubstantialText(content)) {
        elaborationFound = false;
      } else if (isCurrentExitPlanModeCall(content, currentToolUseId)) {
        continue;
      } else if (currentToolUseId) {
        elaborationFound = false;
      } else {
        pendingReset = true;
      }
      continue;
    }
    if (!hasBlockType(content, "tool_use") && hasSubstantialText(content)) {
      elaborationFound = true;
    }
  }
  return { elaborationFound, lastUserText };
}

function classifiedAsApproval(message) {
  const verdict = classify({
    hookName: "exit-plan-mode-guard",
    fallback: "the elaboration requirement",
    systemPrompt: CLASSIFIER_SYSTEM_PROMPT,
    input: message,
    labels: ["approval", "elaboration"],
  });
  return verdict === "approval";
}

function blockAndExit() {
  blockWithError(
    [
      "Blocked: ExitPlanMode was called with no prior turn of plain-text " +
        "elaboration since the last real user message or ExitPlanMode " +
        "attempt, and the last user message was not an approval. Send the " +
        "explanation as its own turn (text only, no tool call) first.",
      "Per smith-mode-plan-claude/SKILL.md §Explain Before ExitPlanMode: " +
        "deliver the explanation as plain text in its own turn first, " +
        "then call ExitPlanMode in a separate, later turn.",
    ].join(" "),
  );
}

async function main() {
  if (isClassifierReentry()) return;

  const input = readHookInput();
  if (!input || typeof input !== "object") return;

  const transcriptPath = input.transcript_path;
  if (typeof transcriptPath !== "string") return;

  const currentToolUseId = typeof input.tool_use_id === "string" ? input.tool_use_id : "";

  let scan;
  try {
    scan = await scanTranscript(transcriptPath, currentToolUseId);
  } catch (error) {
    if (!error || error.code !== "ENOENT") {
      writeSync(
        2,
        `exit-plan-mode-guard: unexpected error, allowing the call: ${error && error.message}\n`,
      );
    }
    return;
  }

  if (scan.elaborationFound) return;
  if (scan.lastUserText && classifiedAsApproval(scan.lastUserText)) return;
  blockAndExit();
}

main().catch(() => {});
