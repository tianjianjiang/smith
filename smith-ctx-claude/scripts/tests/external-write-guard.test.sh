#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../external-write-guard.mjs"

fail() { echo "FAIL: $1"; exit 1; }
run() { printf '%s' "$1" | node "$HOOK"; }
asks() { run "$2" | grep -q '"permissionDecision":"ask"' || fail "$1: expected ask"; }
silent() {
  if [ "$1" != "malformed stdin" ]; then
    printf '%s' "$2" | node -e 'JSON.parse(require("fs").readFileSync(0, "utf8"))' 2>/dev/null ||
      fail "$1: test input is not valid JSON"
  fi
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
asks   "jira comment upsert"  '{"tool_name":"mcp__plugin_atlassian_atlassian__addOrEditJiraIssueComment","tool_input":{}}'
asks   "create content page"  '{"tool_name":"mcp__plugin_atlassian_atlassian__createConfluenceContent","tool_input":{}}'
asks   "update content page"  '{"tool_name":"mcp__plugin_atlassian_atlassian__updateConfluenceContent","tool_input":{}}'
asks   "executeWrite"         '{"tool_name":"mcp__plugin_atlassian_atlassian__executeWrite","tool_input":{}}'
asks   "executeDestructive"   '{"tool_name":"mcp__plugin_atlassian_atlassian__executeDestructive","tool_input":{}}'
asks   "notion-delete-pages"  '{"tool_name":"mcp__plugin_Notion_notion__notion-delete-pages","tool_input":{}}'
asks   "notion-restore-pages" '{"tool_name":"mcp__plugin_Notion_notion__notion-restore-pages","tool_input":{}}'
asks   "notion send session"  '{"tool_name":"mcp__plugin_Notion_notion__notion-send-message-to-session","tool_input":{}}'
asks   "slack create canvas"  '{"tool_name":"mcp__plugin_slack_slack__slack_create_canvas","tool_input":{}}'
asks   "slack update canvas"  '{"tool_name":"mcp__plugin_slack_slack__slack_update_canvas","tool_input":{}}'
asks   "slack create list"    '{"tool_name":"mcp__plugin_slack_slack__slack_create_list","tool_input":{}}'
asks   "slack update list"    '{"tool_name":"mcp__plugin_slack_slack__slack_update_list","tool_input":{}}'
asks   "slack add list row"   '{"tool_name":"mcp__plugin_slack_slack__slack_add_list_record","tool_input":{}}'
asks   "slack edit list row"  '{"tool_name":"mcp__plugin_slack_slack__slack_update_list_record","tool_input":{}}'
asks   "slack file upload"    '{"tool_name":"mcp__plugin_slack_slack__slack_complete_file_upload","tool_input":{}}'
asks   "slack new channel"    '{"tool_name":"mcp__plugin_slack_slack__slack_create_conversation","tool_input":{}}'

silent "slack draft variant"  '{"tool_name":"mcp__plugin_slack_slack__slack_send_message_draft","tool_input":{}}'
silent "getJiraIssue read"    '{"tool_name":"mcp__plugin_atlassian_atlassian__getJiraIssue","tool_input":{}}'
silent "notion-fetch read"    '{"tool_name":"mcp__plugin_Notion_notion__notion-fetch","tool_input":{}}'
silent "executeRead"          '{"tool_name":"mcp__plugin_atlassian_atlassian__executeRead","tool_input":{}}'
silent "slack read canvas"    '{"tool_name":"mcp__plugin_slack_slack__slack_read_canvas","tool_input":{}}'
silent "notion download read" '{"tool_name":"mcp__plugin_Notion_notion__notion-download-attachment","tool_input":{}}'
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

asks   "gh pr-review inline comment" "$(bash_cmd 'gh pr-review review --add-comment --pr 1 -R o/r --review-id R --path a.js --line 3 --body test')"
asks   "gh pr-review review submit" "$(bash_cmd 'gh pr-review review --submit --pr 1 -R o/r --review-id R --event COMMENT --body test')"
asks   "gh pr-review review submit without a body" "$(bash_cmd 'gh pr-review review --submit --pr 1 -R o/r --review-id R --event APPROVE')"
silent "gh pr-review review start" "$(bash_cmd 'gh pr-review review --start --pr 1 -R o/r')"
silent "gh pr-review review view" "$(bash_cmd 'gh pr-review review view --pr 1 -R o/r')"
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

denies() { run "$2" | grep -q '"permissionDecision":"deny"' || fail "$1: expected deny"; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PAGE="12345678-90ab-cdef-1234-567890abcdef"
OTHER_PAGE="abcdefab-90ab-cdef-1234-567890abcdef"
BODY="Weekly summary: the migration finished on Tuesday."
PREVIEW="Draft (replace_content) for page $PAGE: $BODY"

json_string() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
assistant() { printf '{"type":"assistant","message":{"id":"%s","content":[{"type":"text","text":%s}]}}' "$1" "$(json_string "$2")"; }
sidechain_assistant() { printf '{"type":"assistant","isSidechain":true,"message":{"id":"%s","content":[{"type":"text","text":%s}]}}' "$1" "$(json_string "$2")"; }
REPLY_AT="2099-01-01T00:00:00Z"
human_at() { printf '{"type":"user","timestamp":"%s","origin":{"kind":"human"},"message":{"content":%s}}' "$1" "$(json_string "$2")"; }
human() { human_at "$REPLY_AT" "$1"; }
NOTIFICATION='{"type":"user","origin":{"kind":"task-notification"},"message":{"content":"<task-notification>done</task-notification>"}}'
ASK_TURN='{"type":"assistant","message":{"id":"a2","content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{}}]}}'
ASK_ANSWER='{"type":"user","timestamp":"2099-01-01T00:00:00Z","message":{"content":[{"type":"tool_result","tool_use_id":"q1","content":"Post"}]}}'
ASK_REJECTED='{"type":"user","timestamp":"2099-01-01T00:00:00Z","message":{"content":[{"type":"tool_result","tool_use_id":"q1","is_error":true,"content":"rejected"}]}}'

transcript() {
  name="$WORK/$1.jsonl"
  shift
  : > "$name"
  for line in "$@"; do printf '%s\n' "$line" >> "$name"; done
  echo "$name"
}

update_call() {
  printf '{"tool_name":"mcp__plugin_Notion_notion__notion-update-page","cwd":"%s","transcript_path":"%s","tool_input":{"page_id":"%s","command":"replace_content","new_str":%s}%s}' \
    "$WORK" "$1" "${3:-$PAGE}" "$(json_string "$BODY")" "${2:-}"
}

gh_call() {
  printf '{"tool_name":"Bash","cwd":"%s","transcript_path":"%s","tool_input":{"command":%s}}' \
    "${3:-$WORK}" "$1" "$(json_string "$2")"
}

OK=$(transcript ok "$(assistant a1 "$PREVIEW")" "$(human 好)")
NODASH=$(transcript nodash "$(assistant a1 "Draft (replace_content) for page 1234567890abcdef1234567890abcdef: $BODY")" "$(human ok)")
NOREPLY=$(transcript noreply "$(human 'update it')" "$(assistant a1 "$PREVIEW")")
NONE=$(transcript none "$(assistant a1 'I will update the page now.')" "$(human ok)")
CHANGED=$(transcript changed "$(assistant a1 "Draft for page $PAGE: Weekly summary: the migration slipped.")" "$(human ok)")
NOTIFIED=$(transcript notified "$(assistant a1 "$PREVIEW")" "$NOTIFICATION")
SIDE=$(transcript side "$(sidechain_assistant a1 "$PREVIEW")" "$(human ok)")
ASKED=$(transcript asked "$(assistant a1 "$PREVIEW")" "$ASK_TURN" "$ASK_ANSWER")
ASK_NO=$(transcript askno "$(assistant a1 "$PREVIEW")" "$ASK_TURN" "$ASK_REJECTED")

silent "preview then reply"                     "$(update_call "$OK")"
silent "page id previewed without dashes"       "$(update_call "$NODASH")"
silent "AskUserQuestion answer after preview"   "$(update_call "$ASKED")"
denies "subagent call"                          "$(update_call "$OK" ',"agent_id":"sub1"')"
denies "preview but no reply"                   "$(update_call "$NOREPLY")"
denies "no preview"                             "$(update_call "$NONE")"
denies "body changed after preview"             "$(update_call "$CHANGED")"
denies "content right, target page differs"     "$(update_call "$OK" "" "$OTHER_PAGE")"
denies "only a task notification after preview" "$(update_call "$NOTIFIED")"
denies "preview only in a sidechain"            "$(update_call "$SIDE")"
denies "rejected AskUserQuestion after preview" "$(update_call "$ASK_NO")"
asks   "missing transcript falls back to ask"   "$(update_call "$WORK/absent.jsonl")"
REPLACE_CALL=$(printf '{"tool_name":"mcp__plugin_Notion_notion__notion-update-page","transcript_path":"%s","tool_input":{"page_id":"%s","command":"replace_content","content_updates":[{"old_str":"Old paragraph nobody previewed.","new_str":%s}]}}' "$OK" "$PAGE" "$(json_string "$BODY")")
silent "old_str is a locator, not payload"      "$REPLACE_CALL"

LATER="$REPLY_AT"
EARLIER="2000-01-01T00:00:00Z"
printf '%s\n' "# Draft" "" "$BODY" > "$WORK/draft.md"

SECOND="Next step: archive the old tables by Friday."
two_part_call() {
  printf '{"tool_name":"mcp__plugin_Notion_notion__notion-update-page","transcript_path":"%s","tool_input":{"page_id":"%s","command":"update_content","content_updates":[{"old_str":"x","new_str":%s},{"old_str":"y","new_str":%s}]}}' \
    "$1" "$PAGE" "$(json_string "$BODY")" "$(json_string "$SECOND")"
}
CHUNKED=$(transcript chunked "$(assistant a1 "Part 1 (update_content) for page $PAGE: $BODY")" "$(human 好)" "$(assistant a2 "Part 2: $SECOND")" "$(human 好)")
CHUNK_OPEN=$(transcript chunkopen "$(assistant a1 "Part 1 (update_content) for page $PAGE: $BODY")" "$(human 好)" "$(assistant a2 "Part 2: $SECOND")")
TARGET_ALONE=$(transcript targetalone "$(assistant a1 "I read page $PAGE.")" "$(human ok)" "$(assistant a2 "Part 1: $BODY")" "$(human ok)" "$(assistant a3 "Part 2: $SECOND")" "$(human ok)")
FILE_OK=$(transcript fileok "$(assistant a1 "Page $PAGE (replace_content); preview file: $WORK/draft.md")" "$(human_at "$LATER" ok)")
FILE_RELATIVE=$(transcript filerel "$(assistant a1 "Page $PAGE (replace_content); preview file: \`draft.md\`")" "$(human_at "$LATER" ok)")
FILE_STALE=$(transcript filestale "$(assistant a1 "Page $PAGE (replace_content); preview file: $WORK/draft.md")" "$(human_at "$EARLIER" ok)")
FILE_UNANSWERED=$(transcript fileopen "$(human_at "$LATER" 'update it')" "$(assistant a1 "Page $PAGE (replace_content); preview file: $WORK/draft.md")")

silent "chunked preview, each part answered"    "$(two_part_call "$CHUNKED")"
denies "chunked preview, last part unanswered"  "$(two_part_call "$CHUNK_OPEN")"
denies "target shown apart from any content"    "$(two_part_call "$TARGET_ALONE")"
silent "long text previewed as a named file"    "$(update_call "$FILE_OK")"
denies "a relative preview path does not count"  "$(update_call "$FILE_RELATIVE")"
denies "preview file changed after the reply"   "$(update_call "$FILE_STALE")"
denies "preview file never answered"            "$(update_call "$FILE_UNANSWERED")"

GH=$(transcript gh "$(assistant a1 "Comment to post on PR 7: $BODY")" "$(human yes)")
printf '%s\n' "$BODY" > "$WORK/body.md"
silent "gh pr comment previewed and replied"    "$(gh_call "$GH" "gh pr comment 7 --body \"$BODY\"")"
silent "gh --body-file previewed and replied"   "$(gh_call "$GH" 'gh pr comment 7 --body-file body.md')"
REVIEW=$(transcript review "$(assistant a1 "Review comment on PR 7: $BODY")" "$(human yes)")
silent "gh pr review -c is a flag, -b the body" "$(gh_call "$REVIEW" "gh pr review 7 -c -b \"$BODY\"")"
silent "gh pr review --comment then --body=TEXT" "$(gh_call "$REVIEW" "gh pr review 7 --comment --body=\"$BODY\"")"
denies "a review verdict never previewed"       "$(gh_call "$REVIEW" "gh pr review 7 --request-changes -b \"$BODY\"")"
denies "delete-branch never previewed"          "$(gh_call "$GH" "gh pr close 7 -c \"$BODY\" -d")"
denies "gh pr comment not previewed"            "$(gh_call "$GH" 'gh pr comment 7 --body "Something else entirely."')"
asks   "gh --body-file unreadable"              "$(gh_call "$GH" 'gh pr comment 7 --body-file missing.md')"
asks   "gh api --input stays opaque"            "$(gh_call "$GH" 'gh api repos/o/r/issues/7/comments --input body.json')"
denies "an approval never previewed"            "$(gh_call "$GH" 'gh pr review 7 --approve')"
APPROVE=$(transcript approve "$(assistant a1 "I will approve PR 7.")" "$(human yes)")
silent "an approval previewed and answered"     "$(gh_call "$APPROVE" 'gh pr review 7 --approve')"
SUBMIT_EVENT=$(transcript submitevent "$(assistant a1 "Submit review R on PR 7 to approve it.")" "$(human yes)")
SUBMIT_NO_EVENT=$(transcript submitnoevent "$(assistant a1 "Submit review R on PR 7.")" "$(human yes)")
silent "a pr-review submit whose event was previewed" "$(gh_call "$SUBMIT_EVENT" 'gh pr-review review --submit --pr 7 --review-id R --event APPROVE')"
denies "a pr-review submit whose event was not previewed" "$(gh_call "$SUBMIT_NO_EVENT" 'gh pr-review review --submit --pr 7 --review-id R --event APPROVE')"
denies "gh same body, different PR number"      "$(gh_call "$GH" "gh pr comment 9 --body \"$BODY\"")"
denies "gh -R repo never previewed"             "$(gh_call "$GH" "gh pr comment 7 -R other/repo --body \"$BODY\"")"
API_GH=$(transcript apigh "$(assistant a1 "POST to repos/o/r/issues/7/comments: $BODY")" "$(human yes)")
silent "gh api endpoint previewed with body"    "$(gh_call "$API_GH" "gh api repos/o/r/issues/7/comments -f body=\"$BODY\"")"
denies "gh api endpoint differs from preview"   "$(gh_call "$API_GH" "gh api repos/o/r/issues/8/comments -f body=\"$BODY\"")"
SHORT_CALL=$(printf '{"tool_name":"mcp__plugin_Notion_notion__notion-create-comment","transcript_path":"%s","tool_input":{"page_id":"%s","markdown":"lgtm"}}' "$OK" "$PAGE")
denies "short lowercase text is payload too"    "$SHORT_CALL"

FILE_MENTION=$(transcript filemention "$(assistant a1 "Page $PAGE; I edited $WORK/draft.md")" "$(human_at "$LATER" ok)")
denies "a path named without a preview label"   "$(update_call "$FILE_MENTION")"
printf '%s\n' "$BODY" > "$WORK/backdated.md"
touch -t 200001010000 "$WORK/backdated.md"
BACKDATED=$(transcript backdated "$(assistant a1 "Page $PAGE (replace_content); preview file: $WORK/backdated.md")" "$(human_at "2001-01-01T00:00:00Z" ok)")
denies "a backdated preview file still changed after the reply" "$(update_call "$BACKDATED")"
BACKDATED_CONTROL=$(transcript backdatedok "$(assistant a1 "Page $PAGE (replace_content); preview file: $WORK/backdated.md")" "$(human_at "$LATER" ok)")
silent "the same file passes with a later reply" "$(update_call "$BACKDATED_CONTROL")"

META_REPLY='{"type":"user","timestamp":"2099-01-01T00:00:00Z","isMeta":true,"origin":{"kind":"human"},"message":{"content":"ok"}}'
NO_ORIGIN_REPLY='{"type":"user","timestamp":"2099-01-01T00:00:00Z","message":{"content":"ok"}}'
NO_ORIGIN_ECHO='{"type":"user","timestamp":"2099-01-01T00:00:00Z","message":{"content":"<command-name>/clear</command-name>"}}'
NO_STAMP_REPLY='{"type":"user","origin":{"kind":"human"},"message":{"content":"ok"}}'
denies "an isMeta reply does not count"         "$(update_call "$(transcript meta "$(assistant a1 "$PREVIEW")" "$META_REPLY")")"
denies "a reply without origin does not count"  "$(update_call "$(transcript noorigin "$(assistant a1 "$PREVIEW")" "$NO_ORIGIN_REPLY")")"
TEAMMATE_REPLY='{"type":"user","timestamp":"2099-01-01T00:00:00Z","message":{"content":"Another Claude session sent a message: looks good"}}'
denies "a teammate message does not count"      "$(update_call "$(transcript teammate "$(assistant a1 "$PREVIEW")" "$TEAMMATE_REPLY")")"
SDK_REPLY='{"type":"user","timestamp":"2099-01-01T00:00:00Z","entrypoint":"sdk-py","promptSource":"sdk","message":{"content":"yes"}}'
denies "an SDK prompt does not count"           "$(update_call "$(transcript sdk "$(assistant a1 "$PREVIEW")" "$SDK_REPLY")")"
denies "a command echo without origin does not count" "$(update_call "$(transcript echo "$(assistant a1 "$PREVIEW")" "$NO_ORIGIN_ECHO")")"
UPLOAD_SHOWN=$(transcript uploadshown "$(assistant a1 "Share file F0ABC12345 to channel C0ABC12345")" "$(human yes)")
UPLOAD_CALL=$(printf '{"tool_name":"mcp__plugin_slack_slack__slack_complete_file_upload","transcript_path":"%s","tool_input":{"file_id":"F0ABC12345","channel_id":"C0ABC12345"}}' "$UPLOAD_SHOWN")
asks   "a file upload asks even when its ids were shown" "$UPLOAD_CALL"
denies "a reply without a timestamp does not count" "$(update_call "$(transcript nostamp "$(assistant a1 "$PREVIEW")" "$NO_STAMP_REPLY")")"

THREAD=$(transcript thread "$(assistant a1 "Reply on PR 7, thread PRRT_x: $BODY")" "$(human yes)")
silent "pr-review reply to the previewed thread" "$(gh_call "$THREAD" "gh pr-review comments reply --pr 7 --thread-id PRRT_x --body \"$BODY\"")"
denies "pr-review reply to another thread"      "$(gh_call "$THREAD" "gh pr-review comments reply --pr 7 --thread-id PRRT_y --body \"$BODY\"")"
INLINE=$(transcript inline "$(assistant a1 "Inline comment on PR 7, review R, file a.js lines 2 to 3: $BODY")" "$(human yes)")
silent "pr-review inline comment previewed"     "$(gh_call "$INLINE" "gh pr-review review --add-comment --pr 7 --review-id R --path a.js --line 3 --body \"$BODY\"")"
silent "pr-review inline range previewed"       "$(gh_call "$INLINE" "gh pr-review review --add-comment --pr 7 --review-id R --path a.js --start-line 2 --line 3 --body \"$BODY\"")"
denies "pr-review inline comment in another review" "$(gh_call "$INLINE" "gh pr-review review --add-comment --pr 7 --review-id Q --path a.js --line 3 --body \"$BODY\"")"
denies "pr-review inline comment on another line" "$(gh_call "$INLINE" "gh pr-review review --add-comment --pr 7 --review-id R --path a.js --line 9 --body \"$BODY\"")"
denies "pr-review inline range from another start line" "$(gh_call "$INLINE" "gh pr-review review --add-comment --pr 7 --review-id R --path a.js --start-line 1 --line 3 --body \"$BODY\"")"
denies "pr-review inline comment on another file" "$(gh_call "$INLINE" "gh pr-review review --add-comment --pr 7 --review-id R --path b.js --line 3 --body \"$BODY\"")"
denies "pr-review inline comment with other text" "$(gh_call "$INLINE" "gh pr-review review --add-comment --pr 7 --review-id R --path a.js --line 3 --body \"Unpreviewed text\"")"

silent "gh api -F body=@file previewed"         "$(gh_call "$API_GH" 'gh api repos/o/r/issues/7/comments -F body=@body.md')"
asks   "gh api -F body=@file unreadable"        "$(gh_call "$API_GH" 'gh api repos/o/r/issues/7/comments -F body=@missing.md')"
asks   "gh body from shell expansion"           "$(gh_call "$GH" 'gh pr comment 7 --body "$COMMENT"')"
asks   "gh body from command substitution"      "$(gh_call "$GH" 'gh pr comment 7 --body "$(cat body.md)"')"
asks   "gh body file in a compound command"     "$(gh_call "$GH" 'printf evil > body.md && gh pr comment 7 --body-file body.md')"
asks   "gh attached -bTEXT is not parsed"       "$(gh_call "$GH" 'gh pr comment 7 -bUnpreviewedText')"

REPO="$WORK/repo"
git init -q "$REPO"
git -C "$REPO" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m init
SHA=$(git -C "$REPO" rev-parse --short HEAD)
mkdir -p "$WORK/bin"
printf '#!/bin/sh\n[ -n "$FAKE_THREAD_AUTHORS" ] || exit 1\nprintf "%%s\\n" "$FAKE_THREAD_AUTHORS"\n' > "$WORK/bin/gh"
chmod +x "$WORK/bin/gh"
PATH="$WORK/bin:$PATH"
export PATH
SHIP_TURN='{"type":"assistant","message":{"id":"s1","content":[{"type":"tool_use","id":"k1","name":"Skill","input":{"skill":"smith-ship"}}]}}'
IN_SHIP=$(transcript inship "$(human '<command-name>/smith-ship</command-name>')")
NO_SHIP=$(transcript noship "$(human 'reply to the bot')")
SELF_SHIP=$(transcript selfship "$(human 'reply to the bot')" "$SHIP_TURN")
repo_call() { gh_call "$1" "$2" "$REPO"; }
bot_reply() { repo_call "${2:-$IN_SHIP}" "gh pr-review comments reply --pr 7 -R o/r --thread-id PRRT_x --body \"$1\""; }
FAKE_THREAD_AUTHORS=Bot
export FAKE_THREAD_AUTHORS
silent "fixed in a real SHA in a bot-only thread during ship" "$(bot_reply "fixed in $SHA")"
denies "fixed in outside a ship or review"      "$(bot_reply "fixed in $SHA" "$NO_SHIP")"
denies "a ship the assistant started itself does not count" "$(bot_reply "fixed in $SHA" "$SELF_SHIP")"
OTHER_HOST=$(repo_call "$IN_SHIP" "gh pr-review comments reply --pr 7 --hostname other.example --thread-id PRRT_x --body 'fixed in $SHA'")
denies "fixed in to another host is not"        "$OTHER_HOST"
OTHER_HOST_REPO=$(repo_call "$IN_SHIP" "gh pr-review comments reply --pr 7 -R other.example/o/r --thread-id PRRT_x --body 'fixed in $SHA'")
denies "fixed in to a host-qualified repo is not" "$OTHER_HOST_REPO"
denies "fixed in an unknown SHA is not"         "$(bot_reply "fixed in 0123abc")"
denies "fixed in a SHA plus more text is not"   "$(bot_reply "fixed in $SHA, and also reworked the parser")"
FIXED_SMUGGLE=$(repo_call "$IN_SHIP" "gh pr-review comments reply --pr 7 --thread-id PRRT_x --body 'fixed in $SHA' --body 'Unpreviewed text'")
denies "fixed in with a second body is not"     "$FIXED_SMUGGLE"
FIXED_EXTRA=$(repo_call "$IN_SHIP" "gh pr-review comments reply --pr 7 --thread-id PRRT_x --body 'fixed in $SHA' 'Unpreviewed text'")
denies "fixed in with an extra positional is not" "$FIXED_EXTRA"
FAKE_THREAD_AUTHORS="Bot,User"
denies "fixed in a thread a human joined"       "$(bot_reply "fixed in $SHA")"
FAKE_THREAD_AUTHORS=""
denies "fixed in when the thread lookup fails"  "$(bot_reply "fixed in $SHA")"
FAKE_THREAD_AUTHORS=Bot
asks   "fixed in with GH_HOST set is not"       "$(repo_call "$IN_SHIP" "GH_HOST=evil.example gh pr-review comments reply --pr 7 --thread-id PRRT_x --body 'fixed in $SHA'")"
printf 'fixed in %s\n' "$SHA" > "$REPO/fixed.md"
BOT_FILE_REPLY=$(printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' "$REPO" "$(json_string "printf evil > fixed.md && gh pr-review comments reply --pr 7 --thread-id PRRT_x --body-file fixed.md")")
asks   "fixed in from a body file in a compound command is not" "$BOT_FILE_REPLY"
BOT_CHAINED=$(printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' "$REPO" "$(json_string "echo hi && gh pr-review comments reply --pr 7 --thread-id PRRT_x --body 'fixed in $SHA'")")
asks   "fixed in inside a compound command is not" "$BOT_CHAINED"

NL='
'
CODE_BODY='use `foo()` for $5'
CODE=$(transcript code "$(assistant a1 "Comment on PR 7:${NL}${CODE_BODY}${NL}second line")" "$(human yes)")
silent "single-quoted backticks and \$ are literal" "$(gh_call "$CODE" "gh pr comment 7 --body '$CODE_BODY'")"
asks   "double-quoted backticks still expand"   "$(gh_call "$CODE" "gh pr comment 7 --body \"$CODE_BODY\"")"
silent "quoted heredoc body is literal"         "$(gh_call "$CODE" "gh pr comment 7 --body \"\$(cat <<'EOF'${NL}${CODE_BODY}${NL}second line${NL}EOF${NL})\"")"
denies "quoted heredoc with unpreviewed text"   "$(gh_call "$CODE" "gh pr comment 7 --body \"\$(cat <<'EOF'${NL}never shown${NL}EOF${NL})\"")"
denies "single-quoted unpreviewed text"         "$(gh_call "$CODE" "gh pr comment 7 --body 'never shown \`x\`'")"
asks   "unquoted heredoc body expands"          "$(gh_call "$CODE" "gh pr comment 7 --body \"\$(cat <<EOF${NL}${CODE_BODY}${NL}second line${NL}EOF${NL})\"")"
asks   "a single-quoted decoy does not hide an expansion" "$(gh_call "$CODE" "echo '\$B' && gh pr comment 7 --body \"\$B\"")"

silent "body flag before the PR number"         "$(gh_call "$GH" "gh pr comment --body \"$BODY\" 7")"
denies "body flag before a different PR number" "$(gh_call "$GH" "gh pr comment --body \"$BODY\" 9")"
asks   "heredoc with a second delimiter line"   "$(gh_call "$CODE" "gh pr comment 7 --body \"\$(cat <<'EOF'${NL}${CODE_BODY}${NL}EOF${NL}cat /etc/hosts${NL}EOF${NL})\"")"
asks   "unquoted glob in the body"              "$(gh_call "$GH" 'gh pr comment 7 --body notes*')"
asks   "unquoted tilde in the body"             "$(gh_call "$GH" 'gh pr comment 7 --body ~/notes')"
asks   "unquoted tilde after = in an api field" "$(gh_call "$GH" 'gh api repos/o/r/issues/7/comments -f body=~/notes')"
WHY=$(transcript why "$(assistant a1 "Comment on PR 7: Why?")" "$(human yes)")
silent "single-quoted question mark is literal" "$(gh_call "$WHY" "gh pr comment 7 --body 'Why?'")"
ln -s "$WORK/backdated.md" "$WORK/link.md"
LINKED=$(transcript linked "$(assistant a1 "Page $PAGE (replace_content); preview file: $WORK/link.md")" "$(human_at "$LATER" ok)")
denies "a symlinked preview file does not count" "$(update_call "$LINKED")"
COMPACT='{"type":"user","timestamp":"2099-01-01T00:00:00Z","isCompactSummary":true,"isVisibleInTranscriptOnly":true,"message":{"content":"This session is being continued from a previous conversation."}}'
COMPACTED=$(transcript compacted "$(assistant a1 "$PREVIEW")" "$COMPACT")
denies "a compaction summary is not a reply"    "$(update_call "$COMPACTED")"
DASHED=$(transcript dashed "$(assistant a1 "Comment on PR 7: -fixed typo")" "$(human yes)")
silent "a body that starts with a dash is still checked" "$(gh_call "$DASHED" "gh pr comment 7 -b '-fixed typo'")"
JQ=$(transcript jq "$(assistant a1 "POST to repos/o/r/issues/7/comments: $BODY")" "$(human yes)")
silent "gh api read-only flags do not make a write opaque" "$(gh_call "$JQ" "gh api repos/o/r/issues/7/comments -f body='$BODY' --jq .id")"
silent "gh pr close with a dash-c-like reason is not a comment" "$(bash_cmd 'gh pr close 123 --reason -check')"

asks   "unquoted brace expansion in the body"   "$(gh_call "$GH" 'gh pr comment 7 --body {a,b}')"
NOISE=$(transcript noise "$(assistant a1 "unrelated words about hosts and x41")" "$(human yes)")
denies "a one-letter body inside a word is not a preview" "$(gh_call "$NOISE" "gh pr comment 41 --body o")"
denies "a target inside a longer token is not a preview" "$(gh_call "$NOISE" "gh pr comment 1 --body 'unrelated words'")"
CJK=$(transcript cjk "$(assistant a1 "PR 7 草稿內容我們完成了遷移請確認")" "$(human 好)")
silent "CJK text inside a sentence still matches" "$(gh_call "$CJK" "gh pr comment 7 --body '我們完成了遷移'")"

STALE=$(transcript stale "$(assistant a1 "Close issue 5 as not planned: Closing as stale")" "$(human yes)")
silent "issue close with its reason and number previewed" "$(gh_call "$STALE" 'gh issue close -r "not planned" 5 -c "Closing as stale"')"
denies "issue close on a number never previewed" "$(gh_call "$STALE" 'gh issue close -r "not planned" 6 -c "Closing as stale"')"
denies "duplicate-of value does not stand in for the issue" "$(gh_call "$STALE" 'gh issue close --duplicate-of 5 8 -c "Closing as stale"')"

asks   "review body swapped by a -cb cluster"   "$(gh_call "$GH" "gh pr review 7 --body \"$BODY\" -cb 'evil text'")"
asks   "close comment hidden in a -dc cluster"  "$(gh_call "$GH" 'gh pr close 7 -dc "evil text"')"
asks   "close comment attached as -dcVALUE"     "$(gh_call "$GH" 'gh pr close 7 -dcevil')"
asks   "review submit with attached body -abX"  "$(gh_call "$GH" 'gh pr review 7 -abLGTM')"
asks   "review submit -rbX"                     "$(gh_call "$GH" 'gh pr review 7 -rbNo')"

asks   "an unknown gh flag is not parsed"       "$(gh_call "$GH" "gh pr comment 7 --body \"$BODY\" --editor")"
BULLET=$(transcript bullet "$(assistant a1 "Comment on PR 7: - fixed the parser")" "$(human yes)")
silent "a body starting with a bullet is not a flag" "$(gh_call "$BULLET" "gh pr comment 7 --body '- fixed the parser'")"

asks   "GH_REPO on the command line"            "$(gh_call "$GH" "GH_REPO=other/repo gh pr comment 7 --body \"$BODY\"")"
asks   "GH_HOST through env"                    "$(gh_call "$GH" "env GH_HOST=evil.example gh pr comment 7 --body \"$BODY\"")"
asks   "graphql mutation to a full URL"         "$(bash_cmd "gh api https://api.github.com/graphql -f query='mutation { addComment(input: {}) { clientMutationId } }'")"
asks   "graphql query from command substitution" "$(bash_cmd 'gh api graphql -f query="$(cat q.graphql)"')"
denies "pr-review positional target not previewed" "$(gh_call "$GH" "gh pr-review comments reply 77 --pr 7 --body \"$BODY\"")"

asks   "a REST comment whose body mentions graphql" "$(bash_cmd 'gh api repos/o/r/issues/1/comments -f body=see/graphql')"
denies "--hostname never previewed"             "$(gh_call "$GH" "gh pr comment 7 --hostname evil.example --body \"$BODY\"")"
notion_call() {
  printf '{"tool_name":"mcp__plugin_Notion_notion__notion-update-page","transcript_path":"%s","tool_input":{"page_id":"%s","command":"%s","new_str":%s%s}}' \
    "$OK" "$PAGE" "$1" "$(json_string "$BODY")" "${2:-}"
}
silent "control: the previewed Notion call passes" "$(notion_call replace_content)"
denies "a different command than previewed"     "$(notion_call insert_content)"
denies "allow_deleting_content never previewed" "$(notion_call replace_content ',"allow_deleting_content":true')"
denies "a number never previewed"               "$(notion_call replace_content ',"properties":{"Budget":9999999}')"
denies "a number under a key ending in id is payload" "$(notion_call replace_content ',"properties":{"Paid":9999999}')"
denies "clearing a property is payload"         "$(notion_call replace_content ',"properties":{"Status":null}')"
denies "clearing a property with an empty list is payload" "$(notion_call replace_content ',"properties":{"Tags":[]}')"
denies "turning a flag off is payload"          "$(notion_call replace_content ',"is_skill":false')"
denies "removing a cover is payload"            "$(notion_call replace_content ',"cover":null')"
asks   "an icon URL cannot be checked"          "$(notion_call replace_content ',"icon":"https://img.example/x.png"')"
denies "a property named type is payload"       "$(notion_call replace_content ',"properties":{"type":"SECRET LEAK"}')"
silent "allow_async stays structural"            "$(notion_call replace_content ',"allow_async":false')"
asks   "a field the signature does not declare"  "$(notion_call replace_content ',"parent":{"page_id":"x"}')"
asks   "a template reference cannot be checked"  "$(notion_call replace_content ',"template_id":"tmpl1"')"
CREATE_CALL=$(printf '{"tool_name":"mcp__plugin_Notion_notion__notion-create-pages","transcript_path":"%s","tool_input":{"parent":{"type":"page_id","page_id":"%s"},"pages":[{"content":%s}]}}' "$OK" "$PAGE" "$(json_string "$BODY")")
silent "parent.type stays structural on create" "$CREATE_CALL"
asks   "a tool without a declared signature"     '{"tool_name":"mcp__plugin_Notion_notion__notion-move-pages","transcript_path":"/x","tool_input":{"page_ids":["a"]}}'
MOVE=$(transcript move "$(assistant a1 "Move ABC-12 to Done (transition 31)")" "$(human yes)")
silent "cloudId is structural, a shown transition id passes" "$(printf '{"tool_name":"mcp__plugin_atlassian_atlassian__transitionJiraIssue","transcript_path":"%s","tool_input":{"cloudId":"site-xyz.atlassian.net","issueIdOrKey":"ABC-12","transitionId":31,"transitionName":"Done"}}' "$MOVE")"
denies "an unshown sprint id is payload"        "$(printf '{"tool_name":"mcp__plugin_atlassian_atlassian__transitionJiraIssue","transcript_path":"%s","tool_input":{"cloudId":"s","issueIdOrKey":"ABC-12","transitionName":"Done","sprintId":42}}' "$MOVE")"
denies "clearing a Jira description is payload" "$(printf '{"tool_name":"mcp__plugin_atlassian_atlassian__editJiraIssue","transcript_path":"%s","tool_input":{"cloudId":"s","issueIdOrKey":"ABC-12","fields":{"summary":"Done","description":""}}}' "$MOVE")"
CANVAS=$(transcript canvas "$(assistant a1 "Canvas F0CANVAS1, edit replace on section temp:C:abc: Done")" "$(human yes)")
silent "a canvas edit to a shown section passes" "$(printf '{"tool_name":"mcp__plugin_slack_slack__slack_update_canvas","transcript_path":"%s","tool_input":{"canvas_id":"F0CANVAS1","sections":[{"edit_type":"replace","section_id":"temp:C:abc","content":"Done"}]}}' "$CANVAS")"
denies "a canvas edit to an unshown section is denied" "$(printf '{"tool_name":"mcp__plugin_slack_slack__slack_update_canvas","transcript_path":"%s","tool_input":{"canvas_id":"F0CANVAS1","sections":[{"edit_type":"replace","section_id":"temp:C:xyz","content":"Done"}]}}' "$CANVAS")"
INSERT=$(transcript insert "$(assistant a1 "Append to page $PAGE (insert_content): $BODY")" "$(human yes)")
insert_call() { printf '{"tool_name":"mcp__plugin_Notion_notion__notion-update-page","transcript_path":"%s","tool_input":{"page_id":"%s","command":"insert_content","content":%s%s}}' "$INSERT" "$PAGE" "$(json_string "$BODY")" "${1:-}"; }
silent "control: a previewed insert passes"     "$(insert_call)"
denies "an unshown insert position is denied"   "$(insert_call ',"position":{"type":"start"}')"
denies "an unshown comment anchor is denied"    "$(printf '{"tool_name":"mcp__plugin_Notion_notion__notion-create-comment","transcript_path":"%s","tool_input":{"page_id":"%s","markdown":%s,"selection_with_ellipsis":"# Heading...end."}}' "$OK" "$PAGE" "$(json_string "$BODY")")"
denies "clearing a nested declared field is payload" "$(printf '{"tool_name":"mcp__plugin_atlassian_atlassian__updateConfluenceContent","transcript_path":"%s","tool_input":{"cloudId":"s","contentId":"ABC-12","title":"Done","body":null}}' "$MOVE")"
asks   "a Confluence smart link cannot be checked" "$(printf '{"tool_name":"mcp__plugin_atlassian_atlassian__createConfluenceContent","transcript_path":"%s","tool_input":{"cloudId":"s","parent":{"spaceId":"1"},"contentType":"smart_link","title":"Done","body":{"format":"url","value":"https://example.com/x"}}}' "$MOVE")"
denies "a Jira transition to an unshown issue"  "$(printf '{"tool_name":"mcp__plugin_atlassian_atlassian__transitionJiraIssue","transcript_path":"%s","tool_input":{"cloudId":"site-xyz.atlassian.net","issueIdOrKey":"ABC-99","transitionName":"Done"}}' "$MOVE")"

mkfifo "$WORK/pipe.md"
asks   "a FIFO body file is not read"           "$(gh_call "$GH" 'gh pr comment 7 --body-file pipe.md')"
DELETE_CALL=$(printf '{"tool_name":"mcp__plugin_Notion_notion__notion-update-page","transcript_path":"%s","tool_input":{"page_id":"%s","command":"replace_content","content_updates":[{"old_str":"The decisions section nobody saw","new_str":""}]}}' "$OK" "$PAGE")
denies "deleted text never previewed"           "$DELETE_CALL"
DELETED=$(transcript deleted "$(assistant a1 "Delete from page $PAGE (replace_content): The decisions section nobody saw")" "$(human yes)")
silent "a previewed deletion passes"            "$(printf '{"tool_name":"mcp__plugin_Notion_notion__notion-update-page","transcript_path":"%s","tool_input":{"page_id":"%s","command":"replace_content","content_updates":[{"old_str":"The decisions section nobody saw","new_str":""}]}}' "$DELETED" "$PAGE")"
denies "a nested numeric id is payload"         "$(printf '{"tool_name":"mcp__plugin_atlassian_atlassian__editJiraIssue","transcript_path":"%s","tool_input":{"cloudId":"s","issueIdOrKey":"ABC-12","fields":{"summary":"Done","priority":{"id":1}}}}' "$MOVE")"

NO_TOKENIZER="$WORK/no-tokenizer"
mkdir -p "$NO_TOKENIZER/smith-ctx-claude/scripts/lib" "$NO_TOKENIZER/smith-git/scripts/lib"
cp "$HOOK" "$NO_TOKENIZER/smith-ctx-claude/scripts/"
cp "$HERE"/../lib/*.mjs "$NO_TOKENIZER/smith-ctx-claude/scripts/lib/"
cp "$HERE"/../../../smith-git/scripts/lib/hook-utils.mjs "$HERE"/../../../smith-git/scripts/lib/transcript-turns.mjs \
  "$NO_TOKENIZER/smith-git/scripts/lib/"
HOOK="$NO_TOKENIZER/smith-ctx-claude/scripts/external-write-guard.mjs"
asks   "no tokenizer: a gh write asks"          "$(bash_cmd 'gh pr comment 1 --body hi')"
asks   "no tokenizer: a gh read asks too"       "$(bash_cmd 'gh pr view 1')"
silent "no tokenizer: a command without gh passes" "$(bash_cmd 'ls -la')"
denies "no tokenizer: an MCP write is still checked" "$(update_call "$NONE")"

echo "PASS: external-write-guard"
