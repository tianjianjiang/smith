#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { git, readHookInput } from "../../smith-git/scripts/lib/hook-utils.mjs";
import { GH_GLOBAL_VALUE_FLAGS, nonFlagTokensAfterGh } from "./lib/gh-command.mjs";
import { commandExpands, contentLeaves, ghPayload, mcpPayload } from "./lib/write-payload.mjs";
import { invokedShipOrReview, previewState } from "./lib/write-preview.mjs";

const PUBLIC_EXTERNAL_WRITE_PATTERNS = [
  /mcp__plugin_atlassian_atlassian__(createJiraIssue|editJiraIssue|transitionJiraIssue|addCommentToJiraIssue|addOrEditJiraIssueComment|addWorklogToJiraIssue|createIssueLink|createConfluencePage|updateConfluencePage|createConfluenceContent|updateConfluenceContent|createConfluenceFooterComment|createConfluenceInlineComment|executeWrite|executeDestructive)$/,
  /mcp__plugin_Notion_notion__notion-(create|update|move|duplicate|delete|restore)-/,
  /mcp__plugin_Notion_notion__notion-send-message-to-session$/,
  /mcp__plugin_slack_slack__slack_send_message(?!_draft)/,
  /mcp__plugin_slack_slack__slack_(schedule_message|create_canvas|update_canvas|create_list|update_list|add_list_record|update_list_record|complete_file_upload|create_conversation)$/,
];

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
const DRAFT_VARIANT_HINT = "Prefer a *_draft variant where one exists.";
const BOT_THREAD_REPLY = "gh pr-review comments reply";
const GH_BODY_VALUE_FLAGS = ["-b", "--body", "-F", "--body-file"];
const ATTACHED_SHORT_FLAG = /^-[A-Za-z]./;
const SHORT_FLAG_LETTERS = /^-([A-Za-z]+)/;
const FLAG_SHAPE = /^--?[A-Za-z]/;
const REVIEW_ACTION_WORDS = {
  "-a": "approve",
  "--approve": "approve",
  "-r": "request-changes",
  "--request-changes": "request-changes",
  "-c": "comment",
  "--comment": "comment",
};
const CLOSE_ACTION_WORDS = { "-d": "delete-branch", "--delete-branch": "delete-branch" };
const GRAPHQL_ENDPOINT = /(^|\/)graphql\/?$/;
const GH_TARGET_ENV = /\bGH_(REPO|HOST)=/;
const MENTIONS_GH = /\bgh\b/;
const HOST_QUALIFIED_REPO = /^[^/]+\/[^/]+\/[^/]+$/;
const THREAD_AUTHORS_QUERY =
  "query($id: ID!) { node(id: $id) { ... on PullRequestReviewThread { comments(first: 100) { totalCount nodes { author { __typename } } } } } }";
const THREAD_AUTHOR_KINDS =
  '.data.node.comments as $c | if $c.totalCount > ($c.nodes | length) then "Unknown" else ([$c.nodes[] | (.author.__typename // "Unknown")] | unique | join(",")) end';
const GH_WRITE_VALUE_FLAGS = new Set([
  ...GH_API_FLAGS_TAKING_A_VALUE,
  ...GH_BODY_VALUE_FLAGS,
  "--reason",
  "--duplicate-of",
  "--pr",
  "--thread-id",
  "--review-id",
]);
const GH_CLOSE_VALUE_FLAGS = new Set([...GH_WRITE_VALUE_FLAGS, "-c", "--comment"]);
const KNOWN_GH_WRITE_FLAGS = new Set([
  ...GH_WRITE_VALUE_FLAGS,
  ...Object.keys(REVIEW_ACTION_WORDS),
  ...Object.keys(CLOSE_ACTION_WORDS),
  "--paginate",
  "--silent",
  "-i",
  "--include",
]);
const FIXED_IN_REPLY = /^fixed in ([0-9a-f]{7,40})\.?$/i;

function isExternalWrite(toolName) {
  return PUBLIC_EXTERNAL_WRITE_PATTERNS.some((pattern) => pattern.test(toolName));
}

