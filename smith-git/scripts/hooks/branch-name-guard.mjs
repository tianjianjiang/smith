#!/usr/bin/env node
// branch-name-guard.mjs - PreToolUse hook (Conventional Branch naming enforcement)
//
// Enforces: @smith-style/SKILL.md Conventional Branch pattern
// Authoritative rule: @smith-style/SKILL.md lines 117-167
// Hooks: Bash (git commands + git push), EnterWorktree (warns, cannot block)
//
// Why both:
// - Bash git commands: blocks at creation time (git branch, checkout -b, switch -c)
// - Bash git push: blocks at push time (catches EnterWorktree-created branches)
// - EnterWorktree: warns to rename (cannot block - tool doesn't accept formatted names)
import { writeSync } from "node:fs";
import { readHookInput, blockWithError } from "../lib/hook-utils.mjs";
import { commandSegments, gitSubcommandArguments } from "../lib/git-command-tokenizer.mjs";

const CONVENTIONAL_COMMIT_TYPES = [
  "feat",
  "fix",
  "docs",
  "refactor",
  "style",
  "test",
  "chore",
  "perf",
  "build",
  "ci",
];
const TYPE_GROUP = CONVENTIONAL_COMMIT_TYPES.join("|");
const TYPE_LIST_TEXT = CONVENTIONAL_COMMIT_TYPES.join(", ");
const DESCRIPTION_SEGMENT = "[a-z0-9]+(?:\\.[a-z0-9]+)*";
const BRANCH_NAME_PATTERN = new RegExp(
  `^(${TYPE_GROUP})/${DESCRIPTION_SEGMENT}(?:-${DESCRIPTION_SEGMENT})*$`,
);
const FORBIDDEN_SUBSTRINGS = [/post-review/, /after-review/];

