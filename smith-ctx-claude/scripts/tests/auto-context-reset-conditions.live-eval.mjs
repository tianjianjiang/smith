#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const CHECKOUT_ROOT = realpathSync(resolve(HERE, "..", "..", ".."));
const HOOK_UNDER_TEST = realpathSync(resolve(HERE, "..", "enforce-clear.sh"));
const USER_CONFIG_FOLDER = join(homedir(), ".claude");
const RUNNER_CONFIG_FOLDER = resolve(process.env.CLAUDE_CONFIG_DIR ?? USER_CONFIG_FOLDER);
const EVAL_CONFIG_FOLDER = resolve(process.env.SMITH_EVAL_CONFIG_DIR ?? join(homedir(), ".claude-smith-eval"));
const PROBE_ROOT = join(EVAL_CONFIG_FOLDER, "probes");
const EVAL_SKILLS_LINK = join(EVAL_CONFIG_FOLDER, "skills");
const EVAL_SETTINGS_PATH = join(EVAL_CONFIG_FOLDER, "settings.json");
const EVAL_STATE_PATH = join(EVAL_CONFIG_FOLDER, ".claude.json");
const FLAGS_FOLDER = join(EVAL_CONFIG_FOLDER, "plans");
const RUNNER_FLAGS_FOLDER = join(RUNNER_CONFIG_FOLDER, "plans");
const REGISTERED_HOOK_PATH = join(EVAL_SKILLS_LINK, "smith-ctx-claude", "scripts", "enforce-clear.sh");
const RECORD_PATH = join(HERE, "records", "auto-context-reset-conditions.json");
const MODEL = process.env.SMITH_LIVE_CONTEXT_RESET_MODEL ?? "haiku";
const TURN_TIMEOUT_MS = Number(process.env.SMITH_LIVE_CONTEXT_RESET_TURN_TIMEOUT_MS ?? 900000);
const CLAUDE_COMMAND_TIMEOUT_MS = Number(process.env.SMITH_LIVE_CONTEXT_RESET_COMMAND_TIMEOUT_MS ?? 60000);
const QUIET_WAIT_MS = Number(process.env.SMITH_LIVE_CONTEXT_RESET_CONTROL_WAIT_MS ?? 60000);
const DISPATCH_STEP_NAME = "dispatch_successor_session";
const BACKGROUNDED = /backgrounded · ([0-9A-Za-z_-]+)/;
const DISPATCH_REASON = "a fresh background session then continues from the checkpoint";
const RESTORE_PROMPT = "This session continues an earlier session whose context was full";
const FAILED_DISPATCH_MESSAGE = "dispatching a background session for checkpoint";
const BACKGROUND_SESSIONS_SWITCH = "CLAUDE_CODE_DISABLE_AGENT_VIEW";
const FIRST_PROMPT = "Reply only with OK.";
const PENDING_RELOAD_NAME = /^\.pending-reload-([0-9a-f]+)$/;
const FLAG_PREFIXES = [".pending-reload-", ".pending-memory-restore-", ".auto-reset-attempt-", ".plan-state-"];
const VARIABLES_THE_EVAL_DOES_NOT_PASS_ON = [
  "CLAUDE_CONFIG_DIR", "CLAUDE_JOB_DIR", "ANTHROPIC_BASE_URL", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN",
  "AWS_BEARER_TOKEN_BEDROCK", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_PROFILE", "BASIC_MEMORY_MCP_PROJECT",
  "BASIC_MEMORY_CONFIG_DIR", "BASIC_MEMORY_HOME", "SERENA_HOME", BACKGROUND_SESSIONS_SWITCH,
  "CTX_AUTO_RESET_DISPATCH", "CTX_CONTEXT_CRITICAL_PCT",
];
const INSTALLED_COPY_REFERENCE = new RegExp(`(\\$HOME|\\$\\{HOME\\}|~|${homedir().replace(/[.*+?^${}()|[\]\\]/g, "\\$&")})/(\\.claude|\\.smith)/`);
const ONE_TIME_SETUP = `mkdir -p "${PROBE_ROOT}" && cd "${PROBE_ROOT}" && CLAUDE_CONFIG_DIR="${EVAL_CONFIG_FOLDER}" command claude, then /login, accept the folder trust prompt, and exit`;

