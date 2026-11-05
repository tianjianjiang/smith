#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
EXTRACT="$HERE/../extract-session-facts.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

CONFIG="$WORK/config"
SID="11111111-2222-3333-4444-555555555555"
mkdir -p "$CONFIG/projects/-tmp-project"
TRANSCRIPT="$CONFIG/projects/-tmp-project/$SID.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"7","status":"completed","subject":"write the fixture"}}]}}' > "$TRANSCRIPT"

out=$(env -u CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR="$CONFIG" bash "$EXTRACT" 2>&1) || fail "no session id: nonzero exit"
printf '%s' "$out" | grep -q "No transcript available." || fail "no session id: expected no transcript, got: $out"

out=$(CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_CONFIG_DIR="$CONFIG" bash "$EXTRACT" 2>&1) || fail "session id: nonzero exit"
printf '%s' "$out" | grep -q -- "- \[x\] Task #7: write the fixture" || fail "session id: transcript not resolved, got: $out"

out=$(CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_CONFIG_DIR="$WORK/missing" bash "$EXTRACT" 2>&1) || fail "missing projects dir: nonzero exit"
printf '%s' "$out" | grep -q "No transcript available." || fail "missing projects dir: expected no transcript, got: $out"

mkdir -p "$CONFIG/projects/-locked"
chmod 000 "$CONFIG/projects/-locked"
out=$(CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_CONFIG_DIR="$CONFIG" bash "$EXTRACT" 2>/dev/null)
rc=$?
chmod 755 "$CONFIG/projects/-locked"
[ "$rc" = 0 ] || fail "unreadable sibling directory: exit $rc"
printf '%s' "$out" | grep -q -- "- \[x\] Task #7: write the fixture" || fail "unreadable sibling directory: transcript not resolved, got: $out"

out=$(env -u CLAUDE_CODE_SESSION_ID bash "$EXTRACT" "$TRANSCRIPT" 2>&1) || fail "explicit path: nonzero exit"
printf '%s' "$out" | grep -q -- "- \[x\] Task #7: write the fixture" || fail "explicit path: not read, got: $out"

echo "PASS"
