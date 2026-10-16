import { lstatSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { resolve } from "node:path";
import { readTranscriptTurns } from "../../../smith-git/scripts/lib/transcript-turns.mjs";
import { contentLeaves, normalizeText, previewIncludes } from "./write-payload.mjs";

const ABSOLUTE_PATH = /(?<![\w.~/-])(?:~\/|\/)[^\s`'"<>()[\]{}]+/g;
const TRAILING_PUNCTUATION = /[.,:;!?。、，：；）]+$/;
const MAX_PREVIEW_FILE_BYTES = 5 * 1024 * 1024;
const PREVIEW_LABEL = /preview|預覽|プレビュー/i;
const SHIP_OR_REVIEW_SKILLS = ["smith-ship", "smith-review"];

function blocksOfType(content, type) {
  return Array.isArray(content) ? content.filter((block) => block && block.type === type) : [];
}

function rawText(content) {
  return blocksOfType(content, "text")
    .map((block) => (typeof block.text === "string" ? block.text : ""))
    .join("\n");
}

function userText(content) {
  return (typeof content === "string" ? content : rawText(content)).trim();
}

function answersAskUserQuestion(content, askToolUseIds) {
  return blocksOfType(content, "tool_result").some(
    (block) => askToolUseIds.has(block.tool_use_id) && block.is_error !== true,
  );
}

function isUserReply(event, askToolUseIds) {
  if (event.isMeta === true || event.isCompactSummary === true || event.isVisibleInTranscriptOnly === true) {
    return false;
  }
  const content = event.message && event.message.content;
  if (blocksOfType(content, "tool_result").length > 0) {
    return answersAskUserQuestion(content, askToolUseIds);
  }
  return isHumanTurn(event);
}

function isHumanTurn(event) {
  return Boolean(event.origin) && event.origin.kind === "human";
}

function startsShipOrReview(event) {
  if (event.isSidechain === true) return false;
  if (event.type !== "user" || !isHumanTurn(event)) return false;
  const text = userText(event.message && event.message.content);
  return SHIP_OR_REVIEW_SKILLS.some((skill) => invokesSkillCommand(text, skill));
}

function invokesSkillCommand(text, skill) {
  return text.includes(`<command-name>/${skill}</command-name>`) || text.startsWith(`/${skill}`);
}

export function invokedShipOrReview(transcriptPath) {
  if (typeof transcriptPath !== "string") return false;
  let lines;
  try {
    lines = readFileSync(transcriptPath, "utf-8").split("\n");
  } catch {
    return false;
  }
  return lines.some((line) => {
    try {
      return startsShipOrReview(JSON.parse(line));
    } catch {
      return false;
    }
  });
}

function mentionedPaths(text) {
  return text
    .split("\n")
    .filter((line) => PREVIEW_LABEL.test(line))
    .flatMap((line) => line.match(ABSOLUTE_PATH) || [])
    .map((candidate) => {
      const path = candidate.replace(TRAILING_PUNCTUATION, "");
      return path.startsWith("~/") ? resolve(homedir(), path.slice(2)) : path;
    });
}

function readPreviewFile(path, cache) {
  if (cache.has(path)) return cache.get(path);
  let file = null;
  try {
    const stats = lstatSync(path);
    if (stats.isFile() && stats.size <= MAX_PREVIEW_FILE_BYTES) {
      const changedMs = Math.max(stats.mtimeMs, stats.ctimeMs);
      file = { text: normalizeText(readFileSync(path, "utf-8")), changedMs };
    }
  } catch {}
  cache.set(path, file);
  return file;
}

function messageTexts(message, cache, { answeredOnly }) {
  const files = message.paths.map((path) => readPreviewFile(path, cache)).filter(Boolean);
  const usableFiles = answeredOnly
    ? files.filter((file) => file.changedMs <= message.replyMs)
    : files;
  return [message.text, ...usableFiles.map((file) => file.text)];
}

function coversAll(messages, leaves, targets, cache, options) {
  const content = contentLeaves(leaves, targets);
  const views = messages.map((message) => messageTexts(message, cache, options));
  const holds = (view, leaf) => view.some((text) => previewIncludes(text, leaf));
  return leaves.every((leaf) =>
    views.some(
      (view) =>
        holds(view, leaf) &&
        (!targets.has(leaf) || content.length === 0 || content.some((part) => holds(view, part))),
    ),
  );
}

export async function previewState(transcriptPath, leaves, { targets }) {
  const askToolUseIds = new Set();
  const messages = [];
  let pending = [];
  for await (const event of readTranscriptTurns(transcriptPath)) {
    if (!event || event.isSidechain === true) continue;
    const content = event.message && event.message.content;
    if (event.type === "assistant") {
      for (const block of blocksOfType(content, "tool_use")) {
        if (block.name === "AskUserQuestion") askToolUseIds.add(block.id);
      }
      const text = rawText(content);
      if (!text.trim()) continue;
      const message = { text: normalizeText(text), paths: mentionedPaths(text), replyMs: null };
      messages.push(message);
      pending.push(message);
      continue;
    }
    if (event.type !== "user") continue;
    if (pending.length === 0 || !isUserReply(event, askToolUseIds)) continue;
    const replyMs = Date.parse(event.timestamp);
    if (!Number.isFinite(replyMs)) continue;
    for (const message of pending) message.replyMs = replyMs;
    pending = [];
  }
  const cache = new Map();
  const answered = messages.filter((message) => message.replyMs !== null);
  return {
    previewed: coversAll(messages, leaves, targets, cache, { answeredOnly: false }),
    replied: coversAll(answered, leaves, targets, cache, { answeredOnly: true }),
  };
}
