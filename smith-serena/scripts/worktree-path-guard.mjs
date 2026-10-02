#!/usr/bin/env node
// worktree-path-guard.mjs - PreToolUse hook (Serena paths follow the session)
//
// Why: Serena started with --project-from-cwd fixes its project root at
// server start, and the claude-code context is single-project, so there is
// no activate_project. After a mid-session EnterWorktree the session works
// in <primary>/.claude/worktrees/<name>/ while Serena still joins every
// relative_path onto <primary>: an unprefixed replace_content silently edits
// the primary checkout. A worktree belongs to the SAME Serena project as its
// primary checkout, and it lies inside that project's root, so the path
// <prefix>/<file> reaches it without registering a second project.
//
// Contract: reads the PreToolUse hook JSON on stdin. Exit 2 blocks the call
// and names the corrected path on stderr; the model re-issues it. The input
// is not rewritten through updatedInput: the hooks documentation
// (https://code.claude.com/docs/en/hooks, retrieved 2026-09-28) does not
// state that it applies to MCP tools or how it merges when several hooks
// match one call, and a rewrite that is not applied would be the silent
// primary edit again. Any uncertainty -> exit 0: fail open.
//
// Acts when the session cwd and Serena's root lie in different checkouts of
// one repository (lib/serena-root.mjs). Left alone: memory tools (memories
// belong to the primary checkout), tools without a string path, a session
// whose cwd is in the checkout Serena is rooted in. find_symbol,
// replace_in_files and search_for_pattern work on the whole project when the
// path is absent, null or blank, so for them that counts as Serena's root.
//
// Reachable checkout (the session's checkout lies inside Serena's root): a
// path must point into it or into another linked worktree, and a glob must
// start with that checkout's prefix or with **/, because Serena anchors a
// glob at its root. A path outside the checkout Serena is rooted in cannot
// land in it, so it passes. The corrected path is the same file of the
// session's checkout: the prefix joined to the path relative to the top of
// Serena's checkout, which differs from Serena's root when that root is a
// subdirectory.
//
// Unreachable checkout: it lies outside Serena's root (a worktree elsewhere
// on disk, Serena rooted below the primary checkout or in another worktree,
// a session that returned to the primary checkout while Serena is rooted in
// a worktree), or a .gitignore file covers it. Serena 1.7.0 refuses a
// covered path in replace_in_files and leaves it out of symbol lookups
// (replace_content and the line-editing tools would still work), so the
// hook treats every write tool alike: blocked and sent to the built-in
// Edit/Write. Read tools pass with a note naming the checkout that the
// result describes.
//
// rename_symbol applies the language server's workspace edit without a path
// filter (serena/code_editor.py, Serena 1.7.0), and the language server
// indexes the primary checkout and its nested worktrees together. Whether a
// rename then edits another tree is not verified; allowed calls carry a
// warning.
import { isAbsolute, join, relative, resolve } from "node:path";
import {
  readHookInput,
  blockWithError,
} from "../../smith-git/scripts/lib/hook-utils.mjs";
import {
  SERENA_TOOL_PREFIX,
  SERENA_WRITE_TOOLS,
  canonicalPath,
  isInside,
  resolveCheckoutMismatch,
} from "../../smith-git/scripts/lib/serena-root.mjs";

const WHOLE_PROJECT_WHEN_PATH_EMPTY = new Set([
  "find_symbol",
  "replace_in_files",
  "search_for_pattern",
]);
const WORKSPACE_EDIT_TOOLS = new Set(["rename_symbol"]);
const GLOB_PARAMETERS = ["paths_include_glob", "paths_exclude_glob"];
const BUILT_IN_FALLBACK =
  "If Serena reports that the path does not exist, use the built-in Edit/Write with absolute paths inside the session's checkout.";

function allowWithContext(message) {
  process.stdout.write(
    `${JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: message,
      },
    })}\n`,
  );
}

function pathArgument(tool, toolInput) {
  const raw = toolInput.relative_path;
  if (typeof raw === "string") return raw.trim() === "" ? "" : raw;
  if (raw == null && WHOLE_PROJECT_WHEN_PATH_EMPTY.has(tool)) return "";
  return null;
}

function unprefixedGlobs(toolInput, prefix) {
  return GLOB_PARAMETERS.filter((name) => {
    const glob = toolInput[name];
    if (typeof glob !== "string") return false;
    const trimmed = glob.trim();
    return (
      trimmed !== "" &&
      !trimmed.startsWith("**/") &&
      !trimmed.startsWith(`${prefix}/`)
    );
  }).map((name) => `${name}="${join(prefix, toolInput[name].trim())}"`);
}

function main() {
  const input = readHookInput();
  if (!input || typeof input.tool_name !== "string") return;
  if (!SERENA_TOOL_PREFIX.test(input.tool_name)) return;

  const tool = input.tool_name.replace(SERENA_TOOL_PREFIX, "");
  const toolInput = input.tool_input || {};
  const requested = pathArgument(tool, toolInput);
  if (requested === null) return;

  const mismatch = resolveCheckoutMismatch(
    input.cwd,
    process.env.CLAUDE_PROJECT_DIR,
  );
  if (!mismatch) return;
  const { root, rootTop, sessionTop, prefix, otherWorktrees, reachable } =
    mismatch;
  const situation = `session works in checkout ${sessionTop}, but Serena is rooted at ${root}`;

  if (!reachable) {
    if (SERENA_WRITE_TOOLS.has(tool)) {
      blockWithError(
        `Blocked: ${situation} and cannot reliably reach that checkout (it lies outside Serena's root or a .gitignore file covers it). Use the built-in Edit/Write with absolute paths inside ${sessionTop}.`,
      );
    }
    allowWithContext(
      `worktree-path-guard: ${situation} and cannot reliably reach that checkout, so this result describes ${root}, not ${sessionTop}. Read files of ${sessionTop} with the built-in tools.`,
    );
    return;
  }

  const target = canonicalPath(
    isAbsolute(requested) ? requested : resolve(root, requested),
  );
  if (!isInside(rootTop, target)) return;

  const namedCheckout = [sessionTop, ...otherWorktrees].find((w) =>
    isInside(w, target),
  );
  if (!namedCheckout) {
    const corrected = join(prefix, relative(rootTop, target));
    blockWithError(
      `Blocked: ${situation}. Re-issue with relative_path="${corrected}". ${BUILT_IN_FALLBACK}`,
    );
  }

  const globs = unprefixedGlobs(toolInput, relative(root, namedCheckout));
  if (globs.length > 0) {
    blockWithError(
      `Blocked: ${situation}, and Serena matches globs against paths relative to its root. Re-issue with ${globs.join(" and ")}. ${BUILT_IN_FALLBACK}`,
    );
  }

  if (WORKSPACE_EDIT_TOOLS.has(tool)) {
    allowWithContext(
      `worktree-path-guard: ${tool} applies the language server's workspace edit without a path filter, and the language server indexes ${root} together with its nested worktrees. Afterwards run git status in the primary checkout and in every worktree to confirm only ${sessionTop} changed.`,
    );
  }
}

main();