if (process.env.SMITH_LIVE_CONTEXT_RESET_EVAL !== "1") {
  console.log("SKIP: set SMITH_LIVE_CONTEXT_RESET_EVAL=1 to run the live eval of the automatic context reset conditions");
  process.exit(0);
}

function localIsoTimestamp(date = new Date()) {
  const offsetMinutes = -date.getTimezoneOffset();
  const sign = offsetMinutes >= 0 ? "+" : "-";
  const pad = (value) => String(Math.abs(value)).padStart(2, "0");
  const shifted = new Date(date.getTime() + offsetMinutes * 60000).toISOString().slice(0, 19);
  return `${shifted}${sign}${pad(Math.trunc(offsetMinutes / 60))}:${pad(offsetMinutes % 60)}`;
}

function evalEnvironment() {
  const environment = { ...process.env };
  for (const name of VARIABLES_THE_EVAL_DOES_NOT_PASS_ON) delete environment[name];
  return { ...environment, CLAUDE_CONFIG_DIR: EVAL_CONFIG_FOLDER };
}

function run(command, args, options = {}) {
  try {
    return { ok: true, output: execFileSync(command, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], timeout: CLAUDE_COMMAND_TIMEOUT_MS, ...options }) };
  } catch (error) {
    return { ok: false, output: `${error.stdout ?? ""}${error.stderr ?? ""}` };
  }
}

function claude(args, options = {}) {
  return run("claude", args, { env: evalEnvironment(), ...options }).output;
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

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return undefined;
  }
}

function sameFolder(left, right) {
  try {
    return realpathSync(left) === realpathSync(right);
  } catch {
    return resolve(left) === resolve(right);
  }
}

function evalProfileLogin() {
  const status = (() => {
    try {
      return JSON.parse(claude(["auth", "status", "--json"]));
    } catch {
      return {};
    }
  })();
  return { loggedIn: status.loggedIn === true, configDirectory: status.configDirectory };
}

function probeRootIsTrusted() {
  const projects = readJson(EVAL_STATE_PATH)?.projects ?? {};
  return Object.entries(projects).some(([folder, state]) => sameFolder(folder, PROBE_ROOT) && state?.hasTrustDialogAccepted === true);
}

function pointTheEvalSkillsAtThisCheckout() {
  let existing;
  try {
    existing = lstatSync(EVAL_SKILLS_LINK);
  } catch {}
  if (existing && !existing.isSymbolicLink()) return false;
  if (existing) unlinkSync(EVAL_SKILLS_LINK);
  symlinkSync(CHECKOUT_ROOT, EVAL_SKILLS_LINK);
  return true;
}

function evalPermissionRule(rule) {
  return rule.split(`/${USER_CONFIG_FOLDER}/`).join(`/${EVAL_CONFIG_FOLDER}/`);
}

function writeTheEvalSettings(serenaHome) {
  const userPermissions = readJson(join(USER_CONFIG_FOLDER, "settings.json"))?.permissions ?? {};
  const settings = {
    hooks: { Stop: [{ hooks: [{ type: "command", command: REGISTERED_HOOK_PATH }] }] },
    permissions: {
      allow: (userPermissions.allow ?? []).map(evalPermissionRule).filter((rule) => !INSTALLED_COPY_REFERENCE.test(rule)),
      deny: (userPermissions.deny ?? []).map(evalPermissionRule),
    },
    env: { SERENA_HOME: serenaHome },
  };
  writeFileSync(EVAL_SETTINGS_PATH, `${JSON.stringify(settings, null, 2)}\n`);
}

function registeredStopHooks() {
  return (readJson(EVAL_SETTINGS_PATH)?.hooks?.Stop ?? []).flatMap((group) => group.hooks ?? []).map((hook) => hook.command ?? "");
}

function evalAllowRulesNameNoInstalledCopy() {
  return (readJson(EVAL_SETTINGS_PATH)?.permissions?.allow ?? []).every((rule) => !INSTALLED_COPY_REFERENCE.test(rule));
}

