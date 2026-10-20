import { lstatSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { ghNonBodyValueFlags, isCloseOrReopen, nonFlagTokensAfterGh } from "./gh-command.mjs";
import { ANY_KEY, CONTENT, REFERENCE, SCALAR, STRUCTURAL, TARGET, URL_REFERENCE, WRITE_SIGNATURES } from "./write-signatures.mjs";

const UUID_SHAPE = /^[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12}$/i;
const URL_SHAPE = /^[a-z][a-z0-9+.-]*:\/\/\S+$/i;

const BODY_VALUE_FLAGS = new Set(["--body", "-b"]);
const CLOSE_COMMENT_FLAGS = new Set(["--comment", "-c"]);
const BODY_FILE_FLAGS = new Set(["--body-file", "-F"]);
const API_FIELD_FLAGS = new Set(["-f", "--raw-field", "-F", "--field"]);
const API_FILE_FIELD_FLAGS = new Set(["-F", "--field"]);
const SHELL_EXPANSION = /[$`*?[~{]/;
const UNQUOTED_GLOB = new Set(["*", "?", "[", "{"]);
const ASCII_WORD_CHAR = /[A-Za-z0-9]/;
const QUOTED_HEREDOC_SUBSTITUTION = /^\$\(cat <<(-?)(['"])(\w+)\2\n([\s\S]*?)\n\3\s*\)$/;

export function contentLeaves(leaves, targets) {
  return leaves.filter((leaf) => !targets.has(leaf));
}

export function normalizeText(text) {
  return text.replace(/\s+/g, " ").trim();
}

function compactUuid(text) {
  return text.toLowerCase().replace(/-/g, "");
}

function includesAsWhole(text, part) {
  const guardStart = ASCII_WORD_CHAR.test(part[0]);
  const guardEnd = ASCII_WORD_CHAR.test(part[part.length - 1]);
  for (let index = text.indexOf(part); index !== -1; index = text.indexOf(part, index + 1)) {
    const before = text[index - 1];
    const after = text[index + part.length];
    const startsClean = !guardStart || before === undefined || !ASCII_WORD_CHAR.test(before);
    const endsClean = !guardEnd || after === undefined || !ASCII_WORD_CHAR.test(after);
    if (startsClean && endsClean) return true;
  }
  return false;
}

export function previewIncludes(previewText, leaf) {
  if (includesAsWhole(previewText, leaf)) return true;
  return UUID_SHAPE.test(leaf) && includesAsWhole(compactUuid(previewText), compactUuid(leaf));
}

function deletesText(value) {
  const replacement = typeof value.new_str === "string" ? value.new_str.trim() : "";
  return typeof value.old_str === "string" && replacement === "";
}

function clearsValue(value) {
  const blankText = typeof value === "string" && normalizeText(value) === "";
  const emptyList = Array.isArray(value) && value.length === 0;
  return value === null || value === false || blankText || emptyList;
}

function collectStringLeaves(value, leaves, key) {
  if (clearsValue(value)) {
    if (key !== undefined) leaves.push(key);
    return;
  }
  if (typeof value === "string") {
    const text = normalizeText(value);
    if (text) leaves.push(text);
    return;
  }
  if (typeof value === "number") {
    leaves.push(String(value));
    return;
  }
  if (value === true && key !== undefined) {
    leaves.push(key);
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) collectStringLeaves(item, leaves, key);
    return;
  }
  if (value && typeof value === "object") {
    const deletion = deletesText(value);
    if (deletion) collectStringLeaves(value.old_str, leaves, "old_str");
    for (const [childKey, item] of Object.entries(value)) {
      const locator = childKey === "old_str" || (deletion && childKey === "new_str");
      if (!locator) collectStringLeaves(item, leaves, childKey);
    }
  }
}

function collectByRole(value, role, payload, path, key) {
  if (role === STRUCTURAL || value === undefined) return;
  if (role === URL_REFERENCE) {
    collectByRole(value, typeof value === "string" && URL_SHAPE.test(value.trim()) ? REFERENCE : CONTENT, payload, path, key);
    return;
  }
  if (role === REFERENCE) {
    if (clearsValue(value)) collectByRole(value, CONTENT, payload, path, key);
    else payload.opaque = payload.opaque || `the field '${path}' points to content the call does not carry`;
    return;
  }
  const leaves = [];
  collectStringLeaves(value, leaves, key);
  payload.leaves.push(...leaves);
  if (role === TARGET) leaves.forEach((leaf) => payload.targets.add(leaf));
}

function collectBySignature(value, spec, payload, path, key) {
  if (typeof spec === "string") {
    collectByRole(value, spec, payload, path, key);
    return;
  }
  if (clearsValue(value)) {
    collectByRole(value, SCALAR in spec ? spec[SCALAR] : CONTENT, payload, path, key);
    return;
  }
  if (Array.isArray(value)) {
    value.forEach((item, index) => collectBySignature(item, spec, payload, `${path}[${index}]`, key));
    return;
  }
  if (!value || typeof value !== "object") {
    if (SCALAR in spec) collectByRole(value, spec[SCALAR], payload, path, key);
    else if (value !== undefined) payload.opaque = payload.opaque || `the field '${path}' has a shape the guard does not know`;
    return;
  }
  for (const [childKey, item] of Object.entries(value)) {
    const childSpec = childKey in spec ? spec[childKey] : spec[ANY_KEY];
    const childPath = path ? `${path}.${childKey}` : childKey;
    if (childSpec === undefined) {
      payload.opaque = payload.opaque || `the field '${childPath}', which the guard has no role for`;
      continue;
    }
    collectBySignature(item, childSpec, payload, childPath, childKey);
  }
}

export function mcpPayload(toolName, toolInput) {
  const payload = { leaves: [], targets: new Set(), opaque: null };
  const signature = WRITE_SIGNATURES[toolName];
  if (!signature) {
    payload.opaque = "the guard has no declared signature for this tool";
    return payload;
  }
  collectBySignature(toolInput || {}, signature, payload, "");
  return payload;
}

function readBodyFile(path, cwd) {
  if (!path || path === "-") return null;
  try {
    const fullPath = resolve(cwd || process.cwd(), path);
    return lstatSync(fullPath).isFile() ? readFileSync(fullPath, "utf-8") : null;
  } catch {
    return null;
  }
}

function addBody(payload, text) {
  const normalized = normalizeText(text);
  if (normalized) payload.leaves.push(normalized);
}

export function commandExpands(command) {
  let quote = null;
  for (let index = 0; index < command.length; index += 1) {
    const char = command[index];
    if (quote === "'") {
      if (char === "'") quote = null;
      continue;
    }
    if (char === "\\") {
      index += 1;
      continue;
    }
    if (char === "$" || char === "`") return true;
    if (quote === null && (UNQUOTED_GLOB.has(char) || (char === "~" && /(^|[\s=:])$/.test(command.slice(0, index))))) {
      return true;
    }
    if (char === '"') quote = quote === '"' ? null : '"';
    else if (char === "'" && quote === null) quote = "'";
  }
  return false;
}

