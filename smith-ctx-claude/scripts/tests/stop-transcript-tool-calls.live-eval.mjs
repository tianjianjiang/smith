#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const MODEL = process.env.SMITH_LIVE_CONTEXT_RESET_MODEL ?? "haiku";
const TURN_TIMEOUT_MS = Number(process.env.SMITH_LIVE_CONTEXT_RESET_TURN_TIMEOUT_MS ?? 180000);
const SESSION_MODE = process.env.SMITH_PROBE_SESSION_MODE ?? "print";
const SESSION_FOLDER = process.env.SMITH_PROBE_SESSION_FOLDER;
const RECORD_PATH = join(HERE, "records", `stop-transcript-tool-calls.${SESSION_MODE}.json`);
const RUNS = Number(process.env.SMITH_PROBE_RUNS ?? 1);
const BACKGROUNDED = /backgrounded · ([0-9A-Za-z_-]+)/;
const HOOK_FIXTURE = join(HERE, "fixtures", "copy-transcript-on-stop.sh");

if (process.env.SMITH_LIVE_CONTEXT_RESET_EVAL !== "1") {
  console.log("SKIP: set SMITH_LIVE_CONTEXT_RESET_EVAL=1 to run the live Stop transcript eval");
  process.exit(0);
}
if (!["print", "background"].includes(SESSION_MODE)) {
  console.log("FAIL: SMITH_PROBE_SESSION_MODE is print or background");
  process.exit(1);
}
if (SESSION_MODE === "background" && !SESSION_FOLDER) {
  console.log("FAIL: set SMITH_PROBE_SESSION_FOLDER to a folder Claude Code already trusts");
  process.exit(1);
}

function localIsoTimestamp(date = new Date()) {
  const offsetMinutes = -date.getTimezoneOffset();
  const sign = offsetMinutes >= 0 ? "+" : "-";
  const pad = (value) => String(Math.abs(value)).padStart(2, "0");
  const shifted = new Date(date.getTime() + offsetMinutes * 60000).toISOString().slice(0, 19);
  return `${shifted}${sign}${pad(Math.trunc(offsetMinutes / 60))}:${pad(offsetMinutes % 60)}`;
}

function claude(args, options = {}) {
  try {
    return execFileSync("claude", args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], timeout: TURN_TIMEOUT_MS, ...options });
  } catch (error) {
    return `${error.stdout ?? ""}${error.stderr ?? ""}`;
  }
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitForFile(path) {
  const deadline = Date.now() + TURN_TIMEOUT_MS;
  while (Date.now() < deadline && !existsSync(path)) await sleep(1000);
}

function toolCalls(transcript) {
  return transcript.split("\n").filter(Boolean).flatMap((line) => {
    try {
      const entry = JSON.parse(line);
      if (entry.type !== "assistant" || !Array.isArray(entry.message?.content)) return [];
      return entry.message.content
        .filter((block) => block.type === "tool_use")
        .map((block) => ({ timestamp: entry.timestamp, input: JSON.stringify(block.input ?? {}) }));
    } catch {
      return [];
    }
  });
}

const quote = (text) => `'${text.replaceAll("'", "'\\''")}'`;

async function checksOfOneSession() {
  const scratchFolder = mkdtempSync(join(tmpdir(), "smith-stop-transcript-"));
  const copyPath = join(scratchFolder, "transcript-at-stop.jsonl");
  const settingsPath = join(scratchFolder, "settings.json");
  const firstWord = `zq${randomBytes(6).toString("hex")}`;
  const lastWord = `zq${randomBytes(6).toString("hex")}`;
  writeFileSync(settingsPath, `${JSON.stringify({
    hooks: { Stop: [{ hooks: [{ type: "command", command: [HOOK_FIXTURE, copyPath].map(quote).join(" ") }] }] },
  })}\n`);
  const sessionArguments = ["--model", MODEL, "--settings", settingsPath, "--allowedTools", "Bash(echo:*)", "--",
    `Run the shell command "echo ${firstWord}". After it returns, run the shell command "echo ${lastWord}" as a separate tool call. Then reply only with DONE.`];
  const startedAt = Date.now();
  if (SESSION_MODE === "background") {
    const backgroundId = claude(["--bg", ...sessionArguments], { cwd: SESSION_FOLDER }).match(BACKGROUNDED)?.[1];
    await waitForFile(copyPath);
    if (backgroundId) {
      claude(["stop", backgroundId]);
      claude(["rm", backgroundId]);
    }
  } else {
    claude(["-p", ...sessionArguments], { cwd: scratchFolder });
  }
  const copied = existsSync(copyPath);
  const calls = copied ? toolCalls(readFileSync(copyPath, "utf8")) : [];
  const instants = calls.map((call) => Date.parse(call.timestamp));
  const firstCall = calls.findIndex((call) => call.input.includes(firstWord));
  const lastCall = calls.findIndex((call) => call.input.includes(lastWord));
  return {
    stopHookCopiedTheTranscript: copied,
    transcriptAtStopHeldTheFirstToolCall: firstCall >= 0,
    transcriptAtStopHeldTheLastToolCall: lastCall >= 0,
    theTwoWordsCameInSeparateToolCallsInOrder: firstCall >= 0 && lastCall > firstCall,
    everyToolCallCarriesAnInstant: calls.length > 0 && instants.every((instant) => Number.isFinite(instant) && instant >= startedAt - 1000),
    toolCallInstantsAreInOrder: instants.every((instant, index) => index === 0 || instant >= instants[index - 1]),
    toolCallTimestampsEndInZ: calls.length > 0 && calls.every((call) => /Z$/.test(String(call.timestamp))),
  };
}

const sessions = [];
for (let run = 0; run < RUNS; run += 1) sessions.push(await checksOfOneSession());
const checks = Object.fromEntries(Object.keys(sessions[0]).map((name) => [name, sessions.every((session) => session[name])]));
const record = {
  recordedAt: localIsoTimestamp(),
  claudeCodeVersion: claude(["--version"]).trim(),
  model: MODEL,
  sessionMode: SESSION_MODE,
  sessions: RUNS,
  checks,
};
writeFileSync(RECORD_PATH, `${JSON.stringify(record, null, 2)}\n`);
console.log(JSON.stringify(record, null, 2));
const failed = Object.entries(checks).filter(([, passed]) => !passed).map(([name]) => name);
if (failed.length > 0) {
  console.log(`FAIL: Stop transcript eval: ${failed.join(", ")}`);
  process.exit(1);
}
console.log("PASS: the transcript a Stop hook reads holds every tool call of the turn, each with a timestamp");
