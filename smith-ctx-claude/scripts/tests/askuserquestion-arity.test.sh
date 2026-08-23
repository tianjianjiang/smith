#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../askuserquestion-arity.mjs"

fail() { echo "FAIL: $1"; exit 1; }
assert_exit() {
  printf '%s' "$2" | node "$HOOK" >/dev/null 2>&1
  got=$?
  [ "$got" = "$3" ] || fail "$1 (expected exit $3, got $got)"
}

assert_exit "two questions blocked" \
  '{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"a"},{"question":"b"}]}}' 2
assert_exit "four questions blocked" \
  '{"tool_name":"AskUserQuestion","tool_input":{"questions":[{},{},{},{}]}}' 2
assert_exit "one question allowed" \
  '{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"a"}]}}' 0
assert_exit "empty questions allowed" \
  '{"tool_name":"AskUserQuestion","tool_input":{"questions":[]}}' 0
assert_exit "non-array questions allowed" \
  '{"tool_name":"AskUserQuestion","tool_input":{"questions":"nope"}}' 0
assert_exit "other tool allowed" \
  '{"tool_name":"Read","tool_input":{"file_path":"/x"}}' 0
assert_exit "malformed stdin allowed" \
  'not json' 0

echo "PASS: askuserquestion-arity"
