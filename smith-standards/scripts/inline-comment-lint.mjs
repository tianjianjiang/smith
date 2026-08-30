#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { extname } from "node:path";

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
  ".c": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".h": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".cc": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".cpp": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".hpp": SLASH_COMMENT_OR_BLOCK_CONTINUATION,
  ".py": HASH_COMMENT_EXCEPT_SHEBANG,
  ".sh": HASH_COMMENT_EXCEPT_SHEBANG,
  ".bash": HASH_COMMENT_EXCEPT_SHEBANG,
  ".zsh": HASH_COMMENT_EXCEPT_SHEBANG,
};

const CONTENT_FIELD_BY_TOOL = {
  Write: "content",
  Edit: "new_string",
  NotebookEdit: "new_source",
};

const STANDARDS_REMINDER =
  "@smith-standards (Inline Comments section): NEVER add inline comments to code. " +
  "Code must be self-documenting through clear naming, structure, and extraction " +
  "of well-named functions. Allowed exceptions: config file value documentation (.env).";

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

  let commentBlocks = 0;
  let inBlock = false;

  for (const line of content.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed) {
      inBlock = false;
      continue;
    }

    const isComment = commentPattern.test(trimmed);
    if (isComment && !inBlock) {
      commentBlocks += 1;
      inBlock = true;
    } else if (!isComment) {
      inBlock = false;
    }
  }

  if (commentBlocks === 0) return;

  const message =
    `inline-comment-lint: this edit adds ${commentBlocks} comment block(s). ` +
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
