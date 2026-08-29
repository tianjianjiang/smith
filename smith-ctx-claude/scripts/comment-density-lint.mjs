#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve, extname } from "node:path";

const CONFIG_PATH = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "comment-lint-config.json",
);

const DEFAULT_CONFIG = { minCommentLines: 3, minCommentRatio: 0.25 };

const LINE_COMMENT_TOKEN_BY_EXTENSION = {
  ".js": "//",
  ".mjs": "//",
  ".cjs": "//",
  ".ts": "//",
  ".mts": "//",
  ".cts": "//",
  ".tsx": "//",
  ".jsx": "//",
  ".go": "//",
  ".rs": "//",
  ".c": "//",
  ".h": "//",
  ".cc": "//",
  ".cpp": "//",
  ".hpp": "//",
  ".java": "//",
  ".kt": "//",
  ".swift": "//",
  ".scala": "//",
  ".py": "#",
  ".sh": "#",
  ".bash": "#",
  ".zsh": "#",
  ".rb": "#",
};

const ALLOWLISTED_MARKER =
  /\b(TODO|FIXME|XXX|HACK|NOQA|noqa|SPDX|pragma)\b|eslint-disable|eslint-enable|prettier-ignore|@ts-[a-z]|type:\s|istanbul ignore|c8 ignore/;

const STANDARDS_REMINDER =
  "@smith-standards (SKILL.md:29-33): NEVER add inline comments to code. " +
  "Code must be self-documenting through clear naming, structure, and extraction " +
  "of well-named functions. Allowed exceptions: config file value documentation " +
  "(.env), standalone TODO markers on their own line.";

function loadConfig() {
  try {
    const config = JSON.parse(readFileSync(CONFIG_PATH, "utf-8"));
    return {
      minCommentLines: Number.isFinite(config.minCommentLines)
        ? config.minCommentLines
        : DEFAULT_CONFIG.minCommentLines,
      minCommentRatio: Number.isFinite(config.minCommentRatio)
        ? config.minCommentRatio
        : DEFAULT_CONFIG.minCommentRatio,
    };
  } catch {
    return DEFAULT_CONFIG;
  }
}

function addedContent(input) {
  const toolInput = input.tool_input || {};
  if (input.tool_name === "Write") return toolInput.content;
  if (input.tool_name === "Edit") return toolInput.new_string;
  if (input.tool_name === "NotebookEdit") return toolInput.new_source;
  return undefined;
}

function targetExtension(input) {
  const toolInput = input.tool_input || {};
  if (input.tool_name === "NotebookEdit") return ".py";
  const path = toolInput.file_path;
  return typeof path === "string" ? extname(path).toLowerCase() : "";
}

function isBlockCommentContinuation(trimmed) {
  return /^\*[\s/]/.test(trimmed) || trimmed === "*";
}

function isFullLineComment(trimmed, lineToken) {
  if (lineToken === "//") {
    return (
      trimmed.startsWith("//") ||
      trimmed.startsWith("/*") ||
      isBlockCommentContinuation(trimmed)
    );
  }
  return trimmed.startsWith("#") && !trimmed.startsWith("#!");
}

function isCommentBearing(line, lineToken) {
  const trimmed = line.trim();
  if (!trimmed) return false;
  if (trimmed.startsWith("#!")) return false;
  if (ALLOWLISTED_MARKER.test(trimmed)) return false;
  return isFullLineComment(trimmed, lineToken);
}

function main() {
  let input;
  try {
    input = JSON.parse(readFileSync(0, "utf-8"));
  } catch {
    return;
  }
  if (!input || typeof input !== "object") return;

  const lineToken = LINE_COMMENT_TOKEN_BY_EXTENSION[targetExtension(input)];
  if (!lineToken) return;

  const content = addedContent(input);
  if (typeof content !== "string" || !content) return;

  const lines = content.split("\n");
  let nonEmpty = 0;
  let commentLines = 0;
  for (const line of lines) {
    if (!line.trim()) continue;
    nonEmpty += 1;
    if (isCommentBearing(line, lineToken)) commentLines += 1;
  }

  const { minCommentLines, minCommentRatio } = loadConfig();
  const ratio = nonEmpty > 0 ? commentLines / nonEmpty : 0;
  if (commentLines < minCommentLines || ratio <= minCommentRatio) return;

  const message =
    `comment-density-lint: this edit adds ${commentLines} comment line(s) ` +
    `across ${nonEmpty} non-blank line(s) (${Math.round(ratio * 100)}%). ` +
    STANDARDS_REMINDER;

  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: message,
      },
      systemMessage: message,
    }) + "\n",
  );
}

main();
