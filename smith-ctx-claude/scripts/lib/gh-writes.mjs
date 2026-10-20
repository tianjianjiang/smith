import {
  ghApiCommentWrite,
  isCloseOrReopen,
  nonFlagTokensAfterGh,
  valueFlagsFor,
  withAttachedFlagsSplit,
} from "./gh-command.mjs";

const GH_REVIEW_SUBMIT_LONG_FLAGS = new Set(["--approve", "--comment", "--request-changes"]);
const GH_REVIEW_SUBMIT_CHARS = new Set(["a", "c", "r"]);
export const BOT_THREAD_REPLY = "gh pr-review comments reply";
export const PR_REVIEW_PUBLISHING_FLAGS = new Set(["--add-comment", "--submit"]);
const SHORT_FLAG_LETTERS = /^-([A-Za-z]+)/;

function hasReviewSubmitFlag(tokens) {
  return tokens.some((token) => {
    if (token.startsWith("--")) return GH_REVIEW_SUBMIT_LONG_FLAGS.has(token);
    const letters = SHORT_FLAG_LETTERS.exec(token);
    return letters !== null && [...letters[1]].some((char) => GH_REVIEW_SUBMIT_CHARS.has(char));
  });
}

export function flagTokens(tokens, subcommand) {
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

export function ghExternalWriteCommand(tokens, expands) {
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
  if (resource === "pr-review" && subcommand === "review" && normalized.some((token) => PR_REVIEW_PUBLISHING_FLAGS.has(token))) {
    return "gh pr-review review";
  }
  if (resource === "api") return ghApiCommentWrite(normalized, expands);
  return null;
}
