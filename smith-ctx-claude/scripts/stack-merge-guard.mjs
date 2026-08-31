#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readHookInput } from "../../smith-git/scripts/lib/hook-utils.mjs";
import { UNWRAP_DEPTH_EXCEEDED, unwrappedCommandSegments } from "../../smith-git/scripts/lib/git-command-tokenizer.mjs";

const SUBPROCESS_TIMEOUT_MS = 5000;
const SUBPROCESS_OPTIONS = {
  stdio: ["ignore", "pipe", "ignore"],
  encoding: "utf-8",
  timeout: SUBPROCESS_TIMEOUT_MS,
  killSignal: "SIGKILL",
};

const UNVERIFIABLE = Symbol("unverifiable");
const DEPTH_EXCEEDED = Symbol("depth-exceeded");
const DELETE_BRANCH_BOOL_SHORT_CHARS = new Set(["d", "m", "r", "s"]);
const VALUE_TAKING_SHORT_CHARS = new Set(["A", "b", "F", "t", "R"]);
const REPO_FLAGS = new Set(["-R", "--repo"]);
const VALUE_FLAGS = new Set([
  "-A",
  "--author-email",
  "-b",
  "--body",
  "-F",
  "--body-file",
  "-t",
  "--subject",
  "--match-head-commit",
]);
function splitClusteredShortFlag(token) {
  if (token.startsWith("--") || token[0] !== "-" || token.length < 2) return null;
  const chars = [...token.slice(1)];
  const result = [];
  for (let index = 0; index < chars.length; index += 1) {
    const char = chars[index];
    if (VALUE_TAKING_SHORT_CHARS.has(char)) {
      result.push(`-${char}`);
      const remainder = chars.slice(index + 1).join("");
      if (remainder) result.push(remainder.startsWith("=") ? remainder.slice(1) : remainder);
      return result;
    }
    if (!DELETE_BRANCH_BOOL_SHORT_CHARS.has(char)) return null;
    result.push(`-${char}`);
  }
  return result;
}

function withAttachedFlagsSplit(tokens) {
  const result = [];
  for (const token of tokens) {
    if (token.startsWith("--") && token.includes("=")) {
      const equalsIndex = token.indexOf("=");
      result.push(token.slice(0, equalsIndex), token.slice(equalsIndex + 1));
      continue;
    }
    const clustered = splitClusteredShortFlag(token);
    if (clustered !== null) {
      result.push(...clustered);
      continue;
    }
    result.push(token);
  }
  return result;
}

function clusterSetsDeleteBranch(chars) {
  for (const char of chars) {
    if (char === "d") return true;
    if (VALUE_TAKING_SHORT_CHARS.has(char)) return false;
    if (!DELETE_BRANCH_BOOL_SHORT_CHARS.has(char)) return false;
  }
  return false;
}

function mergeTargetAndRepo(tokens) {
  let target = null;
  let repo = null;
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (REPO_FLAGS.has(token)) {
      repo = tokens[index + 1] ?? null;
      index += 1;
      continue;
    }
    if (VALUE_FLAGS.has(token)) {
      index += 1;
      continue;
    }
    if (token.startsWith("-")) continue;
    if (target === null) target = token;
  }
  return { target, repo };
}

const DELETE_BRANCH_NEGATIVE_VALUES = new Set(["0", "f", "F", "false", "False", "FALSE"]);

function deleteBranchAttachedValue(token) {
  return token.startsWith("--delete-branch=") ? token.slice("--delete-branch=".length) : null;
}

function deleteBranchTokenState(token) {
  const attachedValue = deleteBranchAttachedValue(token);
  if (attachedValue !== null) return !DELETE_BRANCH_NEGATIVE_VALUES.has(attachedValue);
  if (token === "--delete-branch") return true;
  if (token.startsWith("--") || token[0] !== "-" || token.length < 2) return null;
  return clusterSetsDeleteBranch([...token.slice(1)]) ? true : null;
}

function deleteBranchIsSetIn(rawArgs) {
  let state = null;
  for (let index = 0; index < rawArgs.length; index += 1) {
    const token = rawArgs[index];
    if (VALUE_FLAGS.has(token) || REPO_FLAGS.has(token)) {
      index += 1;
      continue;
    }
    const tokenState = deleteBranchTokenState(token);
    if (tokenState !== null) state = tokenState;
  }
  return state === true;
}

function globalFlagValue(token) {
  if (token.startsWith("--repo=")) return token.slice("--repo=".length);
  if (token.startsWith("--hostname=")) return null;
  return null;
}

function ghSubcommandPosition(tokens) {
  let index = 1;
  let globalRepo = null;
  while (index < tokens.length) {
    const token = tokens[index];
    if (token === "-R" || token === "--repo") {
      globalRepo = tokens[index + 1] ?? null;
      index += 2;
      continue;
    }
    if (token === "--hostname") {
      index += 2;
      continue;
    }
    if (token.startsWith("--repo=") || token.startsWith("--hostname=")) {
      const value = globalFlagValue(token);
      if (value !== null) globalRepo = value;
      index += 1;
      continue;
    }
    if (token.startsWith("-R") && token.length > 2 && !token.startsWith("--")) {
      globalRepo = token.slice(2);
      index += 1;
      continue;
    }
    if (token.startsWith("-")) {
      index += 1;
      continue;
    }
    break;
  }
  return { subcommandIndex: index, globalRepo };
}

