#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const HOST = process.env.SMITH_PROBE_SYNC_HOST;
const FOLDER = process.env.SMITH_PROBE_SYNC_FOLDER;
const ORCA = process.env.ORCA_CLI_COMMAND ?? "orca";
const ORCA_WORKTREE = process.env.SMITH_PROBE_ORCA_WORKTREE;
const T3_PROVIDER = process.env.SMITH_PROBE_T3_PROVIDER ?? "claudeAgent";
const T3_MODEL = process.env.SMITH_PROBE_T3_MODEL ?? "claude-haiku-5-5";
const COMMAND_LINE_MODEL = process.env.SMITH_LIVE_CONTEXT_RESET_MODEL ?? "haiku";
const SESSION_FILE_TIMEOUT_MS = Number(process.env.SMITH_PROBE_SESSION_FILE_TIMEOUT_MS ?? 90000);
const RECORD_PATH = join(HERE, "records", `chat-cli-sync.${HOST}.json`);

if (process.env.SMITH_LIVE_CONTEXT_RESET_EVAL !== "1") {
  console.log("SKIP: set SMITH_LIVE_CONTEXT_RESET_EVAL=1 to run the live chat and command-line sync eval");
  process.exit(0);
}
if (!["t3", "orca"].includes(HOST)) {
  console.log(`FAIL: SMITH_PROBE_SYNC_HOST must be t3 or orca, got '${HOST}'`);
  process.exit(1);
}
if (!FOLDER) {
  console.log("FAIL: set SMITH_PROBE_SYNC_FOLDER to the absolute folder the chat session runs in");
  process.exit(1);
}
if (HOST === "orca" && !ORCA_WORKTREE) {
  console.log("FAIL: orca mode needs SMITH_PROBE_ORCA_WORKTREE, an Orca workspace selector for that folder");
  process.exit(1);
}

function localIsoTimestamp(date = new Date()) {
  const offsetMinutes = -date.getTimezoneOffset();
  const sign = offsetMinutes >= 0 ? "+" : "-";
  const pad = (value) => String(Math.abs(value)).padStart(2, "0");
  const shifted = new Date(date.getTime() + offsetMinutes * 60000).toISOString().slice(0, 19);
  return `${shifted}${sign}${pad(Math.trunc(offsetMinutes / 60))}:${pad(offsetMinutes % 60)}`;
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function newCodeWord() {
  return `zq${randomBytes(6).toString("hex")}`;
}

function runJson(command, args, options = {}) {
  return JSON.parse(execFileSync(command, args, { encoding: "utf8", ...options }));
}

function sessionFolder() {
  const configFolder = process.env.CLAUDE_CONFIG_DIR ?? join(homedir(), ".claude");
  return join(configFolder, "projects", FOLDER.replace(/[^A-Za-z0-9]/g, "-"));
}

async function sessionIdHolding(codeWord, startedAtMs) {
  const folder = sessionFolder();
  const deadline = Date.now() + SESSION_FILE_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const match = existsSync(folder)
      ? readdirSync(folder)
          .filter((name) => name.endsWith(".jsonl"))
          .filter((name) => statSync(join(folder, name)).mtimeMs >= startedAtMs)
          .find((name) => readFileSync(join(folder, name), "utf8").includes(codeWord))
      : undefined;
    if (match) return match.slice(0, -".jsonl".length);
    await sleep(2000);
  }
  return null;
}

function commandLineTurn(sessionId, prompt) {
  return runJson("claude", ["-p", "--resume", sessionId, "--model", COMMAND_LINE_MODEL, "--output-format", "json", prompt], { cwd: FOLDER });
}

async function probeT3() {
  const [first, second, third] = [newCodeWord(), newCodeWord(), newCodeWord()];
  const startedAtMs = Date.now() - 1000;
  const started = runJson("t3", ["thread", "start", FOLDER, `Remember this code word: ${first}. Reply only with OK.`,
    "--title", "smith sync eval", "--provider", T3_PROVIDER, "--model", T3_MODEL, "--wait", "--json"]);
  const sessionId = await sessionIdHolding(first, startedAtMs);
  if (!sessionId) return { checks: { chatWroteNativeSessionFile: false }, observations: {} };
  const added = commandLineTurn(sessionId, `Tell me the code word you were asked to remember, then also remember this one: ${second}.`);
  const shown = runJson("t3", ["thread", "show", started.threadId, "--json"]).messages ?? [];
  const asked = runJson("t3", ["thread", "send", started.threadId,
    `What is the second code word you were asked to remember? If you do not know, reply exactly UNKNOWN. Then also remember this one: ${third}.`, "--wait", "--json"]);
  const listed = commandLineTurn(sessionId, "List every code word you were asked to remember in this conversation, separated by spaces. Nothing else.");
  return {
    checks: {
      chatWroteNativeSessionFile: true,
      commandLineResumedSameSession: added.session_id === sessionId,
    },
    observations: {
      commandLineKnowsChatTurn: String(added.result ?? "").includes(first),
      chatShowsCommandLineTurn: shown.some((message) => String(message.text ?? "").includes(second)),
      chatKnowsCommandLineTurn: String(asked.reply ?? "").includes(second),
      commandLineKnowsLaterChatTurn: String(listed.result ?? "").includes(third),
      commandLineTurnStillInConversationAfterChatTurn: String(listed.result ?? "").includes(second),
    },
  };
}

async function probeOrca() {
  const [first, second] = [newCodeWord(), newCodeWord()];
  const startedAtMs = Date.now() - 1000;
  const launched = runJson(ORCA, ["agent", "launch", "--agent", "claude", "--surface", "chat", "--model", COMMAND_LINE_MODEL,
    "--worktree", ORCA_WORKTREE, "--prompt", `Remember this code word: ${first}. Reply only with OK.`, "--json"]);
  const chatSessionId = launched.result?.outcome?.sessionId;
  const sessionId = await sessionIdHolding(first, startedAtMs);
  if (!sessionId) return { checks: { chatWroteNativeSessionFile: false }, observations: {} };
  const added = commandLineTurn(sessionId, `Tell me the code word you were asked to remember, then also remember this one: ${second}.`);
  const hits = runJson(ORCA, ["search", second, "--fresh", "--json"]).result?.hits ?? [];
  return {
    checks: {
      chatWroteNativeSessionFile: true,
      commandLineResumedSameSession: added.session_id === sessionId,
    },
    observations: {
      commandLineKnowsChatTurn: String(added.result ?? "").includes(first),
      searchIndexLinksCommandLineTurnToTheChat: hits.some((hit) => hit.sessionId === sessionId && hit.structuredSession?.sessionId === chatSessionId),
      chatSideOfTheTestIsManual: true,
    },
  };
}

const outcome = HOST === "t3" ? await probeT3() : await probeOrca();
const record = {
  recordedAt: localIsoTimestamp(),
  host: HOST,
  hostVersion: execFileSync(HOST === "t3" ? "t3" : ORCA, ["--version"], { encoding: "utf8" }).trim(),
  claudeCodeVersion: execFileSync("claude", ["--version"], { encoding: "utf8" }).trim(),
  ...outcome,
};
writeFileSync(RECORD_PATH, `${JSON.stringify(record, null, 2)}\n`);
console.log(JSON.stringify(record, null, 2));
const failed = Object.entries(outcome.checks).filter(([, passed]) => !passed).map(([name]) => name);
if (failed.length > 0) {
  console.log(`FAIL: chat and command-line sync eval (${HOST}): ${failed.join(", ")}`);
  process.exit(1);
}
console.log(`PASS: chat and command-line sync eval (${HOST}) ran; the observations record which directions carried over`);
