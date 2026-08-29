#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { UNWRAP_DEPTH_EXCEEDED, unwrappedCommandSegments } from "./lib/git-command-tokenizer.mjs";

const DEFERRED_MERGE_FLAGS = new Set(["--auto", "--disable-auto"]);
const HELP_FLAGS = new Set(["--help", "-h"]);

function ghSubcommandIndex(tokens) {
  let index = 1;
  while (index < tokens.length) {
    const token = tokens[index];
    if (token === "-R" || token === "--repo") {
      index += 2;
      continue;
    }
    if (token.startsWith("-")) {
      index += 1;
      continue;
    }
    break;
  }
  return index;
}

function flagName(token) {
  if (token.startsWith("--") && token.includes("=")) return token.slice(0, token.indexOf("="));
  return token;
}

function isHelpInvocation(tokens) {
  return tokens.slice(1).some((token) => HELP_FLAGS.has(flagName(token)));
}

function defersMerge(args) {
  return args.some((token) => DEFERRED_MERGE_FLAGS.has(flagName(token)));
}

function mergesImmediately(command) {
  const segments = unwrappedCommandSegments(command);
  if (segments[UNWRAP_DEPTH_EXCEEDED]) return false;
  for (const tokens of segments) {
    if (tokens[0] !== "gh") continue;
    if (isHelpInvocation(tokens)) continue;
    const subcommandIndex = ghSubcommandIndex(tokens);
    if (tokens[subcommandIndex] !== "pr" || tokens[subcommandIndex + 1] !== "merge") continue;
    if (defersMerge(tokens.slice(subcommandIndex + 2))) continue;
    return true;
  }
  return false;
}

function reminder() {
  return (
    "post-merge-pull-reminder: a `gh pr merge` just ran. If it merged, " +
    "fast-forward-only pull the repository's default branch in the primary " +
    "checkout so it reflects the merge — after any pull request merge this is " +
    "decide-and-do, not optional " +
    "(see @smith-gh-pr and @smith-worktree). For example: `git -C " +
    "«primary-checkout» switch «default-branch» && git -C «primary-checkout» " +
    "pull --ff-only`. Note: run from a worktree, `--delete-branch` can print " +
    "`fatal: '«default-branch»' is already used by worktree …` even though the " +
    "merge succeeded, and a squash merge can leave an orphan local branch to " +
    "delete (@smith-worktree Sync-After-Squash-Merge)."
  );
}

function main() {
  let input;
  try {
    input = JSON.parse(readFileSync(0, "utf-8"));
  } catch {
    return;
  }
  if (!input || typeof input !== "object") return;
  if (input.tool_name !== "Bash") return;

  const command = input.tool_input && input.tool_input.command;
  if (typeof command !== "string") return;

  let merged;
  try {
    merged = mergesImmediately(command);
  } catch {
    return;
  }
  if (!merged) return;

  const message = reminder();
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: message,
      },
      systemMessage: message,
    }) + "\n",
  );
}

main();
