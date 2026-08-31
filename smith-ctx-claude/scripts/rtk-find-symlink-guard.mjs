#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readHookInput } from "../../smith-git/scripts/lib/hook-utils.mjs";
import { unwrappedCommandSegments } from "../../smith-git/scripts/lib/git-command-tokenizer.mjs";

const SUBPROCESS_OPTIONS = {
  stdio: ["ignore", "pipe", "ignore"],
  encoding: "utf-8",
  timeout: 5000,
  killSignal: "SIGKILL",
};
const FIND_HINT = /\bfind\b/;
const SUBCOMMAND_PREDICATES = new Set(["-exec", "-execdir", "-ok", "-okdir"]);
const NEWER_XY_LETTERS = ["a", "B", "c", "m"];
const NEWER_XY_PREDICATES = NEWER_XY_LETTERS.flatMap((x) =>
  [...NEWER_XY_LETTERS, "t"].map((y) => `-newer${x}${y}`),
);
const VALUE_TAKING_FIND_PREDICATES = new Set([
  "-name", "-iname", "-path", "-ipath", "-wholename", "-iwholename",
  "-regex", "-iregex", "-regextype",
  "-newer", "-anewer", "-cnewer", ...NEWER_XY_PREDICATES,
  "-lname", "-ilname",
  "-fstype", "-gid", "-uid", "-group", "-user", "-perm", "-inum", "-links",
  "-size", "-maxdepth", "-mindepth", "-mtime", "-atime", "-ctime",
  "-mmin", "-amin", "-cmin", "-printf", "-fprint", "-fls",
  "-fprint0", "-type", "-xtype", "-used", "-context", "-samefile", "-flags",
]);
const TWO_VALUE_FIND_PREDICATES = new Set(["-fprintf"]);

function findInvocation(tokens) {
  if (tokens[0] === "find") return { invocation: "find", argumentsFrom: 1 };
  if (tokens[0] === "rtk" && tokens[1] === "find") {
    return { invocation: "rtk find", argumentsFrom: 2 };
  }
  return null;
}

function subCommandTokens(tokens, from) {
  const rest = tokens.slice(from);
  const terminatorIndex = rest.findIndex((token) => token === ";" || token === "+");
  return terminatorIndex === -1 ? rest : rest.slice(0, terminatorIndex);
}

function nestedInvocationWithFollowSymlinksFlag(subTokens) {
  if (subTokens.length === 0) return null;
  const [nestedTokens] = unwrappedCommandSegments(subTokens.join(" "));
  const nested = nestedTokens && findInvocation(nestedTokens);
  return nested ? invocationWithFollowSymlinksFlag(nestedTokens, nested) : null;
}

function invocationWithFollowSymlinksFlag(tokens, match) {
  let i = match.argumentsFrom;
  while (i < tokens.length) {
    const token = tokens[i];
    if (SUBCOMMAND_PREDICATES.has(token)) {
      const subTokens = subCommandTokens(tokens, i + 1);
      const nestedLabel = nestedInvocationWithFollowSymlinksFlag(subTokens);
      if (nestedLabel) return nestedLabel;
      i += 1 + subTokens.length + 1;
      continue;
    }
    if (token === "-L") return match.invocation;
    if (TWO_VALUE_FIND_PREDICATES.has(token)) {
      i += 3;
      continue;
    }
    if (VALUE_TAKING_FIND_PREDICATES.has(token)) {
      i += 2;
      continue;
    }
    i += 1;
  }
  return null;
}

function riskyInvocation(command) {
  const segments = unwrappedCommandSegments(command);
  let firstRtkFind = null;
  for (const tokens of segments) {
    const match = findInvocation(tokens);
    if (!match) continue;
    const label = invocationWithFollowSymlinksFlag(tokens, match);
    if (!label) continue;
    if (label === "find") return "find";
    if (!firstRtkFind) firstRtkFind = label;
  }
  return firstRtkFind;
}

const RTK_GAIN_SUBCOMMAND = /^\s*gain\s/m;

function rtkInstalled() {
  try {
    const output = execFileSync("rtk", ["--help"], SUBPROCESS_OPTIONS);
    return RTK_GAIN_SUBCOMMAND.test(output);
  } catch {
    return false;
  }
}

function reminder(invocation) {
  return (
    `rtk-find-symlink-guard: '${invocation} ... -L' doesn't work under ` +
    "rtk-ai/rtk's find subcommand the way it does under real find — rtk " +
    "prints 'unknown flag '-L', ignored' to stderr and exits 0 (verified " +
    "against rtk 0.45.0), but when -L precedes the search path it also " +
    "drops that path and silently scans the current directory instead — " +
    "not just a missed symlink subtree, results from the wrong place " +
    "entirely. Same known-unfixed bug class as github.com/rtk-ai/rtk#2821 " +
    "(unrecognized flag warned on stderr, but the broader/wrong query " +
    "still runs at exit 0 — that report used -newermt, this is the same " +
    "code path hit with -L). Use `test -f` for a plain existence check, " +
    "or `rtk proxy find ... -L ...` for unfiltered native-find output " +
    "with real GNU/BSD find semantics."
  );
}

function main() {
  const input = readHookInput();
  if (!input || typeof input !== "object") return;
  if (input.tool_name !== "Bash") return;

  const command = input.tool_input && input.tool_input.command;
  if (typeof command !== "string") return;
  if (!FIND_HINT.test(command)) return;

  let invocation;
  try {
    invocation = riskyInvocation(command);
  } catch {
    return;
  }
  if (!invocation) return;
  if (!rtkInstalled()) return;

  const message = reminder(invocation);
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
