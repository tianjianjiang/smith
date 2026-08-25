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