function stopHookIsThisCheckouts() {
  const registered = registeredStopHooks();
  if (registered.length !== 1 || !existsSync(registered[0])) return false;
  const path = realpathSync(registered[0]);
  return path === HOOK_UNDER_TEST && readFileSync(path, "utf8").includes(DISPATCH_STEP_NAME);
}

function flagNamesIn(folder, prefix) {
  try {
    return readdirSync(folder).filter((name) => name.startsWith(prefix));
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
}

function flagLinesIn(folder, name) {
  try {
    return readFileSync(join(folder, name), "utf8").split("\n");
  } catch {
    return [];
  }
}

function flagNames(prefix) {
  return flagNamesIn(FLAGS_FOLDER, prefix);
}

function flagLines(name) {
  return flagLinesIn(FLAGS_FOLDER, name);
}

function removeEveryEvalFlag() {
  for (const prefix of FLAG_PREFIXES) {
    for (const name of flagNames(prefix)) rmSync(join(FLAGS_FOLDER, name), { force: true });
  }
}

function runnerFlagsNaming(folder) {
  return FLAG_PREFIXES.flatMap((prefix) => flagNamesIn(RUNNER_FLAGS_FOLDER, prefix)
    .filter((name) => flagLinesIn(RUNNER_FLAGS_FOLDER, name).some((line) => line.includes(folder))));
}

function runnersFlagsNameNoProbe(folder) {
  try {
    return runnerFlagsNaming(folder).length === 0;
  } catch {
    return false;
  }
}

function restoreFlagsWrittenIn(folder) {
  return flagNames(".pending-memory-restore-").filter((name) => flagLines(name)[2] === folder);
}

function attemptMarkersListing(restoreFlagName) {
  return flagNames(".auto-reset-attempt-").filter((name) => flagLines(name).some((line) => line.endsWith(`/${restoreFlagName}`)));
}

function basicMemoryProjectNames() {
  const listed = run("basic-memory", ["project", "list", "--json", "--local"]);
  if (!listed.ok) return undefined;
  try {
    return (JSON.parse(listed.output).projects ?? []).map((project) => project.name);
  } catch {
    return undefined;
  }
}

let answeredSessionListings = 0;
let failedSessionListings = 0;

function listedSessions() {
  try {
    const sessions = JSON.parse(claude(["agents", "--json", "--all"]));
    if (!Array.isArray(sessions)) throw new TypeError("the session list is not an array");
    answeredSessionListings += 1;
    return sessions;
  } catch {
    failedSessionListings += 1;
    return [];
  }
}

function listedSession(shortId) {
  return listedSessions().find((session) => session.id === shortId);
}

function otherSessionsIn(folder, knownIds) {
  return listedSessions().filter((session) => session.cwd === folder && !knownIds.includes(session.id));
}

async function noOtherSessionIn(folder, knownIds) {
  const listingsAnsweredBefore = answeredSessionListings;
  const listingsFailedBefore = failedSessionListings;
  const found = await waitFor(() => otherSessionsIn(folder, knownIds)[0], QUIET_WAIT_MS);
  return { found, listRead: answeredSessionListings > listingsAnsweredBefore && failedSessionListings === listingsFailedBefore };
}

function sessionIsGone(shortId) {
  const listingsAnsweredBefore = answeredSessionListings;
  const listed = listedSession(shortId);
  return answeredSessionListings > listingsAnsweredBefore && !listed;
}

function transcriptText(sessionId) {
  if (!sessionId) return "";
  const projects = join(EVAL_CONFIG_FOLDER, "projects");
  try {
    for (const project of readdirSync(projects)) {
      const candidate = join(projects, project, `${sessionId}.jsonl`);
      if (existsSync(candidate)) return readFileSync(candidate, "utf8");
    }
  } catch {}
  return "";
}

function bashCommandsIn(transcript) {
  return transcript.split("\n").flatMap((line) => {
    try {
      const content = JSON.parse(line).message?.content;
      return Array.isArray(content) ? content.filter((part) => part.type === "tool_use" && part.name === "Bash").map((part) => part.input?.command ?? "") : [];
    } catch {
      return [];
    }
  });
}

function commandsReachingAnInstalledCopy(...transcripts) {
  return transcripts.flatMap(bashCommandsIn).filter((command) => INSTALLED_COPY_REFERENCE.test(command)).map((command) => command.slice(0, 200).split(homedir()).join("~"));
}

function launchFlagNames(shortId) {
  if (!shortId) return [];
  const state = readJson(join(EVAL_CONFIG_FOLDER, "jobs", shortId, "state.json"));
  return (state?.respawnFlags ?? []).filter((flag) => flag.startsWith("--")).map((flag) => flag.split("=")[0]);
}

function removeSession(shortId) {
  if (!shortId) return;
  claude(["stop", shortId]);
  claude(["rm", shortId]);
}

const cleanupProblems = [];

function attemptCleanupStep(description, step) {
  try {
    step();
  } catch (error) {
    cleanupProblems.push(`the cleanup could not ${description} (${error.message})`);
  }
}

function createRunFolder() {
  const folder = mkdtempSync(join(realpathSync(PROBE_ROOT), "zq-run-"));
  const serenaHome = join(folder, "serena-home");
  const basicMemoryFolder = join(folder, "basic-memory");
  mkdirSync(serenaHome);
  mkdirSync(basicMemoryFolder);
  return { folder, serenaHome, basicMemoryFolder, basicMemoryProject: `zq-eval-${randomUUID().slice(0, 8)}` };
}

function registerTheBasicMemoryProject(runFolder) {
  return run("basic-memory", ["project", "add", runFolder.basicMemoryProject, runFolder.basicMemoryFolder, "--local"]).ok
    && (basicMemoryProjectNames() ?? []).includes(runFolder.basicMemoryProject);
}

function writeProbeSettings(folder, runFolder, extraEnvironment) {
  writeFileSync(join(folder, ".claude", "settings.local.json"), `${JSON.stringify({
    env: { CTX_CONTEXT_CRITICAL_PCT: "1", ...extraEnvironment },
    basicMemory: { primaryProject: runFolder.basicMemoryProject },
  })}\n`);
}

function createProbeFolder(runFolder) {
  const folder = mkdtempSync(join(runFolder.folder, "zq-probe-"));
  mkdirSync(join(folder, ".claude"));
  writeProbeSettings(folder, runFolder, {});
  const created = run("uvx", ["-q", "--from", "git+https://github.com/oraios/serena", "serena", "project", "create", folder, "--name", basename(folder).replace(/-/g, "_"), "--language", "markdown"], {
    env: { ...evalEnvironment(), SERENA_HOME: runFolder.serenaHome },
    timeout: TURN_TIMEOUT_MS,
  });
  return { folder, serenaProjectCreated: created.ok && existsSync(join(folder, ".serena", "project.yml")) };
}

function serenaMemoriesIn(folder) {
  try {
    return readdirSync(join(folder, ".serena", "memories")).filter((name) => name.endsWith(".md"));
  } catch {
    return [];
  }
}

function startSession(folder) {
  const started = claude(["--bg", "--model", MODEL, "--permission-mode", "default", "--", FIRST_PROMPT], { cwd: folder });
  return started.match(BACKGROUNDED)?.[1];
}

function sessionIdsOf(shortIds) {
  return shortIds.map((shortId) => listedSession(shortId)?.sessionId).filter(Boolean);
}

function removeFlagsOfTheProbe(sessionIds, folder) {
  const probePendingReloads = flagNames(".pending-reload-").filter((name) => {
    const lines = flagLines(name);
    return sessionIds.includes(lines[1]) || lines[3] === folder;
  });
  const probeKeys = probePendingReloads.map((name) => name.match(PENDING_RELOAD_NAME)?.[1]).filter(Boolean);
  const probeRestoreFlags = restoreFlagsWrittenIn(folder);
  const probePlanStates = flagNames(".plan-state-").filter((name) => (flagLines(name)[1] ?? "").includes(basename(folder)));
  const probeFiles = [
    ...probePlanStates,
    ...probeRestoreFlags,
    ...probePendingReloads,
    ...probeKeys.map((key) => `.auto-reset-attempt-${key}`),
    ...probeRestoreFlags.flatMap(attemptMarkersListing),
  ];
  for (const name of probeFiles) rmSync(join(FLAGS_FOLDER, name), { force: true });
}

function noteTheSessionsLeftIn(folder) {
  const listingsAnsweredBefore = answeredSessionListings;
  const left = otherSessionsIn(folder, []);
  if (answeredSessionListings === listingsAnsweredBefore) cleanupProblems.push("the session list could not be read after the cleanup");
  else if (left.length > 0) cleanupProblems.push(`a session is still listed in a probe folder (${left.map((session) => session.id).join(", ")})`);
}

async function cleanUpTheProbe(folder, knownIds, quietWasObserved, sessionIdsNoLongerListed = []) {
  const unexpectedIds = otherSessionsIn(folder, knownIds).map((session) => session.id);
  if (unexpectedIds.length > 0) cleanupProblems.push(`a session that no check had seen was found in a probe folder at the cleanup (${unexpectedIds.join(", ")})`);
  const shortIds = [...knownIds, ...unexpectedIds];
  const sessionIds = [...sessionIdsOf(shortIds), ...sessionIdsNoLongerListed].filter(Boolean);
  for (const shortId of [...shortIds].reverse()) removeSession(shortId);
  if (!quietWasObserved) {
    const lateWatch = await noOtherSessionIn(folder, []);
    if (!lateWatch.found && !lateWatch.listRead) cleanupProblems.push("the session list could not be read while the cleanup watched for late sessions");
    if (lateWatch.found) {
      cleanupProblems.push(`a session appeared in a probe folder after the cleanup had stopped the others (${lateWatch.found.id})`);
      removeSession(lateWatch.found.id);
    }
  }
  attemptCleanupStep("remove the probe's flag files", () => removeFlagsOfTheProbe(sessionIds, folder));
  attemptCleanupStep("look for the sessions the probe left", () => noteTheSessionsLeftIn(folder));
}

async function measureTheHookFromTheUserSettings(runFolder) {
  const { folder, serenaProjectCreated } = createProbeFolder(runFolder);
  let firstId;
  let successorId;
  let successorSessionId;
  let quietWasObserved = false;
  try {
    firstId = serenaProjectCreated ? startSession(folder) : undefined;
    const successor = firstId ? await waitFor(() => otherSessionsIn(folder, [firstId])[0]) : undefined;
    successorId = successor?.id;
    successorSessionId = successor?.sessionId;
    const successorTranscript = successor
      ? (await waitFor(() => {
        const text = transcriptText(successor.sessionId);
        return text.includes(RESTORE_PROMPT) ? text : undefined;
      }, QUIET_WAIT_MS)) ?? transcriptText(successor.sessionId)
      : "";
    const successorLaunchFlagNames = launchFlagNames(successorId);
    const checkpointMemories = serenaMemoriesIn(folder);
    removeSession(successorId);
    const successorIsGone = Boolean(successor) && sessionIsGone(successorId);
    const afterTheSuccessor = successor ? await noOtherSessionIn(folder, [firstId, successorId]) : { found: undefined, listRead: false };
    quietWasObserved = afterTheSuccessor.listRead && !afterTheSuccessor.found;
    const first = firstId ? listedSession(firstId) : undefined;
    const firstTranscript = transcriptText(first?.sessionId);
    const installedCopyCommands = commandsReachingAnInstalledCopy(firstTranscript, successorTranscript);
    return {
      checks: {
        probeSerenaProjectWasCreated: serenaProjectCreated,
        firstSessionStarted: Boolean(firstId),
        firstSessionBlockReasonNamedTheContinuation: firstTranscript.includes(DISPATCH_REASON),
        checkpointWentToTheProbeSerenaProject: checkpointMemories.length > 0,
        successorAppeared: Boolean(successorId),
        successorWasStartedWithTheHooksRestorePrompt: successorTranscript.includes(RESTORE_PROMPT),
        bothSessionsAreListedInTheProbeFolder: first?.cwd === folder && successor?.cwd === folder,
        evalStoppedTheSuccessor: successorIsGone,
        sessionsRanNoCommandOnAnInstalledCopy: Boolean(firstTranscript) && Boolean(successorTranscript) && installedCopyCommands.length === 0,
      },
      observations: {
        commandsReachingAnInstalledCopy: installedCopyCommands,
        checkpointMemories,
        firstSessionLaunchFlagNames: launchFlagNames(firstId),
        successorLaunchFlagNames,
      },
    };
  } finally {
    await cleanUpTheProbe(folder, [firstId, successorId].filter(Boolean), quietWasObserved, [successorSessionId]);
  }
}

async function measureAFailedDispatch(runFolder) {
  const { folder, serenaProjectCreated } = createProbeFolder(runFolder);
  let firstId;
  let successorId;
  let quietWasObserved = false;
  try {
    firstId = serenaProjectCreated ? startSession(folder) : undefined;
    writeProbeSettings(folder, runFolder, { [BACKGROUND_SESSIONS_SWITCH]: "1" });
    const restoreFlags = firstId ? (await waitFor(() => {
      const found = restoreFlagsWrittenIn(folder);
      return found.length > 0 ? found : undefined;
    })) ?? [] : [];
    const markers = restoreFlags.length > 0 ? await waitFor(() => {
      const found = restoreFlags.flatMap(attemptMarkersListing);
      return found.length > 0 ? found : undefined;
    }, QUIET_WAIT_MS) : undefined;
    const quiet = restoreFlags.length > 0 ? await noOtherSessionIn(folder, [firstId]) : { found: undefined, listRead: false };
    successorId = quiet.found?.id;
    quietWasObserved = quiet.listRead && !quiet.found;
    const first = firstId ? listedSession(firstId) : undefined;
    const firstTranscript = transcriptText(first?.sessionId);
    const installedCopyCommands = commandsReachingAnInstalledCopy(firstTranscript);
    return {
      checks: {
        probeSerenaProjectWasCreated: serenaProjectCreated,
        firstSessionStarted: Boolean(firstId),
        firstSessionBlockReasonNamedTheContinuation: firstTranscript.includes(DISPATCH_REASON),
        checkpointWentToTheProbeSerenaProject: serenaMemoriesIn(folder).length > 0,
        firstSessionWroteItsCheckpointFlag: restoreFlags.length > 0,
        attemptWasRecorded: Boolean(markers),
        firstSessionIsListedInTheProbeFolder: first?.cwd === folder,
        noSuccessorAppeared: restoreFlags.length > 0 && quiet.listRead && !successorId,
        restoreFlagWasKept: restoreFlags.length > 0 && restoreFlags.every((name) => restoreFlagsWrittenIn(folder).includes(name)),
        hookReportedTheFailedDispatch: firstTranscript.includes(FAILED_DISPATCH_MESSAGE),
        reportNamedTheSwitchThatRefusedTheLaunch: firstTranscript.split("\n")
          .some((line) => line.includes(FAILED_DISPATCH_MESSAGE) && line.includes(BACKGROUND_SESSIONS_SWITCH)),
        sessionRanNoCommandOnAnInstalledCopy: Boolean(firstTranscript) && installedCopyCommands.length === 0,
      },
      observations: {
        commandsReachingAnInstalledCopy: installedCopyCommands,
        firstSessionStateAfterTheFailedDispatch: first?.state ?? "not listed",
      },
    };
  } finally {
    await cleanUpTheProbe(folder, [firstId, successorId].filter(Boolean), quietWasObserved);
  }
}

function failedNames(prefix, checks) {
  return Object.entries(checks ?? {}).filter(([, passed]) => !passed).map(([name]) => `${prefix}.${name}`);
}

const login = evalProfileLogin();
const environmentChecks = {
  evalFolderIsNotTheRunnersConfiguration: !sameFolder(EVAL_CONFIG_FOLDER, RUNNER_CONFIG_FOLDER) && !sameFolder(EVAL_CONFIG_FOLDER, USER_CONFIG_FOLDER),
  evalProfileIsLoggedIn: login.loggedIn,
  evalProfileUsesTheEvalFolder: Boolean(login.configDirectory) && sameFolder(login.configDirectory, EVAL_CONFIG_FOLDER),
  probeFolderIsTrustedInTheEvalProfile: probeRootIsTrusted(),
};
if (Object.values(environmentChecks).includes(false)) {
  console.log(JSON.stringify({ environmentChecks }, null, 2));
  console.log(`FAIL: the eval profile is not ready; set it up once: ${ONE_TIME_SETUP}`);
  process.exit(1);
}

const runFolder = createRunFolder();
let versionChecks = {};
let continuation;
let failedDispatch;
try {
  removeEveryEvalFlag();
  const skillsWereLinked = pointTheEvalSkillsAtThisCheckout();
  writeTheEvalSettings(runFolder.serenaHome);
  versionChecks = {
    evalSkillsAreThisCheckout: skillsWereLinked && sameFolder(EVAL_SKILLS_LINK, CHECKOUT_ROOT),
    evalStopHookIsThisCheckoutsAndHasTheDispatchStep: stopHookIsThisCheckouts(),
    evalAllowRulesNameNoInstalledCopy: evalAllowRulesNameNoInstalledCopy(),
    basicMemoryProjectWasRegistered: registerTheBasicMemoryProject(runFolder),
  };
  if (!Object.values(versionChecks).includes(false)) {
    continuation = await measureTheHookFromTheUserSettings(runFolder);
    failedDispatch = await measureAFailedDispatch(runFolder);
  }
} finally {
  attemptCleanupStep(`remove the Basic-Memory project ${runFolder.basicMemoryProject}`, () => {
    const removed = run("basic-memory", ["project", "remove", runFolder.basicMemoryProject, "--local"]);
    if (!removed.ok) throw new Error(removed.output.trim().split("\n")[0] || "no output");
  });
  attemptCleanupStep("remove the run folder", () => rmSync(runFolder.folder, { recursive: true, force: true }));
  for (const problem of cleanupProblems) {
    console.log(`WARN: ${problem}; the manual cleanup is in records/README.md, "Conditions of the automatic continuation"`);
  }
}

const basicMemoryProjectsAfter = basicMemoryProjectNames();
const isolationChecks = {
  runnersFlagsNameNoProbe: runnersFlagsNameNoProbe(runFolder.folder),
  basicMemoryProjectWasRemoved: Array.isArray(basicMemoryProjectsAfter) && !basicMemoryProjectsAfter.includes(runFolder.basicMemoryProject),
  cleanupFoundNoProblem: cleanupProblems.length === 0,
};
const record = {
  recordedAt: localIsoTimestamp(),
  claudeCodeVersion: claude(["--version"]).match(/^\d+\.\d+\.\d+.*/)?.[0] ?? "unknown",
  model: MODEL,
  serenaVersion: run("uvx", ["-q", "--from", "git+https://github.com/oraios/serena", "serena", "--version"], { timeout: TURN_TIMEOUT_MS }).output.trim().split("\n").pop() ?? "unknown",
  environment: { checks: environmentChecks },
  versionUnderTest: { checks: versionChecks },
  continuation,
  failedDispatch,
  isolation: { checks: isolationChecks },
};
writeFileSync(RECORD_PATH, `${JSON.stringify(record, null, 2)}\n`);
console.log(JSON.stringify(record, null, 2));
const failed = [
  ...failedNames("versionUnderTest", versionChecks),
  ...(continuation ? failedNames("continuation", continuation.checks) : ["continuation.notRun"]),
  ...(failedDispatch ? failedNames("failedDispatch", failedDispatch.checks) : ["failedDispatch.notRun"]),
  ...failedNames("isolation", isolationChecks),
];
if (failed.length > 0) {
  console.log(`FAIL: automatic context reset conditions eval: ${failed.join(", ")}`);
  process.exit(1);
}
console.log("PASS: this checkout's hook, registered in the eval profile's user settings, continued a session after its checkpoint, and a refused launch started nothing and kept the checkpoint");
