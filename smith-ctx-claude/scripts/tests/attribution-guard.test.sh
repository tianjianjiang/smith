#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../attribution-guard.sh"
LIB="$HERE/../attribution-lib.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: attribution-guard (jq not installed)"; exit 0; }
command -v node >/dev/null 2>&1 || { echo "SKIP: attribution-guard (node not installed)"; exit 0; }

fail() { echo "FAIL: $1"; exit 1; }

TMP=$(mktemp -d) || fail "mktemp"
trap 'rm -rf "$TMP"' EXIT
CLAUDE_CONFIG_DIR="$TMP/config"
export CLAUDE_CONFIG_DIR
unset CLAUDE_CODE_SESSION_ID
mkdir -p "$CLAUDE_CONFIG_DIR/plans"
bash -c '. "$1"; printf "claude-opus-4-8\n" > "$(attribution_model_file s)"' _ "$LIB" || fail "seed model file"

D="$TMP/drafts"
mkdir -p "$D"
LINE="Assisted-by: Claude:claude-opus-4-8"
printf 'fix: x\n\n%s\n' "$LINE" > "$D/good.txt"
printf 'fix: x\n\n%s [semgrep]\n' "$LINE" > "$D/tool.txt"
printf 'fix: x\n' > "$D/missing.txt"
printf 'fix: x\n\nAssisted-by: Claude Code (claude-opus-4-8)\n' > "$D/hand-typed.txt"
printf 'fix: x\n\n%s\nAssisted-by: Claude:claude-sonnet-5\n' "$LINE" > "$D/extra.txt"
printf 'fix: x on behalf of someone\n\n%s\n' "$LINE" > "$D/behalf.txt"
cp "$D/good.txt" "$D/with space.txt"
ln -s "$D/good.txt" "$D/link.txt"
NESTED="git commit -F $D/good.txt"
NESTED_LS="ls"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  NESTED="sh -c $(printf '%s' "$NESTED" | jq -Rr @sh)"
  NESTED_LS="sh -c $(printf '%s' "$NESTED_LS" | jq -Rr @sh)"
done

assert_exit() {
  [ -n "$2" ] && printf '%s' "$2" | jq . >/dev/null 2>&1 || fail "$1 (test input is not valid JSON)"
  printf '%s' "$2" | timeout 10 "$HOOK" >/dev/null 2>&1
  got=$?
  [ "$got" = "$3" ] || { echo "FAIL: $1 (expected exit $3, got $got)"; FAILURES=$((FAILURES + 1)); }
}
FAILURES=0

bash_json() { jq -n --arg s "$1" --arg c "$2" '{session_id: $s, cwd: "/", tool_name: "Bash", tool_input: {command: $c}}'; }
assert_bash() { assert_exit "$1" "$(bash_json s "$2")" "$3"; }
slack_json() { jq -n --arg m "$1" --argjson extra "${2:-null}" '{session_id: "s", tool_name: "mcp__plugin_slack_slack__slack_send_message_draft", tool_input: ({channel_id: "C1", message: $m} + ($extra // {}))}'; }

echo "--- not a covered write"
assert_exit "empty input allowed" '{}' 0
assert_bash "unrelated command allowed" "ls -la" 0
assert_bash "git status allowed" "git status" 0
assert_bash "git log grepping for commit allowed" "git log --grep commit" 0
assert_bash "echoing the words git commit allowed" "echo git commit" 0
assert_bash "git push allowed" "git push origin HEAD" 0
assert_bash "cherry-pick reuses a message" "git cherry-pick abc123" 0
assert_bash "rebase reuses messages" "git rebase origin/main" 0
assert_bash "gh pr view allowed" "gh pr view 5" 0
assert_bash "gh pr edit without a body allowed" "gh pr edit 5 --add-label bug" 0
assert_bash "gh pr close without a comment allowed" "gh pr close 5" 0
assert_bash "gh pr-review start allowed" "gh pr-review review --start --pr 1 -R o/r" 0
assert_bash "gh api read allowed" "gh api repos/o/r/pulls/1" 0
assert_exit "another MCP tool allowed" '{"session_id":"s","tool_name":"mcp__serena__read_memory","tool_input":{"memory_name":"x"}}' 0

echo "--- the recipe passes"
assert_bash "commit -F an absolute draft" "git commit -F $D/good.txt" 0
assert_bash "commit --file= an absolute draft" "git commit --file=$D/good.txt" 0
assert_bash "a tool suffix" "git commit -F $D/tool.txt" 0
assert_bash "git -C then commit -F" "git -C /repo commit -a -F $D/good.txt" 0
assert_bash "a quoted absolute path" "git commit -F \"$D/good.txt\"" 0
assert_bash "merge -F" "git merge --no-ff -F $D/good.txt feat/x" 0
assert_bash "gh pr create --body-file" "gh pr create --title 'feat: x' --body-file $D/good.txt --assignee @me" 0
assert_bash "gh pr edit --body-file" "gh pr edit 5 --body-file $D/good.txt" 0
assert_bash "gh pr comment --body-file" "gh pr comment 5 -R o/r --body-file $D/good.txt" 0
assert_bash "gh pr review --approve --body-file" "gh pr review 5 -R o/r --approve --body-file $D/good.txt" 0
assert_bash "gh pr merge --body-file" "gh pr merge 5 --squash --body-file $D/good.txt" 0
assert_bash "gh issue comment --body-file" "gh issue comment 5 --body-file $D/good.txt" 0
assert_bash "gh pr-review reply with the line" "gh pr-review comments reply --pr 1 -R o/r --thread-id T --body 'ok

