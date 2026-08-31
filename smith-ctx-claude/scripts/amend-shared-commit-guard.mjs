#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readHookInput } from "../../smith-git/scripts/lib/hook-utils.mjs";
import {
  UNWRAP_DEPTH_EXCEEDED,
  gitSubcommandArguments,
  unwrappedCommandSegments,
} from "../../smith-git/scripts/lib/git-command-tokenizer.mjs";

const SUBPROCESS_TIMEOUT_MS = 5000;
const SUBPROCESS_OPTIONS = {
  stdio: ["ignore", "pipe", "ignore"],
  encoding: "utf-8",
  timeout: SUBPROCESS_TIMEOUT_MS,
  killSignal: "SIGKILL",
};

const UNVERIFIABLE = Symbol("unverifiable");
const DEPTH_EXCEEDED = Symbol("depth-exceeded");
const AMEND_FLAG = "--amend";
const NO_AMEND_FLAG = "--no-amend";
const AMEND_MIN_PREFIX_LENGTH = "--am".length;
const NO_AMEND_MIN_PREFIX_LENGTH = "--no-am".length;

const AMEND_VALUE_TAKING_FLAGS = new Set([
  "-m",
  "--message",
  "-F",
  "--file",
  "-C",
  "--reuse-message",
  "-c",
  "--reedit-message",
  "-A",
  "--author",
  "--date",
  "-t",
  "--template",
  "--fixup",
  "--squash",
]);

function isAmendFlag(token) {
  return token.length >= AMEND_MIN_PREFIX_LENGTH && AMEND_FLAG.startsWith(token);
}

function isNoAmendFlag(token) {
  return token.length >= NO_AMEND_MIN_PREFIX_LENGTH && NO_AMEND_FLAG.startsWith(token);
}

function lastAmendFlagIsPositive(args) {
  let result = false;
  for (let index = 0; index < args.length; index += 1) {
    const token = args[index];
    if (AMEND_VALUE_TAKING_FLAGS.has(token)) {
      index += 1;
      continue;
    }
    if (isAmendFlag(token)) {
      result = true;
      continue;
    }
    if (isNoAmendFlag(token)) {
      result = false;
    }
  }
  return result;
}

function commandAmendsHead(command) {
  const segments = unwrappedCommandSegments(command);
  if (segments[UNWRAP_DEPTH_EXCEEDED]) return DEPTH_EXCEEDED;
  return segments.some((tokens) => {
    const parsed = gitSubcommandArguments(tokens);
    return parsed !== null && parsed.subcommand === "commit" && lastAmendFlagIsPositive(parsed.args);
  });
}

function git(cwd, args) {
  try {
    return execFileSync("git", ["-C", cwd, ...args], SUBPROCESS_OPTIONS).trim();
  } catch {
    return UNVERIFIABLE;
  }
}

function otherBranchesAtHead(cwd) {
  const currentBranch = git(cwd, ["rev-parse", "--abbrev-ref", "HEAD"]);
  if (currentBranch === UNVERIFIABLE) return UNVERIFIABLE;
  if (currentBranch === "HEAD") return [];

  const pointsAtHead = git(cwd, ["branch", "--points-at", "HEAD", "--format=%(refname:short)"]);
  if (pointsAtHead === UNVERIFIABLE) return UNVERIFIABLE;

  return pointsAtHead
    .split("\n")
    .filter(Boolean)
    .filter((branch) => branch !== currentBranch);
}

function emitAsk(reason) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: reason,
      },
    }) + "\n",
  );
}

function sharedCommitReason(others) {
  const branches = others.map((branch) => `'${branch}'`).join(", ");
  const verb = others.length > 1 ? "also point" : "also points";
  return (
    `git commit --amend would rewrite HEAD, but ${branches} ${verb} at the same ` +
    "commit -- this branch has no commit of its own yet, so the commit being " +
    "amended most likely belongs to a parent/base branch, not this one. Per " +
    "reference_amend_on_fresh_stacked_branch_rewrites_parent: check `git log " +
    "--oneline -2` first. Approve only if you specifically intend to rewrite " +
    "that shared commit; otherwise use a new `git commit` instead of `--amend`."
  );
}

function depthExceededReason() {
  return (
    "A shell-wrapped command was nested too deeply to fully unwrap, so " +
    "whether it is a `git commit --amend` that would rewrite a commit shared " +
    "with another branch could not be checked. Approve only if you are " +
    "certain this command does not amend a commit shared with another branch."
  );
}

function unverifiableReason() {
  return (
    "Could not verify whether HEAD is also the tip of another local branch (git " +
    "failed or timed out) before this `git commit --amend`. Approve only if you " +
    "are certain the commit being amended belongs to the current branch alone."
  );
}

function internalErrorReason() {
  return (
    "An internal error occurred while checking whether this `git commit --amend` " +
    "would rewrite a commit shared with another branch, so the check could not " +
    "complete. Approve only if you are certain the commit being amended belongs " +
    "to the current branch alone."
  );
}

function evaluateAmend(command, cwd) {
  const amends = commandAmendsHead(command);
  if (amends === DEPTH_EXCEEDED) {
    emitAsk(depthExceededReason());
    return;
  }
  if (!amends) return;

  const others = otherBranchesAtHead(cwd);
  if (others === UNVERIFIABLE) {
    emitAsk(unverifiableReason());
    return;
  }
  if (others.length > 0) emitAsk(sharedCommitReason(others));
}

function main() {
  const input = readHookInput();
  if (!input || typeof input !== "object") return;
  if (input.tool_name !== "Bash") return;

  const command = input.tool_input && input.tool_input.command;
  if (typeof command !== "string") return;

  const cwd = input.cwd || process.cwd();
  try {
    evaluateAmend(command, cwd);
  } catch {
    emitAsk(internalErrorReason());
  }
}

main();
