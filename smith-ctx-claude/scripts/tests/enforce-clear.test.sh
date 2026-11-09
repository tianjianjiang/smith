#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../enforce-clear.sh"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: enforce-clear - $1"; }

TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT
mkdir -p "$TMP/plans"
export CLAUDE_CONFIG_DIR="$TMP"
export _SMITH_PPID=12345
unset CLAUDE_JOB_DIR

make_transcript() {
  local pct=$1
  local tokens=$((200000 * pct / 100))
  printf '%s\n' "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"model\":\"claude-sonnet-4-20250514\",\"usage\":{\"input_tokens\":$tokens,\"output_tokens\":0}}}" > "$TMP/transcript.jsonl"
}

run_hook() {
  printf '%s' "{\"cwd\":\"$TMP\",\"session_id\":\"s1\",\"transcript_path\":\"$TMP/transcript.jsonl\"}" | bash "$HOOK"
}

make_transcript 40
OUT=$(run_hook)
[ -z "$OUT" ] || fail "40% should produce no output: $OUT"
pass "below threshold silent"

make_transcript 70
OUT=$(run_hook)
[ "$(printf '%s' "$OUT" | jq -r .decision)" = block ] || fail "70% should block: $OUT"
[ "$(printf '%s' "$OUT" | jq -r .reason)" = "Context at 70%. Checkpoint this session, then /clear." ] || fail "unexpected reason: $OUT"
pass "critical blocks with checkpoint reason"

printf '%s' "$OUT" | grep -q 'body=' && fail "hook output must not name a body file: $OUT"
printf '%s' "$OUT" | grep -q 'Checkpoint Parameters' && fail "hook output must not carry checkpoint parameters: $OUT"
pass "output names no checkpoint parameters"

printf '%s' '{"stop_hook_active":true}' | bash "$HOOK" > "$TMP/out" 2>&1
[ ! -s "$TMP/out" ] || fail "stop_hook_active should be silent"
pass "stop_hook_active silent"

echo "PASS: enforce-clear"
