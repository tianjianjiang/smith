#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { existsSync, lstatSync, readFileSync, readdirSync, realpathSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join, relative, resolve, sep } from "node:path";

const MANIFEST_NAME = "hidden-reads.json";
const SCAN_FILES = new Set(["select.mjs", MANIFEST_NAME]);
const RUNNER_FILES = new Set(["run.sh", "run-affected.sh", ...SCAN_FILES]);
const SHARED_HELPER_FOLDER = "lib";
const TEST_SUFFIX = ".test.sh";
const FULL_SUITE_EXIT = 3;
const TOOLING_FOLDER = realpathSync(dirname(fileURLToPath(import.meta.url)));

const SHELL_SELF_DIR = String.raw`\$\(\s*dirname\s+(?:--\s+)?["']?\$\{?(?:0|BASH_SOURCE(?:\[0\])?)\}?["']?\s*\)`;
const SHELL_SELF_DIR_TRIMMED = String.raw`\$\{(?:0|BASH_SOURCE(?:\[0\])?)[%#:/^,][^}]*\}`;
const SHELL_ASSIGNMENT = /(?:^|[\s;{(&|])(?:(?:export|local|readonly|declare|typeset)(?:[ \t]+-[A-Za-z]+)*[ \t]+)?([A-Za-z_][A-Za-z0-9_]*)=/g;
const SHELL_SELF_TOKEN = /\$0(?![0-9])|\$\{0[^}]*\}|\bBASH_SOURCE\b/g;
const SHELL_SOURCE_BEFORE = /(?:^|[\s;&|{(])(?:\.|source)\s+["']?$/;
const SHELL_CALLER_PATH = /\$0(?![0-9])|\$\{0[^}]*\}/;
const SHELL_BASENAME_BEFORE = /\bbasename\s+(?:--\s+)?["']?$/;
const SHELL_PATH = /^\/[A-Za-z0-9._@+-]*(?:\/[A-Za-z0-9._@+-]*)*/;
const SHELL_WORD = /[A-Za-z0-9._@+-]/;
const SHELL_DYNAMIC = /[$`{]/;
const SHELL_WILDCARD = /[*?[]/;
const SHELL_WORD_REST = /^[^\s;|&)]*/;
const JS_SELF_DIR = String.raw`(?:(?:[\w$]+\.)?dirname\(\s*(?:(?:[\w$]+\.)?fileURLToPath\(\s*import\.meta\.url\s*\)|import\.meta\.filename|__filename)\s*\)|import\.meta\.dirname|\b__dirname\b)`;
const JS_SELF_DIR_VARIABLE = new RegExp(String.raw`\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*${JS_SELF_DIR}\s*(?:;|(?=\r?\n|$))`, "g");
const JS_SPECIFIERS = [
  /\bfrom\s*["'`]([^"'`\n]+)["'`]/g,
  /\bimport\s*\(\s*["'`]([^"'`\n]+)["'`]\s*(?:,[^)]*)?\)/g,
  /(?:^|[;\s])import\s*["']([^"'\n]+)["']/g,
  /\brequire\s*\(\s*["'`]([^"'`\n]+)["'`]\s*\)/g,
  /\bimport\.meta\.resolve\s*\(\s*["'`]([^"'`\n]+)["'`]\s*\)/g,
];
const JS_SELF_TOKEN = /\bimport\.meta\.(?:url|filename|dirname|resolve)\b|\b__(?:file|dir)name\b/g;
const JS_MAIN_GUARD = /import\.meta\.url\s*[!=]==|[!=]==\s*import\.meta\.url/g;
const JS_URL = /\bnew\s+URL\s*\(\s*["']([^"'\n]*)["']\s*,\s*import\.meta\.url\s*\)/g;
const URL_SCHEME = /^[A-Za-z][A-Za-z0-9+.-]*:/;
const FILE_EXTENSION = /\.[A-Za-z0-9]+$/;
const JS_PATH_CALL_BEFORE = /\b(resolve|join)\(\s*$/;
const JS_STRING_LITERAL = /^(["'])([^"'\n]*)\1$/;
const JS_EXTENSIONS = [".mjs", ".js", ".cjs"];
const OTHER_CODE_EXTENSIONS = [".py", ".ts", ".mts", ".cts", ".tsx", ".jsx", ".rb", ".pl", ".php", ".lua", ".jq", ".awk", ".bash", ".zsh"];

class FullSuite extends Error {}

function escapeForPattern(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function isGlob(entry) {
  return /[*?]/.test(entry);
}

function globPattern(glob) {
  let source = "";
  for (let index = 0; index < glob.length; index += 1) {
    const character = glob[index];
    if (character === "*" && glob[index + 1] === "*") {
      const followedBySlash = glob[index + 2] === "/";
      source += followedBySlash ? "(?:.*/)?" : ".*";
      index += followedBySlash ? 2 : 1;
    } else if (character === "*") {
      source += "[^/]*";
    } else if (character === "?") {
      source += "[^/]";
    } else {
      source += escapeForPattern(character);
    }
  }
  return new RegExp(`^${source}$`);
}

function statOf(path) {
  try {
    return statSync(path);
  } catch {
    return undefined;
  }
}

function isRegularFile(path) {
  return statOf(path)?.isFile() === true;
}

function isDirectory(path) {
  return statOf(path)?.isDirectory() === true;
}

function isRepositoryRelative(entry) {
  return entry !== "" && !entry.startsWith("/") && !entry.split("/").includes("..");
}

function readManifest(root, files) {
  const path = join(TOOLING_FOLDER, MANIFEST_NAME);
  const shown = relative(root, path);
  if (!existsSync(path)) throw new FullSuite(`${shown} is missing`);
  let data;
  try {
    data = JSON.parse(readFileSync(path, "utf-8"));
  } catch (error) {
    throw new FullSuite(`${shown} is not valid JSON: ${error.message}`);
  }
  if (data === null || typeof data !== "object" || Array.isArray(data)) {
    throw new FullSuite(`${shown} must be an object from a file to its list of dependencies`);
  }
  const manifest = new Map();
  for (const [key, entries] of Object.entries(data)) {
    if (!isRepositoryRelative(key) || !isRegularFile(join(root, key))) {
      throw new FullSuite(`${shown} names ${key}, which is not a file in the repository`);
    }
    if (!Array.isArray(entries) || !entries.every((entry) => typeof entry === "string" && isRepositoryRelative(entry))) {
      throw new FullSuite(`${shown} must list ${key}'s dependencies as repository-relative paths or globs`);
    }
    for (const entry of entries) {
      if (!isGlob(entry)) {
        if (!isRegularFile(join(root, entry))) {
          throw new FullSuite(`${shown} lists ${entry} for ${key}, which is not a file in the repository`);
        }
        continue;
      }
      const pattern = globPattern(entry);
      if (!files().some((file) => pattern.test(file))) {
        throw new FullSuite(`${shown} lists the glob ${entry} for ${key}, which matches no file`);
      }
    }
    manifest.set(key, entries);
  }
  return manifest;
}

function masked(text, spans) {
  let result = text;
  for (const [start, end] of spans) result = result.slice(0, start) + " ".repeat(end - start) + result.slice(end);
  return result;
}

const SHELL_COMMENT_LINE = /^[ \t]*#/;

function withoutLeadingCommentLines(text) {
  const comments = [];
  let start = 0;
  for (const line of text.split("\n")) {
    if (SHELL_COMMENT_LINE.test(line)) comments.push([start, start + line.length]);
    else if (line.trim() !== "") break;
    start += line.length + 1;
  }
  return masked(text, comments);
}

function shellWordEnd(text, start) {
  const stack = [];
  for (let index = start; index < text.length; index += 1) {
    const character = text[index];
    const context = stack[stack.length - 1];
    if (context === "'") {
      if (character === "'") stack.pop();
    } else if (context === "`") {
      if (character === "`") stack.pop();
    } else if (character === "\\") {
      index += 1;
    } else if (context === '"') {
      if (character === '"') stack.pop();
      else if (character === "`") stack.push("`");
      else if (character === "$" && text[index + 1] === "(") {
        stack.push("(");
        index += 1;
      }
    } else if (context === "(") {
      if (character === ")") stack.pop();
      else if (character === "(" || character === '"' || character === "'" || character === "`") stack.push(character);
    } else if (/[\s;&|)]/.test(character)) {
      return index;
    } else if (character === '"' || character === "'" || character === "`") {
      stack.push(character);
    } else if (character === "$" && text[index + 1] === "(") {
      stack.push("(");
      index += 1;
    }
  }
  return text.length;
}

const PATH_COMMANDS = new Set(["cd", "dirname", "realpath", "readlink", "echo", "printf"]);
const SHELL_COMMAND_PREFIX = /^(?:[A-Za-z_][A-Za-z0-9_]*=\S*|builtin|command|exec|env)$/;

function enclosingCommand(prefix) {
  const opened = [];
  for (let index = 0; index < prefix.length; index += 1) {
    if (prefix[index] === "$" && prefix[index + 1] === "(") {
      opened.push(index + 2);
      index += 1;
    } else if (prefix[index] === ")" && opened.length > 0) {
      opened.pop();
    }
  }
  if (opened.length === 0) return undefined;
  const words = prefix.slice(opened[opened.length - 1]).split(/[|;&]/).pop().trim().split(/\s+/);
  return words.find((word) => !SHELL_COMMAND_PREFIX.test(word));
}

function insideDoubleQuotes(text, index) {
  const line = text.slice(text.lastIndexOf("\n", index - 1) + 1, index);
  return (line.replace(/\\./g, "").match(/"/g) ?? []).length % 2 === 1;
}

function spansOf(text, patterns) {
  return patterns.flatMap((pattern) => [...text.matchAll(pattern)].map((match) => [match.index, match.index + match[0].length]));
}

function insideSpans(index, spans) {
  return spans.some(([start, end]) => index >= start && index < end);
}

function anchorPattern(variables) {
  const names = [...variables.keys()].map(escapeForPattern);
  const forms = [String.raw`(?<trimmed>${SHELL_SELF_DIR_TRIMMED})`, SHELL_SELF_DIR];
  if (names.length > 0) {
    const alternatives = names.join("|");
    forms.push(
      String.raw`\$\{(?<trimmedVariable>${alternatives})[%#:/^,][^}]*\}`,
      String.raw`\$\{(?<braced>${alternatives})\}`,
      String.raw`\$(?<plain>${alternatives})(?![A-Za-z0-9_])`,
    );
  }
  return new RegExp(forms.join("|"), "g");
}

const REPOSITORY_ROOT = { root: true };
const SELF_FOLDER = { folder: "", wide: false };

function anchorBase(match, variables) {
  const { trimmed, trimmedVariable, braced, plain } = match.groups;
  if (trimmed || trimmedVariable) return REPOSITORY_ROOT;
  const name = braced ?? plain;
  return name ? variables.get(name) : SELF_FOLDER;
}

const DIRNAME_ARGUMENT = /\bdirname\s+["']?$/;

function anchorsAtRoot(base, text, match, rest) {
  return base.root === true || (rest.startsWith(")") && DIRNAME_ARGUMENT.test(text.slice(0, match.index)));
}

function pathAfterAnchor(text, match) {
  const rest = text.slice(match.index + match[0].length).replace(/^["']*/, "");
  const tail = rest.match(SHELL_PATH)?.[0] ?? "";
  const after = rest.slice(tail.length).replace(/^["']*/, "");
  return { rest, tail, after };
}

function shellAnchorVariables(text) {
  const variables = new Map();
  const spans = [];
  const targets = [];
  for (let changed = true; changed; ) {
    changed = false;
    for (const match of text.matchAll(SHELL_ASSIGNMENT)) {
      const name = match[1];
      const valueStart = match.index + match[0].length;
      const valueEnd = shellWordEnd(text, valueStart);
      const value = text.slice(valueStart, valueEnd);
      if (variables.has(name)) continue;
      const found = [...value.matchAll(anchorPattern(variables))];
      if (found.length === 0) continue;
      const first = found[0];
      const prefix = value.slice(0, first.index);
      const command = enclosingCommand(prefix);
      if (command !== undefined && !PATH_COMMANDS.has(command)) continue;
      const base = anchorBase(first, variables);
      const { rest, tail, after } = pathAfterAnchor(value, first);
      changed = true;
      if (anchorsAtRoot(base, value, first, rest)) {
        variables.set(name, REPOSITORY_ROOT);
        continue;
      }
      const plain = /^["']?$/.test(prefix) && /^\s*$/.test(after);
      const defaulted = /^["']?\$\{[A-Za-z_][A-Za-z0-9_]*:?-$/.test(prefix) && /^\}["']?\s*$/.test(after);
      const changedDirectory = /^["']?\$\(\s*cd\s+["']?$/.test(prefix) && /^\s*&&\s*pwd(?:\s+-[PL])?\s*\)["']?\s*$/.test(after);
      const exact = found.length === 1 && !base.wide && (plain || defaulted || changedDirectory);
      const folder = `${base.folder}${tail.replace(/\/$/, "")}`;
      variables.set(name, { folder, wide: !exact });
      if (exact) spans.push([match.index, valueEnd]);
      if (exact && tail !== "") targets.push(folder);
    }
  }
  return { variables, spans, targets };
}

function shellReferences(text, folder, root) {
  const { variables, spans, targets } = shellAnchorVariables(text);
  const scanned = masked(text, spans);
  const files = targets.map((target) => resolve(folder, `.${target}`));
  const folders = [];
  const sourced = [];
  for (const match of scanned.matchAll(anchorPattern(variables))) {
    const base = anchorBase(match, variables);
    const { rest, tail, after } = pathAfterAnchor(scanned, match);
    if (anchorsAtRoot(base, scanned, match, rest)) {
      folders.push(root);
      continue;
    }
    const baseFolder = resolve(folder, `.${base.folder}`);
    const target = resolve(baseFolder, `.${tail}`);
    const remainder = rest.slice(tail.length);
    const namesFolder = tail.endsWith("/") || after.startsWith("/");
    const sourcedHere = SHELL_SOURCE_BEFORE.test(scanned.slice(scanned.lastIndexOf("\n", match.index) + 1, match.index));
    const wholeQuotedWord = scanned[match.index - 1] === '"' && /^"[ \t]/.test(scanned.slice(match.index + match[0].length));
    const quotedSpace = /^[ \t]/.test(remainder) && !wholeQuotedWord && insideDoubleQuotes(scanned, match.index);
    const word = quotedSpace ? remainder.slice(0, remainder.indexOf('"') + 1 || undefined) : remainder.match(SHELL_WORD_REST)[0];
    if (tail === "" && SHELL_WORD.test(rest[0] ?? "")) {
      folders.push(dirname(baseFolder));
    } else if (base.wide || SHELL_DYNAMIC.test(word)) {
      folders.push(root);
    } else if (tail === "") {
      folders.push(baseFolder);
      if (sourcedHere) {
        files.push(baseFolder);
        sourced.push(baseFolder);
      }
    } else if (quotedSpace) {
      folders.push(dirname(target));
    } else if (SHELL_WILDCARD.test(word)) {
      folders.push(namesFolder ? target : dirname(target));
    } else if (namesFolder) {
      folders.push(target);
    } else {
      files.push(target);
      if (sourcedHere) sourced.push(target);
    }
  }
  const anchors = spansOf(text, [new RegExp(SHELL_SELF_DIR, "g"), new RegExp(SHELL_SELF_DIR_TRIMMED, "g")]);
  for (const token of withoutLeadingCommentLines(text).matchAll(SHELL_SELF_TOKEN)) {
    if (insideSpans(token.index, anchors) || SHELL_BASENAME_BEFORE.test(text.slice(0, token.index))) continue;
    folders.push(root);
    break;
  }
  return { files, folders, sourced };
}

function addModule(path, files, folders) {
  const candidates = [path, ...[...JS_EXTENSIONS, ".json"].flatMap((extension) => [`${path}${extension}`, join(path, `index${extension}`)])];
  const existing = candidates.filter(isRegularFile);
  files.push(...candidates);
  if (existing.length === 0 && !FILE_EXTENSION.test(basename(path))) folders.push(dirname(path));
}

function callArguments(text, start) {
  const parts = [];
  let depth = 0;
  let quote = "";
  let current = "";
  for (let index = start; index < text.length; index += 1) {
    const character = text[index];
    if (quote) {
      current += character;
      if (character === quote) quote = "";
    } else if (character === '"' || character === "'" || character === "`") {
      quote = character;
      current += character;
    } else if (character === "(" || character === "[" || character === "{") {
      depth += 1;
      current += character;
    } else if ((character === ")" || character === "]" || character === "}") && depth > 0) {
      depth -= 1;
      current += character;
    } else if (character === ")") {
      parts.push(current.trim());
      return parts;
    } else if (character === "," && depth === 0) {
      parts.push(current.trim());
      current = "";
    } else {
      current += character;
    }
  }
  return undefined;
}

function jsReferences(text, folder, root) {
  const files = [];
  const folders = [];
  for (const pattern of JS_SPECIFIERS) {
    for (const match of text.matchAll(pattern)) {
      if (!match[1].startsWith("./") && !match[1].startsWith("../")) continue;
      if (match[1].includes("${")) {
        folders.push(root);
        continue;
      }
      addModule(resolve(folder, match[1]), files, folders);
    }
  }
  for (const match of text.matchAll(JS_URL)) {
    if (URL_SCHEME.test(match[1])) continue;
    const target = fileURLToPath(new URL(match[1] || ".", pathToFileURL(`${folder}${sep}`)));
    if (match[1] === "" || match[1] === "." || match[1].endsWith("/")) folders.push(target);
    else files.push(target);
  }
  const variables = new Set();
  const spans = [];
  for (const match of text.matchAll(JS_SELF_DIR_VARIABLE)) {
    variables.add(match[1]);
    spans.push([match.index, match.index + match[0].length]);
  }
  const scanned = masked(text, spans);
  const names = [...variables].map(escapeForPattern);
  const anchor = new RegExp(names.length === 0 ? JS_SELF_DIR : String.raw`${JS_SELF_DIR}|(?<![\w$.])(?:${names.join("|")})(?![\w$])`, "g");
  for (const match of scanned.matchAll(anchor)) {
    const end = match.index + match[0].length;
    const call = scanned.slice(0, match.index).match(JS_PATH_CALL_BEFORE)?.[1];
    const args = call ? callArguments(scanned, end) : undefined;
    if (!args || args[0] !== "") {
      folders.push(root);
      continue;
    }
    const pathParts = args.slice(1).filter((piece) => piece !== "");
    const literals = [];
    for (const part of pathParts) {
      const literal = part.match(JS_STRING_LITERAL);
      if (!literal) break;
      literals.push(literal[2]);
    }
    if (literals.length < pathParts.length) {
      folders.push(root);
      continue;
    }
    addModule(call === "join" ? join(folder, ...literals) : resolve(folder, ...literals), files, folders);
  }
  const consumed = [
    ...spans,
    ...spansOf(text, [new RegExp(JS_SELF_DIR, "g"), JS_URL, JS_MAIN_GUARD, ...JS_SPECIFIERS]),
  ];
  if ([...text.matchAll(JS_SELF_TOKEN)].some((token) => !insideSpans(token.index, consumed))) folders.push(root);
  return { files, folders };
}

function codeKind(path, text) {
  const interpreter = text.match(/^#!\s*(\S+)(?:\s+(\S+))?/);
  const program = interpreter ? basename(interpreter[1] === "/usr/bin/env" ? interpreter[2] ?? "" : interpreter[1]) : "";
  if (JS_EXTENSIONS.some((extension) => path.endsWith(extension)) || program === "node") return "js";
  if (path.endsWith(".sh") || /^(?:ba|z|da)?sh$/.test(program)) return "shell";
  if (interpreter || OTHER_CODE_EXTENSIONS.some((extension) => path.endsWith(extension))) return "other";
  return undefined;
}

function scanner(root) {
  const cache = new Map();
  const inside = (path) => path === root || path.startsWith(root + sep);
  return (path, sourced) => {
    const cacheKey = `${sourced ? "sourced" : "run"}:${path}`;
    if (cache.has(cacheKey)) return cache.get(cacheKey);
    let references = { files: [], folders: [], sourced: [] };
    if (isRegularFile(path)) {
      const text = readFileSync(path, "utf-8");
      const kind = codeKind(path, text) ?? (sourced ? "shell" : undefined);
      if (kind === "js") references = { ...jsReferences(text, dirname(path), root), sourced: [] };
      if (kind === "shell") references = shellReferences(text, dirname(path), root);
      if (kind === "other") references = { files: [], folders: [root], sourced: [] };
      if (kind === "shell" && sourced && SHELL_CALLER_PATH.test(withoutLeadingCommentLines(text))) references.folders.push(root);
    }
    const files = references.files.filter((reference) => inside(reference) && !isDirectory(reference));
    const folders = [...references.folders, ...references.files.filter(isDirectory)].filter(inside);
    const globs = folders.map((reference) => (reference === root ? "**" : `${relative(root, reference)}/**`));
    const result = { files: [...new Set(files)], globs: [...new Set(globs)], sourced: new Set(references.sourced) };
    cache.set(cacheKey, result);
    return result;
  };
}

function isSymbolicLink(path) {
  try {
    return lstatSync(path).isSymbolicLink();
  } catch {
    return false;
  }
}

function linkTarget(path) {
  try {
    const target = realpathSync(path);
    return target === path ? undefined : target;
  } catch {
    return undefined;
  }
}

function repositoryFiles(root) {
  const listing = execFileSync("git", ["-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"], {
    encoding: "utf-8",
    maxBuffer: 64 * 1024 * 1024,
  });
  return [...new Set(listing.split("\0").filter(Boolean))].filter((path) => isRegularFile(join(root, path)));
}

function closureOf(testPath, context) {
  const { root, manifest, scan } = context;
  const parents = new Map();
  const globs = [];
  const queue = [];
  const sourcedScans = new Set();
  const visit = (path, parent, declaredAs, sourced = false) => {
    const key = relative(root, path);
    if (sourced && !sourcedScans.has(key)) {
      sourcedScans.add(key);
      queue.push({ path, sourced });
    }
    if (parents.has(key)) return;
    parents.set(key, { parent, declaredAs });
    if (!sourced) queue.push({ path, sourced });
    const target = linkTarget(path);
    if (target && target.startsWith(root + sep)) visit(target, key, "the target of a symbolic link");
    for (let folder = dirname(path); folder.startsWith(root + sep); folder = dirname(folder)) {
      const folderKey = relative(root, folder);
      if (!parents.has(folderKey) && isSymbolicLink(folder)) parents.set(folderKey, { parent: key, declaredAs: "a linked folder on its path" });
    }
  };
  const visitGlob = (entry, key, declaredAs) => {
    const pattern = globPattern(entry);
    globs.push({ glob: entry, pattern, declaredBy: key });
    for (const file of context.files().filter((candidate) => pattern.test(candidate))) {
      visit(join(root, file), key, declaredAs);
    }
  };
  visit(testPath, null);
  while (queue.length > 0) {
    const { path, sourced } = queue.shift();
    const key = relative(root, path);
    const scanned = scan(path, sourced);
    for (const reference of scanned.files) visit(reference, key, undefined, scanned.sourced.has(reference));
    for (const glob of scanned.globs) visitGlob(glob, key, `${glob}, a folder it reads`);
    for (const entry of manifest.get(key) ?? []) {
      if (isGlob(entry)) visitGlob(entry, key, entry);
      else visit(join(root, entry), key, entry);
    }
  }
  return { parents, globs };
}

function chain(parents, key) {
  const steps = [];
  for (let step = key; step !== null; step = parents.get(step).parent) {
    const { declaredAs } = parents.get(step);
    steps.unshift(declaredAs ? `${step} (declared as ${declaredAs})` : step);
  }
  return steps.join(" -> ");
}

function testsIn(testsFolder) {
  return readdirSync(testsFolder)
    .filter((name) => name.endsWith(TEST_SUFFIX))
    .sort()
    .map((name) => join(testsFolder, name));
}

function context(root) {
  let listing;
  const files = () => (listing ??= repositoryFiles(root));
  return { root, manifest: readManifest(root, files), scan: scanner(root), files };
}

function runnerChange(changed, toolingFolderKey, testsFolderKey) {
  return changed.find((path) => {
    if (dirname(path) === toolingFolderKey && RUNNER_FILES.has(basename(path))) return true;
    return path.startsWith(`${testsFolderKey}/${SHARED_HELPER_FOLDER}/`);
  });
}

function testsToCheck(root, testsFolder, toolingFolderKey, changed) {
  const tests = testsIn(testsFolder);
  if (changed.some((path) => dirname(path) === toolingFolderKey && SCAN_FILES.has(basename(path)))) return tests;
  const changedPaths = new Set(changed);
  return tests.filter((testPath) => {
    if (changedPaths.has(relative(root, testPath))) return true;
    return existsSync(testPath) && changedPaths.has(relative(root, realpathSync(testPath)));
  });
}

function select(root, testsFolder, changedListPath, selectionPath, checkListPath) {
  const changed = [...new Set(readFileSync(changedListPath, "utf-8").split("\0").filter(Boolean))].sort();
  const testsFolderKey = relative(root, testsFolder);
  const toolingFolderKey = relative(root, TOOLING_FOLDER);
  writeFileSync(selectionPath, "");
  writeFileSync(checkListPath, "");
  if (changed.length === 0) {
    console.log("run-affected: no changed files, so no test to run");
    return;
  }
  console.log("run-affected: changed files:");
  for (const path of changed) console.log(`  ${path}`);
  writeFileSync(checkListPath, testsToCheck(root, testsFolder, toolingFolderKey, changed).map((testPath) => `${testPath}\n`).join(""));
  const runner = runnerChange(changed, toolingFolderKey, testsFolderKey);
  if (runner) throw new FullSuite(`${runner} is part of the test runner or its shared helpers`);
  const shared = context(root);
  const selected = [];
  const reached = new Set();
  for (const testPath of testsIn(testsFolder)) {
    const { parents, globs } = closureOf(testPath, shared);
    for (const key of parents.keys()) reached.add(key);
    const reasons = [];
    for (const path of changed) {
      if (parents.has(path)) {
        reasons.push(chain(parents, path));
        continue;
      }
      const glob = globs.find((candidate) => candidate.pattern.test(path));
      if (glob) reasons.push(`${chain(parents, glob.declaredBy)} declares ${glob.glob}, which matches ${path}`);
    }
    if (reasons.length > 0) selected.push({ testPath, reasons });
  }
  const unreached = [...shared.manifest.keys()].find((key) => !reached.has(key));
  if (unreached) throw new FullSuite(`${MANIFEST_NAME} declares dependencies for ${unreached}, which no test reaches`);
  for (const path of changed) {
    if (dirname(path) === testsFolderKey && path.endsWith(TEST_SUFFIX) && !existsSync(join(root, path))) {
      console.log(`run-affected: ${path} was deleted, so it is not run`);
    }
  }
  if (selected.length === 0) {
    console.log("run-affected: no test reaches the changed files, so no test was run");
    return;
  }
  if (selected.some(({ testPath }) => testPath.includes("\n"))) {
    throw new FullSuite("a selected test path contains a line break");
  }
  console.log("run-affected: selected tests and the changed files that reach them:");
  for (const { testPath, reasons } of selected) {
    console.log(`  ${relative(testsFolder, testPath)}`);
    for (const reason of reasons) console.log(`    ${reason}`);
  }
  writeFileSync(selectionPath, selected.map(({ testPath }) => `${testPath}\n`).join(""));
}

function dependencyFiles(root, testPath) {
  const { parents } = closureOf(join(realpathSync(dirname(testPath)), basename(testPath)), context(root));
  const files = [...parents.keys()].filter((key) => isRegularFile(join(root, key))).sort();
  if (files.some((file) => file.includes("\n"))) throw new Error("a dependency path contains a line break");
  for (const file of files) console.log(file);
}

function main() {
  const [command, root, testsFolder, ...rest] = process.argv.slice(2);
  if (!root || !testsFolder) {
    console.log("usage: select.mjs tests ROOT TESTS CHANGED_LIST SELECTION CHECK_LIST | files ROOT TESTS TEST");
    process.exit(2);
  }
  const realRoot = realpathSync(root);
  const realTests = realpathSync(testsFolder);
  try {
    if (command === "tests" && rest.length === 3) return select(realRoot, realTests, rest[0], rest[1], rest[2]);
    if (command === "files" && rest.length === 1) return dependencyFiles(realRoot, rest[0]);
  } catch (error) {
    if (error instanceof FullSuite) {
      console.log(`run-affected: running the full suite, because ${error.message}`);
      process.exit(FULL_SUITE_EXIT);
    }
    throw error;
  }
  console.log(`select.mjs: unknown command ${command}`);
  process.exit(2);
}

main();
