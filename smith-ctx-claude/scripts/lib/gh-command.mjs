export const GH_GLOBAL_VALUE_FLAGS = new Set(["-R", "--repo", "--hostname"]);
const GRAPHQL_MUTATION_KEYWORD = /\bmutation\b/;
const GH_GRAPHQL_COMMENT_MUTATIONS =
  /\b(addComment|addPullRequestReview|submitPullRequestReview|updatePullRequestReview|deletePullRequestReview|addPullRequestReviewComment|updatePullRequestReviewComment|addPullRequestReviewThread|addPullRequestReviewThreadReply|updateIssueComment|deleteIssueComment|addDiscussionComment|updateDiscussionComment|deleteDiscussionComment)\b/g;
const GH_GRAPHQL_PULL_REQUEST_MUTATIONS =
  /\b(createPullRequest|updatePullRequest|mergePullRequest|enablePullRequestAutoMerge|revertPullRequest)\b/;
const GRAPHQL_CREATE_MUTATION = /^(add|submit)/;
const GRAPHQL_UPDATE_MUTATION = /^update/;
const GRAPHQL_ENDPOINT = /(^|\/)graphql\/?$/;
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
const GH_SHORT_FLAGS_TAKING_A_VALUE = new Set([...GH_API_FLAGS_TAKING_A_VALUE].filter((flag) => flag.length === 2));
const GH_CLOSE_SHORT_FLAGS_TAKING_A_VALUE = new Set([...GH_SHORT_FLAGS_TAKING_A_VALUE, "-c"]);
const GH_API_REST_ACTIONS = { POST: "create", PUT: "edit", PATCH: "edit", DELETE: "delete" };
const GH_API_COMMENTS_PATH = /\/(comments|reviews)(\/|\?|#|$)/i;
const GH_API_PULLS_PATH = /\/pulls(\/[^/?#]+)?\/?([?#]|$)/i;
const GH_API_PULL_MERGE_PATH = /\/pulls\/[^/?#]+\/merge\/?([?#]|$)/i;
const GH_API_ISSUE_PATH = /\/issues\/[^/?#]+\/?([?#]|$)/i;
export const GH_BODY_VALUE_FLAGS = ["-b", "--body", "-F", "--body-file"];
const GH_PR_REVIEW_VALUE_FLAGS = [
  "--pr",
  "--thread-id",
  "--review-id",
  "--path",
  "--line",
  "--side",
  "--start-line",
  "--start-side",
  "--event",
  "--commit",
];
const GH_PR_ISSUE_VALUE_FLAGS = [
  "-t",
  "--title",
  "-B",
  "--base",
  "-H",
  "--head",
  "-a",
  "--assignee",
  "-l",
  "--label",
  "-m",
  "--milestone",
  "-r",
  "--reviewer",
  "-p",
  "--project",
  "-T",
  "--template",
  "--add-assignee",
  "--remove-assignee",
  "--add-label",
  "--remove-label",
  "--add-project",
  "--remove-project",
  "--add-reviewer",
  "--remove-reviewer",
  "--reason",
  "--duplicate-of",
  "--subject",
  "-A",
  "--author-email",
  "--match-head-commit",
  "--recover",
];
const GH_BOOLEAN_SHORT_FLAGS_BY_SUBCOMMAND = new Map([
  ["review", new Set(["-a", "-r"])],
  ["merge", new Set(["-m", "-r"])],
]);
export const GH_WRITE_VALUE_FLAGS = new Set([
  ...GH_API_FLAGS_TAKING_A_VALUE,
  ...GH_BODY_VALUE_FLAGS,
  "--reason",
  "--duplicate-of",
  ...GH_PR_REVIEW_VALUE_FLAGS,
]);
const GH_CLOSE_VALUE_FLAGS = new Set([...GH_WRITE_VALUE_FLAGS, "-c", "--comment"]);

export function nonFlagTokensAfterGh(tokens) {
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

export function isCloseOrReopen(subcommand) {
  return subcommand === "close" || subcommand === "reopen";
}

export function valueFlagsFor(subcommand) {
  return isCloseOrReopen(subcommand) ? GH_CLOSE_VALUE_FLAGS : GH_WRITE_VALUE_FLAGS;
}

export function ghNonBodyValueFlags(subcommand) {
  const flags = [...GH_GLOBAL_VALUE_FLAGS, ...GH_PR_ISSUE_VALUE_FLAGS, ...GH_PR_REVIEW_VALUE_FLAGS];
  const booleanShortFlags = GH_BOOLEAN_SHORT_FLAGS_BY_SUBCOMMAND.get(subcommand);
  return new Set(booleanShortFlags ? flags.filter((flag) => !booleanShortFlags.has(flag)) : flags);
}

export function withAttachedFlagsSplit(tokens) {
  const subcommand = nonFlagTokensAfterGh(tokens)[1];
  const valueFlags = valueFlagsFor(subcommand);
  const shortValueFlags = isCloseOrReopen(subcommand) ? GH_CLOSE_SHORT_FLAGS_TAKING_A_VALUE : GH_SHORT_FLAGS_TAKING_A_VALUE;
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
    if (token.length > 2 && shortValueFlags.has(shortFlag)) {
      const remainder = token.slice(2);
      result.push(shortFlag, remainder.startsWith("=") ? remainder.slice(1) : remainder);
      continue;
    }
    result.push(token);
  }
  return result;
}

export function ghApiArgs(normalized) {
  return normalized.slice(normalized.indexOf("api") + 1);
}

export function ghApiEndpointAndMethod(rest) {
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

function graphqlMutationText(text) {
  const start = text.search(GRAPHQL_MUTATION_KEYWORD);
  return start === -1 ? null : text.slice(start);
}

function graphqlMutationAction(text) {
  const mutation = graphqlMutationText(text);
  if (mutation === null) return null;
  const names = [...mutation.matchAll(GH_GRAPHQL_COMMENT_MUTATIONS)].map((match) => match[1]);
  if (names.length === 0) return null;
  if (names.some((name) => GRAPHQL_CREATE_MUTATION.test(name))) return "create";
  return names.some((name) => GRAPHQL_UPDATE_MUTATION.test(name)) ? "update" : "delete";
}

export function ghApiCommentAction(normalized, expands) {
  const rest = ghApiArgs(normalized);
  const { endpoint, method } = ghApiEndpointAndMethod(rest);
  if (endpoint && GRAPHQL_ENDPOINT.test(endpoint)) {
    const opaqueQuery = rest.some(
      (token) => token.startsWith("query=@") || (expands && token.startsWith("query=") && /[$`]/.test(token)),
    );
    if (rest.includes("--input") || opaqueQuery) {
      return { subject: "gh api graphql (query source opaque to the hook)", action: "opaque" };
    }
    const action = graphqlMutationAction(normalized.join(" "));
    return action ? { subject: "gh api graphql", action } : null;
  }
  if (!endpoint || !GH_API_COMMENTS_PATH.test(endpoint) || !Object.hasOwn(GH_API_REST_ACTIONS, method || "")) return null;
  return { subject: `gh api ${endpoint}`, action: GH_API_REST_ACTIONS[method] };
}

export function ghApiCommentWrite(normalized, expands) {
  const write = ghApiCommentAction(normalized, expands);
  return write ? write.subject : null;
}

function ghApiPullRequestAction(normalized) {
  const { endpoint, method } = ghApiEndpointAndMethod(ghApiArgs(normalized));
  if (!endpoint) return null;
  const create = { subject: `gh api ${endpoint}`, action: "create", resource: "pull request" };
  if (GRAPHQL_ENDPOINT.test(endpoint)) {
    const mutation = graphqlMutationText(normalized.join(" "));
    return mutation !== null && GH_GRAPHQL_PULL_REQUEST_MUTATIONS.test(mutation) ? create : null;
  }
  if (GH_API_PULL_MERGE_PATH.test(endpoint)) return method === "PUT" ? create : null;
  if (GH_API_ISSUE_PATH.test(endpoint)) return method === "PATCH" ? { ...create, action: "edit" } : null;
  if (!GH_API_PULLS_PATH.test(endpoint)) return null;
  if (method === "POST") return create;
  return method === "PATCH" ? { ...create, action: "edit" } : null;
}

export function ghApiPrTextAction(normalized, expands) {
  return ghApiPullRequestAction(normalized) || ghApiCommentAction(normalized, expands);
}
