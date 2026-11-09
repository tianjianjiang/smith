import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const AGENT_TOOL = "pr-review-toolkit:review-pr";
const REVIEW_TOOLS = [
  "coderabbit",
  "/code-review",
  AGENT_TOOL,
  "security-review",
  "code-simplifier",
];
const AGENT_TOOL_AGENTS = [
  "code-reviewer",
  "comment-analyzer",
  "pr-test-analyzer",
  "silent-failure-hunter",
  "type-design-analyzer",
  "code-simplifier",
];
const ALWAYS_RUN_AGENT = "code-reviewer";
const RECEIPT_DIRECTORY = "smith-review-receipts";
const RECEIPT_ENTRY = /^(\S+)\s+(ran(?::\S*)?|NA:\S.*)$/;
const RECEIPT_SEPARATOR = "·";
const FALLBACK_BASE = "origin/main";
const LARGE_OUTPUT = 256 * 1024 * 1024;

function git(dir, args, input) {
  return execFileSync("git", ["-C", dir, ...args], {
    input,
    stdio: ["pipe", "pipe", "ignore"],
    encoding: "utf-8",
    maxBuffer: LARGE_OUTPUT,
  }).trim();
}

function gitOrNull(dir, args) {
  try {
    return git(dir, args);
  } catch {
    return null;
  }
}

function twoDigits(value) {
  return String(Math.trunc(Math.abs(value))).padStart(2, "0");
}

function localTimestamp(date = new Date()) {
  const offsetMinutes = -date.getTimezoneOffset();
  const sign = offsetMinutes >= 0 ? "+" : "-";
  const day = `${date.getFullYear()}-${twoDigits(date.getMonth() + 1)}-${twoDigits(date.getDate())}`;
  const time = `${twoDigits(date.getHours())}:${twoDigits(date.getMinutes())}:${twoDigits(date.getSeconds())}`;
  return `${day}T${time}${sign}${twoDigits(offsetMinutes / 60)}:${twoDigits(offsetMinutes % 60)}`;
}

function agentListProblems(tool, status) {
  if (status.startsWith("NA:")) return [];
  if (tool !== AGENT_TOOL) return status === "ran" ? [] : [`${tool} takes plain "ran", not an agent list`];
  const agents = status.startsWith("ran:") ? status.slice(4).split(",") : [];
  if (agents.every((agent) => agent === "")) return [`${tool} must name the agents that ran: ${tool} ran:«agent,…»`];
  const problems = [];
  if (agents.includes("")) problems.push(`${tool} has an empty agent name; separate agents with single commas`);
  const named = agents.filter(Boolean);
  if (new Set(named).size !== named.length) problems.push(`${tool} names an agent twice`);
  const unknown = named.filter((agent) => !AGENT_TOOL_AGENTS.includes(agent));
  problems.push(...unknown.map((agent) => `${tool} names unknown agent "${agent}"; known: ${AGENT_TOOL_AGENTS.join(", ")}`));
  if (!agents.includes(ALWAYS_RUN_AGENT)) problems.push(`${tool} must include ${ALWAYS_RUN_AGENT}`);
  return problems;
}

function receiptProblems(line) {
  const statusByTool = new Map();
  const problems = [];
  for (const entry of String(line).split(RECEIPT_SEPARATOR).map((part) => part.trim()).filter(Boolean)) {
    const match = RECEIPT_ENTRY.exec(entry);
    if (!match) {
      problems.push(`unreadable entry "${entry}"; write «tool» ran, «tool» NA:«reason», or ${AGENT_TOOL} ran:«agent,…» without spaces`);
      continue;
    }
    statusByTool.set(match[1], match[2]);
    problems.push(...agentListProblems(match[1], match[2]));
  }
  for (const tool of REVIEW_TOOLS) {
    const ranForm = tool === AGENT_TOOL ? "ran:«agent,…»" : "ran";
    if (!statusByTool.has(tool)) problems.push(`${tool} has no "${ranForm}" or "NA:«reason»"`);
  }
  return problems;
}

function defaultBase(root) {
  return gitOrNull(root, ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"]) || FALLBACK_BASE;
}

export function reviewedChange(dir, requestedBase) {
  const root = gitOrNull(dir, ["rev-parse", "--show-toplevel"]);
  if (!root) return { problem: "not inside a git work tree" };
  const base = requestedBase || defaultBase(root);
  const mergeBase = gitOrNull(root, ["merge-base", base, "HEAD"]);
  if (!mergeBase) return { problem: `no merge base between ${base} and HEAD` };
  const diff = git(root, ["diff", "--binary", "--no-textconv", "--no-ext-diff", "--no-color", mergeBase, "HEAD"]);
  if (diff === "") return { problem: `HEAD has no change against ${base}` };
  const changeId = git(root, ["patch-id", "--verbatim"], `${diff}\n`).split(" ")[0];
  const receipts = join(git(root, ["rev-parse", "--path-format=absolute", "--git-common-dir"]), RECEIPT_DIRECTORY);
  const dirty = git(root, ["status", "--porcelain", "--untracked-files=all"]) !== "";
  return { root, base, changeId, path: join(receipts, changeId), receipts, dirty };
}

export function receiptState(change) {
  try {
    const receipt = JSON.parse(readFileSync(change.path, "utf-8"));
    if (receipt.changeId !== change.changeId) return "mismatched";
    return receiptProblems(receipt.receipt).length === 0 ? "present" : "incomplete";
  } catch {
    return "missing";
  }
}

export function writeReviewReceipt(dir, line, requestedBase) {
  const problems = receiptProblems(line);
  if (problems.length > 0) throw new Error(`receipt refused: ${problems.join("; ")}`);
  const change = reviewedChange(dir, requestedBase);
  if (change.problem) throw new Error(`receipt refused: ${change.problem}`);
  if (change.dirty) {
    throw new Error("receipt refused: the working tree has uncommitted changes; commit them so the receipt names what was reviewed");
  }
  mkdirSync(change.receipts, { recursive: true });
  const head = git(change.root, ["rev-parse", "HEAD"]);
  writeFileSync(
    change.path,
    JSON.stringify({ changeId: change.changeId, base: change.base, head, receipt: String(line).trim(), writtenAt: localTimestamp() }) + "\n",
  );
  return change;
}
