const COMMAND_SEGMENT_SEPARATOR_CHAR = /[;&|\n\r\f\v]/;
export const WHITESPACE = /\s+/;
export const ENV_ASSIGNMENT = /^[A-Za-z_][A-Za-z0-9_]*=/;
const ESCAPE_CHAR = "\\";

export const GLOBAL_OPTIONS_TAKING_A_VALUE = new Set([
  "-C",
  "-c",
  "--git-dir",
  "--work-tree",
  "--namespace",
  "--exec-path",
  "--config-env",
]);

export function withoutLeadingEnvAssignments(tokens) {
  let index = 0;
  while (index < tokens.length && ENV_ASSIGNMENT.test(tokens[index])) index += 1;
  return tokens.slice(index);
}

export function globalOptionKind(token) {
  if (GLOBAL_OPTIONS_TAKING_A_VALUE.has(token)) return "takes-value";
  if (token.startsWith("-")) return "standalone";
  return "not-an-option";
}

function segmentsRespectingQuotes(command) {
  const segments = [];
  let current = "";
  let quoteChar = null;
  for (let i = 0; i < command.length; i += 1) {
    const char = command[i];
    if (char === ESCAPE_CHAR && quoteChar !== "'" && i + 1 < command.length) {
      const next = command[i + 1];
      if (next !== "\n") current += char + next;
      i += 1;
      continue;
    }
    if (quoteChar) {
      current += char;
      if (char === quoteChar) quoteChar = null;
      continue;
    }
    if (char === "'" || char === '"') {
      quoteChar = char;
      current += char;
      continue;
    }
    if (COMMAND_SEGMENT_SEPARATOR_CHAR.test(char)) {
      segments.push(current);
      current = "";
      continue;
    }
    current += char;
  }
  segments.push(current);
  return segments;
}

function tokensRespectingQuotes(segment) {
  const tokens = [];
  let current = "";
  let quoteChar = null;
  let inToken = false;
  for (let i = 0; i < segment.length; i += 1) {
    const char = segment[i];
    if (char === ESCAPE_CHAR && quoteChar !== "'" && i + 1 < segment.length) {
      current += segment[i + 1];
      inToken = true;
      i += 1;
      continue;
    }
    if (quoteChar) {
      if (char === quoteChar) quoteChar = null;
      else current += char;
      inToken = true;
      continue;
    }
    if (char === "'" || char === '"') {
      quoteChar = char;
      inToken = true;
      continue;
    }
    if (WHITESPACE.test(char)) {
      if (inToken) {
        tokens.push(current);
        current = "";
        inToken = false;
      }
      continue;
    }
    current += char;
    inToken = true;
  }
  if (inToken) tokens.push(current);
  return tokens;
}

export function commandSegments(command) {
  return segmentsRespectingQuotes(command)
    .map((segment) => withoutLeadingEnvAssignments(tokensRespectingQuotes(segment)))
    .filter((tokens) => tokens.length > 0);
}

const SHELL_C_INVOCATIONS = new Set(["sh", "bash", "zsh", "ksh"]);
const MAX_UNWRAP_DEPTH = 8;

function basename(token) {
  const parts = token.split("/");
  return parts[parts.length - 1];
}

function commandBuiltinTargetIndex(tokens) {
  let index = 1;
  while (index < tokens.length && tokens[index].startsWith("-") && tokens[index] !== "-c") {
    index += 1;
  }
  return index;
}

const SHELL_OPTIONS_TAKING_A_VALUE = new Set(["-o", "-O", "+o", "+O"]);

function isShortDashCFlag(token) {
  return token.length >= 2 && token[0] === "-" && token[1] !== "-" && token.endsWith("c");
}

function shellDashCIndex(tokens) {
  let index = 1;
  while (index < tokens.length && (tokens[index].startsWith("-") || tokens[index].startsWith("+"))) {
    if (isShortDashCFlag(tokens[index])) return index;
    if (SHELL_OPTIONS_TAKING_A_VALUE.has(tokens[index])) {
      index += 2;
      continue;
    }
    index += 1;
  }
  return -1;
}

export const UNWRAP_DEPTH_EXCEEDED = Symbol("unwrap-depth-exceeded");

export function unwrappedCommandSegments(command, depth = 0, exceeded = { flag: false }) {
  if (depth >= MAX_UNWRAP_DEPTH) {
    exceeded.flag = true;
    return [];
  }
  const segments = [];
  for (const tokens of commandSegments(command)) {
    const head = basename(tokens[0]);
    if (head === "eval" && tokens.length > 1) {
      segments.push(
        ...unwrappedCommandSegments(tokens.slice(1).join(" "), depth + 1, exceeded),
      );
      continue;
    }
    if (SHELL_C_INVOCATIONS.has(head)) {
      const cIndex = shellDashCIndex(tokens);
      if (cIndex !== -1 && typeof tokens[cIndex + 1] === "string") {
        segments.push(...unwrappedCommandSegments(tokens[cIndex + 1], depth + 1, exceeded));
        continue;
      }
    }
    if (head === "command") {
      const targetIndex = commandBuiltinTargetIndex(tokens);
      if (targetIndex < tokens.length) {
        segments.push([basename(tokens[targetIndex]), ...tokens.slice(targetIndex + 1)]);
        continue;
      }
    }
    segments.push([head, ...tokens.slice(1)]);
  }
  if (exceeded.flag) segments[UNWRAP_DEPTH_EXCEEDED] = true;
  return segments;
}

export function gitSubcommandArguments(tokens) {
  if (tokens[0] !== "git") return null;
  let index = 1;
  while (index < tokens.length) {
    const kind = globalOptionKind(tokens[index]);
    if (kind === "takes-value") index += 2;
    else if (kind === "standalone") index += 1;
    else break;
  }
  if (index >= tokens.length) return null;
  return { subcommand: tokens[index], args: tokens.slice(index + 1) };
}
