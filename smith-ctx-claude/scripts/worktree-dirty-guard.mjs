#!/usr/bin/env node
// worktree-dirty-guard.mjs - PreToolUse hook on EnterWorktree (dirty-tree guard)
//
// Why: a new worktree starts clean from its base ref, so uncommitted changes
// in the current checkout NEVER carry over - and with the default
// worktree.baseRef "fresh" (origin/<default-branch>) even local commits are
// left behind. In a background smith-ship run, step-1 EnterWorktree on a
// dirty checkout silently strands that work. This hook blocks EnterWorktree
// until the dirt is dealt with deliberately.
//
// Contract: reads the PreToolUse hook JSON on stdin; exit 2 blocks the call
// (stderr shown to Claude), anything else allows it. Not a repo or git error
// -> exit 0 (fail open; EnterWorktree does its own validation).
import { execFileSync } from "node:child_process";
import { readFileSync, writeSync } from "node:fs";

const MAX_LINES_SHOWN = 10;

function main() {
  let input;
  try {
    input = JSON.parse(readFileSync(0, "utf-8"));
  } catch {
    return;
  }
  const cwd = input.cwd || process.cwd();

  let status;
  try {
    // -uall: status.showUntrackedFiles=no would otherwise hide untracked
    // files, which are stranded by a new worktree just like modified ones
    status = execFileSync(
      "git",
      ["-C", cwd, "status", "--porcelain", "--untracked-files=all"],
      { stdio: ["ignore", "pipe", "ignore"], encoding: "utf-8" },
    ).trim();
  } catch {
    return;
  }
  if (!status) return;

  const lines = status.split("\n");
  const shown = lines.slice(0, MAX_LINES_SHOWN).join("\n");
  const more =
    lines.length > MAX_LINES_SHOWN
      ? `\n… and ${lines.length - MAX_LINES_SHOWN} more`
      : "";

  // writeSync: stderr can be async on pipes; process.exit would truncate it
  writeSync(
    2,
    [
      `Blocked: the checkout at ${cwd} has ${lines.length} uncommitted change(s) that would NOT carry into a new worktree (stranded):`,
      `${shown}${more}`,
      "Resolve deliberately first: (a) commit them (and set worktree.baseRef: head if they must seed the worktree), (b) stash now and apply inside the worktree, or (c) branch in place (`git switch -c …`) instead of a worktree. See @smith-worktree.",
    ].join("\n") + "\n",
  );
  process.exit(2);
}

main();
