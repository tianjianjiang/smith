#!/usr/bin/env node
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";

const REPOSITORY_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

const LOOSE_END = /loose[\s-]?ends?/i;
const SKILL_NAME = /\bsmith-[a-z]+(?:-[a-z]+)*\b/g;
const SKILL_WORD = /\bskills?\b/i;
const POINT_IN_TIME =
  /\b(status|dates?|timestamps?|pull requests?|PRs?|tickets?|point[- ]in[- ]time)\b/i;
const OBJECTION = /\b(should(n't| not| never)|must not|never|remove|why|don't|do not)\b/i;
const DECLARED_GAP = new RegExp(
  [
    "\\bunverified\\b|\\bunchecked\\b",
    "\\bnot (yet )?(checked|verified|traced|confirmed)\\b",
    "\\b(did not|didn't|have not|haven't) (check|verify|trace|confirm)",
    "\\b(shall|should) i (check|verify)\\b",
    "未驗證|未經驗證|未確認|未檢查|未查證",
    "(尚未|還沒|沒有)(驗證|檢查|確認|追查|查證|核對)",
    "(要不要|是否要|需不需要)我",
  ].join("|"),
  "i",
);
const ROUTER_MARKER = "Skill router";
const PEER_SESSION_OPENING = "Another Claude";

function boundInstant(flag, value) {
  const instant = Date.parse(value);
  if (Number.isNaN(instant)) throw new Error(`${flag} needs an ISO 8601 timestamp`);
  return instant;
}

function parseArguments(argv) {
  const options = {
    projectsDirectory: join(homedir(), ".claude", "projects"),
    since: null,
    until: null,
    sinceInstant: null,
    untilInstant: null,
  };
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (flag === "--projects-dir") {
      if (!value) throw new Error("--projects-dir needs a directory");
      options.projectsDirectory = value;
    } else if (flag === "--since") {
      options.sinceInstant = boundInstant(flag, value);
      options.since = value;
    } else if (flag === "--until") {
      options.untilInstant = boundInstant(flag, value);
      options.until = value;
    } else throw new Error("unknown argument; expected --projects-dir, --since or --until");
  }
  return options;
}

function directoryEntries(path) {
  try {
    return readdirSync(path).sort();
  } catch {
    return null;
  }
}

function entryKind(path) {
  try {
    return statSync(path).isDirectory() ? "directory" : "file";
  } catch {
    return "unreadable";
  }
}

function sessionFiles(projectsDirectory) {
  const files = [];
  let projectDirectories = 0;
  let unreadableEntries = 0;
  for (const name of readdirSync(projectsDirectory).sort()) {
    const directory = join(projectsDirectory, name);
    const kind = entryKind(directory);
    if (kind === "file") continue;
    const entries = kind === "directory" ? directoryEntries(directory) : null;
    if (entries === null) {
      unreadableEntries += 1;
      continue;
    }
    projectDirectories += 1;
    for (const entry of entries) {
      if (entry.endsWith(".jsonl")) files.push(join(directory, entry));
    }
  }
  return { files, projectDirectories, unreadableEntries };
}

function repositorySkills() {
  return new Set(
    readdirSync(REPOSITORY_ROOT).filter((name) => existsSync(join(REPOSITORY_ROOT, name, "SKILL.md"))),
  );
}

function messageContent(event) {
  return event.message && event.message.content;
}

function isHuman(event) {
  return Boolean(event.origin) && event.origin.kind === "human";
}

function opensWithMarkupOrSlash(content) {
  return content.startsWith("<") || content.startsWith("/");
}

function isOwnerTyped(event) {
  if (event.type !== "user" || event.isMeta || event.isSidechain) return false;
  const content = messageContent(event);
  if (typeof content !== "string") return false;
  if (opensWithMarkupOrSlash(content)) return false;
  if (isHuman(event)) return true;
  return (
    !event.origin &&
    event.promptSource === "sdk" &&
    event.entrypoint === "sdk-cli" &&
    !content.startsWith(PEER_SESSION_OPENING)
  );
}

function isQueuedCommand(event) {
  return event.type === "attachment" && Boolean(event.attachment) && event.attachment.type === "queued_command";
}

function ownerPromptQueuedDuringATurn(event) {
  if (!isQueuedCommand(event)) return null;
  const attachment = event.attachment;
  const prompt = attachment.prompt;
  const fromOwner = !attachment.origin || attachment.origin.kind === "human";
  const isOwnerPrompt =
    attachment.commandMode === "prompt" &&
    !attachment.isMeta &&
    fromOwner &&
    typeof prompt === "string" &&
    !opensWithMarkupOrSlash(prompt) &&
    !prompt.startsWith(PEER_SESSION_OPENING);
  return isOwnerPrompt ? prompt : null;
}

