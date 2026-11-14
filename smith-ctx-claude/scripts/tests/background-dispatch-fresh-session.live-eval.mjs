#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SESSION_FOLDER = process.env.SMITH_PROBE_SESSION_FOLDER;
const MODEL = process.env.SMITH_LIVE_CONTEXT_RESET_MODEL ?? "haiku";
const TURN_TIMEOUT_MS = Number(process.env.SMITH_LIVE_CONTEXT_RESET_TURN_TIMEOUT_MS ?? 180000);
const CLAUDE_COMMAND_TIMEOUT_MS = Number(process.env.SMITH_LIVE_CONTEXT_RESET_COMMAND_TIMEOUT_MS ?? 60000);
const CONFIG_FOLDER = process.env.CLAUDE_CONFIG_DIR ?? join(homedir(), ".claude");
const RECORD_PATH = join(HERE, "records", "background-dispatch-fresh-session.json");
const HOOK_FIXTURE = join(HERE, "fixtures", "dispatch-background-session-on-stop.sh");
const BACKGROUNDED = /backgrounded · ([0-9A-Za-z_-]+)/;

if (process.env.SMITH_LIVE_CONTEXT_RESET_EVAL !== "1") {
  console.log("SKIP: set SMITH_LIVE_CONTEXT_RESET_EVAL=1 to run the live background dispatch eval");
  process.exit(0);
}
if (!SESSION_FOLDER) {
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
    return execFileSync("claude", args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], timeout: CLAUDE_COMMAND_TIMEOUT_MS, ...options });
  } catch (error) {
    return `${error.stdout ?? ""}${error.stderr ?? ""}`;
  }
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitFor(read) {
  const deadline = Date.now() + TURN_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const value = read();
    if (value) return value;
    await sleep(1000);
  }
  return undefined;
}

function listedSession(shortId) {
  try {
    return JSON.parse(claude(["agents", "--json", "--all"])).find((session) => session.id === shortId);
  } catch {
    return undefined;
  }
}

function transcriptPath(sessionId) {
  const projects = join(CONFIG_FOLDER, "projects");
  for (const project of readdirSync(projects)) {
    const candidate = join(projects, project, `${sessionId}.jsonl`);
    if (existsSync(candidate)) return candidate;
  }
  return undefined;
}

function lastAssistantText(sessionId) {
  const path = transcriptPath(sessionId);
  if (!path) return "";
  const texts = readFileSync(path, "utf8").split("\n").filter(Boolean).flatMap((line) => {
    try {
      const entry = JSON.parse(line);
      if (entry.type !== "assistant" || !Array.isArray(entry.message?.content)) return [];
      return entry.message.content.filter((block) => block.type === "text").map((block) => block.text);
    } catch {
      return [];
    }
  });
  return texts.at(-1) ?? "";
}

function jobState(shortId) {
  try {
    return JSON.parse(readFileSync(join(CONFIG_FOLDER, "jobs", shortId, "state.json"), "utf8"));
  } catch {
    return {};
  }
}

function launchFlagNames(shortId) {
  return shortId ? (jobState(shortId).respawnFlags ?? []).filter((flag) => flag.startsWith("--")) : [];
}

function removeSession(shortId) {
  if (!shortId) return;
  claude(["stop", shortId]);
  claude(["rm", shortId]);
}

const scratchFolder = mkdtempSync(join(tmpdir(), "smith-background-dispatch-"));
const armPath = join(scratchFolder, "armed");
const settingsPath = join(scratchFolder, "settings.json");
const promptPath = join(scratchFolder, "successor-prompt.txt");
const checkpointPath = join(scratchFolder, "checkpoint.txt");
const conversationWord = `zq${randomBytes(6).toString("hex")}`;
const checkpointWord = `zq${randomBytes(6).toString("hex")}`;
const quote = (text) => `'${text.replaceAll("'", "'\\''")}'`;
writeFileSync(checkpointPath, `The checkpoint code word is ${checkpointWord}.\n`);
writeFileSync(promptPath, [
  "Answer two questions.",
  "First: what code word were you asked to remember earlier in this conversation? If you were not asked, the answer is UNKNOWN.",
  `Second: read the file ${checkpointPath} and give the code word written in it.`,
  "Reply with exactly one line in the form: first=<answer> second=<answer>",
].join(" "));
writeFileSync(settingsPath, `${JSON.stringify({
  hooks: { Stop: [{ hooks: [{ type: "command", command: [HOOK_FIXTURE, armPath, MODEL, scratchFolder, promptPath].map(quote).join(" ") }] }] },
})}\n`);
writeFileSync(armPath, "armed\n");

let firstId;
let successorId;
let checks = { firstSessionStarted: false };
let observations = {};
try {
  const started = claude(
    ["--bg", "--model", MODEL, "--settings", settingsPath, `Remember this code word: ${conversationWord}. Reply only with OK.`],
    { cwd: SESSION_FOLDER, env: { ...process.env, SMITH_PROBE_PASSED_VARIABLE: "present" } },
  );
  firstId = started.match(BACKGROUNDED)?.[1];
  const hookReport = (await waitFor(() => (existsSync(`${armPath}.sent`) && BACKGROUNDED.test(readFileSync(`${armPath}.sent`, "utf8")) ? readFileSync(`${armPath}.sent`, "utf8") : undefined))) ?? (existsSync(`${armPath}.sent`) ? readFileSync(`${armPath}.sent`, "utf8") : "");
  successorId = hookReport.match(BACKGROUNDED)?.[1];
  const successor = successorId ? await waitFor(() => {
    const session = listedSession(successorId);
    return session && /first=.*second=/.test(lastAssistantText(session.sessionId)) ? session : undefined;
  }) : undefined;
  const answer = successor ? lastAssistantText(successor.sessionId) : "";
  const first = firstId ? listedSession(firstId) : undefined;
  checks = {
    firstSessionStarted: Boolean(firstId),
    stopHookDispatchedASession: Boolean(successorId),
    successorIsAnotherSession: Boolean(successorId) && successorId !== firstId,
    successorAnswered: answer.length > 0,
    successorDoesNotKnowTheConversation: /first=\s*UNKNOWN/.test(answer) && !answer.includes(conversationWord),
    successorReadTheCheckpoint: answer.includes(checkpointWord),
  };
  observations = {
    stopHookRanInABackgroundJob: /^job=set$/m.test(hookReport),
    variableOfTheStartingShellReachedTheHook: /^probe_variable=present$/m.test(hookReport),
    firstSessionStateAfterDispatch: first?.state ?? "not listed",
    successorRunsInTheSameFolder: Boolean(successor) && successor.cwd === first?.cwd,
    firstSessionLaunchFlagNames: launchFlagNames(firstId),
    successorLaunchFlagNames: launchFlagNames(successorId),
  };
} finally {
  removeSession(successorId);
  removeSession(firstId);
  rmSync(scratchFolder, { recursive: true, force: true });
}

const record = {
  recordedAt: localIsoTimestamp(),
  claudeCodeVersion: claude(["--version"]).trim(),
  model: MODEL,
  checks,
  observations,
};
writeFileSync(RECORD_PATH, `${JSON.stringify(record, null, 2)}\n`);
console.log(JSON.stringify(record, null, 2));
const failed = Object.entries(checks).filter(([, passed]) => !passed).map(([name]) => name);
if (failed.length > 0) {
  console.log(`FAIL: background dispatch eval: ${failed.join(", ")}`);
  process.exit(1);
}
console.log("PASS: a Stop hook of a background session dispatched a fresh session that read the checkpoint");
