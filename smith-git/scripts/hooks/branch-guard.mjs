#!/usr/bin/env node
// branch-guard.mjs - PreToolUse hook (branch-first edit guard)
//
// Why: the branch_worktree_before_edit rule ("dedicated branch + worktree
// BEFORE the first edit of any repo-modifying task") lived only in memory and
// kept being violated (PR #122: files edited on the default branch before
// branching). The native bgIsolation guard fires only in background sessions
// and misses MCP writes. This hook enforces the rule mechanically: it blocks
// Edit/Write/NotebookEdit and Serena write tools targeting a non-gitignored
// file inside a repo while that repo is on its default branch.
//
// Contract: reads the PreToolUse hook JSON on stdin; exit 2 blocks the tool
// call (stderr is shown to Claude), anything else allows it. Any uncertainty
// (no path — except Serena, see below — not a repo, git error) -> exit 0:
// a guard must fail open, never break unrelated edits.
//
// Per-repo opt-out: touch <repo>/.claude/branch-guard.disabled
//
// Known limit: Serena relative paths are resolved against the session cwd,
// which may differ from Serena's active project root after EnterWorktree
// (see @smith-worktree "MCP write blind spot") - the guard then checks the
// cwd's repo, not Serena's: it allows the edit after EnterWorktree and could
// false-block in the inverse mismatch. Serena calls without a usable path
// (e.g. replace_in_files whole-project mode, where relative_path defaults to
// "") are checked against the session cwd's repo, not allowed through.
import { existsSync } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { readHookInput, blockWithError, git } from "../lib/hook-utils.mjs";

const PROTECTED_BRANCHES = ["main", "master", "develop"];
const OPT_OUT_MARKER = join(".claude", "branch-guard.disabled");

function targetPath(input) {
  const ti = input.tool_input || {};
  const raw = ti.file_path || ti.notebook_path || ti.relative_path || "";
  if (!raw || typeof raw !== "string") return "";
  if (isAbsolute(raw)) return raw;
  return input.cwd ? resolve(input.cwd, raw) : "";
}

// Write may create files in not-yet-existing directories; git -C needs one
// that exists, so walk up to the nearest existing ancestor.
function nearestExistingDir(file) {
  let dir = dirname(file);
  while (!existsSync(dir)) {
    const up = dirname(dir);
    if (up === dir) return "";
    dir = up;
  }
  return dir;
}

function main() {
  const input = readHookInput();
  if (!input) return;

  const file = targetPath(input);
  let dir = "";
  if (file) {
    dir = nearestExistingDir(file);
  } else if (
    /^mcp__(plugin_serena_)?serena__/.test(input.tool_name || "") &&
    input.cwd
  ) {
  
  
  
    dir = input.cwd;
  }
  if (!dir) return;

  let repoRoot;
  try {
    repoRoot = git(dir, ["rev-parse", "--show-toplevel"]);
  } catch {
    return;
  }

  if (existsSync(join(repoRoot, OPT_OUT_MARKER))) return;

  if (file) {
    try {
      git(dir, ["check-ignore", "-q", "--", file]);
      return;
    } catch {
    
    }
  }

  let branch;
  try {
    branch = git(dir, ["rev-parse", "--abbrev-ref", "HEAD"]);
  } catch {
    return;
  }

  const protectedBranches = new Set(PROTECTED_BRANCHES);
  try {
    const originHead = git(dir, [
      "symbolic-ref",
      "--quiet",
      "refs/remotes/origin/HEAD",
    ]);
    const defaultBranch = originHead.split("/").pop();
    if (defaultBranch) protectedBranches.add(defaultBranch);
  } catch {
  
  
  }

  if (!protectedBranches.has(branch)) return;

  blockWithError(
    [
      `Blocked: edit on protected branch '${branch}' of ${repoRoot}.`,
      "Create a dedicated branch+worktree BEFORE the first edit:",
      "EnterWorktree (then rename the branch), or `git switch -c",
      "«type»/«description»`. Per the @smith-git branch-first rule.",
      `Per-repo opt-out: touch ${OPT_OUT_MARKER} in the repo root.`,
    ].join(" "),
  );
}

main();