function unverifiableReason(subject, cause) {
  return [
    `External write '${subject}': the guard cannot check that its payload was shown in chat ` +
      `and answered by the user (${cause}).`,
    DRAFT_VARIANT_HINT,
    "Approve only if you have read THIS payload or action in chat and answered it.",
  ].join(" ");
}

function previewMissingReason(subject, state) {
  const missing = state.previewed
    ? "part of its payload was shown but not yet answered by the user (or its preview file changed after the reply)"
    : "part of its payload has not been shown in chat";
  return (
    `External write '${subject}' blocked: ${missing}. Show every text field and target it will ` +
    "write, verbatim: short parts in chat, one part per turn; long text saved to a durable file " +
    "whose absolute path you give on a line that says 'preview'. Wait for the user's reply to each part, and call it again only " +
    "on a yes (@smith-guidance External writes)."
  );
}

function subagentReason(subject) {
  return (
    `External write '${subject}' blocked: a subagent cannot show its payload to the user. ` +
    "Return the draft to the main thread, which shows it and writes after the user's reply."
  );
}

function withAttachedFlagsSplit(tokens) {
  const valueFlags = valueFlagsFor(nonFlagTokensAfterGh(tokens)[1]);
  const result = [];
  for (const [index, token] of tokens.entries()) {
    if (valueFlags.has(tokens[index - 1])) {
      result.push(token);
      continue;
    }
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

function hasReviewSubmitFlag(tokens) {
  return tokens.some((token) => {
    if (token.startsWith("--")) return GH_REVIEW_SUBMIT_LONG_FLAGS.has(token);
    const letters = SHORT_FLAG_LETTERS.exec(token);
    return letters !== null && [...letters[1]].some((char) => GH_REVIEW_SUBMIT_CHARS.has(char));
  });
}

function ghApiArgs(normalized) {
  return normalized.slice(normalized.indexOf("api") + 1);
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

function flagValues(tokens, flags) {
  return tokens.flatMap((token, index) =>
    flags.includes(token) && tokens[index + 1] !== undefined ? [tokens[index + 1]] : [],
  );
}

function positionalArgs(normalized, subcommand) {
  const valueFlags = new Set([...GH_GLOBAL_VALUE_FLAGS, ...GH_BODY_VALUE_FLAGS]);
  if (isCloseOrReopen(subcommand)) {
    valueFlags.add("-c");
    valueFlags.add("--comment");
  }
  const result = [];
  for (let index = 1; index < normalized.length; index += 1) {
    const token = normalized[index];
    if (valueFlags.has(token)) {
      index += 1;
      continue;
    }
    if (!token.startsWith("-")) result.push(token);
  }
  return result;
}

function isCloseOrReopen(subcommand) {
  return subcommand === "close" || subcommand === "reopen";
}

function valueFlagsFor(subcommand) {
  return isCloseOrReopen(subcommand) ? GH_CLOSE_VALUE_FLAGS : GH_WRITE_VALUE_FLAGS;
}

function flagTokens(tokens, subcommand) {
  const valueFlags = valueFlagsFor(subcommand);
  const result = [];
  for (let index = 1; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (!token.startsWith("-")) continue;
    result.push(token);
    if (valueFlags.has(token)) index += 1;
  }
  return result;
}

function ghActionWords(normalized) {
  const [resource, subcommand] = nonFlagTokensAfterGh(normalized);
  if (resource === "api") {
    const { method } = ghApiEndpointAndMethod(ghApiArgs(normalized));
    return method ? [method] : [];
  }
  const words = subcommand === "review" ? REVIEW_ACTION_WORDS : CLOSE_ACTION_WORDS;
  return [...new Set(normalized.filter((token) => token in words).map((token) => words[token]))];
}

function ghTargets(normalized) {
  const targets = flagValues(normalized, ["-R", "--repo", "--hostname"]);
  const [resource, subcommand] = nonFlagTokensAfterGh(normalized);
  if (resource === "api") {
    const { endpoint } = ghApiEndpointAndMethod(ghApiArgs(normalized));
    if (endpoint) targets.push(endpoint);
  } else if (resource === "pr-review") {
    targets.push(...flagValues(normalized, ["--pr", "--thread-id"]));
    targets.push(...positionalArgs(normalized, subcommand).slice(3));
  } else {
    targets.push(...positionalArgs(normalized, subcommand).slice(2));
  }
  return targets;
}

function ghExternalWriteCommand(tokens, expands) {
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
    isCloseOrReopen(subcommand) &&
    flagTokens(normalized, subcommand).some((token) => token === "--comment" || /^-[A-Za-z]*c/.test(token))
  ) {
    return `gh ${resource} ${subcommand} --comment`;
  }
  if (resource === "pr" && subcommand === "review") {
    return hasReviewSubmitFlag(normalized.slice(1)) ? "gh pr review" : null;
  }
  if (resource === "pr-review" && subcommand === "comments" && normalized.includes("reply")) {
    return BOT_THREAD_REPLY;
  }
  if (resource === "api") {
    const rest = ghApiArgs(normalized);
    const { endpoint, method } = ghApiEndpointAndMethod(rest);
    if (endpoint && GRAPHQL_ENDPOINT.test(endpoint)) {
      const opaqueQuery = rest.some(
        (token) => token.startsWith("query=@") || (expands && token.startsWith("query=") && /[$`]/.test(token)),
      );
      if (rest.includes("--input") || opaqueQuery) {
        return "gh api graphql (query source opaque to the hook)";
      }
      return GH_GRAPHQL_WRITE_MUTATIONS.test(tokens.join(" ")) ? "gh api graphql" : null;
    }
    if (!endpoint || !GH_API_COMMENTS_PATH.test(endpoint)) return null;
    return GH_API_WRITE_METHODS.has(method) ? `gh api ${endpoint}` : null;
  }
  return null;
}

function threadHasOnlyBotAuthors(threadId, cwd) {
  try {
    const kinds = execFileSync(
      "gh",
      ["api", "graphql", "-f", `query=${THREAD_AUTHORS_QUERY}`, "-f", `id=${threadId}`, "--jq", THREAD_AUTHOR_KINDS],
      { cwd, encoding: "utf-8", timeout: 10000, stdio: ["ignore", "pipe", "ignore"] },
    );
    return kinds.trim() === "Bot";
  } catch {
    return false;
  }
}

function isFixedInReply(payload, cwd, normalized, context) {
  if (payload.opaque || payload.readsFile || !cwd) return false;
  const content = contentLeaves(payload.leaves, payload.targets);
  const match = content.length === 1 && FIXED_IN_REPLY.exec(content[0]);
  if (!match) return false;
  if (git(cwd, ["cat-file", "-e", `${match[1]}^{commit}`], { failOpen: true }) === null) return false;
  if (normalized.includes("--hostname")) return false;
  if (flagValues(normalized, ["-R", "--repo"]).some((repo) => HOST_QUALIFIED_REPO.test(repo))) return false;
  const threadIds = flagValues(normalized, ["--thread-id"]);
  const bodyFlagCount = normalized.filter((token) => GH_BODY_VALUE_FLAGS.includes(token)).length;
  const threadFlagValues = flagValues(normalized, ["--pr", "--thread-id", "--review-id"]);
  const extraPositionals = positionalArgs(normalized, "comments")
    .slice(3)
    .filter((token) => !threadFlagValues.includes(token));
  return (
    threadIds.length === 1 &&
    bodyFlagCount === 1 &&
    extraPositionals.length === 0 &&
    invokedShipOrReview(context.transcriptPath) &&
    threadHasOnlyBotAuthors(threadIds[0], cwd)
  );
}

function unscannable(subject) {
  return { subject, leaves: [], opaque: "the command could not be fully scanned" };
}

async function loadTokenizer() {
  try {
    return await import("../../smith-git/scripts/lib/git-command-tokenizer.mjs");
  } catch {
    return null;
  }
}

function bashExternalWrite(command, cwd, tokenizer, context = {}) {
  if (!tokenizer) {
    return MENTIONS_GH.test(command) ? unscannable("a gh command the shared tokenizer failed to load for") : null;
  }
  let segments;
  try {
    segments = tokenizer.unwrappedCommandSegments(command);
  } catch {
    return MENTIONS_GH.test(command) ? unscannable("a gh command the shared tokenizer could not split") : null;
  }
  if (segments[tokenizer.UNWRAP_DEPTH_EXCEEDED]) {
    return unscannable("a shell-wrapped command nested too deeply to fully unwrap");
  }
  const expands = commandExpands(command);
  const setsGhTarget = GH_TARGET_ENV.test(command);
  const multiStep = segments.length > 1;
  const subjects = [];
  const leaves = [];
  const targets = new Set();
  let opaque = null;
  for (const tokens of segments) {
    const matched = ghExternalWriteCommand(tokens, expands);
    if (!matched) continue;
    const normalized = withAttachedFlagsSplit(tokens);
    const subcommand = nonFlagTokensAfterGh(normalized)[1];
    let payload;
    try {
      payload = ghPayload(normalized, cwd, ghTargets(normalized), expands);
      payload.leaves.push(...ghActionWords(normalized));
      if (flagTokens(tokens, subcommand).some((token) => ATTACHED_SHORT_FLAG.test(token))) {
        payload.opaque = payload.opaque || "a short flag with letters or a value attached, which gh may parse differently";
      }
      const unknownFlag = flagTokens(normalized, subcommand).find(
        (token) => FLAG_SHAPE.test(token) && !KNOWN_GH_WRITE_FLAGS.has(token),
      );
      if (unknownFlag) {
        payload.opaque = payload.opaque || `the flag '${unknownFlag}', which the guard does not parse`;
      }
    } catch {
      payload = { leaves: [], targets: new Set(), opaque: "the hook failed while reading the command" };
    }
    if (
      context.verifyThread &&
      matched === BOT_THREAD_REPLY &&
      !multiStep &&
      !setsGhTarget &&
      isFixedInReply(payload, cwd, normalized, context)
    ) {
      continue;
    }
    if (!subjects.includes(matched)) subjects.push(matched);
    leaves.push(...payload.leaves);
    payload.targets.forEach((target) => targets.add(target));
    opaque = opaque || payload.opaque;
    if (payload.readsFile && multiStep) {
      opaque = opaque || "a body file read by a command that also runs other steps, which may change it first";
    }
  }
  if (subjects.length === 0) return null;
  if (setsGhTarget) {
    opaque = opaque || "GH_REPO or GH_HOST set on the command line, which changes the target unseen";
  }
  return { subject: subjects.join(", "), leaves, targets, opaque };
}

function matchedWrite(input, toolName, tokenizer) {
  if (toolName === "Bash") {
    const command = input.tool_input && input.tool_input.command;
    if (typeof command !== "string") return null;
    return bashExternalWrite(command, input.cwd, tokenizer, {
      verifyThread: true,
      transcriptPath: input.transcript_path,
    });
  }
  return isExternalWrite(toolName) ? { subject: toolName, ...mcpPayload(toolName, input.tool_input) } : null;
}

function decide(permissionDecision, reason) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision,
        permissionDecisionReason: reason,
      },
    }) + "\n",
  );
}

async function judgeWrite(input, write) {
  if (input.agent_id) return decide("deny", subagentReason(write.subject));
  if (write.opaque) return decide("ask", unverifiableReason(write.subject, write.opaque));
  if (contentLeaves(write.leaves, write.targets).length === 0) {
    return decide("ask", unverifiableReason(write.subject, "it carries no text to match"));
  }
  if (typeof input.transcript_path !== "string") {
    return decide("ask", unverifiableReason(write.subject, "no transcript path"));
  }
  const state = await previewState(input.transcript_path, write.leaves, { targets: write.targets });
  if (state.previewed && state.replied) return;
  decide("deny", previewMissingReason(write.subject, state));
}

async function main() {
  const input = readHookInput();
  const toolName = input && input.tool_name;
  if (typeof toolName !== "string") return;
  const tokenizer = await loadTokenizer();
  let write;
  try {
    write = matchedWrite(input, toolName, tokenizer);
  } catch {
    const command = input.tool_input && input.tool_input.command;
    const mayBeGhWrite = toolName === "Bash" && typeof command === "string" && MENTIONS_GH.test(command);
    if (isExternalWrite(toolName) || mayBeGhWrite) {
      decide("ask", unverifiableReason(toolName, "the hook failed while reading the call"));
    }
    return;
  }
  if (!write) return;
  try {
    await judgeWrite(input, write);
  } catch {
    decide("ask", unverifiableReason(write.subject, "the transcript or a preview file could not be read"));
  }
}

main().catch(() => {});
