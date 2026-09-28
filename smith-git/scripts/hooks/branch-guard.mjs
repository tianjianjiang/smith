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
// Serena paths: a Serena relative_path is resolved against Serena's project
// root (lib/serena-root.mjs), which stays at the launch checkout after
// EnterWorktree, and against the session cwd only when that root cannot be
// determined. Steering an unprefixed path into the worktree is the job of
// smith-serena/scripts/worktree-path-guard.mjs. Serena calls without a usable
// path (e.g. replace_in_files whole-project mode, where relative_path
// defaults to "") are checked against the same base, not allowed through.
import { existsSync } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { readHookInput, blockWithError, git } from "../lib/hook-utils.mjs";
import {
  SERENA_TOOL_PREFIX,
  findSerenaProjectRoot,
} from "../lib/serena-root.mjs";

const PROTECTED_BRANCHES = ["main", "master", "develop"];
const OPT_OUT_MARKER = join(".claude", "branch-guard.disabled");

function relativePathBase(input) {
  if (SERENA_TOOL_PREFIX.test(input.tool_name || "")) {
    const serenaRoot = findSerenaProjectRoot(process.env.CLAUDE_PROJECT_DIR);
    if (serenaRoot) return serenaRoot;
  }
  return input.cwd || "";
}

function targetPath(input) {
  const ti = input.tool_input || {};
  const raw = ti.file_path || ti.notebook_path || ti.relative_path || "";
  if (!raw || typeof raw !== "string") return "";
  if (isAbsolute(raw)) return raw;
  const base = relativePathBase(input);
  return base ? resolve(base, raw) : "";
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
  } else if (SERENA_TOOL_PREFIX.test(input.tool_name || "")) {
  
  
  
    dir = relativePathBase(input);
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
