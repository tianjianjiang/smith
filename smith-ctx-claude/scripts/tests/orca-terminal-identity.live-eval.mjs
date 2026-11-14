#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ORCA = process.env.ORCA_CLI_COMMAND ?? "orca";
const WORKTREE = process.env.SMITH_PROBE_ORCA_WORKTREE;
const SETTLE_TIMEOUT_MS = Number(process.env.SMITH_PROBE_ORCA_SETTLE_TIMEOUT_MS ?? 20000);
const RECORD_PATH = join(HERE, "records", "orca-terminal-identity.json");
const DONE_MARKER = "--- done";
const SHOW_MARKER = "--- show";
const HOOK_VARIABLES = ["ORCA_AGENT_HOOK_PORT", "ORCA_AGENT_HOOK_TOKEN", "ORCA_PANE_KEY"];

if (process.env.SMITH_LIVE_CONTEXT_RESET_EVAL !== "1") {
  console.log("SKIP: set SMITH_LIVE_CONTEXT_RESET_EVAL=1 to run the live Orca terminal identity eval");
  process.exit(0);
}
if (!WORKTREE) {
  console.log("FAIL: set SMITH_PROBE_ORCA_WORKTREE to an Orca workspace selector such as path:«folder»");
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

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function readWhenDone(path) {
  const deadline = Date.now() + SETTLE_TIMEOUT_MS;
  while (Date.now() < deadline) {
    if (existsSync(path)) {
      const text = readFileSync(path, "utf8");
      if (text.includes(DONE_MARKER)) return text;
    }
    await sleep(500);
  }
  return "";
}

function lineValue(text, key) {
  return text.split("\n").find((line) => line.startsWith(`${key}=`))?.slice(key.length + 1) ?? "";
}

function parseShowReply(text) {
  const body = text.slice(text.indexOf(SHOW_MARKER) + SHOW_MARKER.length, text.indexOf(DONE_MARKER));
  try {
    return JSON.parse(body);
  } catch {
    return {};
  }
}

const scratchFolder = mkdtempSync(join(tmpdir(), "smith-orca-identity-"));
const outputPath = join(scratchFolder, "terminal-report.txt");
const insideTerminal = [
  "{ echo \"names=$(env | grep '^ORCA_' | cut -d= -f1 | sort | tr '\\n' ' ')\"",
  "echo \"handle=$ORCA_TERMINAL_HANDLE\"",
  "echo \"tab=$ORCA_TAB_ID\"",
  "echo \"pane=$ORCA_PANE_KEY\"",
  `echo '${SHOW_MARKER}'`,
  `'${ORCA}' terminal show --json`,
  `echo '${DONE_MARKER}'; } > '${outputPath}' 2>&1`,
].join("; ");
const activeBefore = orca("terminal", "show").result?.terminal?.handle ?? "";
const created = orca("terminal", "create", "--worktree", WORKTREE, "--title", "smith probe: terminal identity", "--command", insideTerminal).result?.terminal ?? {};
const report = await readWhenDone(outputPath);
if (created.handle) orca("terminal", "close", "--terminal", created.handle);
rmSync(scratchFolder, { recursive: true, force: true });

const variableNames = lineValue(report, "names").split(" ").filter(Boolean);
const handleInTerminal = lineValue(report, "handle");
const tabInTerminal = lineValue(report, "tab");
const paneInTerminal = lineValue(report, "pane");
const handleFromBareShow = parseShowReply(report).result?.terminal?.handle ?? "";
const checks = {
  terminalReported: report.includes(DONE_MARKER),
  handleVariableIsTheCreatedHandle: Boolean(created.handle) && handleInTerminal === created.handle,
  tabVariableIsTheCreatedTab: Boolean(created.tabId) && tabInTerminal === created.tabId,
  paneKeyStartsWithTheTabId: Boolean(tabInTerminal) && paneInTerminal.startsWith(`${tabInTerminal}:`),
  hookVariablesPresent: HOOK_VARIABLES.every((name) => variableNames.includes(name)),
};
const record = {
  recordedAt: localIsoTimestamp(),
  orcaVersion: execFileSync(ORCA, ["--version"], { encoding: "utf8" }).trim(),
  checks,
  observations: {
    orcaVariableNames: variableNames,
    showWithoutHandleNamedTheCallingTerminal: handleFromBareShow === created.handle,
    showWithoutHandleNamedTheTerminalActiveBefore: Boolean(activeBefore) && handleFromBareShow === activeBefore,
    thisProcessHasTheHandleVariable: Boolean(process.env.ORCA_TERMINAL_HANDLE),
    thisProcessIsAClaudeCodeBackgroundJob: Boolean(process.env.CLAUDE_JOB_DIR),
  },
};
writeFileSync(RECORD_PATH, `${JSON.stringify(record, null, 2)}\n`);
console.log(JSON.stringify(record, null, 2));
const failed = Object.entries(checks).filter(([, passed]) => !passed).map(([name]) => name);
if (failed.length > 0) {
  console.log(`FAIL: Orca terminal identity eval: ${failed.join(", ")}`);
  process.exit(1);
}
console.log("PASS: a process in an Orca terminal reads its own handle from ORCA_TERMINAL_HANDLE");
