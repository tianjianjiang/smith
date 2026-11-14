#!/usr/bin/env node
import { spawn, execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const RECORD_PATH = join(HERE, "records", "host-clear-reset.json");
const TURN_TIMEOUT_MS = Number(process.env.SMITH_LIVE_CONTEXT_RESET_TURN_TIMEOUT_MS ?? 120000);
const CLEAR_SETTLE_MS = Number(process.env.SMITH_LIVE_CONTEXT_RESET_CLEAR_SETTLE_MS ?? 15000);
const MODEL = process.env.SMITH_LIVE_CONTEXT_RESET_MODEL ?? "haiku";
const FILLER = Array.from({ length: 400 }, (_, index) => `filler${index}`).join(" ");

if (process.env.SMITH_LIVE_CONTEXT_RESET_EVAL !== "1") {
  console.log("SKIP: set SMITH_LIVE_CONTEXT_RESET_EVAL=1 to run the live host-sent /clear eval");
  process.exit(0);
}

function localIsoTimestamp(date = new Date()) {
  const offsetMinutes = -date.getTimezoneOffset();
  const sign = offsetMinutes >= 0 ? "+" : "-";
  const pad = (value) => String(Math.abs(value)).padStart(2, "0");
  const shifted = new Date(date.getTime() + offsetMinutes * 60000).toISOString().slice(0, 19);
  return `${shifted}${sign}${pad(Math.trunc(offsetMinutes / 60))}:${pad(offsetMinutes % 60)}`;
}

function userLine(text) {
  return `${JSON.stringify({ type: "user", message: { role: "user", content: [{ type: "text", text }] } })}\n`;
}

function totalInputTokens(usage = {}) {
  return (usage.input_tokens ?? 0) + (usage.cache_read_input_tokens ?? 0) + (usage.cache_creation_input_tokens ?? 0);
}

function startSession(workDir, hookLog) {
  const settings = JSON.stringify({
    hooks: { SessionStart: [{ hooks: [{ type: "command", command: `cat >> "${hookLog}"; echo >> "${hookLog}"` }] }] },
  });
  const child = spawn(
    "claude",
    ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
      "--model", MODEL, "--tools", "", "--setting-sources", "project", "--settings", settings],
    { cwd: workDir, stdio: ["pipe", "pipe", "pipe"] },
  );
  const messages = [];
  const waiters = [];
  let buffered = "";
  let stderrText = "";
  child.stderr.on("data", (chunk) => { stderrText += chunk; });
  child.stdout.on("data", (chunk) => {
    buffered += chunk;
    const lines = buffered.split("\n");
    buffered = lines.pop();
    for (const line of lines.filter(Boolean)) {
      let message;
      try { message = JSON.parse(line); } catch { continue; }
      messages.push(message);
      for (const waiter of [...waiters]) waiter(message);
    }
  });
  const nextResult = (timeoutMs) => new Promise((resolve) => {
    const timer = setTimeout(() => { waiters.splice(waiters.indexOf(onMessage), 1); resolve(null); }, timeoutMs);
    const onMessage = (message) => {
      if (message.type !== "result") return;
      clearTimeout(timer);
      waiters.splice(waiters.indexOf(onMessage), 1);
      resolve(message);
    };
    waiters.push(onMessage);
  });
  const send = (text) => child.stdin.write(userLine(text));
  const close = () => new Promise((resolve) => { child.on("close", resolve); child.stdin.end(); });
  return { messages, nextResult, send, close, stderr: () => stderrText };
}

async function runSession({ sendClear }) {
  const workDir = mkdtempSync(join(tmpdir(), "smith-host-clear-"));
  const hookLog = join(workDir, "session-start.jsonl");
  const nonce = `zq${randomBytes(6).toString("hex")}`;
  const session = startSession(workDir, hookLog);
  try {
    session.send(`Remember this code word: ${nonce}. Ignore the rest of this message. ${FILLER}`);
    const remembered = await session.nextResult(TURN_TIMEOUT_MS);
    if (!remembered) throw new Error(`no result for the first turn; stderr: ${session.stderr().slice(0, 500)}`);
    const messageCountBeforeClear = session.messages.length;
    let clearResult = null;
    if (sendClear) {
      session.send("/clear");
      clearResult = await session.nextResult(CLEAR_SETTLE_MS);
    }
    const messagesAfterClear = session.messages.slice(messageCountBeforeClear);
    session.send("What code word did I ask you to remember? If you do not know, reply exactly UNKNOWN.");
    const answered = await session.nextResult(TURN_TIMEOUT_MS);
    if (!answered) throw new Error(`no result for the question turn; stderr: ${session.stderr().slice(0, 500)}`);
    await session.close();
    const hookSources = existsSync(hookLog)
      ? readFileSync(hookLog, "utf8").split("\n").filter(Boolean).flatMap((line) => {
          try { return [JSON.parse(line).source]; } catch { return []; }
        })
      : [];
    return {
      recalled: String(answered.result ?? "").includes(nonce),
      questionInputTokens: totalInputTokens(answered.usage),
      sessionIdChanged: remembered.session_id !== answered.session_id,
      hookSources,
      clearProducedResult: clearResult !== null,
      messageTypesAfterClear: [...new Set(messagesAfterClear.map((message) => [message.type, message.subtype].filter(Boolean).join(":")))],
    };
  } finally {
    rmSync(workDir, { recursive: true, force: true });
  }
}

const control = await runSession({ sendClear: false });
const treatment = await runSession({ sendClear: true });
const checks = {
  controlRecallsCodeWord: control.recalled,
  clearedSessionDoesNotRecall: !treatment.recalled,
  sessionStartHookSawClear: treatment.hookSources.includes("clear"),
  clearedQuestionTurnReadsFewerInputTokens: treatment.questionInputTokens < control.questionInputTokens,
};
const record = {
  recordedAt: localIsoTimestamp(),
  claudeCodeVersion: execFileSync("claude", ["--version"], { encoding: "utf8" }).trim(),
  model: MODEL,
  checks,
  observations: {
    sessionIdChangedAfterClear: treatment.sessionIdChanged,
    clearProducedResultMessage: treatment.clearProducedResult,
    messageTypesAfterClear: treatment.messageTypesAfterClear,
    sessionStartSourcesControl: control.hookSources,
    sessionStartSourcesCleared: treatment.hookSources,
  },
};
writeFileSync(RECORD_PATH, `${JSON.stringify(record, null, 2)}\n`);
console.log(JSON.stringify(record, null, 2));
const failed = Object.entries(checks).filter(([, passed]) => !passed).map(([name]) => name);
if (failed.length > 0) {
  console.log(`FAIL: host-sent /clear eval: ${failed.join(", ")}`);
  process.exit(1);
}
console.log("PASS: host-sent /clear resets the context of a live stream-json session");