function mergeInvocationsWithDeleteBranch(command) {
  const segments = unwrappedCommandSegments(command);
  if (segments[UNWRAP_DEPTH_EXCEEDED]) return DEPTH_EXCEEDED;

  const invocations = [];
  for (const tokens of segments) {
    if (tokens[0] !== "gh") continue;
    const { subcommandIndex, globalRepo } = ghSubcommandPosition(tokens);
    if (tokens[subcommandIndex] !== "pr" || tokens[subcommandIndex + 1] !== "merge") continue;

    const rawArgs = tokens.slice(subcommandIndex + 2);
    if (!deleteBranchIsSetIn(rawArgs)) continue;
    const argsWithoutDeleteBranchEquals = rawArgs.filter(
      (token) => deleteBranchAttachedValue(token) === null,
    );
    const args = withAttachedFlagsSplit(argsWithoutDeleteBranchEquals);
    const { target, repo } = mergeTargetAndRepo(args);
    invocations.push({ target, repo: repo ?? globalRepo });
  }
  return invocations;
}

function gh(cwd, args) {
  try {
    return execFileSync("gh", args, { cwd, ...SUBPROCESS_OPTIONS }).trim();
  } catch {
    return UNVERIFIABLE;
  }
}

function repoArgs(repo) {
  return repo ? ["-R", repo] : [];
}

function headRefName(target, repo, cwd) {
  const args = ["pr", "view", ...(target ? [target] : []), "--json", "headRefName", ...repoArgs(repo)];
  const output = gh(cwd, args);
  if (output === UNVERIFIABLE) return UNVERIFIABLE;
  try {
    return JSON.parse(output).headRefName || UNVERIFIABLE;
  } catch {
    return UNVERIFIABLE;
  }
}

function childPrNumbers(baseBranch, repo, cwd) {
  const output = gh(cwd, [
    "pr",
    "list",
    "--base",
    baseBranch,
    "--state",
    "open",
    "--json",
    "number",
    ...repoArgs(repo),
  ]);
  if (output === UNVERIFIABLE) return UNVERIFIABLE;
  try {
    const prs = JSON.parse(output || "[]");
    return Array.isArray(prs) ? prs.map((pr) => pr.number) : UNVERIFIABLE;
  } catch {
    return UNVERIFIABLE;
  }
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

function depthExceededReason() {
  return (
    "A shell-wrapped command was nested too deeply to fully unwrap, so " +
    "whether it is a `gh pr merge --delete-branch` that would orphan a " +
    "stacked child PR's base branch could not be checked. Approve only if " +
    "you are certain no open PR is based on any branch this command deletes."
  );
}

function unverifiableReason(context) {
  return (
    `Could not verify ${context} (gh failed or timed out) before this ` +
    "`gh pr merge --delete-branch`. Deleting a branch that is the base of an " +
    "open child PR leaves that PR pointing at a deleted branch. Approve only " +
    "if you are certain no open PR is based on the branch being deleted."
  );
}

function orphanedChildrenReason(headBranch, children) {
  const prs = children.map((prNumber) => `#${prNumber}`).join(", ");
  return (
    `Merging with --delete-branch will delete '${headBranch}', but open PR(s) ` +
    `${prs} are based on it -- their base branch would be deleted out from ` +
    "under them (real incident: #86->#87 2026-06-15). Retarget " +
    `those PRs first (\`gh pr edit <number> --base <new-base>\`), or use ` +
    "`gh stack` to handle the cascade, before merging with --delete-branch."
  );
}

function internalErrorReason() {
  return (
    "An internal error occurred while checking whether this `gh pr merge " +
    "--delete-branch` would orphan a stacked child PR, so the check could not " +
    "complete. Approve only if you are certain no open PR is based on the " +
    "branch being deleted."
  );
}

function evaluateMerge(command, cwd) {
  const invocations = mergeInvocationsWithDeleteBranch(command);
  if (invocations === DEPTH_EXCEEDED) {
    emitAsk(depthExceededReason());
    return;
  }
  if (invocations.length === 0) return;

  for (const { target, repo } of invocations) {
    const headBranch = headRefName(target, repo, cwd);
    if (headBranch === UNVERIFIABLE) {
      emitAsk(unverifiableReason(`the head branch of ${target || "the current PR"}`));
      return;
    }
    const children = childPrNumbers(headBranch, repo, cwd);
    if (children === UNVERIFIABLE) {
      emitAsk(unverifiableReason(`open PRs based on '${headBranch}'`));
      return;
    }
    if (children.length > 0) {
      emitAsk(orphanedChildrenReason(headBranch, children));
      return;
    }
  }
}

function main() {
  const input = readHookInput();
  if (!input || typeof input !== "object") return;
  if (input.tool_name !== "Bash") return;

  const command = input.tool_input && input.tool_input.command;
  if (typeof command !== "string") return;

  const cwd = input.cwd || process.cwd();
  try {
    evaluateMerge(command, cwd);
  } catch {
    emitAsk(internalErrorReason());
  }
}

main();
