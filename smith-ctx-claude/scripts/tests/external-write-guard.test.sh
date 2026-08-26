#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../external-write-guard.mjs"

fail() { echo "FAIL: $1"; exit 1; }
run() { printf '%s' "$1" | node "$HOOK"; }
asks() { run "$2" | grep -q '"permissionDecision":"ask"' || fail "$1: expected ask"; }
silent() {
  out=$(run "$2") || fail "$1: hook crashed"
  [ -z "$out" ] || fail "$1: expected silent, got: $out"
}
reason_includes() {
  out=$(run "$3") || fail "$1: hook crashed"
  echo "$out" | grep -q "$2" || fail "$1: expected reason to include '$2', got: $out"
}

asks   "editJiraIssue"        '{"tool_name":"mcp__plugin_atlassian_atlassian__editJiraIssue","tool_input":{}}'
asks   "addCommentToJira"     '{"tool_name":"mcp__plugin_atlassian_atlassian__addCommentToJiraIssue","tool_input":{}}'
asks   "notion-create-pages"  '{"tool_name":"mcp__plugin_Notion_notion__notion-create-pages","tool_input":{}}'
asks   "notion-update-page"   '{"tool_name":"mcp__plugin_Notion_notion__notion-update-page","tool_input":{}}'
asks   "notion-move-pages"    '{"tool_name":"mcp__plugin_Notion_notion__notion-move-pages","tool_input":{}}'
asks   "notion-duplicate"     '{"tool_name":"mcp__plugin_Notion_notion__notion-duplicate-page","tool_input":{}}'
asks   "confluence create"    '{"tool_name":"mcp__plugin_atlassian_atlassian__createConfluencePage","tool_input":{}}'
asks   "confluence update"    '{"tool_name":"mcp__plugin_atlassian_atlassian__updateConfluencePage","tool_input":{}}'
asks   "slack non-draft send" '{"tool_name":"mcp__plugin_slack_slack__slack_send_message","tool_input":{}}'
asks   "slack schedule send"  '{"tool_name":"mcp__plugin_slack_slack__slack_schedule_message","tool_input":{}}'

silent "slack draft variant"  '{"tool_name":"mcp__plugin_slack_slack__slack_send_message_draft","tool_input":{}}'
silent "getJiraIssue read"    '{"tool_name":"mcp__plugin_atlassian_atlassian__getJiraIssue","tool_input":{}}'
silent "notion-fetch read"    '{"tool_name":"mcp__plugin_Notion_notion__notion-fetch","tool_input":{}}'
silent "unrelated tool"       '{"tool_name":"Read","tool_input":{"file_path":"/x"}}'
silent "malformed stdin"      'not json at all'

bash_cmd() {
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1")"
}

deeply_nested_eval_payload() {
  node -e '
    let cmd = "gh pr comment 123 --body hi";
    for (let i = 0; i < 9; i++) cmd = "eval " + JSON.stringify(cmd);
    process.stdout.write(JSON.stringify({tool_name:"Bash",tool_input:{command:cmd}}));
  '
}

asks   "gh pr comment"        "$(bash_cmd 'gh pr comment 123 --body "lgtm"')"
asks   "gh issue comment"     "$(bash_cmd 'gh issue comment 45 --body "ping"')"
asks   "gh pr review approve" "$(bash_cmd 'gh pr review 123 --approve')"
asks   "gh pr review comment" "$(bash_cmd 'gh pr review 123 -c -b "nit"')"
asks   "gh pr review request-changes" "$(bash_cmd 'gh pr review 123 --request-changes -b "fix this"')"
asks   "gh api comments POST" "$(bash_cmd 'gh api repos/o/r/issues/123/comments -f body=hi')"
asks   "gh api reviews POST"  "$(bash_cmd 'gh api -X POST repos/o/r/pulls/123/reviews -f body=hi')"
asks   "gh api graphql addComment" "$(bash_cmd "gh api graphql -f query='mutation { addComment(input: {}) { clientMutationId } }'")"
asks   "gh api graphql addPullRequestReview" "$(bash_cmd "gh api graphql -f query='mutation { addPullRequestReview(input: {}) { clientMutationId } }'")"
asks   "gh command chained with harmless prefix" "$(bash_cmd 'echo start && gh pr comment 1 --body "x"')"
asks   "gh api graphql --input (opaque query source)" "$(bash_cmd 'gh api graphql --input mutation.json')"
asks   "gh api graphql -f query=@file (opaque query source)" "$(bash_cmd 'gh api graphql -f query=@mutation.graphql')"

reason_includes "chained gh commands name both writes" "gh pr comment" \
  "$(bash_cmd 'gh pr comment 1 --body hi && gh pr review 2 --approve')"
reason_includes "chained gh commands name both writes" "gh pr review" \
  "$(bash_cmd 'gh pr comment 1 --body hi && gh pr review 2 --approve')"
