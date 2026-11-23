#!/usr/bin/env node
import { execFileSync, execSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ORCA = process.env.ORCA_CLI_COMMAND ?? "orca";
const WORKTREE = process.env.SMITH_PROBE_ORCA_WORKTREE;
const SESSION_FOLDER = process.env.SMITH_PROBE_SESSION_FOLDER;
const CLAUDE_COMMAND = process.env.SMITH_PROBE_CLAUDE_COMMAND ?? "claude";
const MODEL = process.env.SMITH_LIVE_CONTEXT_RESET_MODEL ?? "haiku";
const PERMISSION_MODE = process.env.SMITH_PROBE_PERMISSION_MODE ?? "acceptEdits";
const TURN_TIMEOUT_MS = String(process.env.SMITH_LIVE_CONTEXT_RESET_TURN_TIMEOUT_MS ?? 120000);
const RECORD_NAME = process.env.SMITH_PROBE_RECORD_NAME ?? "default-launch";
const RECORD_PATH = join(HERE, "records", `orca-session-reset-conditions.${RECORD_NAME}.json`);
const HOOK_FIXTURE = join(HERE, "fixtures", "orca-report-hook-environment.sh");
const MODE_LABELS = ["accept edits on", "auto mode on", "plan mode on", "bypass permissions on"];
const HALF_TYPED_TEXT = "half typed words";

if (process.env.SMITH_LIVE_CONTEXT_RESET_EVAL !== "1") {
  console.log("SKIP: set SMITH_LIVE_CONTEXT_RESET_EVAL=1 to run the live Orca session reset conditions eval");
  process.exit(0);
}
if (!WORKTREE || !SESSION_FOLDER) {
  console.log("FAIL: set SMITH_PROBE_ORCA_WORKTREE (an Orca workspace selector) and SMITH_PROBE_SESSION_FOLDER (a folder Claude Code already trusts)");
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

function sendPrompt(terminal, text) {
  try {
    return orca("terminal", "send", "--terminal", terminal, "--text", text, "--enter", "--wait-submit", "10").result?.send?.prompt?.stages ?? [];
  } catch (error) {
    return [`refused: ${String(error.stdout ?? error.message).match(/"code"\s*:\s*"([^"]+)"/)?.[1] ?? "unknown"}`];
  }
}

function typeWithoutEnter(terminal, text) {
  orca("terminal", "send", "--terminal", terminal, "--text", text);
}

function waitIdle(terminal) {
  try {
    return orca("terminal", "wait", "--terminal", terminal, "--for", "tui-idle", "--timeout-ms", TURN_TIMEOUT_MS).result?.wait?.satisfied === true;
  } catch {
    return false;
  }
}

function screenText(terminal) {
  return (orca("terminal", "read", "--terminal", terminal, "--screen").result?.terminal?.tail ?? []).join("\n");
}

function permissionModeLabel(screen) {
  return MODE_LABELS.find((label) => screen.includes(label)) ?? "none shown";
}

function lineValue(text, key) {
  return text.split("\n").find((line) => line.startsWith(`${key}=`))?.slice(key.length + 1) ?? "";
}

function shellQuote(text) {
  return `'${text.replaceAll("'", "'\\''")}'`;
}

const scratchFolder = mkdtempSync(join(tmpdir(), "smith-orca-conditions-"));
const reportPath = join(scratchFolder, "hook-report.txt");
const settingsPath = join(scratchFolder, "settings.json");
writeFileSync(settingsPath, `${JSON.stringify({ hooks: { Stop: [{ hooks: [{ type: "command", command: shellQuote(HOOK_FIXTURE) }] }] } })}\n`);
const startCommand = [
  `cd ${shellQuote(SESSION_FOLDER)}`,
  `SMITH_PROBE_REPORT_FILE=${shellQuote(reportPath)} ${CLAUDE_COMMAND} --model ${shellQuote(MODEL)} --permission-mode ${shellQuote(PERMISSION_MODE)} --settings ${shellQuote(settingsPath)}`,
].join(" && ");
const terminal = orca("terminal", "create", "--worktree", WORKTREE, "--title", "smith probe: reset conditions", "--command", startCommand).result?.terminal?.handle;

let checks = { sessionStarted: false };
let observations = {};
try {
  const startedIdle = waitIdle(terminal);
  const firstNonce = `zq${randomBytes(6).toString("hex")}`;
  const firstStages = sendPrompt(terminal, `Remember this code word: ${firstNonce}. Reply only with OK.`);
  const firstTurnSettled = waitIdle(terminal);
  const hookReport = existsSync(reportPath) ? readFileSync(reportPath, "utf8") : "";
  const modeBeforeReset = permissionModeLabel(screenText(terminal));
  const clearStages = sendPrompt(terminal, "/clear");
  const clearSettled = waitIdle(terminal);
  const modeAfterReset = permissionModeLabel(screenText(terminal));
  const questionStages = sendPrompt(terminal, "What code word did I ask you to remember? If you do not know, reply exactly UNKNOWN.");
  const questionSettled = waitIdle(terminal);
  const screenAfterQuestion = screenText(terminal);

  const secondNonce = `zq${randomBytes(6).toString("hex")}`;
  sendPrompt(terminal, `Remember this code word: ${secondNonce}. Reply only with OK.`);
  const secondTurnSettled = waitIdle(terminal);
  typeWithoutEnter(terminal, HALF_TYPED_TEXT);
  const clearOverDraftStages = sendPrompt(terminal, "/clear");
  const clearOverDraftSettled = waitIdle(terminal);
  const screenAfterClearOverDraft = screenText(terminal);
  typeWithoutEnter(terminal, "\x15");
  sendPrompt(terminal, "What code word did I ask you to remember? If you do not know, reply exactly UNKNOWN.");
  const secondQuestionSettled = waitIdle(terminal);
  const screenAfterSecondQuestion = screenText(terminal);

  const hookVariableNames = lineValue(hookReport, "names").split(" ").filter(Boolean);
  checks = {
    sessionStarted: startedIdle && firstStages.includes("input_accepted"),
    everyStepReachedIdle: firstTurnSettled && clearSettled && questionSettled && secondTurnSettled && clearOverDraftSettled && secondQuestionSettled,
    stopHookReported: hookReport.length > 0,
    stopHookHandleIsTheSessionTerminal: lineValue(hookReport, "handle") === terminal,
    plainClearResetTheSession: clearStages.includes("input_accepted") && questionStages.includes("input_accepted")
      && /⏺\s*UNKNOWN/.test(screenAfterQuestion) && !screenAfterQuestion.includes(firstNonce),
    permissionModeUnchangedByReset: modeBeforeReset !== "none shown" && modeBeforeReset === modeAfterReset,
  };
  observations = {
    stopHookOrcaVariableNames: hookVariableNames,
    stopHookRanInABackgroundJob: lineValue(hookReport, "job") === "set",
    permissionModeBeforeReset: modeBeforeReset,
    permissionModeAfterReset: modeAfterReset,
    clearReceiptStages: clearStages,
    clearOverHalfTypedTextReceiptStages: clearOverDraftStages,
    clearOverHalfTypedTextResetTheSession: !screenAfterSecondQuestion.includes(secondNonce),
    halfTypedTextStillOnScreenAfterClear: screenAfterClearOverDraft.includes(HALF_TYPED_TEXT),
  };
} finally {
  if (terminal) orca("terminal", "close", "--terminal", terminal);
}

const record = {
  recordedAt: localIsoTimestamp(),
  orcaVersion: execFileSync(ORCA, ["--version"], { encoding: "utf8" }).trim(),
  claudeCodeVersion: execSync(`${CLAUDE_COMMAND} --version`, { encoding: "utf8" }).trim(),
  launch: RECORD_NAME,
  model: MODEL,
  requestedPermissionMode: PERMISSION_MODE,
  checks,
  observations,
};
writeFileSync(RECORD_PATH, `${JSON.stringify(record, null, 2)}\n`);
console.log(JSON.stringify(record, null, 2));
const failed = Object.entries(checks).filter(([, passed]) => !passed).map(([name]) => name);
if (failed.length > 0) {
  console.log(`FAIL: Orca session reset conditions eval (${RECORD_NAME}): ${failed.join(", ")}`);
  process.exit(1);
}
console.log(`PASS: Orca session reset conditions measured (${RECORD_NAME})`);
