#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmdirSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SESSION_FOLDER = process.env.SMITH_PROBE_SESSION_FOLDER;
const MODEL = process.env.SMITH_LIVE_CONTEXT_RESET_MODEL ?? "haiku";
const TURN_TIMEOUT_MS = Number(process.env.SMITH_LIVE_CONTEXT_RESET_TURN_TIMEOUT_MS ?? 180000);
const CONTROL_WAIT_MS = Number(process.env.SMITH_LIVE_CONTEXT_RESET_CONTROL_WAIT_MS ?? 60000);
const CONFIG_FOLDER = process.env.CLAUDE_CONFIG_DIR ?? join(homedir(), ".claude");
const FLAGS_FOLDER = join(CONFIG_FOLDER, "plans");
const RECORD_PATH = join(HERE, "records", "auto-context-reset.json");
const ENFORCE_CLEAR = resolve(HERE, "..", "enforce-clear.sh");
const WRITE_RELOAD_FLAG = resolve(HERE, "..", "write-reload-flag.sh");
const BACKGROUNDED = /backgrounded · ([0-9a-f]+)/;
const DISPATCH_REASON = "a fresh background session then continues from the checkpoint";
const UNCHANGED_REASON = "Checkpoint this session, then /clear.";

if (process.env.SMITH_LIVE_CONTEXT_RESET_EVAL !== "1") {
  console.log("SKIP: set SMITH_LIVE_CONTEXT_RESET_EVAL=1 to run the live automatic context reset eval");
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
    return execFileSync("claude", args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], ...options });
  } catch (error) {
    return `${error.stdout ?? ""}${error.stderr ?? ""}`;
  }
}

function sleep(milliseconds) {
  return new Promise((resolveSleep) => setTimeout(resolveSleep, milliseconds));
}

async function waitFor(read, timeoutMilliseconds = TURN_TIMEOUT_MS) {
  const deadline = Date.now() + timeoutMilliseconds;
  while (Date.now() < deadline) {
    const value = read();
    if (value) return value;
    await sleep(1000);
  }
  return undefined;
}

function listedSessions() {
  try {
    return JSON.parse(claude(["agents", "--json", "--all"]));
  } catch {
    return [];
  }
}

function listedSession(shortId) {
  return listedSessions().find((session) => session.id === shortId);
}

function sessionNamedAfter(label, excludedIds) {
  return listedSessions().find((session) => (session.name ?? "").includes(label) && !excludedIds.includes(session.id));
}

function transcriptPath(sessionId) {
  const projects = join(CONFIG_FOLDER, "projects");
  for (const project of readdirSync(projects)) {
    const candidate = join(projects, project, `${sessionId}.jsonl`);
    if (existsSync(candidate)) return candidate;
  }
  return undefined;
}

function transcriptText(sessionId) {
  const path = sessionId ? transcriptPath(sessionId) : undefined;
  return path ? readFileSync(path, "utf8") : "";
}

