#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ORCA = process.env.ORCA_CLI_COMMAND ?? "orca";
const WORKTREE = process.env.SMITH_PROBE_ORCA_WORKTREE;
const SESSION_FOLDER = process.env.SMITH_PROBE_SESSION_FOLDER;
const START_TIMEOUT_MS = String(process.env.SMITH_PROBE_ORCA_SETTLE_TIMEOUT_MS ?? 25000);
const RECORD_PATH = join(HERE, "records", "orca-launch-variants.json");

if (process.env.SMITH_LIVE_CONTEXT_RESET_EVAL !== "1") {
  console.log("SKIP: set SMITH_LIVE_CONTEXT_RESET_EVAL=1 to run the live Orca launch variants eval");
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

function commandOutput(command, args) {
  try {
    return execFileSync(command, args, { encoding: "utf8" });
  } catch {
    return "";
  }
}

function shellQuote(text) {
  return `'${text.replaceAll("'", "'\\''")}'`;
}

function claudeProcessInTerminal(terminal) {
  const candidates = commandOutput("pgrep", ["-x", "claude"]).split("\n").filter(Boolean);
  return candidates.find((pid) => commandOutput("ps", ["eww", "-o", "command=", "-p", pid]).split(" ").includes(`ORCA_TERMINAL_HANDLE=${terminal}`));
}

function childProcessCount(pid) {
  return commandOutput("pgrep", ["-P", pid]).split("\n").filter(Boolean).length;
}

function observeLaunch(argumentText) {
  const terminal = orca("terminal", "create", "--worktree", WORKTREE, "--title", "smith probe: launch variant", "--command", `cd ${shellQuote(SESSION_FOLDER)} && claude ${argumentText}`.trim()).result?.terminal?.handle;
  try {
    try {
      orca("terminal", "wait", "--terminal", terminal, "--for", "tui-idle", "--timeout-ms", START_TIMEOUT_MS);
    } catch {
      return { processFound: false, hostsChildProcesses: false, showsSessionBanner: false };
    }
    const screen = (orca("terminal", "read", "--terminal", terminal, "--screen").result?.terminal?.tail ?? []).join("\n");
    const pid = claudeProcessInTerminal(terminal);
    return {
      processFound: Boolean(pid),
      hostsChildProcesses: Boolean(pid) && childProcessCount(pid) > 0,
      showsSessionBanner: screen.includes("Claude Code v"),
    };
  } finally {
    if (terminal) orca("terminal", "close", "--terminal", terminal);
  }
}

const scratchFolder = mkdtempSync(join(tmpdir(), "smith-orca-launch-"));
const emptySettingsPath = join(scratchFolder, "settings.json");
writeFileSync(emptySettingsPath, "{}\n");
const variants = {
  bare: "",
  model: "--model haiku",
  permissionMode: "--permission-mode acceptEdits",
  settings: `--settings ${shellQuote(emptySettingsPath)}`,
};
const launches = {};
for (const [name, argumentText] of Object.entries(variants)) launches[name] = observeLaunch(argumentText);

const withArguments = Object.entries(launches).filter(([name]) => name !== "bare").map(([, launch]) => launch);
const checks = {
  everyLaunchFoundItsProcess: Object.values(launches).every((launch) => launch.processFound),
  everyLaunchWithAnArgumentHostsItsSession: withArguments.every((launch) => launch.hostsChildProcesses && launch.showsSessionBanner),
};
const record = {
  recordedAt: localIsoTimestamp(),
  orcaVersion: execFileSync(ORCA, ["--version"], { encoding: "utf8" }).trim(),
  claudeCodeVersion: execFileSync("claude", ["--version"], { encoding: "utf8" }).trim(),
  checks,
  observations: {
    launches,
    bareLaunchHostsItsSession: launches.bare.hostsChildProcesses && launches.bare.showsSessionBanner,
  },
};
writeFileSync(RECORD_PATH, `${JSON.stringify(record, null, 2)}\n`);
console.log(JSON.stringify(record, null, 2));
const failed = Object.entries(checks).filter(([, passed]) => !passed).map(([name]) => name);
if (failed.length > 0) {
  console.log(`FAIL: Orca launch variants eval: ${failed.join(", ")}`);
  process.exit(1);
}
console.log("PASS: claude started with an argument hosts its session in the terminal's own process");