function assistantText(event) {
  const content = messageContent(event);
  if (!Array.isArray(content)) return "";
  return content
    .filter((block) => block && block.type === "text" && typeof block.text === "string")
    .map((block) => block.text)
    .join("\n");
}

function loadedSkills(event) {
  const content = messageContent(event);
  if (!Array.isArray(content)) return [];
  return content
    .filter((block) => block && block.type === "tool_use" && block.name === "Skill")
    .map((block) => block.input && block.input.skill)
    .filter((skill) => typeof skill === "string")
    .map((skill) => skill.toLowerCase().split(":").pop());
}

function routerSuggestions(event) {
  const attachment = event.attachment;
  if (!attachment || attachment.type !== "hook_additional_context") return null;
  const content = Array.isArray(attachment.content)
    ? attachment.content.join("\n")
    : String(attachment.content || "");
  if (!content.includes(ROUTER_MARKER)) return null;
  return [...new Set(content.match(SKILL_NAME) || [])];
}

function newTally() {
  return { messages: 0, sessions: new Set() };
}

function record(tally, session) {
  tally.messages += 1;
  tally.sessions.add(session);
}

function summary(tally) {
  return { messages: tally.messages, sessions: tally.sessions.size };
}

function addSession(sessionsBySkill, skill, session) {
  if (!sessionsBySkill.has(skill)) sessionsBySkill.set(skill, new Set());
  sessionsBySkill.get(skill).add(session);
}

function isBounded(options) {
  return options.sinceInstant !== null || options.untilInstant !== null;
}

function withinWindow(instant, options) {
  if (!isBounded(options)) return true;
  if (Number.isNaN(instant)) return false;
  if (options.sinceInstant !== null && instant < options.sinceInstant) return false;
  if (options.untilInstant !== null && instant > options.untilInstant) return false;
  return true;
}

function userEventIndexesByText(events) {
  const indexesByText = new Map();
  events.forEach((event, index) => {
    if (!event || !isOwnerTyped(event)) return;
    const content = messageContent(event);
    if (!indexesByText.has(content)) indexesByText.set(content, []);
    indexesByText.get(content).push(index);
  });
  return indexesByText;
}

function claimLaterDelivery(indexesByText, prompt, queuedAt) {
  const indexes = indexesByText.get(prompt) || [];
  const position = indexes.findIndex((index) => index > queuedAt);
  if (position === -1) return false;
  indexes.splice(position, 1);
  return true;
}

function isHumanMessageWithBlockContent(event) {
  return !event.isMeta && Array.isArray(messageContent(event)) && isHuman(event);
}

