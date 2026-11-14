#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ORCA = process.env.ORCA_CLI_COMMAND ?? "orca";
const TERMINAL = process.env.SMITH_PROBE_TERMINAL;
const RESET_VIA = process.env.SMITH_ORCA_RESET_VIA ?? "outside-send";
const ARM_FILE = process.env.SMITH_PROBE_ARM_FILE;
const TURN_TIMEOUT_MS = String(process.env.SMITH_LIVE_CONTEXT_RESET_TURN_TIMEOUT_MS ?? 120000);
const RECORD_LABEL = process.env.SMITH_PROBE_RECORD_LABEL;
const RECORD_PATH = join(HERE, "records", `orca-clear-reset.${RESET_VIA}${RECORD_LABEL ? `.${RECORD_LABEL}` : ""}.json`);

if (process.env.SMITH_LIVE_CONTEXT_RESET_EVAL !== "1") {
  console.log("SKIP: set SMITH_LIVE_CONTEXT_RESET_EVAL=1 to run the live Orca /clear eval");
  process.exit(0);
}
if (!TERMINAL) {
  console.log("FAIL: set SMITH_PROBE_TERMINAL to the Orca handle of a terminal running an idle interactive Claude Code");
  process.exit(1);
}
if (!["outside-send", "stop-hook"].includes(RESET_VIA)) {
  console.log(`FAIL: SMITH_ORCA_RESET_VIA must be outside-send or stop-hook, got '${RESET_VIA}'`);
  process.exit(1);
}
if (RESET_VIA === "stop-hook" && !ARM_FILE) {
  console.log("FAIL: stop-hook mode needs SMITH_PROBE_ARM_FILE, the same path the probed session was started with");
  process.exit(1);
}

function localIsoTimestamp(date = new Date()) {
  const offsetMinutes = -date.getTimezoneOffset();
  const sign = offsetMinutes >= 0 ? "+" : "-";
  const pad = (value) => String(Math.abs(value)).padStart(2, "0");
  const shifted = new Date(date.getTime() + offsetMinutes * 60000).toISOString().slice(0, 19);
  return `${shifted}${sign}${pad(Math.trunc(offsetMinutes / 60))}:${pad(offsetMinutes % 60)}`;
}

function orca(...args) {
  return JSON.parse(execFileSync(ORCA, [...args, "--json"], { encoding: "utf8" }));
}

function sendPrompt(text) {
  const reply = orca("terminal", "send", "--terminal", TERMINAL, "--text", text, "--enter", "--wait-submit", "10");
  return reply.result?.send?.prompt?.stages ?? [];
}

function waitIdle() {
  return orca("terminal", "wait", "--terminal", TERMINAL, "--for", "tui-idle", "--timeout-ms", TURN_TIMEOUT_MS).result?.wait?.satisfied === true;
}

function screenText() {
  return (orca("terminal", "read", "--terminal", TERMINAL, "--screen").result?.terminal?.tail ?? []).join("\n");
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

const nonce = `zq${randomBytes(6).toString("hex")}`;
if (RESET_VIA === "stop-hook") writeFileSync(ARM_FILE, "armed\n");
sendPrompt(`Remember this code word: ${nonce}. Reply only with OK.`);
const firstTurnSettled = waitIdle();
let clearStages = [];
if (RESET_VIA === "outside-send") {
  clearStages = sendPrompt("/clear");
} else {
  await sleep(10000);
  const sentPath = `${ARM_FILE}.sent`;
  clearStages = existsSync(sentPath) ? JSON.parse(readFileSync(sentPath, "utf8")).result?.send?.prompt?.stages ?? [] : [];
}
const clearSettled = waitIdle();
const screenAfterClear = screenText();
sendPrompt("What code word did I ask you to remember? If you do not know, reply exactly UNKNOWN.");
const questionSettled = waitIdle();
const screenAfterQuestion = screenText();
const checks = {
  everyStepReachedIdle: firstTurnSettled && clearSettled && questionSettled,
  clearInputAccepted: clearStages.includes("input_accepted"),
  codeWordGoneFromScreenAfterClear: !screenAfterClear.includes(nonce),
  answerDoesNotRecallCodeWord: !screenAfterQuestion.includes(nonce),
  answerIsUnknown: /⏺\s*UNKNOWN/.test(screenAfterQuestion),
};
const record = {
  recordedAt: localIsoTimestamp(),
  orcaVersion: execFileSync(ORCA, ["--version"], { encoding: "utf8" }).trim(),
  claudeCodeVersion: execFileSync("claude", ["--version"], { encoding: "utf8" }).trim(),
  resetVia: RESET_VIA,
  checks,
  observations: { clearReceiptStages: clearStages },
};
writeFileSync(RECORD_PATH, `${JSON.stringify(record, null, 2)}\n`);
console.log(JSON.stringify(record, null, 2));
const failed = Object.entries(checks).filter(([, passed]) => !passed).map(([name]) => name);
if (failed.length > 0) {
  console.log(`FAIL: Orca /clear eval (${RESET_VIA}): ${failed.join(", ")}`);
  process.exit(1);
}
console.log(`PASS: /clear sent through Orca (${RESET_VIA}) resets an interactive Claude Code session`);
