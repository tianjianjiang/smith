#!/usr/bin/env node
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { readHookInput } from "../../smith-git/scripts/lib/hook-utils.mjs";

const APPROVAL_REGEX =
  /^(go|yes|ok|y|proceed|continue|sure|yep|yeah|do it|好|可以|繼續|行|沒問題|開始|執行)(\s*(ahead|on|please|吧))?[!.。]*$/i;
const LENGTH_THRESHOLD = 20;

function classifyMessage(text) {
  if (!text || typeof text !== "string") return "unknown";
  const trimmed = text.trim();
  if (trimmed.length === 0) return "unknown";
  if (trimmed.length <= LENGTH_THRESHOLD && APPROVAL_REGEX.test(trimmed)) {
    return "approval";
  }
  return "elaboration";
}

function getStateFilePath() {
  const configDir = process.env.CLAUDE_CONFIG_DIR || `${process.env.HOME}/.claude`;
  return `${configDir}/state/exit-plan-mode-message-classification.json`;
}

function writeState(classification, messageText) {
  const statePath = getStateFilePath();
  const state = {
    timestamp: new Date().toISOString(),
    classification,
    message_preview: messageText.slice(0, 100),
  };
  try {
    mkdirSync(dirname(statePath), { recursive: true });
    writeFileSync(statePath, JSON.stringify(state, null, 2), "utf8");
  } catch (error) {
    process.stderr.write(
      `classify-user-message: failed to write state: ${error.message}\n`,
    );
  }
}

function main() {
  const input = readHookInput();
  if (!input || typeof input !== "object") return;
  const message = input.user_message;
  if (typeof message !== "string") return;
  const classification = classifyMessage(message);
  writeState(classification, message);
}

main();
