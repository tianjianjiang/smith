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

const SLASH_COMMENT_OR_BLOCK_CONTINUATION = /^(\/\/|\/\*|\*([\s/]|$))/;
const HASH_COMMENT_EXCEPT_SHEBANG = /^#(?!!)/;

const COMMENT_PATTERN_BY_EXTENSION = {
  ".js": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".mjs": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".cjs": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".ts": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".mts": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".cts": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".tsx": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".jsx": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".go": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".rs": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".c": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".h": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".cc": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".cpp": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".hpp": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".java": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".kt": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".swift": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".scala": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".py": HASH_COMMENT_EXCEPT_SHEBANG,
  ".sh": HASH_COMMENT_EXCEPT_SHEBANG,
  ".bash": HASH_COMMENT_EXCEPT_SHEBANG,
  ".zsh": HASH_COMMENT_EXCEPT_SHEBANG,
  ".rb": HASH_COMMENT_EXCEPT_SHEBANG,
};

const MACHINE_DIRECTIVE = /^(\/\/|#|\/\*|\*(?:[\s/]|$))\s*(?:eslint-disable|eslint-enable|prettier-ignore|SPDX|pragma|noqa|@ts-[a-z]+|istanbul ignore|c8 ignore|type:\s*ignore)\b/i;

const CONTENT_FIELD_BY_TOOL = {
  Write: "content",
  Edit: "new_string",
  NotebookEdit: "new_source",
};

const STANDARDS_REMINDER =
  "@smith-standards (Inline Comments section): NEVER add inline comments to code. " +
  "Code must be self-documenting through clear naming, structure, and extraction " +
  "of well-named functions. Allowed exceptions: config file value documentation (.env).";

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
  const field = CONTENT_FIELD_BY_TOOL[input.tool_name];
  return field ? input.tool_input?.[field] : undefined;
}

function targetExtension(input) {
  if (input.tool_name === "NotebookEdit") return ".py";
  const path = input.tool_input?.file_path;
  return typeof path === "string" ? extname(path).toLowerCase() : "";
}

function main() {
  let input;
  try {
    input = JSON.parse(readFileSync(0, "utf-8"));
  } catch {
    return;
  }
  if (!input || typeof input !== "object") return;

  const commentPattern = COMMENT_PATTERN_BY_EXTENSION[targetExtension(input)];
  if (!commentPattern) return;

  const content = addedContent(input);
  if (typeof content !== "string" || !content) return;

  let nonEmpty = 0;
  let commentLines = 0;
  for (const line of content.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    nonEmpty += 1;
    if (commentPattern.test(trimmed) && !MACHINE_DIRECTIVE.test(trimmed)) {
      commentLines += 1;
    }
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
