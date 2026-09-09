#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/commit-attribution-guard.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: commit-attribution-guard (jq not installed)"; exit 0; }

fail() { echo "FAIL: $1"; exit 1; }

assert_exit() {
  printf '%s' "$2" | "$HOOK" >/dev/null 2>&1
  got=$?
  [ "$got" = "$3" ] || fail "$1 (expected exit $3, got $got)"
}

VALID_TRAILER="Assisted-by: Claude:claude-sonnet-5"

assert_exit "-m with valid trailer allowed" \
  "{\"tool_input\":{\"command\":\"git commit -m \\\"fix: x\\n\\n$VALID_TRAILER\\\"\"}}" 0
assert_exit "-m missing trailer blocked" \
  '{"tool_input":{"command":"git commit -m \"fix: x\""}}' 2
assert_exit "--message missing trailer blocked" \
  '{"tool_input":{"command":"git commit --message \"fix: x\""}}' 2

assert_exit "heredoc body with valid trailer allowed" \
  "{\"tool_input\":{\"command\":\"git commit -m \\\"\$(cat <<'EOF'\nfix: x\n\n$VALID_TRAILER\nEOF\n)\\\"\"}}" 0
assert_exit "heredoc body missing trailer blocked" \
  '{"tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\nfix: x\nEOF\n)\""}}' 2

assert_exit "on behalf of phrase blocked even with trailer" \
  "{\"tool_input\":{\"command\":\"git commit -m \\\"fix: x\\n\\n$VALID_TRAILER on behalf of Mike\\\"\"}}" 2

assert_exit "unrelated git command allowed" \
  '{"tool_input":{"command":"git status"}}' 0
assert_exit "git log allowed" \
  '{"tool_input":{"command":"git log --oneline -5"}}' 0
assert_exit "non-Bash tool allowed" \
  '{"tool_input":{"command":"git status"},"tool_name":"Read"}' 0
assert_exit "malformed stdin allowed" 'not json' 0
assert_exit "null stdin allowed" 'null' 0

assert_exit "commit -F pointing at a nonexistent file is skipped, not false-blocked" \
  '{"tool_input":{"command":"git commit -F /nonexistent/path/for/test-guard"}}' 0

echo "PASS: commit-attribution-guard"
