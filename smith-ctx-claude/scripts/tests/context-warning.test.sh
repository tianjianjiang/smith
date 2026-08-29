#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../context-warning.sh"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: context-warning - $1"; }

TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT

make_transcript() {
  local pct=$1
  local tokens=$((200000 * pct / 100))
  cat > "$TMP/transcript.jsonl" << EOF
{"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-20250514","usage":{"input_tokens":$tokens,"output_tokens":0}}}
EOF
}

run_hook() {
  printf '%s' "{\"cwd\":\"$TMP\",\"transcript_path\":\"$TMP/transcript.jsonl\"}" | bash "$HOOK"
}

make_transcript 40
OUT=$(run_hook)
[ -z "$OUT" ] || fail "40% should produce no output"
pass "40% silent"

make_transcript 50
OUT=$(run_hook)
echo "$OUT" | grep -q "context: 50%" || fail "50% should show context percentage"
echo "$OUT" | grep -q "warn: 50%" || fail "50% should show warn threshold"
pass "50% structured"

make_transcript 55
OUT=$(run_hook)
echo "$OUT" | grep -q "context: 55%" || fail "55% should show context percentage"
pass "55% structured"

make_transcript 60
OUT=$(run_hook)
echo "$OUT" | grep -q "action: save" || fail "60% should show action"
pass "60% critical action"

make_transcript 70
OUT=$(run_hook)
echo "$OUT" | grep -q "action: save" || fail "70% should show action"
pass "70% critical action"

printf '%s' '{"cwd":"/nonexistent","transcript_path":"/nonexistent"}' | bash "$HOOK" > "$TMP/out" 2>&1
[ ! -s "$TMP/out" ] || fail "missing transcript should be silent"
pass "missing transcript silent"

echo "PASS: context-warning"
