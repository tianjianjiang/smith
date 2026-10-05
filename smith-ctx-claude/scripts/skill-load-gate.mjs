#!/usr/bin/env node
import { basename } from "node:path";
import { readHookInput } from "../../smith-git/scripts/lib/hook-utils.mjs";
import {
  UNWRAP_DEPTH_EXCEEDED,
  gitSubcommandArguments,
  unwrappedCommandSegments,
} from "../../smith-git/scripts/lib/git-command-tokenizer.mjs";
import { nonFlagTokensAfterGh } from "./lib/gh-command.mjs";
import {
  READING_IS_NOT_LOADING,
  readGateTable,
  skillsAvailableInSession,
} from "./lib/skills-invoked.mjs";

const TARGET_FILE_KEYS = ["file_path", "relative_path"];
const SHELL_STRING_ARGUMENT =
  /(?:\b(?:ba|z|da|k)?sh\s+(?:[^\s'"]+\s+)*?-[a-zA-Z]*c[a-zA-Z]*|\beval)(?:\s+--)?\s+(?:'([^']*)'|"((?:[^"\\]|\\.)*)")/g;
const ESCAPE_IN_DOUBLE_QUOTES = /\\([$`"\\])/g;
const ESCAPE_IN_BACKTICKS = /\\([$`\\])/g;
const ESCAPE_SEQUENCE = /\\./g;
const SHELL_PUNCTUATION_BEFORE_A_WORD = /^[<>({!`$]+/;
const REDIRECTION_AFTER_A_WORD = /[<>].*$/;
const REDIRECTION_ALONE = /^(\d*[<>]|&>)/;
const SHELL_PUNCTUATION_AFTER_A_WORD = /[)`;"']+$/;
const HERE_DOCUMENT_OPERATOR =
  /<<(?!<)-?[ \t]*((?:'[^'\n]*'|"[^"\n]*"|\\.|\$\([^)\n]*\)|`[^`\n]*`|[^\s;&|()<>'"\\`])+)/y;
const REDIRECTION_OPERATOR = /&>>?|\d*(?:>>|>&|<&|<>|>\||<<<|[<>])/y;
const FILE_DESCRIPTOR_START = /^\d/;
const REDIRECTION_TARGET_END = /[\s;&|()<>]/;
const ASSIGNMENT_WORD = /^[A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]*\])?\+?=/;
const DELIMITER_START = /^['"\\A-Za-z_]/;
const DELIMITER_QUOTING = /['"\\]/g;
const OPENERS_IN_COMMANDS = [
  ["$(", "substitution"],
  ["<(", "substitution"],
  [">(", "substitution"],
  ["=(", "substitution"],
  ["${", "parameter"],
  ["`", "backticks"],
  ['"', "double quotes"],
  ["(", "parentheses"],
];
const OPENERS_IN_TEXT = OPENERS_IN_COMMANDS.filter(([opener]) => ["$(", "${", "`", '"'].includes(opener));
const HERE_DOCUMENT_BODY = "here-document body";
const CONTEXTS_WITH_LITERAL_APOSTROPHES = new Set(["double quotes", HERE_DOCUMENT_BODY]);
const CONTEXT_CLOSERS = {
  substitution: ")",
  parentheses: ")",
  parameter: "}",
  backticks: "`",
  "double quotes": '"',
};
const COMMAND_CONTEXTS = new Set(["command", "substitution", "parentheses"]);
const BODY_CONTEXTS = new Set(["substitution", "backticks", "parentheses"]);
const CHARACTER_BEFORE_A_WORD = /[\s;&|()]/;
const CHARACTER_BEFORE_A_COMMENT = /[\s;&|()<>]/;
const LEADING_ASSIGNED_SUBSTITUTION = /(^|[;&|]\s*|\n\s*)[A-Za-z_][A-Za-z0-9_]*=\$\([^)]*\)\s+/g;
const CONTROL_OPERATORS = new Set(["&&", "||", ";", "|", "&"]);
const DURATION_OR_NUMBER = /^\d+(\.\d+)?[a-z]?$/;
const WORDS_THAT_PRECEDE_A_COMMAND = new Set([
  "if",
  "while",
  "until",
  "then",
  "do",
  "else",
  "elif",
  "time",
  "timeout",
  "xargs",
  "exec",
  "rtk",
  "proxy",
  "gtimeout",
  "noglob",
  "builtin",
  "coproc",
  "command",
  "env",
  "nice",
  "nohup",
  "sudo",
]);
const UNSCANNED_COMMAND =
  "skill-load-gate: this command is wrapped too deeply to scan, so it cannot be shown " +
  "to hold no governed action (see smith-ctx-claude/skill-gate.json). " +
  "Approve only if it holds none, or run the inner command directly.";

function matches(pattern, text, flags) {
  try {
    return new RegExp(pattern, flags).test(text);
  } catch {
    return false;
  }
}

function targetFile(toolInput) {
  for (const key of TARGET_FILE_KEYS) {
    if (typeof toolInput[key] === "string") return toolInput[key];
  }
  return "";
}

function toolRuleApplies(rule, toolName, toolInput) {
  if (typeof rule.tool !== "string" || !matches(rule.tool, toolName)) return false;
  return typeof rule.path !== "string" || matches(rule.path, targetFile(toolInput), "i");
}

function bareWord(token) {
  if (REDIRECTION_ALONE.test(token)) return null;
  return token
    .replace(SHELL_PUNCTUATION_BEFORE_A_WORD, "")
    .replace(REDIRECTION_AFTER_A_WORD, "")
    .replace(SHELL_PUNCTUATION_AFTER_A_WORD, "");
}

function precedesACommand(word) {
  return (
    word === null ||
    word === "" ||
    word.startsWith("-") ||
    WORDS_THAT_PRECEDE_A_COMMAND.has(word) ||
    DURATION_OR_NUMBER.test(word) ||
    ASSIGNMENT_WORD.test(word)
  );
}

function invocationOf(program, tokens) {
  const words = tokens.map(bareWord);
  const position = words.findIndex((word) => !precedesACommand(word));
  if (position === -1 || basename(words[position]) !== program) return null;
  return [program, ...words.slice(position + 1).filter((word) => word !== null)];
}

function simpleCommands(tokens) {
  const commands = [[]];
  for (const token of tokens) {
    if (CONTROL_OPERATORS.has(token)) {
      commands.push([]);
      continue;
    }
    commands[commands.length - 1].push(token);
    if (token.endsWith(";")) commands.push([]);
  }
  return commands;
}

function invocationsOf(program, segments) {
  return segments
    .flatMap(simpleCommands)
    .map((tokens) => invocationOf(program, tokens))
    .filter((invocation) => invocation);
}

function subcommandOf(invocation) {
  if (invocation[0] === "git") {
    const parsed = gitSubcommandArguments(invocation);
    return parsed ? parsed.subcommand : null;
  }
  if (invocation[0] === "gh") return nonFlagTokensAfterGh(invocation).join(" ");
  return null;
}

function commandRuleApplies(rule, segments) {
  const command = rule.command;
  if (!command || !Array.isArray(command.subcommands)) return false;
  return invocationsOf(command.program, segments).some((invocation) => {
    const subcommand = subcommandOf(invocation);
    if (subcommand === null) return false;
    const governed = command.subcommands.some(
      (candidate) => subcommand === candidate || subcommand.startsWith(`${candidate} `),
    );
    if (!governed) return false;
    return (
      typeof command.argument !== "string" ||
      invocation.some((token) => matches(command.argument, token))
    );
  });
}

function opensSingleQuotedSpan(command, index) {
  return command[index] === "'" || command.startsWith("$'", index);
}

function singleQuotedSpanEnd(command, index) {
  if (command[index] === "'") return command.indexOf("'", index + 1);
  for (let position = index + 2; position < command.length; position += 1) {
    if (command[position] === "\\") position += 1;
    else if (command[position] === "'") return position;
  }
  return -1;
}

function singleQuotedSpanAsPlainQuotes(command, index, end) {
  if (command[index] === "'") return command.slice(index, end + 1);
  return `'${command.slice(index + 2, end).replace(ESCAPE_SEQUENCE, "")}'`;
}

function startsAComment(command, index, wordCharacterIndex) {
  if (command[index] !== "#" || wordCharacterIndex === index - 1) return false;
  return index === 0 || CHARACTER_BEFORE_A_COMMENT.test(command[index - 1]);
}

function hereDocumentAt(command, index) {
  if (command[index - 1] === "<") return null;
  HERE_DOCUMENT_OPERATOR.lastIndex = index;
  const match = HERE_DOCUMENT_OPERATOR.exec(command);
  if (!match || !DELIMITER_START.test(match[1])) return null;
  const delimiter = match[1].replace(DELIMITER_QUOTING, "");
  return { text: match[0], delimiter, expands: delimiter === match[1] };
}

function redirectionAt(command, index) {
  REDIRECTION_OPERATOR.lastIndex = index;
  const match = REDIRECTION_OPERATOR.exec(command);
  if (!match) return null;
  const startsAWord = index === 0 || CHARACTER_BEFORE_A_WORD.test(command[index - 1]);
  return FILE_DESCRIPTOR_START.test(match[0]) && !startsAWord ? null : match[0];
}

function hereDocumentBodies(command, start, documents) {
  const bodies = [];
  let position = start;
  for (const document of documents) {
    const bodyStart = position;
    let found = false;
    while (!found && position < command.length) {
      const lineEnd = command.indexOf("\n", position);
      const line = command.slice(position, lineEnd === -1 ? command.length : lineEnd);
      position = lineEnd === -1 ? command.length : lineEnd + 1;
      found = line.trim() === document.delimiter;
    }
    if (!found) return null;
    bodies.push({ ...document, body: command.slice(bodyStart, position) });
  }
  return { end: position, bodies };
}

function openerAt(command, index, context) {
  const openers = COMMAND_CONTEXTS.has(context) ? OPENERS_IN_COMMANDS : OPENERS_IN_TEXT;
  const startsAWord = index === 0 || CHARACTER_BEFORE_A_WORD.test(command[index - 1]);
  return (
    openers.find(([opener]) => command.startsWith(opener, index) && (opener !== "=(" || startsAWord)) ?? null
  );
}

function apostropheIsLiteralIn(contexts, apostrophesQuoteInParameters) {
  if (apostrophesQuoteInParameters && contexts[contexts.length - 1] === "parameter") return false;
  return CONTEXTS_WITH_LITERAL_APOSTROPHES.has(contexts.findLast((context) => context !== "parameter"));
}

function shellStructure(command, outermostContext = "command", apostrophesQuoteInParameters = false) {
  let text = "";
  const substitutions = [];
  const contexts = [outermostContext];
  const delimiters = [];
  let bodyStart = -1;
  let wordCharacterIndex = null;
  let redirectionTarget = null;
  const emit = (piece) => {
    if (bodyStart === -1 && !redirectionTarget?.started && !contexts.includes("parameter")) text += piece;
  };
  for (let index = 0; index < command.length; index += 1) {
    const context = contexts[contexts.length - 1];
    const character = command[index];
    const opener = openerAt(command, index, context);
    if (redirectionTarget) {
      if (!redirectionTarget.started && (character === " " || character === "\t")) continue;
      redirectionTarget.started = true;
      if (contexts.length === redirectionTarget.depth && REDIRECTION_TARGET_END.test(character)) {
        redirectionTarget = null;
      }
    }
    if (character === "\\") {
      emit(command.slice(index, index + 2));
      wordCharacterIndex = index + 1;
      index += 1;
    } else if (character === CONTEXT_CLOSERS[context]) {
      contexts.pop();
      if (context !== "parentheses") wordCharacterIndex = index;
      if (BODY_CONTEXTS.has(context) && !contexts.some((open) => BODY_CONTEXTS.has(open))) {
        const body = command.slice(bodyStart, index);
        substitutions.push(context === "backticks" ? body.replace(ESCAPE_IN_BACKTICKS, "$1") : body);
        bodyStart = -1;
      }
      emit(character);
    } else if (opener) {
      emit(opener[0]);
      contexts.push(opener[1]);
      if (BODY_CONTEXTS.has(opener[1]) && bodyStart === -1) bodyStart = index + opener[0].length;
      index += opener[0].length - 1;
    } else if (!apostropheIsLiteralIn(contexts, apostrophesQuoteInParameters) && opensSingleQuotedSpan(command, index)) {
      const end = singleQuotedSpanEnd(command, index);
      if (end === -1) {
        text += command.slice(index);
        break;
      }
      emit(singleQuotedSpanAsPlainQuotes(command, index, end));
      index = end;
    } else if (!COMMAND_CONTEXTS.has(context)) {
      emit(character);
    } else if (startsAComment(command, index, wordCharacterIndex)) {
      const lineEnd = command.indexOf("\n", index);
      index = (lineEnd === -1 ? command.length : lineEnd) - 1;
    } else {
      const hereDocument = hereDocumentAt(command, index);
      const redirection = hereDocument ? null : redirectionAt(command, index);
      if (hereDocument) {
        delimiters.push(hereDocument);
        emit(hereDocument.text);
        index += hereDocument.text.length - 1;
      } else if (redirection) {
        emit(" ");
        redirectionTarget = { depth: contexts.length, started: false };
        index += redirection.length - 1;
      } else if (character === "\n" && delimiters.length > 0) {
        emit("\n");
        const documents = hereDocumentBodies(command, index + 1, delimiters.splice(0));
        if (documents) {
          for (const { expands, body } of documents.bodies) {
            if (!expands) continue;
            substitutions.push(
              ...shellStructure(body, HERE_DOCUMENT_BODY, apostrophesQuoteInParameters).substitutions,
            );
          }
          index = documents.end - 1;
        }
      } else {
        emit(character);
      }
    }
  }
  if (bodyStart !== -1) substitutions.push(command.slice(bodyStart));
  return { text, substitutions };
}

function withoutLeadingAssignedSubstitutions(command) {
  return command.replace(LEADING_ASSIGNED_SUBSTITUTION, "$1");
}

function scansOf(command, apostrophesQuoteInParameters) {
  const { text, substitutions } = shellStructure(command, "command", apostrophesQuoteInParameters);
  const scansUnderTheSameReading = (inner) => scansOf(inner, apostrophesQuoteInParameters);
  return [
    unwrappedCommandSegments(withoutLeadingAssignedSubstitutions(text)),
    ...substitutions.flatMap(scansUnderTheSameReading),
    ...[...text.matchAll(SHELL_STRING_ARGUMENT)].flatMap(([, singleQuoted, doubleQuoted]) =>
      scansUnderTheSameReading(singleQuoted ?? doubleQuoted.replace(ESCAPE_IN_DOUBLE_QUOTES, "$1")),
    ),
  ];
}

function scansUnderEitherShellReading(command) {
  return [...scansOf(command, false), ...scansOf(command, true)];
}

function refusal(unmet) {
  const lines = unmet.map((rule) => `${rule.action} is governed by @${rule.skill}`);
  const skills = [...new Set(unmet.map((rule) => `@${rule.skill}`))].join(", ");
  return (
    `skill-load-gate: ${lines.join("; ")}, not loaded in this session. ` +
    `Load ${skills} with the Skill tool, then run the action again in a later message. ` +
    READING_IS_NOT_LOADING
  );
}

function decide(permissionDecision, permissionDecisionReason) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision, permissionDecisionReason },
    }) + "\n",
  );
}

async function main() {
  const input = readHookInput();
  if (!input || typeof input.tool_name !== "string") return;
  if (input.agent_id) return;
  if (typeof input.transcript_path !== "string") return;

  const table = readGateTable();
  if (!table) return;

  const toolInput = input.tool_input && typeof input.tool_input === "object" ? input.tool_input : {};
  let applicable;
  if (input.tool_name === "Bash") {
    if (typeof toolInput.command !== "string") return;
    const scans = scansUnderEitherShellReading(toolInput.command);
    if (scans.some((segments) => segments[UNWRAP_DEPTH_EXCEEDED])) {
      decide("ask", UNSCANNED_COMMAND);
      return;
    }
    const scanned = scans.flat();
    applicable = table.rules.filter((rule) => commandRuleApplies(rule, scanned));
  } else {
    applicable = table.rules.filter((rule) => toolRuleApplies(rule, input.tool_name, toolInput));
  }
  if (applicable.length === 0) return;

  const available = await skillsAvailableInSession(input.transcript_path);
  const unmet = applicable.filter(
    (rule) => typeof rule.skill !== "string" || !available.has(rule.skill.toLowerCase()),
  );
  if (unmet.length === 0) return;

  decide("deny", refusal(unmet));
}

main().catch(() => {});
