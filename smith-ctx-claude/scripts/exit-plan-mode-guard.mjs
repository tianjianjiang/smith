#!/usr/bin/env node
import { writeSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { readHookInput, blockWithError } from "../../smith-git/scripts/lib/hook-utils.mjs";
import {
  hasBlockType,
  isGenuineNewUserTurn,
  readTranscriptTurns,
  toolUseNames,
} from "../../smith-git/scripts/lib/transcript-turns.mjs";

const MIN_ELABORATION_CHARS = 80;
const CLASSIFIER_BIN = process.env.SMITH_APPROVAL_CLASSIFIER_BIN || "claude";
const CLASSIFIER_MODEL = process.env.SMITH_APPROVAL_CLASSIFIER_MODEL || "haiku";
const CLASSIFIER_TIMEOUT_MS = Number(process.env.SMITH_APPROVAL_CLASSIFIER_TIMEOUT_MS) || 30000;
const CLASSIFIER_REENTRY_ENV = "SMITH_APPROVAL_CLASSIFIER";
const CLASSIFIER_SYSTEM_PROMPT = [
  "You classify one message from a software engineering chat session.",
  "The assistant has just presented a plan and is about to submit it for approval.",
  "Decide whether the message is the user approving that plan so the work can proceed as it stands.",
  "A message that adds instructions, asks a question, requests a change, or raises a doubt is not an approval,",
  "even when it opens with an affirmative word.",
  "Answer with exactly one lowercase word and nothing else: approval, or elaboration.",
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

function userTurnText(event) {
  const content = event.message && event.message.content;
  if (typeof content === "string") return content.trim();
  if (!Array.isArray(content)) return "";
  return content
    .filter((block) => block && block.type === "text" && typeof block.text === "string")
    .map((block) => block.text)
    .join("\n")
    .trim();
}

function isLocalCommandEcho(text) {
  return text.startsWith("<local-command-stdout>") || text.startsWith("<command-name>");
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
  const result = spawnSync(
    CLASSIFIER_BIN,
    [
      "-p",
      "--model",
      CLASSIFIER_MODEL,
      "--system-prompt",
      CLASSIFIER_SYSTEM_PROMPT,
      "--strict-mcp-config",
      "--mcp-config",
      '{"mcpServers":{}}',
      "--setting-sources",
      "",
    ],
    {
      input: message,
      encoding: "utf8",
      cwd: tmpdir(),
      timeout: CLASSIFIER_TIMEOUT_MS,
      env: { ...process.env, [CLASSIFIER_REENTRY_ENV]: "1" },
    },
  );
  if (result.error || result.status !== 0 || typeof result.stdout !== "string") {
    writeSync(
      2,
      "exit-plan-mode-guard: approval classifier unavailable, falling back to the " +
        `elaboration requirement: ${(result.error && result.error.message) || `exit ${result.status}`}\n`,
    );
    return false;
  }
  return result.stdout.trim().toLowerCase() === "approval";
}

function blockAndExit() {
  blockWithError(
    [
      "Blocked: ExitPlanMode was called with no prior turn of plain-text " +
        "elaboration since the last real user message or ExitPlanMode " +
        "attempt, and the last user message was not an approval. Send the " +
        "explanation as its own turn (text only, no tool call) first.",
      "Per smith-plan-claude/SKILL.md §Explain Before ExitPlanMode: " +
        "deliver the explanation as plain text in its own turn first, " +
        "then call ExitPlanMode in a separate, later turn.",
    ].join(" "),
  );
}

async function main() {
  if (process.env[CLASSIFIER_REENTRY_ENV] === "1") return;

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
