#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../skill-load-gate.mjs"
TABLE="$HERE/../../skill-gate.json"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

COVERED="$TMPD/covered-actions"
: > "$COVERED"

transcript_loading() {
  path="$TMPD/loaded-$1.jsonl"
  printf '%s\n' \
    '{"type":"user","message":{"content":"go"}}' \
    "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"id\":\"call-1\",\"name\":\"Skill\",\"input\":{\"skill\":\"$1\"}}]}}" \
    '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"call-1","content":"Launching skill"}]}}' \
    > "$path"
  echo "$path"
}

NOTHING_LOADED="$TMPD/nothing-loaded.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}' \
  > "$NOTHING_LOADED"

run() {
  node -e '
    const [transcript, tool, toolInput, extra] = process.argv.slice(1);
    process.stdout.write(JSON.stringify({
      hook_event_name: "PreToolUse",
      transcript_path: transcript,
      tool_name: tool,
      tool_input: JSON.parse(toolInput),
      ...JSON.parse(extra || "{}"),
    }));
  ' "$1" "$2" "$3" "$4" | node "$HOOK"
}

bash_command() { node -e 'process.stdout.write(JSON.stringify({ command: process.argv[1] }))' "$1"; }

refused() {
  out=$(run "$NOTHING_LOADED" "$3" "$4" "") || fail "$1: hook crashed"
  echo "$out" | grep -q '"permissionDecision":"deny"' || fail "$1: expected a refusal, got: $out"
  echo "$out" | grep -q "@$2" || fail "$1: refusal should name @$2, got: $out"
}

allowed() {
  out=$(run "$(transcript_loading "$2")" "$3" "$4" "") || fail "$1: hook crashed"
  [ -z "$out" ] || fail "$1: expected silence with $2 loaded, got: $out"
}

governed() {
  echo "$1" >> "$COVERED"
  refused "$1 without $2" "$2" "$3" "$4"
  echo "$out" | grep -q "$1 is governed by" || fail "$1: refusal should name the action, got: $out"
  allowed "$1 with $2" "$2" "$3" "$4"
}

ungoverned() {
  out=$(run "$NOTHING_LOADED" "$2" "$3" "$4") || fail "$1: hook crashed"
  [ -z "$out" ] || fail "$1: expected silence, got: $out"
}

SKILL_FILE_EDIT='{"file_path":"/repo/smith-git/SKILL.md","old_string":"a","new_string":"b"}'

governed "git commit" smith-git Bash "$(bash_command 'git commit -m message')"
governed "git push" smith-git Bash "$(bash_command 'git push -u origin feat/thing')"
governed "pull request create or edit" smith-gh-pr Bash "$(bash_command 'gh pr create --title t --body b')"
governed "pull request review or comment" smith-gh-pr Bash "$(bash_command 'gh pr review 12 --approve')"
governed "review or comment through the GitHub API" smith-gh-pr Bash \
  "$(bash_command 'gh api repos/owner/name/pulls/12/comments -f body=text')"
governed "message draft to another person" smith-slack \
  mcp__plugin_slack_slack__slack_send_message_draft '{"channel_id":"C1","message":"hello"}'
governed "ticket write" smith-tickets \
  mcp__plugin_atlassian_atlassian__createJiraIssue '{"summary":"s"}'
governed "issue create or edit" smith-tickets Bash "$(bash_command 'gh issue create --title t')"
governed "subagent spawn" smith-subagents Agent '{"description":"d","prompt":"p"}'
governed "web fetch or search" smith-research WebFetch '{"url":"https://example.com"}'
governed "skill file write" smith-skills Edit "$SKILL_FILE_EDIT"
governed "leave plan mode" smith-mode-plan-claude ExitPlanMode '{"plan":"p"}'

node -e '
  const table = JSON.parse(require("fs").readFileSync(process.argv[1], "utf-8"));
  const covered = new Set(require("fs").readFileSync(process.argv[2], "utf-8").split("\n").filter(Boolean));
  const missing = table.rules.map((rule) => rule.action).filter((action) => !covered.has(action));
  if (missing.length > 0) { console.log(missing.join("; ")); process.exit(1); }
' "$TABLE" "$COVERED" || fail "a rule of skill-gate.json has no refused and allowed case"