function census(options) {
  const { files, projectDirectories, unreadableEntries } = sessionFiles(options.projectsDirectory);
  const knownSkills = repositorySkills();
  const distinctOwnerTypedMessages = new Set();
  const sessionsWithOwnerMessages = new Set();
  const looseEnd = newTally();
  const namesUnloadedSkill = newTally();
  const pointInTimeInSkill = newTally();
  const turnFinal = {
    followedByOwner: 0,
    declaredGap: 0,
    looseEndReplies: 0,
    looseEndRepliesAfterDeclaredGap: 0,
  };
  const router = {
    events: 0,
    eventsAfterOwnerTyped: 0,
    suggestionsOfLoadedSkill: 0,
    suggestions: 0,
  };
  const excluded = {
    unreadableEntries,
    unparsableLines: 0,
    eventsBeforeAnyTimestamp: 0,
    humanMessagesWithBlockContent: 0,
    humanMessagesOpeningWithMarkupOrSlash: 0,
    textMessagesFromOtherSources: 0,
    routerSuggestionsOfUnknownSkills: 0,
  };
  const suggestedSessions = new Map();
  const loadedSessions = new Map();
  let ownerTypedMessages = 0;
  let ownerTypedWhileATurnRan = 0;

  function recordOwnerMessage(content, file, loaded) {
    ownerTypedMessages += 1;
    distinctOwnerTypedMessages.add(content);
    sessionsWithOwnerMessages.add(file);
    const pointsAtLooseEnd = LOOSE_END.test(content);
    if (pointsAtLooseEnd) record(looseEnd, file);
    const namesUnloaded = (content.match(SKILL_NAME) || []).some((skill) => !loaded.has(skill));
    if (namesUnloaded) record(namesUnloadedSkill, file);
    if (SKILL_WORD.test(content) && POINT_IN_TIME.test(content) && OBJECTION.test(content)) {
      record(pointInTimeInSkill, file);
    }
    return pointsAtLooseEnd;
  }

  for (const file of files) {
    const loaded = new Set();
    let pendingAssistantText = "";
    let lastUserWasOwnerTyped = false;
    let latestInstant = Number.NaN;
    const events = [];
    for (const line of readFileSync(file, "utf-8").split("\n")) {
      if (!line) continue;
      try {
        events.push(JSON.parse(line));
      } catch {
        excluded.unparsableLines += 1;
      }
    }
    const undeliveredUserEvents = userEventIndexesByText(events);
    for (const [index, event] of events.entries()) {
      if (!event || event.isSidechain) continue;

      const eventInstant = Date.parse(event.timestamp);
      if (!Number.isNaN(eventInstant)) latestInstant = eventInstant;
      const counted = withinWindow(latestInstant, options);
      if (!counted && Number.isNaN(latestInstant)) excluded.eventsBeforeAnyTimestamp += 1;

      const suggested = routerSuggestions(event);
      if (suggested) {
        if (!counted) continue;
        router.events += 1;
        if (lastUserWasOwnerTyped) router.eventsAfterOwnerTyped += 1;
        for (const skill of suggested) {
          router.suggestions += 1;
          if (loaded.has(skill)) router.suggestionsOfLoadedSkill += 1;
          if (knownSkills.has(skill)) addSession(suggestedSessions, skill, file);
          else excluded.routerSuggestionsOfUnknownSkills += 1;
        }
        continue;
      }

      const queuedPrompt = ownerPromptQueuedDuringATurn(event);
      if (queuedPrompt !== null) {
        if (claimLaterDelivery(undeliveredUserEvents, queuedPrompt, index)) continue;
        lastUserWasOwnerTyped = true;
        pendingAssistantText = "";
        if (counted) {
          ownerTypedWhileATurnRan += 1;
          recordOwnerMessage(queuedPrompt, file, loaded);
        }
        continue;
      }
      if (isQueuedCommand(event)) {
        lastUserWasOwnerTyped = false;
        continue;
      }

      if (event.type === "assistant") {
        for (const skill of loadedSkills(event)) {
          loaded.add(skill);
          if (counted) addSession(loadedSessions, skill, file);
        }
        const text = assistantText(event);
        if (text) pendingAssistantText = text;
        continue;
      }

      if (event.type !== "user") continue;
      const content = messageContent(event);
      if (typeof content !== "string") {
        lastUserWasOwnerTyped = isHumanMessageWithBlockContent(event);
        if (lastUserWasOwnerTyped) {
          pendingAssistantText = "";
          if (counted) excluded.humanMessagesWithBlockContent += 1;
        }
        continue;
      }
      lastUserWasOwnerTyped = isOwnerTyped(event);
      if (!lastUserWasOwnerTyped) {
        if (!counted || event.isMeta) continue;
        if (isHuman(event) && opensWithMarkupOrSlash(content)) {
          excluded.humanMessagesOpeningWithMarkupOrSlash += 1;
        } else excluded.textMessagesFromOtherSources += 1;
        continue;
      }

      const answeredAssistantText = pendingAssistantText;
      pendingAssistantText = "";
      if (!counted) continue;

      const pointsAtLooseEnd = recordOwnerMessage(content, file, loaded);
      if (answeredAssistantText) {
        const declaredGap = DECLARED_GAP.test(answeredAssistantText);
        turnFinal.followedByOwner += 1;
        if (declaredGap) turnFinal.declaredGap += 1;
        if (pointsAtLooseEnd) turnFinal.looseEndReplies += 1;
        if (pointsAtLooseEnd && declaredGap) turnFinal.looseEndRepliesAfterDeclaredGap += 1;
      }
    }
  }

  const routerBySkill = {};
  for (const skill of [...suggestedSessions.keys()].sort()) {
    const sessions = suggestedSessions.get(skill);
    const loadedIn = loadedSessions.get(skill) || new Set();
    routerBySkill[skill] = {
      sessionsSuggested: sessions.size,
      ofThoseLoaded: [...sessions].filter((session) => loadedIn.has(session)).length,
    };
  }

  return {
    window: { since: options.since, until: options.until },
    projectDirectories,
    sessionFiles: files.length,
    sessionsWithOwnerMessages: sessionsWithOwnerMessages.size,
    ownerTypedMessages,
    ownerTypedWhileATurnRan,
    distinctOwnerTypedMessages: distinctOwnerTypedMessages.size,
    corrections: {
      looseEnd: summary(looseEnd),
      namesUnloadedSkill: summary(namesUnloadedSkill),
      pointInTimeInSkill: summary(pointInTimeInSkill),
    },
    turnFinal,
    router,
    routerBySkill,
    excluded,
  };
}

try {
  const result = census(parseArguments(process.argv.slice(2)));
  process.stdout.write(JSON.stringify(result, null, 2) + "\n");
} catch (error) {
  process.stderr.write(`correction-census: ${error.code || error.message}\n`);
  process.exit(1);
}
