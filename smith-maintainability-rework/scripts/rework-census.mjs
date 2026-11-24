#!/usr/bin/env node
import { execFileSync } from "node:child_process";

const GITLINK_MODE = "160000";
const DEFAULT_FIX_PATTERN = String.raw`^fix(\([^)]*\))?!?:`;
const USAGE = "usage: rework-census.mjs [--repo PATH] [--range REVS] [--fixes-through REV] [--ext .py]... [--fix-pattern REGEX]";
const NEUTRAL_CONFIG = [
  "-c", "core.quotePath=false",
  "-c", "color.ui=never",
  "-c", "diff.noprefix=false",
  "-c", "diff.mnemonicPrefix=false",
  "-c", "log.showSignature=false",
  "-c", "diff.algorithm=myers",
  "-c", "diff.indentHeuristic=true",
  "-c", "diff.renames=true",
  "-c", "diff.renameLimit=1000",
  "-c", "log.showRoot=true",
];

function parseArguments(argv) {
  const options = { repo: ".", range: "HEAD", fixesThrough: "HEAD", extensions: [], fixPattern: DEFAULT_FIX_PATTERN };
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (value === undefined || value.startsWith("--")) throw new Error(`${flag} needs a value\n${USAGE}`);
    if (flag === "--repo") options.repo = value;
    else if (flag === "--range") options.range = value;
    else if (flag === "--fixes-through") options.fixesThrough = value;
    else if (flag === "--ext") options.extensions.push(value);
    else if (flag === "--fix-pattern") options.fixPattern = value;
    else throw new Error(`unknown option ${flag}\n${USAGE}`);
    index += 1;
  }
  return options;
}

function gitReader(location) {
  return (...args) => execFileSync("git", ["--literal-pathspecs", ...location, ...NEUTRAL_CONFIG, ...args], {
    encoding: "utf8",
    env: { ...process.env, GIT_NO_LAZY_FETCH: "1" },
    maxBuffer: 1 << 28,
    stdio: ["ignore", "pipe", "pipe"],
  });
}

function workTreeRootReader(repo) {
  const locate = gitReader(["-C", repo]);
  const gitDirectory = locate("rev-parse", "--absolute-git-dir").trim();
  if (locate("rev-parse", "--is-inside-work-tree").trim() !== "true") return locate;
  const root = locate("rev-parse", "--show-toplevel").trim();
  return gitReader(["--git-dir", gitDirectory, "--work-tree", root, "-C", root]);
}

function matchesExtensions(path, extensions) {
  return extensions.length === 0 || extensions.some((extension) => path.endsWith(extension));
}

function listCommits(git, range) {
  const output = git("log", "--reverse", "--no-merges", "--format=%H%x1f%P%x1f%s", "--end-of-options", range);
  return output.split("\n").filter(Boolean).map((line) => {
    const [sha, parents, subject] = line.split("\x1f");
    return { sha, parent: parents.split(" ")[0] || null, subject };
  });
}

function addsLines(git, commit, extensions) {
  const fields = git("show", "--raw", "--numstat", "-z", "--format=", "-M", commit.sha).split("\0");
  const gitlinks = new Set();
  let addsTextLines = false;
  for (let index = 0; index < fields.length; index += 1) {
    const field = fields[index].replace(/^\n/, "");
    if (field.startsWith(":")) {
      const [, afterMode, , , status] = field.slice(1).split(" ");
      const pathCount = status.startsWith("R") ? 2 : 1;
      if (afterMode === GITLINK_MODE) gitlinks.add(fields[index + pathCount]);
      index += pathCount;
      continue;
    }
    const [added, , ...pathParts] = field.split("\t");
    const renamed = pathParts.length === 1 && pathParts[0] === "";
    const path = renamed ? fields[index + 2] : pathParts.join("\t");
    if (renamed) index += 2;
    const countsAsText = pathParts.length > 0 && Number(added) > 0 && !gitlinks.has(path);
    if (countsAsText && matchesExtensions(path, extensions)) addsTextLines = true;
  }
  return addsTextLines;
}

