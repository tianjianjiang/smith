#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const RECORD_PATH = join(HERE, "records", "t3-fresh-context.json");
const PROJECT = process.env.SMITH_PROBE_T3_PROJECT;
const PROVIDER = process.env.SMITH_PROBE_T3_PROVIDER ?? "claudeAgent";
const MODEL = process.env.SMITH_PROBE_T3_MODEL ?? "claude-haiku-5-5";
const SELF_SEND_SETTLE_MS = Number(process.env.SMITH_PROBE_T3_SELF_SEND_SETTLE_MS ?? 30000);
const QUESTION = "What code word did I ask you to remember? If you do not know, reply exactly UNKNOWN.";

if (process.env.SMITH_LIVE_CONTEXT_RESET_EVAL !== "1") {
  console.log("SKIP: set SMITH_LIVE_CONTEXT_RESET_EVAL=1 to run the live T3 Code fresh-context eval");
  process.exit(0);
}
if (!PROJECT) {
  console.log("FAIL: set SMITH_PROBE_T3_PROJECT to a T3 Code project id or a path inside a project");
  process.exit(1);
}

function localIsoTimestamp(date = new Date()) {
  const offsetMinutes = -date.getTimezoneOffset();
  const sign = offsetMinutes >= 0 ? "+" : "-";
  const pad = (value) => String(Math.abs(value)).padStart(2, "0");
  const shifted = new Date(date.getTime() + offsetMinutes * 60000).toISOString().slice(0, 19);
  return `${shifted}${sign}${pad(Math.trunc(offsetMinutes / 60))}:${pad(offsetMinutes % 60)}`;
}

function t3(...args) {
  return JSON.parse(execFileSync("t3", [...args, "--json"], { encoding: "utf8" }));
}

function newCodeWord() {
  return `zq${randomBytes(6).toString("hex")}`;
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

const firstWord = newCodeWord();
const started = t3("thread", "start", PROJECT, `Remember this code word: ${firstWord}. Reply only with OK.`,
  "--title", "smith fresh-context eval", "--provider", PROVIDER, "--model", MODEL, "--wait");
const thread = started.threadId;
const send = (message) => t3("thread", "send", thread, message, "--wait");
const control = send(QUESTION);
const clearRun = send("/clear");
const afterCommandLineClear = send(QUESTION);
const secondWord = newCodeWord();
const selfSend = send(
  `Remember this code word: ${secondWord}. Then call your t3_thread_send tool on this same thread with freshContext set to true and this exact message: ${QUESTION} If you have no such tool, reply exactly NO_TOOL.`,
);
await sleep(SELF_SEND_SETTLE_MS);
const messages = t3("thread", "show", thread).messages ?? [];
const lastUser = messages.findLast((message) => message.role === "user");
const lastAssistant = messages.findLast((message) => message.role === "assistant");
const checks = {
  controlRecallsCodeWord: String(control.reply ?? "").includes(firstWord),
  commandLineClearCompleted: clearRun.status === "completed",
  answerAfterCommandLineClearIsUnknown: String(afterCommandLineClear.reply ?? "").trim() === "UNKNOWN",
  agentHadTheSendTool: !String(selfSend.reply ?? "").includes("NO_TOOL"),
  selfSentQuestionArrivedAsNewTurn: lastUser?.text === QUESTION && lastUser?.runId !== selfSend.runId,
  answerAfterSelfSentFreshContextIsUnknown: String(lastAssistant?.text ?? "").trim() === "UNKNOWN",
};
const record = {
  recordedAt: localIsoTimestamp(),
  t3Version: execFileSync("t3", ["--version"], { encoding: "utf8" }).trim(),
  provider: PROVIDER,
  model: MODEL,
  checks,
};
writeFileSync(RECORD_PATH, `${JSON.stringify(record, null, 2)}\n`);
console.log(JSON.stringify(record, null, 2));
const failed = Object.entries(checks).filter(([, passed]) => !passed).map(([name]) => name);
if (failed.length > 0) {
  console.log(`FAIL: T3 Code fresh-context eval: ${failed.join(", ")}`);
  process.exit(1);
}
console.log("PASS: a T3 Code thread is reset by a command-line /clear and by the agent's own freshContext send");
