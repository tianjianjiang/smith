#!/usr/bin/env node
import { readHookInput } from "../../smith-git/scripts/lib/hook-utils.mjs";
import {
  UNWRAP_DEPTH_EXCEEDED,
  gitSubcommandArguments,
} from "../../smith-git/scripts/lib/git-command-tokenizer.mjs";
import { invocationsOf, scansUnderEitherShellReading, simpleCommands } from "./lib/shell-scan.mjs";

const ERASING_PROGRAMS = new Set(["rm", "unlink", "shred"]);
const FIND_ACTIONS_THAT_RUN_A_PROGRAM = new Set(["-exec", "-execdir", "-ok", "-okdir"]);
const FIND_ERASING_ACTION = "-delete";
const GIT_ERASING_FLAGS = new Map([
  ["rm", [["f", "--force"]]],
  ["clean", [["f", "--force"], ["i", "--interactive"]]],
]);
const GIT_FLAGS_WITHOUT_A_VALUE = new Map([
  ["rm", { letters: "nfrq", longNames: ["--dry-run", "--force", "--quiet", "--cached", "--ignore-unmatch", "--sparse"] }],
  ["clean", { letters: "dfinqxX", longNames: ["--dry-run", "--force", "--quiet", "--interactive"] }],
]);
const GIT_OPTIONS_THAT_SPARE_FILES = new Map([["rm", "--cached"]]);
const CLAUDE_REMOVE_SUBCOMMAND = "rm";
const COMMAND_LOOKUP_OPTION = /^-[pvV]*[vV][pvV]*$/;
const KEYWORDS_BEFORE_A_COMMAND = new Set(["if", "then", "do", "else", "elif", "while", "until", "!", "{"]);
const CLAUDE_DISCARDING_FLAGS = new Set(["--discard-unpushed", "--force-remove-worktree"]);
const WORDS_THAT_NAME_AN_ERASER = [...new Set([...ERASING_PROGRAMS, ...GIT_ERASING_FLAGS.keys()])];
const ERASING_WORD_IN_UNSCANNED_TEXT = new RegExp(
  `(^|[^A-Za-z0-9_-])(${WORDS_THAT_NAME_AN_ERASER.join("|")})([^A-Za-z0-9_-]|$)|${FIND_ERASING_ACTION}\\b`,
);
const UNDOABLE_ALTERNATIVE =
  'Move it into a scratch folder instead (mv «path» "$(mktemp -d)"/) or send it to the Trash ' +
  "(/usr/bin/trash «path»), as smith-undoable/SKILL.md asks. " +
  "This hook judges the command, not whether what it erases survives elsewhere; it allows " +
  "rmdir, docker rm, git rm without -f and claude rm without its discarding flags. To look up " +
  "whether a program exists, use type «name» or which «name».";

function optionsOf(args) {
  const end = args.indexOf("--");
  return end === -1 ? args : args.slice(0, end);
}

function longOptionGiven(args, longName) {
  return args.some((arg) => /^--[a-z-]+$/.test(arg) && longName.startsWith(arg));
}

function flagGiven(args, letter, longName) {
  return longOptionGiven(args, longName) || args.some((arg) => /^-[A-Za-z]+$/.test(arg) && arg.includes(letter));
}

function isAKnownFlag(arg, { letters, longNames }) {
  if (arg.startsWith("--")) return longNames.some((longName) => longName.startsWith(arg));
  return [...arg.slice(1)].every((letter) => letters.includes(letter));
}

function onlyKnownFlags(subcommand, options) {
  const known = GIT_FLAGS_WITHOUT_A_VALUE.get(subcommand);
  return options.filter((arg) => arg.startsWith("-")).every((arg) => isAKnownFlag(arg, known));
}

function sparesTheWorkingTree(subcommand, options) {
  if (!onlyKnownFlags(subcommand, options)) return false;
  const optionThatSparesFiles = GIT_OPTIONS_THAT_SPARE_FILES.get(subcommand);
  return flagGiven(options, "n", "--dry-run") || (optionThatSparesFiles && longOptionGiven(options, optionThatSparesFiles));
}

function gitErasure(invocation) {
  const parsed = gitSubcommandArguments(invocation);
  const erasingFlags = parsed && GIT_ERASING_FLAGS.get(parsed.subcommand);
  if (!erasingFlags) return null;
  const options = optionsOf(parsed.args);
  if (sparesTheWorkingTree(parsed.subcommand, options)) return null;
  const flag = erasingFlags.find(([letter, longName]) => flagGiven(options, letter, longName));
  return flag ? `git ${parsed.subcommand} -${flag[0]}` : null;
}

function findErasure(invocation) {
  if (invocation.includes(FIND_ERASING_ACTION)) return `find ${FIND_ERASING_ACTION}`;
  for (const [index, token] of invocation.entries()) {
    if (!FIND_ACTIONS_THAT_RUN_A_PROGRAM.has(token)) continue;
    const program = erasingProgramsRun([invocation.slice(index + 1)])[0];
    if (program) return `find ${token} ${program}`;
  }
  return null;
}

function claudeErasure(invocation) {
  const options = optionsOf(invocation);
  if (!options.includes(CLAUDE_REMOVE_SUBCOMMAND)) return null;
  const flag = options.find((token) => CLAUDE_DISCARDING_FLAGS.has(token));
  return flag ? `claude ${CLAUDE_REMOVE_SUBCOMMAND} ${flag}` : null;
}

function erasingProgramsRun(segments) {
  return [...ERASING_PROGRAMS].filter((program) => invocationsOf(program, segments).length > 0);
}

const ERASURE_CHECKS = [
  ["git", gitErasure],
  ["find", findErasure],
  ["claude", claudeErasure],
];

function erasuresIn(segments) {
  const found = erasingProgramsRun(segments);
  for (const [program, erasure] of ERASURE_CHECKS) {
    found.push(...invocationsOf(program, segments).map(erasure).filter(Boolean));
  }
  return [...new Set(found)];
}

function looksUpACommand(tokens) {
  const position = tokens.findIndex((token) => !KEYWORDS_BEFORE_A_COMMAND.has(token));
  return tokens[position] === "command" && COMMAND_LOOKUP_OPTION.test(tokens[position + 1] ?? "");
}

function deny(reason) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: `erase-guard: ${reason} ${UNDOABLE_ALTERNATIVE}`,
      },
    }) + "\n",
  );
}

function main() {
  const input = readHookInput();
  if (!input || input.tool_name !== "Bash") return;
  const command = input.tool_input?.command;
  if (typeof command !== "string") return;
  const scans = scansUnderEitherShellReading(command);
  if (scans.some((segments) => segments[UNWRAP_DEPTH_EXCEEDED])) {
    if (ERASING_WORD_IN_UNSCANNED_TEXT.test(command)) {
      deny("this command is wrapped too deeply to scan and names an erasing command; run the inner command directly.");
    }
    return;
  }
  const erasures = erasuresIn(scans.flat().flatMap(simpleCommands).filter((tokens) => !looksUpACommand(tokens)));
  if (erasures.length === 0) return;
  deny(`${erasures.join(", ")} erases files, and a file whose content exists nowhere else cannot be brought back.`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`erase-guard: the guard itself failed, so this command was NOT checked: ${error?.message ?? error}\n`);
}
