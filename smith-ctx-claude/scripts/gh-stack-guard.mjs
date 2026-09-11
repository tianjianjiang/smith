#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { readHookInput } from "../../smith-git/scripts/lib/hook-utils.mjs";
import { commandSegments } from "../../smith-git/scripts/lib/git-command-tokenizer.mjs";

const CONFIG_PATH = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "gh-stack-config.json",
);
const DEFAULT_NATIVE_STACK_MARKERS = ["gh-stack"];
const SUBPROCESS_OPTIONS = {
  stdio: ["ignore", "pipe", "ignore"],
  encoding: "utf-8",
  timeout: 5000,
  killSignal: "SIGKILL",
};
const HAND_ROLLED_STACK_HINT = /--onto|pr\s+create|force-with-lease=|gh-stack/;
const TRACKING_FILE = /(^|\/)\.git\/(worktrees\/[^/]+\/)?gh-stack$/;
const RAW_SHA_REFSPEC = /^[0-9a-f]{7,40}:refs\/heads\//;
const LEASE_WITH_SHA = /^--force-with-lease=[^:]+:[0-9a-f]{7,40}$/;

function rebasesOnto(tokens) {
  return (
    tokens[0] === "git" && tokens.includes("rebase") && tokens.includes("--onto")
  );
}

function pushesRawShaRefspec(tokens) {
  return (
    tokens[0] === "git" &&
    tokens.includes("push") &&
    tokens.some((token) => LEASE_WITH_SHA.test(token)) &&
    tokens.some((token) => RAW_SHA_REFSPEC.test(token))
  );
}

function touchesTrackingFile(tokens) {
  return tokens.some((token) => TRACKING_FILE.test(token));
}

function stackedCreateBase(tokens) {
  if (tokens[0] !== "gh") return null;
  let createIndex = -1;
  for (let i = 1; i < tokens.length - 1; i += 1) {
    if (tokens[i] === "pr" && tokens[i + 1] === "create") {
      createIndex = i + 1;
      break;
    }
  }
  if (createIndex === -1) return null;
  for (let i = createIndex + 1; i < tokens.length; i += 1) {
    const token = tokens[i];
    if (token === "--base" || token === "-B") return tokens[i + 1] ?? "";
    if (token.startsWith("--base=")) return token.slice("--base=".length);
  }
  return null;
}

function defaultBranch(cwd) {
  const probes = [
    ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
    ["rev-parse", "--abbrev-ref", "origin/HEAD"],
  ];
  for (const args of probes) {
    try {
      const ref = execFileSync(
        "git",
        ["-C", cwd, ...args],
        SUBPROCESS_OPTIONS,
      ).trim();
      if (ref) return ref.replace(/^origin\//, "");
    } catch {
      continue;
    }
  }
  return "";
}

function classify(command, cwd) {
  let resolvedDefaultBranch;
  let advisory = false;
  for (const tokens of commandSegments(command)) {
    if (rebasesOnto(tokens)) return "ask";
    if (pushesRawShaRefspec(tokens)) return "ask";
    if (touchesTrackingFile(tokens)) return "ask";
    const base = stackedCreateBase(tokens);
    if (base === null) continue;
    if (resolvedDefaultBranch === undefined) {
      resolvedDefaultBranch = defaultBranch(cwd);
    }
    if (resolvedDefaultBranch && base !== resolvedDefaultBranch) advisory = true;
  }
  return advisory ? "advise" : null;
}

function nativeStackMarkers() {
  try {
    const config = JSON.parse(readFileSync(CONFIG_PATH, "utf-8"));
    const markers = config.nativeStackMarkers;
    return Array.isArray(markers) && markers.length
      ? markers
      : DEFAULT_NATIVE_STACK_MARKERS;
  } catch {
    return DEFAULT_NATIVE_STACK_MARKERS;
  }
}

function nativeStackInstalled(markers) {
  try {
    const listing = execFileSync("gh", ["extension", "list"], SUBPROCESS_OPTIONS);
    return markers.some((marker) => listing.includes(marker));
  } catch {
    return false;
  }
}

const NATIVE_FLOW =
  "The gh stack extension (github/gh-stack) is installed; drive the stack " +
  "with it: `gh stack view` says \"not part of a stack\" → `gh stack checkout " +
  "<stack#|PR#>` (tracking is per worktree), then `gh stack sync` (fetch, " +
  "cascade rebase, --force-with-lease --atomic push, link PRs); conflicts → " +
  "`gh stack rebase` / `--continue` / `--abort`. Per @smith-gh-pr Stacked PRs.";

function askReason() {
  return (
    "gh-stack-guard: this command hand-rolls a stacked-PR rebase " +
    "(git rebase --onto, a raw-SHA --force-with-lease refspec push, or a " +
    "write to the .git/gh-stack tracking file). A stale tracking-file trunk " +
    "head used as the --onto base replays already-merged commits into a " +
    "false conflict, and the raw-SHA cascade has been flagged by the model " +
    "safeguard as history tampering. " +
    NATIVE_FLOW
  );
}

function advisory() {
  return (
    "gh-stack-guard: this command hand-builds a stacked pull request " +
    "(gh pr create with a non-default --base). Prefer `gh stack submit` " +
    "(or `gh stack link` for branches managed elsewhere). Verify tools with " +
    "`gh extension list`; do not assume a native tool is absent. " +
    NATIVE_FLOW
  );
}

function main() {
  const input = readHookInput();
  if (!input || typeof input !== "object") return;
  if (input.tool_name !== "Bash") return;

  const command = input.tool_input && input.tool_input.command;
  if (typeof command !== "string") return;
  if (!HAND_ROLLED_STACK_HINT.test(command)) return;

  const cwd = input.cwd || process.cwd();
  const decision = classify(command, cwd);
  if (decision === null) return;
  if (!nativeStackInstalled(nativeStackMarkers())) return;

  if (decision === "ask") {
    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "ask",
          permissionDecisionReason: askReason(),
        },
      }) + "\n",
    );
    return;
  }
  const message = advisory();
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: message,
      },
      systemMessage: message,
    }) + "\n",
  );
}

main();