function changedFiles(git, commit, extensions) {
  const fields = git("diff", "--raw", "-z", "-M", commit.parent, commit.sha).split("\0");
  const files = [];
  for (let index = 0; index + 1 < fields.length; ) {
    const [beforeMode, , , , status] = fields[index].slice(1).split(" ");
    const renamed = status.startsWith("R");
    const before = fields[index + 1];
    const after = renamed ? fields[index + 2] : before;
    index += renamed ? 3 : 2;
    const blamable = !status.startsWith("A") && beforeMode !== GITLINK_MODE;
    if (blamable && matchesExtensions(before, extensions)) files.push({ before, after });
  }
  return files;
}

function removedRanges(git, commit, { before, after }) {
  const diff = git(
    "diff", "-U0", "--inter-hunk-context=0", "-M", "--no-color", "--no-ext-diff", "--no-textconv",
    commit.parent, commit.sha, "--", before, after,
  );
  return diff.split("\n").flatMap((line) => {
    const hunk = /^@@ -(\d+)(?:,(\d+))? \+/.exec(line);
    if (!hunk) return [];
    const length = hunk[2] === undefined ? 1 : Number(hunk[2]);
    return length > 0 ? [{ start: Number(hunk[1]), length }] : [];
  });
}

function introducingCommits(git, commit, extensions) {
  const introducers = new Set();
  for (const file of changedFiles(git, commit, extensions)) {
    for (const { start, length } of removedRanges(git, commit, file)) {
      const blame = git(
        "blame", "--porcelain", "--no-textconv", "--ignore-revs-file", "",
        "-L", `${start},+${length}`, commit.parent, "--", file.before,
      );
      for (const line of blame.split("\n")) {
        const header = /^([0-9a-f]{40}|[0-9a-f]{64}) \d+ \d+/.exec(line);
        if (header) introducers.add(header[1]);
      }
    }
  }
  return introducers;
}

function census(options) {
  const git = workTreeRootReader(options.repo);
  const fixPattern = new RegExp(options.fixPattern);
  const commits = listCommits(git, options.range);
  const candidates = new Map();
  for (const commit of commits) {
    if (addsLines(git, commit, options.extensions)) candidates.set(commit.sha, commit);
  }
  const fixedBy = new Map();
  let fixes = 0;
  let unattributableFixes = 0;
  for (const commit of listCommits(git, options.fixesThrough)) {
    if (!fixPattern.test(commit.subject) || commit.parent === null) continue;
    fixes += 1;
    const introducers = introducingCommits(git, commit, options.extensions);
    if (introducers.size === 0) unattributableFixes += 1;
    for (const introducer of introducers) {
      if (!fixedBy.has(introducer)) fixedBy.set(introducer, []);
      fixedBy.get(introducer).push(commit.sha);
    }
  }
  const fixInducing = [...candidates.values()]
    .filter((commit) => fixedBy.has(commit.sha))
    .map((commit) => ({ sha: commit.sha, subject: commit.subject, fixedBy: fixedBy.get(commit.sha) }));
  const introducersOutsideRange = [...fixedBy.keys()].filter((sha) => !candidates.has(sha)).length;
  return {
    range: options.range,
    fixesThrough: options.fixesThrough,
    extensions: options.extensions,
    fixPattern: options.fixPattern,
    commits: commits.length,
    candidates: candidates.size,
    fixes,
    unattributableFixes,
    introducersOutsideRange,
    fixInducing,
    share: candidates.size === 0 ? null : fixInducing.length / candidates.size,
  };
}

try {
  console.log(JSON.stringify(census(parseArguments(process.argv.slice(2))), null, 2));
} catch (error) {
  console.error(`rework-census: ${error.message}`);
  process.exit(1);
}