for command in 'gh pr new --fill' 'gh pr edit 12 --body text' 'gh pr comment 12 --body text' \
  'gh issue comment 3 --body text' 'gh api repos/owner/name/pulls/12/reviews -f event=APPROVE' \
  'gh api -X POST repos/owner/name/issues/3/comments?per_page=1'; do
  refused "alternative: $command" smith-gh-pr Bash "$(bash_command "$command")"
done
refused "alternative: gh issue new" smith-tickets Bash "$(bash_command 'gh issue new --title t')"
for tool in mcp__plugin_slack_slack__slack_send_message mcp__plugin_slack_slack__slack_schedule_message; do
  refused "alternative: $tool" smith-slack "$tool" '{"channel_id":"C1","message":"hello"}'
done
refused "alternative: editJiraIssue" smith-tickets mcp__plugin_atlassian_atlassian__editJiraIssue '{"issueIdOrKey":"K-1"}'
refused "alternative: Task" smith-subagents Task '{"description":"d","prompt":"p"}'
refused "alternative: WebSearch" smith-research WebSearch '{"query":"q"}'
refused "alternative: Write" smith-skills Write '{"file_path":"/repo/smith-new/SKILL.md","content":"x"}'
refused "alternative: bare file name" smith-skills Write '{"file_path":"SKILL.md","content":"x"}'
refused "alternative: file name in another case" smith-skills Edit '{"file_path":"/repo/smith-git/skill.md","old_string":"a","new_string":"b"}'
for tool in replace_content replace_symbol_body insert_after_symbol insert_before_symbol create_text_file; do
  refused "alternative: Serena $tool" smith-skills "mcp__serena__$tool" '{"relative_path":"smith-git/SKILL.md"}'
done
refused "alternative: Serena through the plugin" smith-skills \
  mcp__plugin_serena_serena__replace_content '{"relative_path":"smith-git/SKILL.md"}'

refused "global option before the subcommand" smith-git Bash "$(bash_command 'git -C /repo commit -m message')"
refused "repository flag before the subcommand" smith-gh-pr Bash "$(bash_command 'gh -R owner/name pr create --fill')"
refused "governed command after another command" smith-git Bash "$(bash_command 'git add file && git commit -m message')"
refused "governed command inside a shell wrapper" smith-git Bash "$(bash_command "sh -c 'git push'")"
refused "governed command after a shell keyword" smith-git Bash "$(bash_command 'if true; then git push; fi')"
refused "governed command in a loop body" smith-git Bash "$(bash_command 'for b in a b; do git push origin $b; done')"
refused "governed command in a command substitution" smith-git Bash "$(bash_command 'out=$(git push 2>&1); echo "$out"')"
refused "governed command in a quoted substitution" smith-git Bash "$(bash_command 'echo "$(git commit -m x)"')"
refused "governed command in backticks" smith-git Bash "$(bash_command 'echo `git push`')"
refused "governed command behind a duration prefix" smith-git Bash "$(bash_command 'timeout 60 git push')"
refused "governed command behind a decimal duration" smith-git Bash "$(bash_command 'timeout 1.5 git push')"
refused "governed command in a subshell" smith-git Bash "$(bash_command '(git push)')"
refused "governed command in a brace group" smith-git Bash "$(bash_command '{ git push; }')"
refused "governed command as an if condition" smith-git Bash "$(bash_command 'if ! git push; then echo no; fi')"
refused "governed command as an until condition" smith-git Bash "$(bash_command 'until git push; do sleep 1; done')"
refused "subshell with a semicolon, then a redirection" smith-git Bash "$(bash_command '(cd x; git push) > log')"
refused "substitution inside a shell string" smith-git Bash "$(bash_command "sh -c 'out=\$(git push)'")"
refused "governed command after a nested substitution" smith-git Bash \
  "$(bash_command 'echo "$(cd $(pwd) && git push)"')"
refused "substitution after a quoted closing parenthesis" smith-git Bash \
  "$(bash_command 'out=$(echo "a)"; git push)')"
refused "substitution between two apostrophes in double quotes" smith-git Bash \
  "$(bash_command 'echo "don'"'"'t"; out=$(git push 2>&1); echo "it'"'"'s done"')"