function endsHeredocEarly(body, delimiter) {
  return body.split("\n").some((line) => line.replace(/^\t+/, "") === delimiter);
}

function isExpanded(payload, text) {
  return payload.expands && SHELL_EXPANSION.test(text);
}

function addShellBody(payload, token) {
  const heredoc = QUOTED_HEREDOC_SUBSTITUTION.exec(token);
  if (heredoc && endsHeredocEarly(heredoc[4], heredoc[3])) {
    payload.opaque = "a heredoc whose delimiter line appears more than once; pass it with --body-file";
    return;
  }
  if (heredoc) {
    addBody(payload, heredoc[1] ? heredoc[4].replace(/^\t+/gm, "") : heredoc[4]);
    return;
  }
  if (isExpanded(payload, token)) {
    payload.opaque = "a body or target built by shell expansion; pass it with --body-file";
    return;
  }
  addBody(payload, token);
}

function addBodyFile(payload, path, cwd) {
  if (path === undefined) {
    payload.opaque = "a body-file flag with no file named after it";
    return;
  }
  if (isExpanded(payload, path)) {
    payload.opaque = "a body file path built by shell expansion";
    return;
  }
  payload.readsFile = true;
  const text = readBodyFile(path, cwd);
  if (text === null) {
    payload.opaque = `body file '${path}' cannot be read by the hook`;
    return;
  }
  addBody(payload, text);
}

function collectApiFields(tokens, payload, cwd) {
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (token === "--input") {
      payload.opaque = "request body passed with --input";
      index += 1;
      continue;
    }
    if (!API_FIELD_FLAGS.has(token)) continue;
    const field = tokens[index + 1] || "";
    index += 1;
    const equalsIndex = field.indexOf("=");
    const value = equalsIndex === -1 ? "" : field.slice(equalsIndex + 1);
    if (API_FILE_FIELD_FLAGS.has(token) && value.startsWith("@")) {
      addBodyFile(payload, value.slice(1), cwd);
      continue;
    }
    addShellBody(payload, value);
  }
}

function collectBodyFlags(tokens, payload, cwd) {
  const subcommand = nonFlagTokensAfterGh(tokens)[1];
  const textFlags = isCloseOrReopen(subcommand) ? new Set([...BODY_VALUE_FLAGS, ...CLOSE_COMMENT_FLAGS]) : BODY_VALUE_FLAGS;
  const otherValueFlags = ghNonBodyValueFlags(subcommand);
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    const next = tokens[index + 1];
    if (textFlags.has(token)) {
      if (next !== undefined) addShellBody(payload, next);
      index += 1;
      continue;
    }
    if (BODY_FILE_FLAGS.has(token)) {
      addBodyFile(payload, next, cwd);
      index += 1;
      continue;
    }
    if (otherValueFlags.has(token)) index += 1;
  }
}

export function ghPayload(tokens, cwd, targets, expands) {
  const payload = { leaves: [], opaque: null, expands };
  if (nonFlagTokensAfterGh(tokens)[0] === "api") {
    collectApiFields(tokens, payload, cwd);
  } else {
    collectBodyFlags(tokens, payload, cwd);
  }
  if (targets.some((target) => isExpanded(payload, target))) {
    payload.opaque = "a target built by shell expansion";
  }
  const targetLeaves = targets.map(normalizeText).filter(Boolean);
  payload.leaves.push(...targetLeaves);
  payload.targets = new Set(targetLeaves);
  return payload;
}
