import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export const PLANS_DIR = join(
  process.env.CLAUDE_CONFIG_DIR || join(homedir(), ".claude"),
  "plans",
);

export const UNENFORCED = "unenforced";

const CHECKED_VERDICTS = new Set([
  "contract-pasted",
  "editor-role",
  "exempt",
  "blocked",
]);

function git(cwd, args) {
  const env = { ...process.env };
  delete env.GIT_DIR;
  delete env.GIT_WORK_TREE;
  delete env.GIT_COMMON_DIR;
  return execFileSync("git", ["-C", cwd, ...args], {
    stdio: ["ignore", "pipe", "ignore"],
    encoding: "utf-8",
    env,
  }).trim();
}

export function checkoutRoot(cwd) {
  if (!cwd) return "";
  try {
    return git(cwd, ["rev-parse", "--show-toplevel"]);
  } catch {
    return "";
  }
}

export function currentBranch(cwd) {
  if (!cwd) return "";
  try {
    const name = git(cwd, ["rev-parse", "--abbrev-ref", "HEAD"]);
    return name === "HEAD" ? git(cwd, ["rev-parse", "HEAD"]) : name;
  } catch {
    return "";
  }
}

export function scopeRootFor(cwd, repoRoot = checkoutRoot(cwd)) {
  return repoRoot || cwd || "";
}

export function scopeRootCandidates(cwd, repoRoot = checkoutRoot(cwd)) {
  return [...new Set([repoRoot, cwd].filter(Boolean))];
}

function token(value) {
  if (typeof value !== "string") return "";
  return value
    .replace(/[^A-Za-z0-9._-]+/g, "-")
    .slice(0, 60)
    .replace(/^-+|-+$/g, "");
}

export function ledgerPath(scopeRoot) {
  if (!scopeRoot) return "";
  const key = createHash("md5").update(scopeRoot).digest("hex").slice(0, 16);
  return join(PLANS_DIR, `.spawn-ledger-${key}`);
}

export function readLedger(scopeRoots, branch) {
  const paths = [
    ...new Set((scopeRoots || []).map(ledgerPath).filter(Boolean)),
  ];
  if (!paths.length) return null;

  const entries = [];
  let malformed = 0;
  let unreadable = 0;
  let found = 0;

  for (const path of paths) {
    let raw;
    try {
      raw = readFileSync(path, "utf-8");
    } catch (error) {
      if (!error || error.code !== "ENOENT") unreadable += 1;
      continue;
    }
    found += 1;
    for (const line of raw.split("\n")) {
      if (!line.trim()) continue;
      let entry;
      try {
        entry = JSON.parse(line);
      } catch {
        malformed += 1;
        continue;
      }
      if (!entry || typeof entry !== "object") {
        malformed += 1;
        continue;
      }
      const verdict = typeof entry.verdict === "string" ? entry.verdict : "";
      const accountedFor = CHECKED_VERDICTS.has(token(verdict));
      if (accountedFor && branch && entry.branch && entry.branch !== branch) {
        continue;
      }
      entries.push(entry);
    }
  }

  if (!found && !unreadable) return null;
  return { entries, malformed, unreadable };
}

export function verdictFor(ledger) {
  if (ledger === null) {
    return {
      verdict: "SKIP:no-ledger",
      detail:
        "no spawn ledger for this checkout: either no subagent was spawned " +
        "here, or subagent-contract-guard is not registered. Ambiguous, so " +
        "answer the check by attestation and say the ledger was absent.",
    };
  }

  const { entries, malformed, unreadable } = ledger;
  if (!entries.length && !malformed && !unreadable) {
    return {
      verdict: "N/A:no-spawns",
      detail: "the ledger exists and records no spawn on this branch.",
    };
  }

  const counts = new Map();
  const reasons = new Set();
  for (const entry of entries) {
    const verdict =
      typeof entry.verdict === "string" && entry.verdict
        ? token(entry.verdict)
        : "unrecognized";
    counts.set(verdict, (counts.get(verdict) || 0) + 1);
    if (CHECKED_VERDICTS.has(verdict)) continue;
    reasons.add(
      verdict === UNENFORCED ? token(entry.reason) || "unknown" : verdict,
    );
  }
  if (malformed) {
    counts.set("malformed-line", malformed);
    reasons.add("malformed-line");
  }
  if (unreadable) {
    counts.set("unreadable-ledger", unreadable);
    reasons.add("unreadable-ledger");
  }

  const summary = [...counts.keys()]
    .sort()
    .map((name) => `${name}=${counts.get(name)}`)
    .join(" ");
  const total = entries.length + malformed;

  if (reasons.size) {
    return {
      verdict: `FAIL:unchecked-spawn(${[...reasons].sort().join(",")})`,
      detail:
        `${total} ledger record(s) visible from this branch: ${summary}. ` +
        "At least one spawn cannot be shown to have been checked against the " +
        "contract. Only accounted-for records are narrowed by branch; a record " +
        "that cannot be shown to have been checked counts on every branch of " +
        "the checkout, so that no branch name can hide one.",
    };
  }
  return {
    verdict: "PASS",
    detail: `${total} spawn(s) on this branch: ${summary}.`,
  };
}