with_apostrophe=$(printf '%s\n' "cat > notes.md <<'EOF'" "Don't forget" "EOF" 'git add notes.md && git push')
refused "command after a here-document holding an apostrophe" smith-git Bash "$(bash_command "$with_apostrophe")"
unquoted_delimiter=$(printf '%s\n' "cat > n.md <<EOF" "it's" "EOF" 'git push')
refused "command after an unquoted here-document holding an apostrophe" smith-git Bash "$(bash_command "$unquoted_delimiter")"
odd_quote=$(printf '%s\n' "cat <<'EOF' > f" '27" wide' "EOF" 'git push')
refused "command after a here-document holding a lone double quote" smith-git Bash "$(bash_command "$odd_quote")"
empty_document=$(printf '%s\n' 'cat <<EOF >a' 'EOF' 'git push' 'cat <<EOF >b' 'x' 'EOF')
refused "command after an empty here-document" smith-git Bash "$(bash_command "$empty_document")"
quoted_operator=$(printf '%s\n' 'echo "<<EOF"' 'git push' 'EOF')
refused "command after a quoted here-document operator" smith-git Bash "$(bash_command "$quoted_operator")"
two_documents=$(printf '%s\n' 'cat <<A <<B' 'a' 'A' 'b' 'B' 'git push')
refused "command after two here-documents on one line" smith-git Bash "$(bash_command "$two_documents")"
heading_in_message=$(printf '%s\n' 'git commit -m "feat: x' '' '# Notes" && gh pr create --fill')
refused "command after a quoted line starting with a hash" smith-gh-pr Bash "$(bash_command "$heading_in_message")"
hyphenated_delimiter=$(printf '%s\n' 'cat > body.md <<PR-BODY' '## Summary' 'PR-BODY' 'gh pr create --body-file body.md')
refused "command after a hyphenated here-document delimiter" smith-gh-pr Bash \
  "$(bash_command "$hyphenated_delimiter")"
escaped_delimiter=$(printf '%s\n' 'cat <<E\OF' 'x' 'EOF' 'git push')
refused "command after a here-document delimiter with a backslash" smith-git Bash "$(bash_command "$escaped_delimiter")"
double_quoted_delimiter=$(printf '%s\n' 'cat <<"EOF"' "it's" 'EOF' 'git push')
refused "command after a double-quoted here-document delimiter" smith-git Bash \
  "$(bash_command "$double_quoted_delimiter")"
tab_stripped=$(printf 'cat <<-EOF\n\tit'"'"'s\n\tEOF\ngit push\n')
refused "command after a tab-stripped here-document" smith-git Bash "$(bash_command "$tab_stripped")"
unclosed_document=$(printf '%s\n' 'cat <<PR-BODY' 'never closed' 'git push')
refused "command after a here-document that never closes" smith-git Bash "$(bash_command "$unclosed_document")"
after_closed_substitution=$(printf '%s\n' 'v="$(date)"; cat <<'"'"'EOF'"'"'' "it's" 'EOF' 'git push')
refused "here-document after a closed quoted substitution" smith-git Bash \
  "$(bash_command "$after_closed_substitution")"
backtick_document=$(printf '%s\n' 'echo `cat <<EOF`' 'git push' 'EOF')
refused "command after a here-document operator in backticks" smith-git Bash "$(bash_command "$backtick_document")"
refused "hash inside a word" smith-git Bash "$(bash_command 'curl https://x/#top && git push')"
refused "hash right after a command substitution" smith-git Bash "$(bash_command 'echo $(true)#x; git push')"
refused "hash right after a process substitution" smith-git Bash "$(bash_command 'echo <(true)#x; git push')"
refused "hash right after an output process substitution" smith-git Bash "$(bash_command 'echo >(true)#x; git push')"
refused "hash right after a zsh process substitution" smith-git Bash "$(bash_command 'cat =(true)#x; git push')"
ungoverned "comment right after a subshell" Bash "$(bash_command '(true)#; git push')"
redirected_subshell=$(printf '%s\n' '(' '  cd /tmp' '  git push' ') >/dev/null')
refused "multi-line subshell with a redirection" smith-git Bash "$(bash_command "$redirected_subshell")"
refused "subshell with unspaced operators and a redirection" smith-git Bash \
  "$(bash_command '(cd /tmp&&git push) >/dev/null')"