$LINE'" 0
assert_bash "gh pr-review add-comment with the line" "gh pr-review review --add-comment --pr 1 -R o/r --review-id R --path a.js --line 3 --body 'fix

$LINE'" 0
assert_exit "Slack draft with the line" "$(slack_json "hello

$LINE")" 0
assert_exit "Slack draft in a thread with the line" "$(slack_json "hello

$LINE" '{"thread_ts":"1.2"}')" 0

assert_bash "a draft path with a space" "git commit -F \"$D/with space.txt\"" 0
assert_bash "gh pr new --body-file" "gh pr new --title x --body-file $D/good.txt" 0
assert_bash "gh pr revert --body-file" "gh pr revert 5 --body-file $D/good.txt" 0
assert_bash "gh pr comment --body-file=" "gh pr comment 5 --body-file=$D/good.txt" 0
assert_bash "gh pr close --comment with the line" "gh pr close 5 -d --comment 'done

$LINE'" 0
assert_bash "gh pr reopen --comment with the line" "gh pr reopen 5 --comment 'again

$LINE'" 0
assert_bash "gh issue close --comment with the line" "gh issue close 5 --reason completed --comment 'done

$LINE'" 0
assert_bash "gh issue reopen --comment with the line" "gh issue reopen 5 --comment 'again

$LINE'" 0
assert_bash "gh pr-review submit with the line" "gh pr-review review --submit --pr 1 -R o/r --review-id R --event COMMENT --body 'ok

$LINE'" 0

echo "--- declared signatures without a payload"
assert_bash "gh pr comment --delete-last" "gh pr comment 5 --delete-last --yes" 0
assert_bash "gh api comment delete" "gh api -X DELETE repos/o/r/pulls/comments/1" 0
assert_bash "commit --amend --no-edit" "git commit --amend --no-edit" 0
assert_bash "commit --fixup" "git commit --fixup abc123" 0
assert_bash "merge --ff-only" "git merge --ff-only origin/main" 0
assert_bash "merge --abort" "git merge --abort" 0
assert_bash "pull --ff-only" "git pull --ff-only" 0
assert_bash "pull --rebase origin main" "git pull --rebase origin main" 0
assert_bash "revert --no-commit" "git revert --no-commit abc123" 0
assert_bash "gh pr merge without a body" "gh pr merge 5 --squash --delete-branch" 0
assert_bash "gh pr review --approve without a body" "gh pr review 5 --approve" 0
assert_bash "gh pr-review submit without a body" "gh pr-review review --submit --pr 1 -R o/r --review-id R --event COMMENT" 0

echo "--- not used: the line did not reach the text"
assert_bash "a draft without the line" "git commit -F $D/missing.txt" 2
assert_bash "a hand-typed line" "git commit -F $D/hand-typed.txt" 2
assert_bash "an extra line" "git commit -F $D/extra.txt" 2
assert_bash "gh pr create body without the line" "gh pr create --title x --body-file $D/missing.txt" 2
assert_bash "on behalf of with the line" "git commit -F $D/behalf.txt" 2
assert_bash "gh pr review --comment draft without the line" "gh pr review 5 --comment --body-file $D/missing.txt" 2
assert_bash "gh pr reopen --comment without the line" "gh pr reopen 5 --comment 'again'" 2
assert_bash "gh issue close --comment without the line" "gh issue close 5 --comment 'done'" 2
assert_bash "gh issue reopen --comment without the line" "gh issue reopen 5 --comment 'again'" 2
assert_bash "gh pr-review submit without the line" "gh pr-review review --submit --pr 1 -R o/r --review-id R --event COMMENT --body 'ok'" 2
assert_exit "Slack draft with a non-string message" '{"session_id":"s","tool_name":"mcp__plugin_slack_slack__slack_send_message_draft","tool_input":{"channel_id":"C1","message":123}}' 2
assert_bash "gh pr-review reply without the line" "gh pr-review comments reply --pr 1 -R o/r --thread-id T --body 'ok'" 2
assert_exit "Slack draft without the line" "$(slack_json "hello")" 2
slack_json "hello" | "$HOOK" 2>&1 >/dev/null | grep -q "end the message field" || { echo "FAIL: a Slack refusal names the Slack recipe"; FAILURES=$((FAILURES + 1)); }
assert_exit "Slack draft with a hand-typed line" "$(slack_json "hello

