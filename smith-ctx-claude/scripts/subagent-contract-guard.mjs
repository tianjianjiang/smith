#!/usr/bin/env node
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  PLANS_DIR,
  UNENFORCED,
  checkoutRoot,
  currentBranch,
  ledgerPath,
  scopeRootFor,
} from "./lib/spawn-ledger.mjs";
import {
  CONTRACT_SOURCE,
  canonicalContract,
  normalize,
  stripQuoteMarkers,
} from "./lib/contract-template.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const CONFIG_PATH = resolve(HERE, "..", "subagent-contract-config.json");
const OPT_OUT_MARKER = join(".claude", "subagent-contract-guard.disabled");
const SPAWN_TOOLS = new Set(["Agent", "Task"]);
const EDITOR_ROLE_DECLARATION =
  /^ {0,3}(?:(?:[-*+]|\d+[.)]|#{1,6})[ \t]+)?(?:\*{1,2}|_{1,2})?EDITOR ROLE(?![A-Za-z0-9])/m;
const NAMESPACED_SUBAGENT_TYPE = /^[^:\s]+:[^:\s]+$/;

let pendingEntry = null;
let pendingScopeRoot = "";

function stringOrEmpty(value) {
  return typeof value === "string" ? value : "";
}

function exemptSubagentTypes() {
  try {
    const configured = JSON.parse(readFileSync(CONFIG_PATH, "utf-8"))
      .exemptSubagentTypes;
    if (Array.isArray(configured)) {
      return {
        names: configured.filter((n) => typeof n === "string" && n !== ""),
        usable: true,
      };
    }
    return { names: [], usable: false };
  } catch {
    return { names: [], usable: false };
  }
}

function isExempt(subagentType) {
  if (NAMESPACED_SUBAGENT_TYPE.test(subagentType)) {
    return { exempt: true, configUsable: true };
  }
  const { names, usable } = exemptSubagentTypes();
  return {
    exempt: names.some(
      (name) => name.toLowerCase() === subagentType.toLowerCase(),
    ),
    configUsable: usable,
  };
}

function safeLedgerPath(scopeRoot) {
  try {
    return ledgerPath(scopeRoot) || "an underivable path";
  } catch {
    return "an underivable path";
  }
}

function record(entry, scopeRoot) {
  try {
    const path = ledgerPath(scopeRoot);
    if (!path) return false;
    mkdirSync(PLANS_DIR, { recursive: true });
    appendFileSync(path, JSON.stringify(entry) + "\n");
    return true;
  } catch {
    return false;
  }
}

function advise(message) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: message,
      },
      systemMessage: message,
    }) + "\n",
  );
}

function unclearableFailNote(scopeRoot) {
  return (
    "The ledger is append-only, so this branch's /smith-preflight " +
    "subagent-contract check FAILs from here on — a later correct spawn does " +
    "not clear it, because the unchecked spawn really did run. Inspect the " +
    `record at ${safeLedgerPath(scopeRoot)}.`
  );
}

function allow(entry, scopeRoot, extraAdvice) {
  const notes = [];
  if (!record(entry, scopeRoot)) {
    if (entry.verdict === UNENFORCED && entry.reason !== "opt-out") {
      writeSync(
        2,
        [
          "Blocked: this spawn could not be checked against the subagent",
          `contract (${entry.reason}), AND the record of that could not be`,
          `written to the ledger at ${safeLedgerPath(scopeRoot)}.`,
          "Neither the check nor the audit trail is available, so allowing it",
          "would leave no trace that anything went unchecked. Recover by making",
          "that path writable, by pointing CLAUDE_CONFIG_DIR somewhere that is,",
          "or by unregistering this hook — not by rewording the prompt, which",
          "cannot reach this branch.",
        ].join(" ") + "\n",
      );
      process.exit(2);
    }
    notes.push(
      "subagent-contract-guard: this spawn could not be written to the ledger " +
        `at ${safeLedgerPath(scopeRoot)}, so ` +
        "/smith-preflight's subagent-contract check will not see it. The spawn " +
        "was allowed; the audit for this branch is now incomplete, and a PASS " +
        "there would be reporting less than what ran.",
    );
  }
  if (extraAdvice) notes.push(extraAdvice);
  if (notes.length) advise(notes.join(" "));
}

function blockAndExit(contract, subagentType) {
  writeSync(
    2,
    [
      `Blocked: the '${subagentType || "unnamed"}' spawn does not carry the`,
      "canonical read-only subagent contract. A subagent inherits no skills,",
      "AGENTS.md, or memory, so a re-worded contract silently drops the two",
      "clauses that exist nowhere but the template. Paste this block verbatim",
      "at the top of the prompt, then re-issue the spawn:",
      "",
      contract.display,
      "",
      "Source: smith-subagents/SKILL.md, Contract template. For a bounded",
      "editor spawn, OPEN A LINE with EDITOR ROLE and name the ONE artifact it",
      "may change plus the single tool granted; this guard then stands aside.",
      `Per-checkout opt-out: touch ${OPT_OUT_MARKER} in the checkout root, but`,
      "note it records every later spawn THAT WOULD HAVE BEEN CHECKED as",
      "unchecked, and FAILs this branch's /smith-preflight from then on.",
    ].join("\n") + "\n",
  );
  process.exit(2);
}