refused "negated subshell with an unspaced semicolon" smith-git Bash "$(bash_command '! (echo a;git push)')"
refused "zsh process substitution" smith-git Bash "$(bash_command 'cat =(git push)')"
refused "parenthesis inside double quotes before a hash" smith-git Bash \
  "$(bash_command 'echo "fix (see #12)" && git push')"
refused "governed command in an output process substitution" smith-git Bash \
  "$(bash_command 'echo x | tee >(git push)')"
refused "substitution in the string of a shell with clustered flags" smith-git Bash \
  "$(bash_command "bash -lc 'out=\$(git push)'")"
refused "nested backticks" smith-git Bash "$(bash_command 'echo `echo \`git push\``')"
refused "redirection after an assignment" smith-git Bash "$(bash_command 'A=1 >/dev/null git push')"
refused "spaced redirection after a keyword" smith-git Bash "$(bash_command 'time > out git push')"
refused "redirection after a wrapper" smith-git Bash "$(bash_command 'env >/dev/null git push')"
refused "spaced redirection inside a brace group" smith-gh-pr Bash "$(bash_command '{ > out gh issue comment 1 -b x; }')"
refused "subscripted assignment before the command" smith-git Bash "$(bash_command 'A[0]=1 git push')"
refused "prefix with a flag" smith-git Bash "$(bash_command 'timeout --foreground 60 git push')"
refused "xargs with a flag" smith-git Bash "$(bash_command 'echo o | xargs -n1 git push')"
refused "while condition" smith-git Bash "$(bash_command 'while git push; do :; done')"
refused "else branch" smith-git Bash "$(bash_command 'if false; then :; else git push; fi')"
refused "elif condition" smith-git Bash "$(bash_command 'if false; then :; elif git push; then :; fi')"
refused "exec prefix" smith-git Bash "$(bash_command 'exec git push')"
refused "builtin prefix" smith-git Bash "$(bash_command 'builtin git push')"
refused "coproc prefix" smith-git Bash "$(bash_command 'coproc git push')"
refused "redirection between git and its subcommand" smith-git Bash "$(bash_command 'git 2>/dev/null push')"
refused "redirection between gh and its subcommand" smith-gh-pr Bash "$(bash_command 'gh 2>/dev/null pr create --fill')"
closing_here_string=$(printf '%s\n' 'cat <<< EOF' 'git push' 'EOF')
refused "command after a here-string whose word recurs" smith-git Bash "$(bash_command "$closing_here_string")"
substituted_delimiter=$(printf '%s\n' 'cat <<EOF$(x)' 'body' 'EOF$(x)' 'git push' 'EOF$')
refused "command after a delimiter holding a substitution" smith-git Bash "$(bash_command "$substituted_delimiter")"
ungoverned "greater-than sign inside double quotes" Bash "$(bash_command 'echo "a > b; git push"')"
ungoverned "digit inside a word before a redirection" Bash "$(bash_command 'git push2>/dev/null')"
refused "shell string after an end-of-options marker" smith-git Bash "$(bash_command "sh -c -- 'out=\$(git push)'")"
refused "shell string after a flag cluster not ending in c" smith-git Bash "$(bash_command "bash -cx 'out=\$(git push)'")"
refused "shell string after another option" smith-git Bash "$(bash_command "bash -e -c 'out=\$(git push)'")"
ungoverned "grep counting a quoted mention" Bash "$(bash_command "grep -c 'git push' notes.md")"
refused "escaped substitution in a double-quoted shell string" smith-git Bash \
  "$(bash_command 'sh -c "out=\$(git push)"')"
refused "command after an ANSI-C quoted apostrophe" smith-git Bash "$(bash_command "echo \$'it\\'s'; git push")"
refused "repository path given by a substitution" smith-git Bash "$(bash_command 'git -C "$(pwd)" push')"
refused "repository path given by backticks" smith-git Bash "$(bash_command 'git -C `pwd` push')"
refused "repository path given as an empty string" smith-git Bash "$(bash_command 'git -C "" push')"
refused "gh repository given by a substitution" smith-gh-pr Bash \
  "$(bash_command 'gh -R "$(echo o/r)" pr create --title t --body b')"
ungoverned "array assignment" Bash "$(bash_command 'arr=(a b); echo ok')"
ungoverned "repository path by substitution, ungoverned subcommand" Bash "$(bash_command 'git -C "$(pwd)" status')"
refused "hash in a parameter length" smith-git Bash "$(bash_command 'echo ${#x}; git push')"
refused "hash after a space in a parameter expansion" smith-git Bash "$(bash_command 'echo ${line%% #*}; git push')"
refused "hash inside backticks" smith-git Bash "$(bash_command 'echo `echo #`; git push')"
refused "hash after an escaped space" smith-git Bash "$(bash_command 'echo \ #; git push')"
refused "hash after a subshell inside a quoted substitution" smith-git Bash \
  "$(bash_command 'echo "$( (echo) ; echo " # " )" ; git push')"
refused "apostrophe in double quotes inside a quoted substitution" smith-git Bash \
  "$(bash_command "echo \"\$(echo \"'\")\"; git push")"
