#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../enforce-clear.sh"

readonly DEFAULT_CRITICAL_PCT=60
readonly SONNET_4_CONTEXT_TOKENS=200000

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: enforce-clear - $1"; }

TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT
mkdir -p "$TMP/plans"
export CLAUDE_CONFIG_DIR="$TMP"
export _SMITH_PPID=12345
export CLAUDE_JOB_DIR="$TMP"
unset CTX_CONTEXT_CRITICAL_PCT

make_transcript() {
  local pct=$1
  local tokens=$((SONNET_4_CONTEXT_TOKENS * pct / 100))
  printf '%s\n' "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"model\":\"claude-sonnet-4-20250514\",\"usage\":{\"input_tokens\":$tokens,\"output_tokens\":0}}}" > "$TMP/transcript.jsonl"
}

run_hook() {
  printf '%s' "{\"cwd\":\"$TMP\",\"session_id\":\"s1\",\"transcript_path\":\"$TMP/transcript.jsonl\"}" | bash "$HOOK"
}

make_transcript $((DEFAULT_CRITICAL_PCT - 1))
OUT=$(run_hook)
[ -z "$OUT" ] || fail "one point below the critical threshold should produce no output: $OUT"
pass "below threshold silent"

make_transcript "$DEFAULT_CRITICAL_PCT"
OUT=$(run_hook)
[ "$(printf '%s' "$OUT" | jq -r .decision)" = block ] || fail "the critical threshold should block: $OUT"
[ "$(printf '%s' "$OUT" | jq -r .reason)" = "Context at ${DEFAULT_CRITICAL_PCT}%. Checkpoint this session, then /clear." ] || fail "unexpected reason: $OUT"
pass "critical blocks with checkpoint reason"

printf '%s' "$OUT" | grep -q 'body=' && fail "hook output must not name a body file: $OUT"
printf '%s' "$OUT" | grep -q 'Checkpoint Parameters' && fail "hook output must not carry checkpoint parameters: $OUT"
pass "output names no checkpoint parameters"

printf '%s' '{"stop_hook_active":true}' | bash "$HOOK" > "$TMP/out" 2>&1
[ ! -s "$TMP/out" ] || fail "stop_hook_active should be silent"
pass "stop_hook_active silent"

STATE_FILE="$TMP/plans/.plan-state-$(source "$HERE/../lib-context.sh" && plan_state_key "$TMP")"
FLAG_FILE="$TMP/plans/.pending-reload-$(source "$HERE/../lib-context.sh" && session_key "" "$TMP")"

make_transcript "$DEFAULT_CRITICAL_PCT"
open_items=("- [ ] top-level open" "  - [ ] nested open")
{ printf '# Plan\n\n- [x] done\n'; printf '%s\n' "${open_items[@]}"; } > "$TMP/plan.md"
printf 's1\n%s\n0\n\n%s\n' "$TMP/transcript.jsonl" "$TMP/plan.md" > "$STATE_FILE"
OUT=$(run_hook)
[ "$(printf '%s' "$OUT" | jq -r .reason)" = "Context at ${DEFAULT_CRITICAL_PCT}% (${#open_items[@]} pending). Checkpoint this session, then /clear." ] || fail "pending plan reason: $OUT"
pass "pending plan reason counts its unchecked items"
[ "$(sed -n 1p "$FLAG_FILE")" = "$TMP/plan.md" ] || fail "pending reload flag should name the plan: $(cat "$FLAG_FILE")"
[ "$(sed -n 5p "$FLAG_FILE")" = plan-pending ] || fail "pending reload flag type: $(cat "$FLAG_FILE")"
pass "pending plan reload flag names the plan"

make_transcript "$DEFAULT_CRITICAL_PCT"
printf '# Plan\n\n- [x] done\n' > "$TMP/plan.md"
printf 's1\n%s\n0\n\n%s\n' "$TMP/transcript.jsonl" "$TMP/plan.md" > "$STATE_FILE"
OUT=$(run_hook)
[ "$(printf '%s' "$OUT" | jq -r .reason)" = "Context at ${DEFAULT_CRITICAL_PCT}% (plan completed). Checkpoint this session, then /clear." ] || fail "completed plan reason: $OUT"
pass "completed plan reason says plan completed"

make_transcript "$DEFAULT_CRITICAL_PCT"
rm -f "$TMP/missing.md"
printf 's1\n%s\n0\n\n%s\n' "$TMP/transcript.jsonl" "$TMP/missing.md" > "$STATE_FILE"
OUT=$(run_hook)
[ "$(printf '%s' "$OUT" | jq -r .reason)" = "Context at ${DEFAULT_CRITICAL_PCT}%. Checkpoint this session, then /clear." ] || fail "deleted plan reason: $OUT"
pass "deleted plan reason names no plan"
[ "$(sed -n 5p "$FLAG_FILE")" = no-plan ] || fail "deleted plan reload flag type: $(cat "$FLAG_FILE")"
pass "deleted plan reload flag type is no-plan"

echo "PASS: enforce-clear"
