#!/usr/bin/env node
import { readHookInput } from "../../smith-git/scripts/lib/hook-utils.mjs";

const PUBLIC_EXTERNAL_WRITE_PATTERNS = [
  /mcp__plugin_atlassian_atlassian__(createJiraIssue|editJiraIssue|transitionJiraIssue|addCommentToJiraIssue|addWorklogToJiraIssue|createIssueLink|createConfluencePage|updateConfluencePage|createConfluenceFooterComment|createConfluenceInlineComment)$/,
  /mcp__plugin_Notion_notion__notion-(create|update|move|duplicate)-/,
  /mcp__plugin_slack_slack__slack_send_message(?!_draft)/,
  /mcp__plugin_slack_slack__slack_schedule_message$/,
];

const GH_GLOBAL_VALUE_FLAGS = new Set(["-R", "--repo", "--hostname"]);
const GH_API_METHOD_FLAGS = new Set(["-X", "--method"]);
const GH_API_IMPLICIT_POST_FLAGS = new Set([
  "-f",
  "--raw-field",
  "-F",
  "--field",
  "--input",
]);
const GH_API_FLAGS_TAKING_A_VALUE = new Set([
  ...GH_GLOBAL_VALUE_FLAGS,
  ...GH_API_METHOD_FLAGS,
  ...GH_API_IMPLICIT_POST_FLAGS,
  "-H",
  "--header",
  "-p",
  "--preview",
  "-q",
  "--jq",
  "-t",
  "--template",
  "--cache",
]);
const GH_SHORT_FLAGS_TAKING_A_VALUE = new Set(
  [...GH_API_FLAGS_TAKING_A_VALUE, "-c"].filter((flag) => flag.length === 2),
);
const GH_API_WRITE_METHODS = new Set(["POST", "PUT", "PATCH", "DELETE"]);
const GH_API_COMMENTS_PATH = /\/(comments|reviews)(\/|\?|#|$)/i;
const GH_GRAPHQL_WRITE_MUTATIONS =
  /\bmutation\b[\s\S]*\b(addComment|addPullRequestReview|submitPullRequestReview|updatePullRequestReview|deletePullRequestReview|addPullRequestReviewComment|updatePullRequestReviewComment|addPullRequestReviewThread|addPullRequestReviewThreadReply|updateIssueComment|deleteIssueComment|addDiscussionComment|updateDiscussionComment|deleteDiscussionComment)\b/;
const GH_REVIEW_SUBMIT_LONG_FLAGS = new Set(["--approve", "--comment", "--request-changes"]);
const GH_REVIEW_SUBMIT_CHARS = new Set(["a", "c", "r"]);
const GH_REVIEW_BODY_CHARS = new Set(["b", "F"]);
const DRAFT_VARIANT_HINT = "Prefer a *_draft variant where one exists.";

function isExternalWrite(toolName) {
  return PUBLIC_EXTERNAL_WRITE_PATTERNS.some((pattern) => pattern.test(toolName));
}

function consentReason(subject, ...extraGuidance) {
  return [
    `External write '${subject}' is human-facing content: @smith-guidance ` +
      `requires a per-artifact explicit yes (draft it, show it, wait).`,
    ...extraGuidance,
    "Approve only if the user has read and okayed THIS write.",
  ].join(" ");
}

function withAttachedFlagsSplit(tokens) {
  const result = [];
  for (const token of tokens) {
    if (token.startsWith("--") && token.includes("=")) {
      const equalsIndex = token.indexOf("=");
      result.push(token.slice(0, equalsIndex), token.slice(equalsIndex + 1));
      continue;
    }
    const shortFlag = token.slice(0, 2);
    if (token.length > 2 && GH_SHORT_FLAGS_TAKING_A_VALUE.has(shortFlag)) {
      const remainder = token.slice(2);
      result.push(shortFlag, remainder.startsWith("=") ? remainder.slice(1) : remainder);
      continue;
    }
    result.push(token);
  }
  return result;
}

function isReviewFlagChar(char) {
  return GH_REVIEW_SUBMIT_CHARS.has(char) || GH_REVIEW_BODY_CHARS.has(char);
}

function hasReviewSubmitFlag(tokens) {
  return tokens.some((token) => {
    if (token.startsWith("--")) return GH_REVIEW_SUBMIT_LONG_FLAGS.has(token);
    if (token[0] !== "-" || token.length < 2) return false;
    const chars = [...token.slice(1)];
    return chars.every(isReviewFlagChar) && chars.some((char) => GH_REVIEW_SUBMIT_CHARS.has(char));
  });
}

function nonFlagTokensAfterGh(tokens) {
  const result = [];
  for (let index = 1; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (GH_GLOBAL_VALUE_FLAGS.has(token)) {
      index += 1;
      continue;
    }
    if (token.startsWith("-")) continue;
    result.push(token);
  }
  return result;
}

function ghApiEndpointAndMethod(rest) {
  let endpoint = null;
  let method = null;
  for (let index = 0; index < rest.length; index += 1) {
    const token = rest[index];
    if (GH_API_METHOD_FLAGS.has(token)) {
      method = (rest[index + 1] || "").toUpperCase();
      index += 1;
      continue;
    }
    if (GH_API_FLAGS_TAKING_A_VALUE.has(token)) {
      if (GH_API_IMPLICIT_POST_FLAGS.has(token) && method === null) method = "POST";
      index += 1;
      continue;
    }
    if (token.startsWith("-")) continue;
    if (endpoint === null) endpoint = token;
  }
  return { endpoint, method };
}

function ghExternalWriteCommand(tokens) {
  if (tokens[0] !== "gh") return null;
  const normalized = withAttachedFlagsSplit(tokens);
  const positional = nonFlagTokensAfterGh(normalized);
  const [resource, subcommand] = positional;
  const isPrOrIssue = resource === "pr" || resource === "issue";

  if (isPrOrIssue && subcommand === "comment") {
    return `gh ${resource} comment`;
  }
  if (
    isPrOrIssue &&
    (subcommand === "close" || subcommand === "reopen") &&
    (normalized.includes("-c") || normalized.includes("--comment"))
  ) {
    return `gh ${resource} ${subcommand} --comment`;
  }
  if (resource === "pr" && subcommand === "review") {
    return hasReviewSubmitFlag(normalized.slice(1)) ? "gh pr review" : null;
  }
  if (resource === "pr-review" && subcommand === "comments" && normalized.includes("reply")) {
    return "gh pr-review comments reply";
  }
  if (resource === "api") {
    const apiIndex = normalized.indexOf("api");
    const rest = normalized.slice(apiIndex + 1);
    if (rest.includes("graphql") || rest.includes("/graphql")) {
      if (rest.includes("--input") || rest.some((token) => token.startsWith("query=@"))) {
        return "gh api graphql (query source opaque to the hook)";
      }
      return GH_GRAPHQL_WRITE_MUTATIONS.test(tokens.join(" ")) ? "gh api graphql" : null;
    }
    const { endpoint, method } = ghApiEndpointAndMethod(rest);
    if (!endpoint || !GH_API_COMMENTS_PATH.test(endpoint)) return null;
    return GH_API_WRITE_METHODS.has(method) ? `gh api ${endpoint}` : null;
  }
  return null;
}

async function bashExternalWrite(command) {
  let tokenizer;
  try {
    tokenizer = await import("./lib/git-command-tokenizer.mjs");
  } catch {
    return ["a Bash command that could not be scanned because the shared tokenizer failed to load"];
  }
  const segments = tokenizer.unwrappedCommandSegments(command);
  if (segments[tokenizer.UNWRAP_DEPTH_EXCEEDED]) {
    return ["a shell-wrapped command nested too deeply to fully unwrap"];
  }
  const matches = [];
  for (const tokens of segments) {
    const matched = ghExternalWriteCommand(tokens);
    if (matched && !matches.includes(matched)) matches.push(matched);
  }
  return matches;
}

function askDecision(reason) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: reason,
      },
    }) + "\n",
  );
}

async function main() {
  const input = readHookInput();
  const toolName = input && input.tool_name;
  if (typeof toolName !== "string") return;

  if (toolName === "Bash") {
    const command = input.tool_input && input.tool_input.command;
    if (typeof command !== "string") return;
    const matches = await bashExternalWrite(command);
    if (matches.length > 0) askDecision(consentReason(matches.join(", ")));
    return;
  }

  if (isExternalWrite(toolName)) askDecision(consentReason(toolName, DRAFT_VARIANT_HINT));
}

main().catch(() => {});