refused "substitution after an apostrophe in a nested double quote" smith-git Bash \
  "$(bash_command "echo \"\$(echo \"'\")\$(git push)\"")"
numeric_shift=$(printf '%s\n' 'echo $((1<<2))' 'git push' '2')
refused "command after an arithmetic shift by a number" smith-git Bash "$(bash_command "$numeric_shift")"
bracket_shift=$(printf '%s\n' 'echo $[1<<2]' 'git push' '2]')
refused "command after a bracket arithmetic shift by a number" smith-git Bash "$(bash_command "$bracket_shift")"
here_string=$(printf '%s\n' 'read v <<< done' 'git push' 'done=1')
refused "command after a here-string" smith-git Bash "$(bash_command "$here_string")"
comment_line=$(printf '%s\n' "# don't forget" 'git push')
refused "command after a comment line holding an apostrophe" smith-git Bash "$(bash_command "$comment_line")"
trailing_comment=$(printf '%s\n' "ls # don't" 'git push')
refused "command after a trailing comment holding an apostrophe" smith-git Bash "$(bash_command "$trailing_comment")"
trailing_comment_substitution=$(printf '%s\n' "ls # it's" 'echo $(git push)')
refused "substitution after a trailing comment holding an apostrophe" smith-git Bash \
  "$(bash_command "$trailing_comment_substitution")"
trailing_double_quote=$(printf '%s\n' 'cd /tmp # 27" wide' 'git commit -m x')
refused "command after a trailing comment holding a double quote" smith-git Bash \
  "$(bash_command "$trailing_double_quote")"
refused "governed command after an escaped hash" smith-git Bash "$(bash_command 'echo \# x; git push')"
refused "governed command after a hash inside quotes" smith-git Bash "$(bash_command 'echo "a # b" && git push')"
refused "substitution after an escaped apostrophe" smith-git Bash "$(bash_command "echo don\\'t \$(git push)")"
refused "backticks after an escaped apostrophe" smith-git Bash "$(bash_command "echo don\\'t \`git push\`")"
refused "substitution after an escaped double quote" smith-git Bash \
  "$(bash_command "echo \"a \\\" it's\" \$(git push)")"
refused "substitution after an ANSI-C quoted apostrophe" smith-git Bash "$(bash_command "echo \$'\\'' \$(git push)")"
refused "substitution inside an eval string" smith-git Bash "$(bash_command "eval 'out=\$(git push)'")"
refused "redirection before the command" smith-git Bash "$(bash_command '>/dev/null git push')"
refused "redirection with a file before the command" smith-gh-pr Bash "$(bash_command '2> err.log gh pr create --fill')"
refused "assignment holding a substitution with a space" smith-gh-pr Bash \
  "$(bash_command 'GH_TOKEN=$(gh auth token) gh pr create --fill')"
refused "shell string inside a substitution" smith-git Bash "$(bash_command "echo \$(sh -c 'git commit -m x')")"
refused "MacPorts timeout name" smith-git Bash "$(bash_command 'gtimeout 60 git push')"
refused "zsh noglob modifier" smith-git Bash "$(bash_command 'noglob git push')"
refused "governed command behind xargs" smith-git Bash "$(bash_command 'echo origin | xargs git push')"
refused "governed command in a process substitution" smith-git Bash "$(bash_command 'cat <(git push)')"
refused "substitution assigned to a variable, quoted argument" smith-gh-pr Bash \
  "$(bash_command 'ID=$(gh api "repos/o/r/pulls/1/comments" -f body=hi --jq .id)')"
