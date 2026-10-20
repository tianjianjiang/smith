#!/usr/bin/env node
import { readHookInput } from "../../smith-git/scripts/lib/hook-utils.mjs";
import {
  UNWRAP_DEPTH_EXCEEDED,
  gitSubcommandArguments,
} from "../../smith-git/scripts/lib/git-command-tokenizer.mjs";
import { nonFlagTokensAfterGh } from "./lib/gh-command.mjs";
import { invocationsOf, scansUnderEitherShellReading } from "./lib/shell-scan.mjs";
import {
  READING_IS_NOT_LOADING,
  readGateTable,
  skillsAvailableInSession,
} from "./lib/skills-invoked.mjs";

const TARGET_FILE_KEYS = ["file_path", "relative_path"];
const UNSCANNED_COMMAND =
  "skill-load-gate: this command is wrapped too deeply to scan, so it cannot be shown " +
  "to hold no governed action (see smith-ctx-claude/skill-gate.json). " +
  "Approve only if it holds none, or run the inner command directly.";

function matches(pattern, text, flags) {
  try {
    return new RegExp(pattern, flags).test(text);
  } catch {
    return false;
  }
}

function targetFile(toolInput) {
  for (const key of TARGET_FILE_KEYS) {
    if (typeof toolInput[key] === "string") return toolInput[key];
  }
  return "";
}

function toolRuleApplies(rule, toolName, toolInput) {
  if (typeof rule.tool !== "string" || !matches(rule.tool, toolName)) return false;
  return typeof rule.path !== "string" || matches(rule.path, targetFile(toolInput), "i");
}

function subcommandOf(invocation) {
  if (invocation[0] === "git") {
    const parsed = gitSubcommandArguments(invocation);
    return parsed ? parsed.subcommand : null;
  }
  if (invocation[0] === "gh") return nonFlagTokensAfterGh(invocation).join(" ");
  return null;
}

function commandRuleApplies(rule, segments) {
  const command = rule.command;
  if (!command || !Array.isArray(command.subcommands)) return false;
  return invocationsOf(command.program, segments).some((invocation) => {
    const subcommand = subcommandOf(invocation);
    if (subcommand === null) return false;
    const governed = command.subcommands.some(
      (candidate) => subcommand === candidate || subcommand.startsWith(`${candidate} `),
    );
    if (!governed) return false;
    return (
      typeof command.argument !== "string" ||
      invocation.some((token) => matches(command.argument, token))
    );
  });
}

function refusal(unmet) {
  const lines = unmet.map((rule) => `${rule.action} is governed by @${rule.skill}`);
  const skills = [...new Set(unmet.map((rule) => `@${rule.skill}`))].join(", ");
  return (
    `skill-load-gate: ${lines.join("; ")}, not loaded in this session. ` +
    `Load ${skills} with the Skill tool, then run the action again in a later message. ` +
    READING_IS_NOT_LOADING
  );
}

function decide(permissionDecision, permissionDecisionReason) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision, permissionDecisionReason },
    }) + "\n",
  );
}

async function main() {
  const input = readHookInput();
  if (!input || typeof input.tool_name !== "string") return;
  if (input.agent_id) return;
  if (typeof input.transcript_path !== "string") return;

  const table = readGateTable();
  if (!table) return;

  const toolInput = input.tool_input && typeof input.tool_input === "object" ? input.tool_input : {};
  let applicable;
  if (input.tool_name === "Bash") {
    if (typeof toolInput.command !== "string") return;
    const scans = scansUnderEitherShellReading(toolInput.command);
    if (scans.some((segments) => segments[UNWRAP_DEPTH_EXCEEDED])) {
      decide("ask", UNSCANNED_COMMAND);
      return;
    }
    const scanned = scans.flat();
    applicable = table.rules.filter((rule) => commandRuleApplies(rule, scanned));
  } else {
    applicable = table.rules.filter((rule) => toolRuleApplies(rule, input.tool_name, toolInput));
  }
  if (applicable.length === 0) return;

  const available = await skillsAvailableInSession(input.transcript_path);
  const unmet = applicable.filter(
    (rule) => typeof rule.skill !== "string" || !available.has(rule.skill.toLowerCase()),
  );
  if (unmet.length === 0) return;

  decide("deny", refusal(unmet));
}

main().catch(() => {});