function lastAssistantText(sessionId) {
  const texts = transcriptText(sessionId).split("\n").filter(Boolean).flatMap((line) => {
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

function flagLines(name) {
  try {
    return readFileSync(join(FLAGS_FOLDER, name), "utf8").split("\n");
  } catch {
    return [];
  }
}

function flagNames(prefix) {
  try {
    return readdirSync(FLAGS_FOLDER).filter((name) => name.startsWith(prefix));
  } catch {
    return [];
  }
}

function restoreFlagsLabelled(label) {
  return flagNames(".pending-memory-restore-").filter((name) => flagLines(name)[3] === label);
}

function removeFlagsOfTheProbe(labels, sessionIds) {
  const probeFlags = [
    ...labels.flatMap(restoreFlagsLabelled),
    ...flagNames(".pending-reload-").filter((name) => sessionIds.includes(flagLines(name)[1])),
  ];
  for (const name of probeFlags) rmSync(join(FLAGS_FOLDER, name), { force: true });
}

const attemptMarkersBeforeTheProbe = new Set(flagNames(".auto-reset-attempt-"));

function removeAttemptMarkersOfTheProbe() {
  const added = flagNames(".auto-reset-attempt-").filter((name) => !attemptMarkersBeforeTheProbe.has(name));
  for (const name of added) rmSync(join(FLAGS_FOLDER, name), { force: true });
}

function createMemoryFile(label, codeWord) {
  const memoriesFolder = join(SESSION_FOLDER, ".serena", "memories");
  const createdFolders = [join(SESSION_FOLDER, ".serena"), memoriesFolder].filter((folder) => !existsSync(folder));
  mkdirSync(memoriesFolder, { recursive: true });
  const memoryPath = join(memoriesFolder, `${label}.md`);
  writeFileSync(memoryPath, `# ${label}\n\nWhen you restore this checkpoint, report the code word ${codeWord}.\n`);
  return { memoryPath: realpathSync(memoryPath), createdFolders: createdFolders.map((folder) => realpathSync(folder)).reverse() };
}

function removeMemoryFile(memory) {
  if (!memory) return;
  rmSync(memory.memoryPath, { force: true });
  for (const folder of memory.createdFolders) {
    try {
      rmdirSync(folder);
    } catch {}
  }
}

function writeSettings(path, environment) {
  writeFileSync(path, `${JSON.stringify({
    env: environment,
    permissions: { allow: [`Bash(${WRITE_RELOAD_FLAG} *)`] },
    hooks: { Stop: [{ hooks: [{ type: "command", command: `'${ENFORCE_CLEAR.replaceAll("'", "'\\''")}'` }] }] },
  })}\n`);
}

function firstPrompt(conversationWord, label) {
  return [
    `Remember this code word: ${conversationWord}. Reply only with OK.`,
    "When you are told to checkpoint this session, do exactly one thing:",
    `run ${WRITE_RELOAD_FLAG} ${label} with the Bash tool, then reply DONE.`,
  ].join(" ");
}

function startFirstSession(settingsPath, conversationWord, label) {
  const started = claude(
    ["--bg", "--model", MODEL, "--permission-mode", "default", "--settings", settingsPath, "--", firstPrompt(conversationWord, label)],
    { cwd: SESSION_FOLDER },
  );
  return started.match(BACKGROUNDED)?.[1];
}

const scratchFolder = mkdtempSync(join(tmpdir(), "smith-auto-context-reset-"));
const dispatchSettingsPath = join(scratchFolder, "dispatch-settings.json");
const controlSettingsPath = join(scratchFolder, "control-settings.json");
const label = `zq_probe_${randomBytes(6).toString("hex")}`;
const controlLabel = `zq_probe_${randomBytes(6).toString("hex")}`;
const conversationWord = `zq${randomBytes(6).toString("hex")}`;
const checkpointWord = `zq${randomBytes(6).toString("hex")}`;
const controlConversationWord = `zq${randomBytes(6).toString("hex")}`;
writeSettings(dispatchSettingsPath, { CTX_CONTEXT_CRITICAL_PCT: "1" });
writeSettings(controlSettingsPath, { CTX_AUTO_RESET_DISPATCH: "0", CTX_CONTEXT_CRITICAL_PCT: "1" });

let memory;
let firstId;
let successorId;
let controlId;
let controlSuccessorId;
let checks = { firstSessionStarted: false };
let observations = {};
try {
  memory = createMemoryFile(label, checkpointWord);
  firstId = startFirstSession(dispatchSettingsPath, conversationWord, label);
  const successor = firstId ? await waitFor(() => sessionNamedAfter(label, [firstId])) : undefined;
  successorId = successor?.id;
  const answered = successor ? await waitFor(() => lastAssistantText(successor.sessionId).includes(checkpointWord)) : false;
  const answer = successor ? lastAssistantText(successor.sessionId) : "";
  const first = firstId ? listedSession(firstId) : undefined;
  const firstTranscript = transcriptText(first?.sessionId);

  controlId = startFirstSession(controlSettingsPath, controlConversationWord, controlLabel);
  const control = controlId ? await waitFor(() => {
    const session = listedSession(controlId);
    return session && /DONE/.test(lastAssistantText(session.sessionId)) ? session : undefined;
  }) : undefined;
  const controlSuccessor = await waitFor(() => sessionNamedAfter(controlLabel, [controlId]), CONTROL_WAIT_MS);
  controlSuccessorId = controlSuccessor?.id;
  const controlTranscript = transcriptText(control?.sessionId ?? listedSession(controlId)?.sessionId);

  checks = {
    firstSessionStarted: Boolean(firstId),
    blockReasonNamedTheBackgroundContinuation: firstTranscript.includes(DISPATCH_REASON),
    successorWithTheLabelInItsNameAppeared: Boolean(successorId),
    successorIsAnotherSession: Boolean(successorId) && successorId !== firstId,
    successorReportedTheCheckpointCodeWord: Boolean(answered) && answer.includes(checkpointWord),
    successorDoesNotKnowTheConversation: Boolean(successor) && !transcriptText(successor.sessionId).includes(conversationWord),
    dispatchConsumedTheRestoreFlag: restoreFlagsLabelled(label).length === 0,
    controlSessionStarted: Boolean(controlId),
    controlDispatchedNoSuccessor: Boolean(controlId) && !controlSuccessorId,
    controlBlockReasonUnchanged: controlTranscript.includes(UNCHANGED_REASON) && !controlTranscript.includes(DISPATCH_REASON),
  };
  observations = {
    successorNamePattern: successor?.name?.replaceAll(label, "«label»") ?? "not listed",
    firstSessionStateAfterDispatch: first?.state ?? "not listed",
    successorRunsInTheSameFolder: Boolean(successor) && successor.cwd === first?.cwd,
    firstSessionTranscriptAlsoHoldsTheUnchangedReason: firstTranscript.includes(UNCHANGED_REASON),
    controlSessionWroteARestoreFlag: restoreFlagsLabelled(controlLabel).length > 0,
    firstSessionLaunchFlagNames: launchFlagNames(firstId),
    successorLaunchFlagNames: launchFlagNames(successorId),
  };
} finally {
  const sessionIds = [firstId, successorId, controlId, controlSuccessorId]
    .map((shortId) => (shortId ? listedSession(shortId)?.sessionId : undefined))
    .filter(Boolean);
  removeSession(controlSuccessorId);
  removeSession(controlId);
  removeSession(successorId);
  removeSession(firstId);
  removeFlagsOfTheProbe([label, controlLabel], sessionIds);
  removeAttemptMarkersOfTheProbe();
  removeMemoryFile(memory);
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
  console.log(`FAIL: automatic context reset eval: ${failed.join(", ")}`);
  process.exit(1);
}
console.log("PASS: a session at the critical threshold checkpointed and a background successor restored the checkpoint");