refused "substitution with a quoted option value" smith-git Bash "$(bash_command "X=\$(git -C '/tmp/a b' push)")"
refused "backtick substitution assigned to a variable" smith-gh-pr Bash \
  "$(bash_command 'ID=`gh api "repos/o/r/pulls/1/reviews" -f event=APPROVE`')"
refused "governed command after an inner substitution" smith-git Bash \
  "$(bash_command 'out=$(cd "$(dirname x)" && git push)')"
refused "redirection attached to the subcommand" smith-git Bash "$(bash_command 'git push>/dev/null 2>&1')"
refused "input redirection attached to the subcommand" smith-git Bash "$(bash_command 'git commit<message.txt')"
refused "redirection attached to a gh subcommand" smith-gh-pr Bash "$(bash_command 'gh pr create>/dev/null')"
refused "redirection attached to the endpoint" smith-gh-pr Bash \
  "$(bash_command 'gh api repos/o/r/issues/1/comments>out.json -f body=x')"
refused "reply path below a comment" smith-gh-pr Bash \
  "$(bash_command 'gh api repos/o/r/pulls/comments/55/replies -f body=x')"
refused "alternative: gh issue edit" smith-tickets Bash "$(bash_command 'gh issue edit 3 --body text')"
refused "governed command behind a proxy" smith-git Bash "$(bash_command 'rtk proxy git commit -m message')"
refused "governed command by absolute path" smith-git Bash "$(bash_command '/usr/bin/git push')"

deep='git push'
for level in 1 2 3 4 5 6 7 8 9 10; do deep="sh -c \"$(printf '%s' "$deep" | sed 's/\\/\\\\/g; s/"/\\"/g')\""; done
out=$(run "$NOTHING_LOADED" Bash "$(bash_command "$deep")" "") || fail "deep wrapping: hook crashed"
echo "$out" | grep -q '"permissionDecision":"ask"' || fail "a command wrapped too deeply to scan should ask, got: $out"

both=$(run "$NOTHING_LOADED" Bash "$(bash_command 'git commit -m message && gh pr create --fill')" "")
echo "$both" | grep -q '@smith-git' || fail "two governed commands: smith-git not named"
echo "$both" | grep -q '@smith-gh-pr' || fail "two governed commands: smith-gh-pr not named"

partial=$(run "$(transcript_loading smith-git)" Bash "$(bash_command 'git commit -m message && gh pr create --fill')" "")
echo "$partial" | grep -q '"permissionDecision":"deny"' || fail "one of two skills loaded should still refuse, got: $partial"
echo "$partial" | grep -q '@smith-gh-pr' || fail "one of two skills loaded: the missing one is not named"
echo "$partial" | grep -q '@smith-git' && fail "one of two skills loaded: the loaded one is named as missing"

other=$(run "$(transcript_loading smith-git)" Bash "$(bash_command 'gh pr create --fill')" "")
echo "$other" | grep -q '"permissionDecision":"deny"' || fail "another skill loaded should not allow the action, got: $other"

failed_load="$TMPD/failed-load.jsonl"
printf '%s\n' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"call-1","name":"Skill","input":{"skill":"smith-git"}}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"call-1","is_error":true,"content":"refused"}]}}' \
  > "$failed_load"
out=$(run "$failed_load" Bash "$(bash_command 'git commit -m message')" "")
echo "$out" | grep -q '"permissionDecision":"deny"' || fail "a Skill call that failed should not allow the action, got: $out"

heredoc_message=$(printf '%s\n' 'git commit -m "$(cat <<'"'"'EOF'"'"'' \
  'The guard now refuses gh issue create and `gh pr create` without the skill.' 'EOF' ')"')
out=$(run "$(transcript_loading smith-git)" Bash "$(bash_command "$heredoc_message")" "") || fail "heredoc message: hook crashed"
[ -z "$out" ] || fail "a commit message that mentions other governed commands should need smith-git only, got: $out"
out=$(run "$NOTHING_LOADED" Bash "$(bash_command "$heredoc_message")" "")
echo "$out" | grep -q 'git commit is governed by @smith-git' || fail "heredoc commit should still be governed, got: $out"

