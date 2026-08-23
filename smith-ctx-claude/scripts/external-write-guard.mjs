#!/usr/bin/env node
import { readFileSync } from "node:fs";

const PUBLIC_EXTERNAL_WRITE_PATTERNS = [
  /mcp__plugin_atlassian_atlassian__(createJiraIssue|editJiraIssue|transitionJiraIssue|addCommentToJiraIssue|addWorklogToJiraIssue|createIssueLink|createConfluencePage|updateConfluencePage|createConfluenceFooterComment|createConfluenceInlineComment)$/,
  /mcp__plugin_Notion_notion__notion-(create|update|move|duplicate)-/,
  /mcp__plugin_slack_slack__slack_send_message(?!_draft)/,
  /mcp__plugin_slack_slack__slack_schedule_message$/,
];

function readHookInput() {
  try {
    return JSON.parse(readFileSync(0, "utf-8"));
  } catch {
    return null;
  }
}

function isExternalWrite(toolName) {
  return PUBLIC_EXTERNAL_WRITE_PATTERNS.some((pattern) => pattern.test(toolName));
}

function consentReason(toolName) {
  return (
    `External write '${toolName}' is human-facing content: @smith-guidance ` +
    `requires a per-artifact explicit yes (draft it, show it, wait). Prefer a ` +
    `*_draft variant where one exists. Approve only if the user has read and ` +
    `okayed THIS write.`
  );
}

function main() {
  const input = readHookInput();
  const toolName = input && input.tool_name;
  if (typeof toolName !== "string") return;
  if (!isExternalWrite(toolName)) return;

  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: consentReason(toolName),
      },
    }) + "\n",
  );
}

main();
