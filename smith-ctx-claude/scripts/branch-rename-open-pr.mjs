#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync, writeSync } from "node:fs";
import { commandSegments, globalOptionKind } from "../../smith-git/scripts/lib/git-command-tokenizer.mjs";

const SUBPROCESS_TIMEOUT_MS = 5000;
const SUBPROCESS_OPTIONS = {
  stdio: ["ignore", "pipe", "ignore"],
  encoding: "utf-8",
  timeout: SUBPROCESS_TIMEOUT_MS,
  killSignal: "SIGKILL",
};
const MOVE_FLAG = /^--move$|^-[a-zA-Z]*[mM]/;

function git(cwd, args) {
  return execFileSync("git", ["-C", cwd, ...args], SUBPROCESS_OPTIONS).trim();
}

function branchInvocationArguments(command) {
  const invocations = [];
  for (const tokens of commandSegments(command)) {
    if (tokens[0] !== "git") continue;
    let index = 1;
    while (index < tokens.length) {
      const kind = globalOptionKind(tokens[index]);
      if (kind === "takes-value") index += 2;
      else if (kind === "standalone") index += 1;
      else break;
    }
    if (tokens[index] === "branch") invocations.push(tokens.slice(index + 1));
  }
  return invocations;
}

function isRename(argumentTokens) {
  return argumentTokens.some((token) => MOVE_FLAG.test(token));
}

function branchBeingRenamed(argumentTokens, cwd) {
  const positionals = argumentTokens.filter((token) => !token.startsWith("-"));
  if (positionals.length >= 2) return positionals[0];
  if (positionals.length === 1) {
    try {
      return git(cwd, ["rev-parse", "--abbrev-ref", "HEAD"]);
    } catch {
      return "";
    }
  }
  return "";
}

const OPEN_PR_STATE_UNVERIFIABLE = Symbol("open-pr-state-unverifiable");

function openPrState(branch, cwd) {
  try {
    const output = execFileSync(
      "gh",
      ["pr", "list", "--head", branch, "--state", "open", "--json", "number"],
      { cwd, ...SUBPROCESS_OPTIONS },
    ).trim();
    const prs = JSON.parse(output || "[]");
    return Array.isArray(prs) ? prs.map((pr) => pr.number) : [];
  } catch (error) {
    if (error && error.code === "ENOENT") return [];
    return OPEN_PR_STATE_UNVERIFIABLE;
  }
}

function emitBlock(branch, prNumbers) {
  const prs = prNumbers.map((n) => `#${n}`).join(", ");
  writeSync(
    2,
    [
      `Blocked: renaming branch '${branch}' would CLOSE its open PR (${prs})`,
      "on GitHub once the rename is pushed, and that close is UNRECOVERABLE -",
      "the PR cannot be reopened. Do NOT rename a branch that has an open PR.",
      "If the name is wrong, open a fresh correctly-named branch/PR and close",
      "this one deliberately, or keep the name. Per the",
      "branch_rename_closes_open_pr rule.",
    ].join(" ") + "\n",
  );
  process.exit(2);
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

function unverifiableReason(branch) {
  return (
    `Could not verify open-PR state for branch '${branch}' (gh failed or timed ` +
    `out). Renaming a branch that has an open PR CLOSES it UNRECOVERABLY once ` +
    `pushed. Approve only if you are certain no open PR has '${branch}' as its ` +
    `head. Per the branch_rename_closes_open_pr rule.`
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

  const cwd = input.cwd || process.cwd();
  for (const argumentTokens of branchInvocationArguments(command)) {
    if (!isRename(argumentTokens)) continue;
    const branch = branchBeingRenamed(argumentTokens, cwd);
    if (branch === "HEAD") continue;
    if (!branch) {
      emitAsk(unverifiableReason("the current branch"));
      return;
    }
    const state = openPrState(branch, cwd);
    if (state === OPEN_PR_STATE_UNVERIFIABLE) {
      emitAsk(unverifiableReason(branch));
      return;
    }
    if (state.length > 0) emitBlock(branch, state);
  }
}

main();