slash_loaded="$TMPD/slash-loaded.jsonl"
printf '%s\n' \
  '{"type":"user","isMeta":true,"message":{"content":[{"type":"text","text":"Base directory for this skill: /home/someone/.claude/skills/smith-git\n\n# Git"}]}}' \
  > "$slash_loaded"
out=$(run "$slash_loaded" Bash "$(bash_command 'git commit -m message')" "") || fail "slash-loaded: hook crashed"
[ -z "$out" ] || fail "a skill loaded by a slash command should allow the action, got: $out"

ungoverned "git status" Bash "$(bash_command 'git status')"
ungoverned "git log mentioning commit" Bash "$(bash_command 'git log --grep commit')"
ungoverned "quoted mention of a governed command" Bash "$(bash_command 'echo "then run git push"')"
ungoverned "unquoted mention after another program" Bash "$(bash_command 'grep -rn gh pr create docs/')"
ungoverned "text after a closed backtick substitution" Bash "$(bash_command 'echo `date` git push')"
ungoverned "echoed mention" Bash "$(bash_command 'echo git push')"
ungoverned "governed command inside a trailing comment" Bash "$(bash_command "echo done # can't; git push")"
ungoverned "escaped substitution" Bash "$(bash_command 'echo "\$(git push)"')"
quoted_body=$(printf '%s\n' "cat <<'EOF' > notes.md" '$(git push)' 'EOF')
ungoverned "substitution inside a quoted here-document body" Bash "$(bash_command "$quoted_body")"
backslash_body=$(printf '%s\n' 'cat <<\EOF > notes.md' '$(git push)' 'EOF')
ungoverned "substitution inside a backslash-quoted here-document body" Bash "$(bash_command "$backslash_body")"
mentioned_in_body=$(printf '%s\n' 'cat <<EOF > notes.md' "then run git push, it's \"done\"" 'EOF')
ungoverned "mention inside an unquoted here-document body" Bash "$(bash_command "$mentioned_in_body")"
escaped_in_body=$(printf '%s\n' 'cat <<EOF > notes.md' '\$(git push)' 'EOF')
ungoverned "escaped substitution inside an unquoted here-document body" Bash "$(bash_command "$escaped_in_body")"
expanding_body=$(printf '%s\n' 'cat <<EOF > notes.md' "it's \$(git push)" 'EOF')
refused "substitution inside an unquoted here-document body" smith-git Bash "$(bash_command "$expanding_body")"
backtick_body=$(printf '%s\n' 'cat <<EOF > notes.md' 'a "quote" and `git push`' 'EOF')
refused "backticks inside an unquoted here-document body" smith-git Bash "$(bash_command "$backtick_body")"
second_document_body=$(printf '%s\n' "cat <<'A' <<B" '$(true)' 'A' '$(git push)' 'B')
refused "substitution inside the second, unquoted here-document" smith-git Bash \
  "$(bash_command "$second_document_body")"
for command in 'if true; then env GIT_EDITOR=true git commit; fi' 'if true; then sudo git push; fi' \
  '{ command git push; }' 'timeout 120 env GIT_TERMINAL_PROMPT=0 git push' \
  'for b in a; do nohup git push origin $b; done' 'if x; then :; else nice git commit -m y; fi'; do
  refused "wrapper after a keyword or prefix: $command" smith-git Bash "$(bash_command "$command")"
done
refused "wrapper after a keyword before gh" smith-gh-pr Bash "$(bash_command 'then env GH_TOKEN=x gh pr create')"
ungoverned "command lookup after a keyword" Bash "$(bash_command 'if true; then command -v git; fi')"
refused "substitution after an apostrophe in a quoted parameter" smith-git Bash \
  "$(bash_command "echo \"\${NAME:-it's me}\" \$(git push)")"
refused "substitution after an apostrophe in a parameter in double quotes" smith-git Bash \
  "$(bash_command "echo \"\${NAME:-it's me} \$(git push)\"")"
parameter_in_body=$(printf '%s\n' 'cat <<EOF' "\${NAME:-it's me}" '$(git push)' 'EOF')
refused "substitution after an apostrophe in a parameter in a here-document body" smith-git Bash \
  "$(bash_command "$parameter_in_body")"
refused "command after an apostrophe that quotes in a parameter under bash" smith-git Bash \
  "$(bash_command "x=; echo \"\${x:-'\"'}\"; git push")"
