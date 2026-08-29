#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../post-merge-pull-reminder.mjs"

fail() { echo "FAIL: $1"; exit 1; }

run() { printf '%s' "$2" | node "$HOOK"; }
advises() {
  out=$(run "$1" "$2") || fail "$1: hook crashed"
  echo "$out" | grep -q 'post-merge-pull-reminder' || fail "$1: expected advisory, got: $out"
  echo "$out" | grep -q '"hookEventName":"PostToolUse"' || fail "$1: missing PostToolUse event, got: $out"
}
silent() {
  out=$(run "$1" "$2") || fail "$1: hook crashed"
  [ -z "$out" ] || fail "$1: expected silent, got: $out"
}

advises "plain gh pr merge with number" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 5"}}'
advises "gh pr merge with no argument" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge"}}'
advises "gh pr merge squash delete-branch" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --squash --delete-branch 5"}}'
advises "gh pr merge clustered short flags" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge -sd 5"}}'
advises "global repo flag before subcommand" \
  '{"tool_name":"Bash","tool_input":{"command":"gh -R owner/repo pr merge 5"}}'
advises "long global repo flag before subcommand" \
  '{"tool_name":"Bash","tool_input":{"command":"gh --repo owner/repo pr merge"}}'
advises "attached global repo flag before subcommand" \
  '{"tool_name":"Bash","tool_input":{"command":"gh --repo=owner/repo pr merge 5"}}'
advises "repo flag after subcommand" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 5 --repo owner/repo"}}'
advises "chained after cd" \
  '{"tool_name":"Bash","tool_input":{"command":"cd /repo && gh pr merge 5"}}'
advises "env-prefixed gh pr merge" \
  '{"tool_name":"Bash","tool_input":{"command":"GH_HOST=github.com gh pr merge 5"}}'
advises "attached subject value equal to a deferred flag" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --squash --subject=--auto 5"}}'
advises "chained deferred then immediate merge" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --auto 5 && gh pr merge 6"}}'
advises "chained immediate then deferred merge" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 5 && gh pr merge --auto 6"}}'
advises "help in one segment does not suppress a real merge in another" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --help && gh pr merge 6"}}'

silent "deferred merge with --auto" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --auto 5"}}'
silent "deferred merge with --disable-auto" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --disable-auto 5"}}'
silent "deferred merge with attached --auto=true" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --auto=true 5"}}'
silent "deferred merge with attached --disable-auto=true" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --disable-auto=true 5"}}'
silent "auto alongside squash" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --squash --auto 5"}}'
silent "auto with attached subject value" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --auto --subject=x 5"}}'
silent "subject value then a following deferred flag" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge -t subj --auto 5"}}'
silent "merge help is not a merge" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --help"}}'
silent "merge help short flag is not a merge" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge -h"}}'
silent "global help flag before subcommand is not a merge" \
  '{"tool_name":"Bash","tool_input":{"command":"gh --help pr merge"}}'
silent "global short help flag before subcommand is not a merge" \
  '{"tool_name":"Bash","tool_input":{"command":"gh -h pr merge"}}'
silent "over-nested wrapping stays silent" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 5 ; command command command command command command command command gh pr view"}}'
silent "echoed gh pr merge is not an invocation" \
  '{"tool_name":"Bash","tool_input":{"command":"echo gh pr merge 5"}}'
silent "gh pr view is not a merge" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr view 5"}}'
silent "gh pr create is not a merge" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr create --base main"}}'
silent "git merge is not gh pr merge" \
  '{"tool_name":"Bash","tool_input":{"command":"git merge main"}}'
silent "gh issue subcommand is not pr merge" \
  '{"tool_name":"Bash","tool_input":{"command":"gh issue comment 5 --body x"}}'
silent "unrelated command is silent" \
  '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
silent "non-Bash tool is silent" \
  '{"tool_name":"Read","tool_input":{"file_path":"/x"}}'
silent "malformed stdin is silent" 'not json'
silent "valid JSON null is silent" 'null'
silent "valid JSON non-object is silent" '5'
silent "missing command is silent" \
  '{"tool_name":"Bash","tool_input":{}}'

echo "PASS: post-merge-pull-reminder"