const BRANCH_CATEGORY_BY_SHORT_CHAR = {
  m: "rename-or-copy",
  M: "rename-or-copy",
  c: "rename-or-copy",
  C: "rename-or-copy",
  a: "listing",
  r: "listing",
  d: "listing",
  D: "listing",
  l: "listing",
  u: "non-create",
};
const BRANCH_CATEGORY_BY_LONG_FLAG = {
  "--move": "rename-or-copy",
  "--copy": "rename-or-copy",
  "--all": "listing",
  "--remotes": "listing",
  "--delete": "listing",
  "--list": "listing",
  "--set-upstream-to": "non-create",
  "--unset-upstream": "non-create",
  "--edit-description": "non-create",
};
const SHELL_SUBSTITUTION = /\$\{?\w|\$\(|`/;
const SHELL_SUBSTITUTION_STRIP =
  /\$\{[^}]*\}?|\$\([^)]*\)?|\$[A-Za-z_][A-Za-z0-9_]*|`[^`]*`?/g;
const UNDERSCORE = /_/g;
const CONSECUTIVE_HYPHENS = /-{2,}/g;
const EDGE_HYPHENS = /^-+|-+$/g;

function longFlags(flags) {
  return flags.filter((flag) => flag.startsWith("--"));
}

function shortFlagChars(flags) {
  return flags.filter((flag) => flag.length === 2 && flag[0] === "-").map((flag) => flag[1]);
}

function valueForToken(token, flags, args, index) {
  for (const flag of longFlags(flags)) {
    if (token === flag) return args[index + 1] ?? null;
    if (token.startsWith(`${flag}=`)) return token.slice(flag.length + 1);
  }
  if (token.startsWith("--") || !token.startsWith("-")) return undefined;
  const chars = shortFlagChars(flags);
  for (let i = 1; i < token.length; i += 1) {
    if (chars.includes(token[i])) {
      const tail = token.slice(i + 1);
      return tail !== "" ? tail : (args[index + 1] ?? null);
    }
  }
  return undefined;
}

function nameAfterFlag(args, flags) {
  for (let i = 0; i < args.length; i += 1) {
    const value = valueForToken(args[i], flags, args, i);
    if (value !== undefined) return value;
  }
  return null;
}

function branchTokenCategory(token) {
  if (token.startsWith("--")) {
    return BRANCH_CATEGORY_BY_LONG_FLAG[token.split("=")[0]] ?? null;
  }
  if (!token.startsWith("-")) return null;
  for (let i = 1; i < token.length; i += 1) {
    const category = BRANCH_CATEGORY_BY_SHORT_CHAR[token[i]];
    if (category) return category;
  }
  return null;
}

function branchCategories(args) {
  const categories = new Set();
  for (const token of args) {
    const category = branchTokenCategory(token);
    if (category) categories.add(category);
  }
  return categories;
}

function lastPositionalTargetName(positionals) {
  return positionals.length >= 1 ? positionals[positionals.length - 1] : null;
}

function newBranchName(positionals) {
  return positionals.length >= 1 ? positionals[0] : null;
}

function containsUnresolvedShellSubstitution(name) {
  return SHELL_SUBSTITUTION.test(name);
}

function withShellSubstitutionsRemoved(name) {
  return name.replace(SHELL_SUBSTITUTION_STRIP, "");
}

function branchBeingCreatedOrRenamed(tokens) {
  const parsed = gitSubcommandArguments(tokens);
  if (!parsed) return null;
  const { subcommand, args } = parsed;

  if (subcommand === "checkout") {
    return nameAfterFlag(args, ["-b", "-B", "--orphan"]);
  }
  if (subcommand === "switch") {
    return nameAfterFlag(args, ["-c", "-C", "--create", "--orphan"]);
  }
  if (subcommand === "branch") {
    const positionals = args.filter((token) => !token.startsWith("-"));
    const categories = branchCategories(args);
    if (categories.has("rename-or-copy")) return lastPositionalTargetName(positionals);
    if (categories.has("listing")) return null;
    if (categories.has("non-create")) return null;
    return newBranchName(positionals);
  }
  if (subcommand === "stash" && args[0] === "branch") {
    return args[1] ?? null;
  }
  if (subcommand === "worktree" && args[0] === "add") {
    return nameAfterFlag(args.slice(1), ["-b", "-B"]);
  }
  return null;
}

function suggestedFix(name) {
  return name
    .toLowerCase()
    .replace(UNDERSCORE, "-")
    .replace(CONSECUTIVE_HYPHENS, "-")
    .replace(EDGE_HYPHENS, "");
}

function forbiddenSubstringReason(name) {
  if (!FORBIDDEN_SUBSTRINGS.some((pattern) => pattern.test(name))) return null;
  return (
    "names the change's ORIGIN (a review round), not what it does — " +
    "per @smith-style Branch Names, never put post-review/after-review " +
    "in a branch name"
  );
}

function violation(name) {
  const forbidden = forbiddenSubstringReason(name);
  if (forbidden) return forbidden;
  if (!BRANCH_NAME_PATTERN.test(name)) {
    return (
      "doesn't match the Conventional Branch pattern " +
      "`type/description` (type: " +
      TYPE_LIST_TEXT +
      "; description: lowercase letters/digits in hyphen-separated segments, " +
      "no underscores, no uppercase, no consecutive/leading/trailing hyphens)"
    );
  }
  return null;
}

function branchBeingPushed(tokens) {
  const parsed = gitSubcommandArguments(tokens);
  if (!parsed || parsed.subcommand !== "push") return null;
  const { args } = parsed;

  const branchFromHeadColon = args.find((arg) => arg.startsWith("HEAD:"));
  if (branchFromHeadColon) return branchFromHeadColon.slice(5);

  const upstreamFlags = ["-u", "--set-upstream"];
  for (let i = 0; i < args.length; i += 1) {
    if (upstreamFlags.includes(args[i])) {
      const remoteBranch = args[i + 2];
      if (remoteBranch && !remoteBranch.startsWith("-")) return remoteBranch;
    }
  }

  return null;
}

function emitBlock(name, reason) {
  const suggestion = suggestedFix(name);
  const suggestionIsValid = suggestion !== name && !violation(suggestion);
  blockWithError(
    [
      `Blocked: branch name '${name}' ${reason}.`,
      suggestionIsValid
        ? `Did you mean '${suggestion}'?`
        : "Choose a name matching the pattern.",
      "Per @smith-style/SKILL.md Branch Names",
      "(https://conventionalbranch.org/).",
    ].join(" "),
  );
}

function emitWarning(branchName, reason) {
  const typeMatch = branchName.match(/^worktree-(.+)$/);
  const baseName = typeMatch ? typeMatch[1] : branchName;

  const suggestion = `refactor/${baseName}`;
  const suggestionIsValid = !violation(suggestion);

  writeSync(
    2,
    [
      `Warning: EnterWorktree will create branch '${branchName}' which ${reason}.`,
      suggestionIsValid
        ? `Rename immediately after: git branch -m ${suggestion}`
        : `Rename immediately after: git branch -m <type>/${baseName}`,
      "Per @smith-style/SKILL.md Branch Names",
      "(https://conventionalbranch.org/).",
    ].join(" ") + "\n",
  );
}

function main() {
  const input = readHookInput();
  if (!input || typeof input !== "object") return;

  if (input.tool_name === "Bash") {
    const command = input.tool_input && input.tool_input.command;
    if (typeof command !== "string") return;

    for (const tokens of commandSegments(command)) {
      const branchName = branchBeingCreatedOrRenamed(tokens);
      if (branchName && branchName !== "HEAD") {
        if (containsUnresolvedShellSubstitution(branchName)) {
          const worstCaseName = withShellSubstitutionsRemoved(branchName);
          const reason = forbiddenSubstringReason(worstCaseName);
          if (reason) emitBlock(worstCaseName, reason);
          continue;
        }
        const reason = violation(branchName);
        if (reason) emitBlock(branchName, reason);
      }

      const pushTarget = branchBeingPushed(tokens);
      if (pushTarget && pushTarget !== "HEAD") {
        const reason = violation(pushTarget);
        if (reason) emitBlock(pushTarget, reason);
      }
    }
  }

  if (input.tool_name === "EnterWorktree") {
    const name = input.tool_input && input.tool_input.name;
    if (!name) return;

    const branchName = `worktree-${name}`;
    const reason = violation(branchName);
    if (reason) emitWarning(branchName, reason);
  }
}

main();