Assisted-by: Claude Code")" 2
assert_exit "an unknown session model" "$(bash_json other "git commit -F $D/good.txt")" 2

echo "--- covered writes that match no declared signature (fail closed)"
assert_bash "commit -m" 'git commit -m "fix: x"' 2
assert_bash "commit in the editor" "git commit" 2
assert_bash "commit -e with -F" "git commit -e -F $D/good.txt" 2
assert_bash "commit with a short flag cluster" "git commit -aF $D/good.txt" 2
assert_bash "commit -s" "git commit -s -F $D/good.txt" 2
assert_bash "commit with an unknown global option" "git -c user.name=x commit -F $D/good.txt" 2
assert_bash "commit-tree" "git commit-tree HEAD^{tree} -F $D/good.txt" 2
assert_bash "a relative draft path" "git commit -F good.txt" 2
assert_bash "a symlinked draft" "git commit -F $D/link.txt" 2
assert_bash "a missing draft" "git commit -F $D/nowhere.txt" 2
assert_bash "an expanded draft path" 'git commit -F "$MSG"' 2
assert_bash "a write after another step" "git add -A && git commit -F $D/good.txt" 2
assert_bash "a draft rewritten inside sh -c" "sh -c 'cp $D/missing.txt $D/good.txt; git commit -F $D/good.txt'" 2
assert_bash "a draft rewritten inside a subshell" "(cp $D/missing.txt $D/good.txt; git commit -F $D/good.txt)" 2
assert_bash "a draft rewritten inside eval" "eval 'cp $D/missing.txt $D/good.txt; git commit -F $D/good.txt'" 2
assert_bash "an ANSI-C quoted literal body" "gh pr-review comments reply --pr 1 -R o/r --thread-id T --body \$'$LINE [x\\nAssisted-by: wrong]'" 2
assert_bash "a substitution that may rewrite the draft" "git commit -F $D/good.txt \"\$(cp $D/missing.txt $D/good.txt)\"" 2
assert_bash "a draft written in the same command" "printf x > $D/new.txt; git commit -F $D/new.txt" 2
assert_bash "merge with a generated message" "git merge feat/x" 2
assert_bash "pull that may merge" "git pull" 2
assert_bash "revert with a generated message" "git revert abc123" 2
assert_bash "gh pr create --body literal" "gh pr create --title x --body 'x'" 2
assert_bash "gh pr create --fill" "gh pr create --fill" 2
assert_bash "gh pr create with no body" "gh pr create --title x" 2
assert_bash "gh pr comment --body literal" "gh pr comment 5 --body 'x'" 2
assert_bash "gh pr edit --body literal" "gh pr edit 5 --body 'x'" 2
assert_bash "gh pr revert without a body" "gh pr revert 5" 2
assert_bash "gh pr close --comment without the line" "gh pr close 5 --comment 'done'" 2
assert_bash "gh pr-review body built by expansion" 'gh pr-review comments reply --pr 1 -R o/r --thread-id T --body "$(cat f)"' 2
assert_bash "gh api comment create" "gh api repos/o/r/pulls/1/comments -f body=x" 2
assert_bash "gh api pull request create" "gh api -X POST repos/o/r/pulls -f title=x -f body=x" 2
assert_bash "gh api pull request merge" "gh api -X PUT repos/o/r/pulls/1/merge -f commit_message=x" 2
assert_bash "gh api issue edit" "gh api -X PATCH repos/o/r/issues/1 -f body=x" 2
assert_bash "gh api graphql pull request update" "gh api graphql -f query='mutation { updatePullRequest(input: {pullRequestId: \"x\", body: \"x\"}) { clientMutationId } }'" 2
assert_bash "gh api pull request edit" "gh api -X PATCH repos/o/r/pulls/1 -f body=x" 2
assert_exit "Slack draft with an undeclared field" "$(slack_json "hello

$LINE" '{"blocks":"x"}')" 2

bash_json s "gh api repos/o/r/pulls/1/comments -f body=x" | "$HOOK" 2>&1 >/dev/null | grep -q "gh pr-review" || { echo "FAIL: a gh api refusal names gh pr-review"; FAILURES=$((FAILURES + 1)); }

echo "--- shell wrappers nested too deeply to read"
assert_bash "a deeply nested commit blocked" "$NESTED" 2
assert_bash "a deeply nested ls allowed" "$NESTED_LS" 0

echo "--- a guard that cannot load blocks"
mkdir -p "$TMP/lone"
cp "$HOOK" "$TMP/lone/attribution-guard.sh"
bash_json s "git status" | "$TMP/lone/attribution-guard.sh" >/dev/null 2>&1
[ "$?" = 2 ] || { echo "FAIL: a missing guard module blocks the call"; FAILURES=$((FAILURES + 1)); }

[ "$FAILURES" = 0 ] || fail "attribution-guard ($FAILURES case(s))"
echo "PASS: attribution-guard"
