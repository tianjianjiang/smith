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
import { readHookInput, blockWithError, git } from "../lib/hook-utils.mjs";

const MAX_LINES_SHOWN = 10;

function main() {
  const input = readHookInput();
  if (!input) return;
  const cwd = input.cwd || process.cwd();

  const status = git(cwd, ["status", "--porcelain", "--untracked-files=all"], {
    failOpen: true,
  });
  if (!status) return;
  if (!status) return;

  const lines = status.split("\n");
  const shown = lines.slice(0, MAX_LINES_SHOWN).join("\n");
  const more =
    lines.length > MAX_LINES_SHOWN
      ? `\n… and ${lines.length - MAX_LINES_SHOWN} more`
      : "";

  blockWithError(
    [
      `Blocked: the checkout at ${cwd} has ${lines.length} uncommitted change(s) that would NOT carry into a new worktree (stranded):`,
      `${shown}${more}`,
      "Resolve deliberately first: (a) commit them (and set worktree.baseRef: head if they must seed the worktree), (b) stash now and apply inside the worktree, or (c) branch in place (`git switch -c …`) instead of a worktree. See @smith-worktree.",
    ].join("\n"),
  );
}

main();
