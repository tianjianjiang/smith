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
  let parenDepth = 0;
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
    if (char === "(") {
      parenDepth += 1;
      current += char;
      continue;
    }
    if (char === ")") {
      if (parenDepth > 0) parenDepth -= 1;
      current += char;
      continue;
    }
    if (parenDepth === 0 && COMMAND_SEGMENT_SEPARATOR_CHAR.test(char)) {
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

const WRAPPER_VALUE_FLAGS = {
  sudo: new Set([
    "-u",
    "--user",
    "-g",
    "--group",
    "-h",
    "--host",
    "-p",
    "--prompt",
    "-C",
    "-D",
    "--chdir",
    "-R",
    "-T",
    "-U",
  ]),
  nice: new Set(["-n", "--adjustment"]),
  time: new Set(["-o", "-f", "--format"]),
};

function wrapperTargetIndex(tokens, valueFlags) {
  let index = 1;
  while (index < tokens.length && tokens[index].startsWith("-")) {
    index += valueFlags && valueFlags.has(tokens[index]) ? 2 : 1;
  }
  return index;
}

const ENV_VALUE_FLAGS = new Set(["-u", "--unset", "-C", "--chdir", "-a", "--argv0"]);
const ENV_SPLIT_STRING_FLAGS = new Set(["-S", "--split-string"]);

function splitStringWords(value) {
  return value.split(WHITESPACE).filter(Boolean);
}

function envWrapperRemainder(tokens) {
  let index = 1;
  while (index < tokens.length) {
    const token = tokens[index];
    if (ENV_SPLIT_STRING_FLAGS.has(token)) {
      const value = tokens[index + 1];
      if (typeof value !== "string") return null;
      const words = splitStringWords(value);
      return words.length > 0 ? [...words, ...tokens.slice(index + 2)] : null;
    }
    if (token.startsWith("-S") && token.length > 2 && !token.startsWith("--")) {
      const words = splitStringWords(token.slice(2));
      return words.length > 0 ? [...words, ...tokens.slice(index + 1)] : null;
    }
    if (ENV_VALUE_FLAGS.has(token)) {
      index += 2;
      continue;
    }
    if (token.startsWith("-") || ENV_ASSIGNMENT.test(token)) {
      index += 1;
      continue;
    }
    break;
  }
  return index < tokens.length ? tokens.slice(index) : null;
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

function parenGroupInner(rawSegment) {
  const trimmed = rawSegment.trim();
  if (!trimmed.startsWith("(")) return null;
  let quoteChar = null;
  let parenDepth = 0;
  for (let i = 0; i < trimmed.length; i += 1) {
    const char = trimmed[i];
    if (char === ESCAPE_CHAR && quoteChar !== "'" && i + 1 < trimmed.length) {
      i += 1;
      continue;
    }
    if (quoteChar) {
      if (char === quoteChar) quoteChar = null;
      continue;
    }
    if (char === "'" || char === '"') {
      quoteChar = char;
      continue;
    }
    if (char === "(") {
      parenDepth += 1;
      continue;
    }
    if (char === ")") {
      parenDepth -= 1;
      if (parenDepth === 0) return i === trimmed.length - 1 ? trimmed.slice(1, i) : null;
    }
  }
  return null;
}

function unwrapTokenWrappers(tokens, depth, exceeded) {
  let current = tokens;
  let currentDepth = depth;
  while (true) {
    if (currentDepth >= MAX_UNWRAP_DEPTH) {
      exceeded.flag = true;
      return null;
    }
    const head = basename(current[0]);
    if (head === "command") {
      const targetIndex = commandBuiltinTargetIndex(current);
      if (targetIndex < current.length) {
        current = [basename(current[targetIndex]), ...current.slice(targetIndex + 1)];
        currentDepth += 1;
        continue;
      }
    }
    if (head === "nohup" && current.length > 1) {
      current = [basename(current[1]), ...current.slice(2)];
      currentDepth += 1;
      continue;
    }
    if (Object.hasOwn(WRAPPER_VALUE_FLAGS, head)) {
      const targetIndex = wrapperTargetIndex(current, WRAPPER_VALUE_FLAGS[head]);
      if (targetIndex < current.length) {
        current = [basename(current[targetIndex]), ...current.slice(targetIndex + 1)];
        currentDepth += 1;
        continue;
      }
    }
    if (head === "env") {
      const remainder = envWrapperRemainder(current);
      if (remainder !== null) {
        current = [basename(remainder[0]), ...remainder.slice(1)];
        currentDepth += 1;
        continue;
      }
    }
    return { tokens: current, depth: currentDepth };
  }
}

export function unwrappedCommandSegments(command, depth = 0, exceeded = { flag: false }) {
  if (depth >= MAX_UNWRAP_DEPTH) {
    exceeded.flag = true;
    return [];
  }
  const segments = [];
  for (const rawSegment of segmentsRespectingQuotes(command)) {
    const inner = parenGroupInner(rawSegment);
    if (inner !== null) {
      segments.push(...unwrappedCommandSegments(inner, depth + 1, exceeded));
      continue;
    }
    const tokens = withoutLeadingEnvAssignments(tokensRespectingQuotes(rawSegment));
    if (tokens.length === 0) continue;
    const unwrapped = unwrapTokenWrappers(tokens, depth, exceeded);
    if (unwrapped === null) continue;
    const finalTokens = unwrapped.tokens;
    const tokenDepth = unwrapped.depth;
    const head = basename(finalTokens[0]);
    if (head === "eval" && finalTokens.length > 1) {
      segments.push(
        ...unwrappedCommandSegments(finalTokens.slice(1).join(" "), tokenDepth + 1, exceeded),
      );
      continue;
    }
    if (SHELL_C_INVOCATIONS.has(head)) {
      const cIndex = shellDashCIndex(finalTokens);
      if (cIndex !== -1 && typeof finalTokens[cIndex + 1] === "string") {
        segments.push(...unwrappedCommandSegments(finalTokens[cIndex + 1], tokenDepth + 1, exceeded));
        continue;
      }
    }
    segments.push([head, ...finalTokens.slice(1)]);
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
