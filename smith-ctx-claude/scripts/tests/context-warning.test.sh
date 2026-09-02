#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../context-warning.sh"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: context-warning - $1"; }

TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT
mkdir -p "$TMP/plans"
export CLAUDE_CONFIG_DIR="$TMP"
export _SMITH_PPID=12345
source "$HERE/../lib-context.sh"
CACHE_FILE="$TMP/plans/.model-$(session_key "" "$TMP")"

make_transcript_with_model() {
  local tokens=$1 model_json=$2
  cat > "$TMP/transcript.jsonl" << EOF
{"type":"assistant","message":{"role":"assistant",${model_json}"usage":{"input_tokens":$tokens,"output_tokens":0}}}
EOF
}

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

[ "$(model_to_context_window claude-opus-4-5)" = 200000 ] || fail "claude-opus-4-5 window must be 200000"
[ "$(model_to_context_window claude-opus-4-5-20251101)" = 200000 ] || fail "dated opus-4-5 window must be 200000"
[ "$(model_to_context_window claude-opus-4-1)" = 200000 ] || fail "claude-opus-4-1 window must be 200000"
[ "$(model_to_context_window claude-opus-4-6)" = 1000000 ] || fail "claude-opus-4-6 window must be 1000000"
[ "$(model_to_context_window claude-opus-5)" = 1000000 ] || fail "claude-opus-5 window must be 1000000"
[ "$(model_to_context_window 'claude-opus-4-5[1m]')" = 1000000 ] || fail "[1m] suffix stays authoritative"
[ "$(model_to_context_window claude-sonnet-4-5)" = 200000 ] || fail "claude-sonnet-4-5 window must be 200000"
[ "$(model_to_context_window claude-haiku-4-5)" = 200000 ] || fail "claude-haiku-4-5 window must be 200000"
[ "$(model_to_context_window claude-sonnet-4-6)" = 1000000 ] || fail "claude-sonnet-4-6 window must be 1000000"
pass "model window map"

printf 'claude-opus-4-5\n' > "$CACHE_FILE"
make_transcript_with_model 510000 '"model":"claude-fable-5-1",'
OUT=$(run_hook)
echo "$OUT" | grep -q "warning" || fail "live model (1M) must win over stale cache: $OUT"
echo "$OUT" | grep -q "critical" && fail "stale 200K cache must not drive the percentage: $OUT"
pass "live transcript model beats stale cache"

printf 'claude-opus-4-5\n' > "$CACHE_FILE"
make_transcript_with_model 130000 ''
OUT=$(run_hook)
echo "$OUT" | grep -q "critical" || fail "without a transcript model the cached model (200K) applies: $OUT"
pass "cache used only as fallback"
rm -f "$CACHE_FILE"

make_transcript_with_model 510000 '"model":"claude-fable-5-1",'
OUT=$(run_hook)
echo "$OUT" | grep -q "critical" && fail "fable 5.1 at 510K tokens is 51%, not critical: $OUT"
pass "fable 5.1 uses 1M window"

printf '%s\n' '{"type":"user","message":{"role":"user","content":"pasted: \"assistant\" {\"model\":\"claude-opus-4-5\"}"}}' >> "$TMP/transcript.jsonl"
[ "$(transcript_model "$TMP/transcript.jsonl")" = "claude-fable-5-1" ] || fail "a trailing user record mentioning assistant must not hide the live model: $(transcript_model "$TMP/transcript.jsonl")"
pass "transcript model ignores user records"

printf '%s\n' '{"role":"assistant","tru' > "$TMP/transcript.jsonl"
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","model":"claude-fable-5-1","usage":{"input_tokens":10,"output_tokens":0}}}' >> "$TMP/transcript.jsonl"
[ "$(transcript_model "$TMP/transcript.jsonl")" = "claude-fable-5-1" ] || fail "a truncated leading fragment must not abort model detection: '$(transcript_model "$TMP/transcript.jsonl")'"
pass "transcript model survives a truncated leading line"

printf '%s\n' '{"type":"assistant","message":{"role":"assistant","model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0}}}' >> "$TMP/transcript.jsonl"
[ "$(transcript_model "$TMP/transcript.jsonl")" = "claude-fable-5-1" ] || fail "a trailing <synthetic> API-error record must not replace the live model: '$(transcript_model "$TMP/transcript.jsonl")'"
pass "transcript model skips synthetic records"

printf '%s\n' '{"type":"assistant","isSidechain":true,"message":{"role":"assistant","model":"claude-haiku-4-5-20251001","usage":{"input_tokens":5,"output_tokens":0}}}' >> "$TMP/transcript.jsonl"
[ "$(transcript_model "$TMP/transcript.jsonl")" = "claude-fable-5-1" ] || fail "a trailing subagent record must not replace the main agent's model: '$(transcript_model "$TMP/transcript.jsonl")'"
pass "transcript model skips subagent records"

echo "PASS: context-warning"
