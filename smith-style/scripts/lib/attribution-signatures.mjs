import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { globalOptionKind } from "../../../smith-git/scripts/lib/git-command-tokenizer.mjs";

const REGISTRY = JSON.parse(
  readFileSync(join(dirname(fileURLToPath(import.meta.url)), "..", "attribution-signatures.json"), "utf-8"),
);
const LONG_FLAG = /^--[^=]+/;

function isFlag(token) {
  return token.startsWith("-") && token !== "-" && token !== "--";
}

function flagParts(token) {
  if (!LONG_FLAG.test(token)) return { name: token, attached: undefined };
  const equalsIndex = token.indexOf("=");
  return equalsIndex === -1
    ? { name: token, attached: undefined }
    : { name: token.slice(0, equalsIndex), attached: token.slice(equalsIndex + 1) };
}

function mayBeFlag(token, flag) {
  if (!isFlag(token)) return false;
  if (flag.startsWith("--")) return token === flag || token.startsWith(`${flag}=`);
  return !token.startsWith("--") && token.slice(1).includes(flag[1]);
}

function valueFlagsOf(entry) {
  return new Set([...(entry.globalValueFlags || []), ...entry.signatures.flatMap((signature) => signature.valueFlags || [])]);
}

function positionalWords(entry, args) {
  if (entry.program === "git") {
    let index = 0;
    while (index < args.length) {
      const kind = globalOptionKind(args[index]);
      if (kind === "not-an-option") break;
      index += kind === "takes-value" ? 2 : 1;
    }
    return args.slice(index, index + 1);
  }
  const valueFlags = valueFlagsOf(entry);
  const words = [];
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === "--") break;
    if (valueFlags.has(args[index])) index += 1;
    else if (!isFlag(args[index])) words.push(args[index]);
  }
  return words;
}

function startsWithWords(words, expected) {
  return expected.every((word, index) => words[index] === word);
}

function coveredEntry(entry, args, recognizers) {
  const words = positionalWords(entry, args);
  return entry.covered.find((covered) => {
    if (!startsWithWords(words, covered.words)) return false;
    if (covered.recognizer) {
      const recognize = recognizers[covered.recognizer];
      return recognize ? recognize([entry.program, ...args]) : true;
    }
    if (covered.whenAnyFlag) return args.some((token) => covered.whenAnyFlag.some((flag) => mayBeFlag(token, flag)));
    return true;
  });
}

function afterGlobalFlags(entry, args) {
  const flags = new Set(entry.globalFlags || []);
  const valueFlags = new Set(entry.globalValueFlags || []);
  let index = 0;
  while (index < args.length && isFlag(args[index])) {
    if (flags.has(args[index])) index += 1;
    else if (valueFlags.has(args[index]) && args[index + 1] !== undefined) index += 2;
    else return null;
  }
  return args.slice(index);
}

function signatureMatch(signature, rest) {
  if (!startsWithWords(rest, signature.words)) return null;
  const tokens = rest.slice(signature.words.length);
  const payloadFlags = new Set(signature.payload ? signature.payload.flags : []);
  const valueFlags = new Set(signature.valueFlags || []);
  const flags = new Set(signature.flags || []);
  const present = new Set();
  const payloadValues = [];
  let positionals = 0;
  let afterSeparator = false;
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (afterSeparator || !isFlag(token)) {
      if (token === "--" && !afterSeparator) afterSeparator = true;
      else positionals += 1;
      continue;
    }
    const { name, attached } = flagParts(token);
    if (payloadFlags.has(name) || valueFlags.has(name)) {
      const value = attached ?? tokens[(index += 1)];
      if (value === undefined) return null;
      if (payloadFlags.has(name)) payloadValues.push(value);
    } else if (!flags.has(name) || attached !== undefined) {
      return null;
    }
    present.add(name);
  }
  if (signature.positionals !== "any" && positionals > signature.positionals) return null;
  if (!(signature.required || []).every((group) => group.some((flag) => present.has(flag)))) return null;
  if (payloadValues.length !== (signature.payload ? 1 : 0)) return null;
  return { payload: signature.payload ? { from: signature.payload.from, value: payloadValues[0] } : null };
}

export function classifyCommand(tokens, recognizers = {}) {
  const entry = REGISTRY.commands.find((candidate) => candidate.program === tokens[0]);
  if (!entry) return null;
  const args = tokens.slice(1);
  const covered = coveredEntry(entry, args, recognizers);
  if (!covered) return null;
  const subject = [entry.program, ...covered.words].join(" ");
  const unmatched = { subject, unmatched: true, hint: covered.hint };
  const rest = afterGlobalFlags(entry, args);
  if (!rest) return unmatched;
  for (const signature of entry.signatures.filter((candidate) => startsWithWords(candidate.words, covered.words))) {
    const match = signatureMatch(signature, rest);
    if (match) return { subject, ...match };
  }
  return unmatched;
}

export function classifyTool(toolName, toolInput) {
  const entry = REGISTRY.tools.find((candidate) => toolName === candidate.name || toolName.endsWith(`__${candidate.name}`));
  if (!entry) return null;
  const input = toolInput && typeof toolInput === "object" ? toolInput : {};
  const fields = new Set(entry.fields);
  const value = input[entry.payload.field];
  if (Object.keys(input).some((key) => !fields.has(key)) || typeof value !== "string") {
    return { subject: entry.name, unmatched: true };
  }
  return { subject: entry.name, payload: { from: "field", value } };
}
