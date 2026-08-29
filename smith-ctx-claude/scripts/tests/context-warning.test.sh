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
echo "$OUT" | grep -q "warning" || fail "50% should produce warning"
pass "50% warning"

make_transcript 55
OUT=$(run_hook)
echo "$OUT" | grep -q "warning" || fail "55% should produce warning"
pass "55% warning"

make_transcript 60
OUT=$(run_hook)
echo "$OUT" | grep -q "critical" || fail "60% should produce critical"
pass "60% critical"

make_transcript 70
OUT=$(run_hook)
echo "$OUT" | grep -q "critical" || fail "70% should produce critical"
pass "70% critical"

printf '%s' '{"cwd":"/nonexistent","transcript_path":"/nonexistent"}' | bash "$HOOK" > "$TMP/out" 2>&1
[ ! -s "$TMP/out" ] || fail "missing transcript should be silent"
pass "missing transcript silent"

echo "PASS: context-warning"