refused "command after a quoted apostrophe pattern in a parameter" smith-git Bash \
  "$(bash_command "echo \"\${x#'\"'}\"; git push")"
refused "command after a double-quoted default holding an apostrophe" smith-git Bash \
  "$(bash_command "echo \"\${x:-\"it's\"}\" && git push")"
refused "line after a double-quoted default holding an apostrophe" smith-gh-pr Bash \
  "$(bash_command "$(printf '%s\n' "printf '%s\\\\n' \"\${NAME:-\"the user's repo\"}\"" 'gh pr create --fill')")"
refused "substitution in a zsh shell string" smith-git Bash "$(bash_command "zsh -c 'out=\$(git push)'")"
refused "command in a dash shell string" smith-git Bash "$(bash_command "dash -c 'git push'")"
refused "gh repository option spelled out before the subcommand" smith-gh-pr Bash \
  "$(bash_command 'gh --repo owner/name pr create --fill')"
refused "substitution in a ksh shell string" smith-git Bash "$(bash_command "ksh -c 'out=\$(git push)'")"
refused "command after a leading output-and-error redirection" smith-git Bash "$(bash_command '&>/dev/null git push')"
piped_document=$(printf '%s\n' "cat <<'EOF' | gh pr create --body-file -" 'body' 'EOF')
refused "command after a here-document operator on its line" smith-gh-pr Bash "$(bash_command "$piped_document")"
chained_document=$(printf '%s\n' 'cat <<EOF > notes.md && git push' 'body' 'EOF')
refused "command chained after an unquoted here-document operator" smith-git Bash \
  "$(bash_command "$chained_document")"
quoted_second_document=$(printf '%s\n' "cat <<A <<'B'" 'a' 'A' '$(git push)' 'B')
ungoverned "substitution inside a quoted document after an unquoted one" Bash \
  "$(bash_command "$quoted_second_document")"
body_in_substitution=$(printf '%s\n' 'gh pr view --json x "$(cat <<EOF' '$(git push)' 'EOF' ')"')
refused "substitution in an unquoted body inside a substitution" smith-git Bash \
  "$(bash_command "$body_in_substitution")"
paren_in_body=$(printf '%s\n' "x=\"\$(cat <<'EOF'" ') git push' 'EOF' ')"')
ungoverned "closing parenthesis inside a here-document in a substitution" Bash "$(bash_command "$paren_in_body")"
ungoverned "mention in a single-quoted code span" Bash "$(bash_command "echo 'then \`gh pr comment\` it'")"
ungoverned "another subcommand of a governed program" Bash "$(bash_command 'git stash push')"
ungoverned "gh pr view" Bash "$(bash_command 'gh pr view 12')"
ungoverned "gh pr list searching for a governed phrase" Bash "$(bash_command 'gh pr list --search "pr create"')"
ungoverned "gh api read of another path" Bash "$(bash_command 'gh api repos/owner/name/pulls/12')"
ungoverned "gh api field value that mentions comments" Bash \
  "$(bash_command 'gh api repos/owner/name/issues/3 -f body=see/the/comments')"
ungoverned "edit of another file" Edit '{"file_path":"/repo/README.md","old_string":"a","new_string":"b"}'
ungoverned "file whose name only ends like a skill file" Edit '{"file_path":"/repo/MY-SKILL.md","old_string":"a","new_string":"b"}'
ungoverned "backup beside a skill file" Edit '{"file_path":"/repo/smith-git/SKILL.md.bak","old_string":"a","new_string":"b"}'
ungoverned "read-only Slack tool" mcp__plugin_slack_slack__slack_read_channel '{"channel_id":"C1"}'
ungoverned "tool call inside a subagent" Bash "$(bash_command 'git commit -m message')" '{"agent_id":"agent-1"}'

out=$(run "$TMPD/does-not-exist.jsonl" Bash "$(bash_command 'git commit -m message')" "") || fail "missing transcript: hook crashed"
[ -z "$out" ] || fail "missing transcript should let the action through, got: $out"

out=$(printf 'not json' | node "$HOOK") || fail "malformed stdin: hook crashed"
[ -z "$out" ] || fail "malformed stdin should be silent"

echo "PASS: skill-load-gate"