function main() {
  let input;
  try {
    input = JSON.parse(readFileSync(0, "utf-8"));
  } catch {
    return;
  }
  if (!input || typeof input !== "object") return;
  if (!SPAWN_TOOLS.has(input.tool_name)) return;

  const toolInput = input.tool_input;
  if (!toolInput || typeof toolInput !== "object") return;
  if (!Object.keys(toolInput).length) return;
  const promptIsText = typeof toolInput.prompt === "string";
  const prompt = stringOrEmpty(toolInput.prompt);
  if (promptIsText && !prompt.trim()) return;

  const subagentType = stringOrEmpty(toolInput.subagent_type);
  const cwd = stringOrEmpty(input.cwd);
  const repoRoot = checkoutRoot(cwd);
  const scopeRoot = scopeRootFor(cwd, repoRoot);
  const entry = {
    ts: new Date().toISOString(),
    session: stringOrEmpty(input.session_id),
    cwd,
    branch: currentBranch(cwd),
    tool: input.tool_name,
    subagent_type: subagentType,
  };

  pendingEntry = entry;
  pendingScopeRoot = scopeRoot;

  if (!promptIsText) {
    allow(
      { ...entry, verdict: UNENFORCED, reason: "prompt-not-text" },
      scopeRoot,
      "subagent-contract-guard: this spawn carried no prompt text to check, " +
        `so the contract was NOT verified (fields seen: ${Object.keys(toolInput).join(", ")}). ` +
        "If the Agent tool's prompt field has moved or been renamed, the guard " +
        "is a no-op until it is taught the new shape; make the ledger path " +
        "writable, or unregister the hook, until it is. " +
        unclearableFailNote(scopeRoot),
    );
    return;
  }

  const exemption = isExempt(subagentType);
  if (exemption.exempt) {
    allow({ ...entry, verdict: "exempt" }, scopeRoot);
    return;
  }
  if (!exemption.configUsable) {
    advise(
      `subagent-contract-guard: ${CONFIG_PATH} is missing or does not hold an ` +
        "exemption array, so NO name-based exemption applies and built-in " +
        "helpers whose prompt you do not author will be blocked. Repair the " +
        "file if that is not what you meant.",
    );
  }

  if (repoRoot && existsSync(join(repoRoot, OPT_OUT_MARKER))) {
    allow(
      { ...entry, verdict: UNENFORCED, reason: "opt-out" },
      scopeRoot,
      `subagent-contract-guard: ${OPT_OUT_MARKER} is present, so this spawn ` +
        "was allowed WITHOUT being checked against the contract. " +
        unclearableFailNote(scopeRoot),
    );
    return;
  }

  if (EDITOR_ROLE_DECLARATION.test(prompt)) {
    allow({ ...entry, verdict: "editor-role" }, scopeRoot);
    return;
  }

  let contract = null;
  try {
    contract = canonicalContract();
  } catch {
    contract = null;
  }
  if (!contract) {
    allow(
      { ...entry, verdict: UNENFORCED, reason: "contract-source-unreadable" },
      scopeRoot,
      "subagent-contract-guard: could not obtain the canonical contract from " +
        `${CONTRACT_SOURCE}, so this spawn was NOT checked. Either that file ` +
        "is unreachable (repair the skills symlink), or its Contract template " +
        "section no longer extracts — a renamed heading, an indented or fenced " +
        "block, a second blockquote in the section, or a clause added after " +
        "the «placeholder» line. Paste the block by hand meanwhile. " +
        unclearableFailNote(scopeRoot),
    );
    return;
  }

  if (normalize(stripQuoteMarkers(prompt)).includes(contract.required)) {
    allow({ ...entry, verdict: "contract-pasted" }, scopeRoot);
    return;
  }

  record({ ...entry, verdict: "blocked" }, scopeRoot);
  blockAndExit(contract, subagentType);
}

try {
  main();
} catch (error) {
  if (pendingEntry) {
    record(
      { ...pendingEntry, verdict: UNENFORCED, reason: "guard-crashed" },
      pendingScopeRoot,
    );
  }
  advise(
    "subagent-contract-guard: the guard itself failed, so this spawn was NOT " +
      `checked: ${(error && error.message) || error}. Paste the ` +
      "smith-subagents/SKILL.md Contract template block by hand, and treat " +
      "/smith-preflight's subagent-contract answer as unmeasured.",
  );
}