asks   "gh api attached -XPOST"     "$(bash_cmd 'gh api -XPOST repos/o/r/issues/123/comments --input body.json')"
asks   "gh api assignment --method=POST" "$(bash_cmd 'gh api --method=POST repos/o/r/pulls/123/reviews --input body.json')"
asks   "gh api comments with query-string suffix" "$(bash_cmd 'gh api "repos/o/r/issues/123/comments?foo=bar" -f body=hi')"
asks   "eval-wrapped gh pr comment"  "$(bash_cmd 'eval "gh pr comment 123 --body hi"')"
asks   "sh -c wrapped gh pr comment" "$(bash_cmd 'sh -c "gh pr comment 123 --body hi"')"
asks   "bash -c wrapped gh pr review" "$(bash_cmd 'bash -c "gh pr review 123 --approve"')"
asks   "command-prefixed gh pr comment" "$(bash_cmd 'command gh pr comment 123 --body hi')"
asks   "absolute-path gh pr comment"  "$(bash_cmd '/usr/bin/gh pr comment 123 --body hi')"
asks   "nested eval inside sh -c"     "$(bash_cmd 'sh -c "eval \"gh pr comment 123 --body hi\""')"
asks   "gh api comments --input alone implies POST" "$(bash_cmd 'gh api repos/o/r/issues/123/comments --input body.json')"
asks   "gh api -X=POST equals-form on short flag" "$(bash_cmd 'gh api -X=POST repos/o/r/issues/123/comments --input body.json')"
asks   "gh pr review clustered short flags -ab" "$(bash_cmd 'gh pr review 123 -ab lgtm')"
asks   "gh pr review --approve=true assignment form" "$(bash_cmd 'gh pr review 123 --approve=true')"
asks   "gh pr-review comments reply" "$(bash_cmd 'gh pr-review comments reply --pr 1 -R o/r --thread-id PRRT_x --body test')"
asks   "gh pr-review comments reply with --pr before reply" "$(bash_cmd 'gh pr-review comments --pr 1 -R o/r reply --thread-id PRRT_x --body test')"
asks   "-R interspersed before resource"  "$(bash_cmd 'gh -R o/r pr comment 1 --body x')"
asks   "-R interspersed between resource and subcommand" "$(bash_cmd 'gh pr -R o/r comment 1 --body x')"
asks   "-R interspersed before api endpoint" "$(bash_cmd 'gh api -R o/r repos/o/r/issues/1/comments -f body=x')"
asks   "gh api leading-slash /graphql mutation" "$(bash_cmd "gh api /graphql -f query='mutation { addComment(input: {}) { clientMutationId } }'")"

silent "gh pr-review threads resolve"  "$(bash_cmd 'gh pr-review threads resolve --pr 1 -R o/r --thread-id PRRT_x')"
silent "gh pr-review threads list"     "$(bash_cmd 'gh pr-review threads list --pr 1 -R o/r --unresolved')"
silent "gh pr review no submit flag" "$(bash_cmd 'gh pr review 123')"
asks   "command -p prefixed gh pr comment" "$(bash_cmd 'command -p gh pr comment 123 --body hi')"
asks   "bash -e -c wrapped gh pr comment" "$(bash_cmd 'bash -e -c "gh pr comment 123 --body hi"')"
asks   "bash -ec clustered short flags wrapped gh pr comment" "$(bash_cmd 'bash -ec "gh pr comment 123 --body hi"')"
asks   "bash -O extglob -c (value-taking shell option before -c)" "$(bash_cmd 'bash -O extglob -c "gh pr comment 123 --body hi"')"
asks   "bash -o pipefail -c (value-taking shell option before -c)" "$(bash_cmd 'bash -o pipefail -c "gh pr comment 123 --body hi"')"
asks   "sh -xc clustered short flags wrapped gh pr comment" "$(bash_cmd 'sh -xc "gh pr comment 123 --body hi"')"
asks   "deeply nested eval fails closed, not silently allowed" "$(deeply_nested_eval_payload)"
asks   "gh pr close with comment"   "$(bash_cmd 'gh pr close 123 --comment closing-this')"
asks   "gh issue reopen with -c"    "$(bash_cmd 'gh issue reopen 45 -c back-again')"
asks   "gh pr close with attached -cVALUE" "$(bash_cmd 'gh pr close 123 -cTestComment')"
asks   "gh pr reopen with attached -cVALUE" "$(bash_cmd 'gh pr reopen 123 -cReopeningNow')"
asks   "gh issue close with attached -cVALUE" "$(bash_cmd 'gh issue close 45 -cTestComment')"

silent "gh pr close without comment" "$(bash_cmd 'gh pr close 123')"
silent "gh issue reopen without comment" "$(bash_cmd 'gh issue reopen 45')"
silent "gh pr view read"      "$(bash_cmd 'gh pr view 123')"
silent "gh api comments GET"  "$(bash_cmd 'gh api repos/o/r/issues/123/comments')"
silent "gh api graphql read mentioning mutation name in a string" \
  "$(bash_cmd "gh api graphql -f query='query { search(query: \"addComment bug\", type: ISSUE) { issueCount } }'")"
silent "eval-wrapped harmless command" "$(bash_cmd 'eval "gh pr view 123"')"
silent "gh api graphql resolveReviewThread" "$(bash_cmd "gh api graphql -f query='mutation { resolveReviewThread(input: {}) { thread { isResolved } } }'")"
silent "gh api graphql query read" "$(bash_cmd "gh api graphql -f query='query { repository(owner:\"o\",name:\"r\") { id } }'")"
silent "gh api unrelated write" "$(bash_cmd 'gh api -X POST repos/o/r/labels -f name=bug')"
silent "git command untouched" "$(bash_cmd 'git commit -m "fix"')"

echo "PASS: external-write-guard"
