#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../enforce-clear.sh"
source "$HERE/lib/set-aside.sh"

readonly DEFAULT_CRITICAL_PCT=60
readonly SONNET_4_CONTEXT_TOKENS=200000

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: enforce-clear - $1"; }

TMP=$(mktemp -d)
mkdir -p "$TMP/plans"
export CLAUDE_CONFIG_DIR="$TMP"
export _SMITH_PPID=12345
export CLAUDE_JOB_DIR="$TMP"
export CTX_AUTO_RESET_DISPATCH=0
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
printf 's1\n%s\n0\n\n%s\n' "$TMP/transcript.jsonl" "$TMP/missing.md" > "$STATE_FILE"
OUT=$(run_hook)
[ "$(printf '%s' "$OUT" | jq -r .reason)" = "Context at ${DEFAULT_CRITICAL_PCT}%. Checkpoint this session, then /clear." ] || fail "deleted plan reason: $OUT"
pass "deleted plan reason names no plan"
[ "$(sed -n 5p "$FLAG_FILE")" = no-plan ] || fail "deleted plan reload flag type: $(cat "$FLAG_FILE")"
pass "deleted plan reload flag type is no-plan"

reset_flags() { set_aside "$STATE_FILE" "$FLAG_FILE" "$FLAG_FILE.exit-marker"; }
readonly NO_PLAN_REASON="Context at ${DEFAULT_CRITICAL_PCT}%. Checkpoint this session, then /clear."

reset_flags
make_transcript "$DEFAULT_CRITICAL_PCT"
OUT=$(run_hook)
STATUS=$?
[ "$STATUS" -eq 0 ] || fail "a block should exit 0, got $STATUS"
[ "$(printf '%s' "$OUT" | jq -c 'keys')" = '["decision","hookSpecificOutput","reason"]' ] || fail "unexpected block keys: $OUT"
[ "$(printf '%s' "$OUT" | jq -r .hookSpecificOutput.hookEventName)" = Stop ] || fail "block should name the Stop event: $OUT"
case "$(printf '%s' "$OUT" | jq -r .hookSpecificOutput.additionalContext)" in
  "Session: "*) ;;
  *) fail "additional context should open with the session summary: $OUT" ;;
esac
pass "block exits 0 with decision, reason and a session summary"

[ "$(sed -n 2p "$FLAG_FILE")" = s1 ] || fail "reload flag should name the session: $(cat "$FLAG_FILE")"
sed -n 3p "$FLAG_FILE" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4}$' || fail "reload flag timestamp: $(cat "$FLAG_FILE")"
[ "$(sed -n 4p "$FLAG_FILE")" = "$TMP" ] || fail "reload flag should name the working directory: $(cat "$FLAG_FILE")"
pass "reload flag names the session, a timestamp and the working directory"
! ls "$TMP"/session-facts-*.md >/dev/null 2>&1 || fail "a block must leave no session facts file in the job folder: nothing reads it"
pass "block leaves no session facts file"

reset_flags
OUT=$(printf '%s' "{\"cwd\":\"$TMP\",\"session_id\":\"s1\",\"transcript_path\":\"$TMP/missing.jsonl\"}" | bash "$HOOK")
STATUS=$?
[ "$STATUS" -eq 0 ] && [ -z "$OUT" ] || fail "a missing transcript should be silent with exit 0: status $STATUS, $OUT"
[ ! -e "$FLAG_FILE" ] || fail "a missing transcript should leave no reload flag"
pass "missing transcript silent, no reload flag"

OUT=$(printf '%s' "{\"cwd\":\"$TMP\",\"session_id\":\"s1\"}" | bash "$HOOK")
STATUS=$?
[ "$STATUS" -eq 0 ] && [ -z "$OUT" ] || fail "an input without a transcript path should be silent with exit 0: status $STATUS, $OUT"
pass "no transcript path silent"

reset_flags
make_transcript "$DEFAULT_CRITICAL_PCT"
printf '\ns1\n' > "$FLAG_FILE"
: > "$FLAG_FILE.exit-marker"
OUT=$(run_hook)
[ -z "$OUT" ] || fail "an exit marker of the same session should allow the stop: $OUT"
[ ! -e "$FLAG_FILE.exit-marker" ] || fail "the exit marker should be consumed"
pass "exit marker of the same session allows the stop once"

printf '\ns1\n' > "$FLAG_FILE"
: > "$FLAG_FILE.exit-marker"
OUT=$(SMITH_PLAN_LIB="$TMP/no-plan-library.sh" run_hook 2>&1)
[ -z "$OUT" ] || fail "without the plan library an exit marker of the same session should still allow the stop: $OUT"
[ ! -e "$FLAG_FILE.exit-marker" ] || fail "without the plan library the exit marker should still be consumed"
pass "exit marker consumed without the plan library"

printf '\nother-session\n' > "$FLAG_FILE"
: > "$FLAG_FILE.exit-marker"
OUT=$(run_hook)
[ "$(printf '%s' "$OUT" | jq -r .reason)" = "$NO_PLAN_REASON" ] || fail "an exit marker of another session should still block: $OUT"
[ ! -e "$FLAG_FILE.exit-marker" ] || fail "the exit marker of another session should be consumed"
pass "exit marker of another session still blocks"

reset_flags
readonly LOWERED_PCT=$((DEFAULT_CRITICAL_PCT - 10))
readonly RAISED_PCT=$((DEFAULT_CRITICAL_PCT + 10))
make_transcript "$LOWERED_PCT"
OUT=$(CTX_CONTEXT_CRITICAL_PCT=$LOWERED_PCT run_hook)
[ "$(printf '%s' "$OUT" | jq -r .reason)" = "Context at ${LOWERED_PCT}%. Checkpoint this session, then /clear." ] || fail "a lowered threshold should block at its own value: $OUT"
make_transcript "$DEFAULT_CRITICAL_PCT"
OUT=$(CTX_CONTEXT_CRITICAL_PCT=$RAISED_PCT run_hook)
[ -z "$OUT" ] || fail "a raised threshold should be silent at the default value: $OUT"
pass "threshold follows CTX_CONTEXT_CRITICAL_PCT"

reset_flags
mkdir -p "$TMP/bin"
printf '#!/bin/sh\necho "$@" >> "%s"\n' "$TMP/orca-calls.log" > "$TMP/bin/orca"
chmod +x "$TMP/bin/orca"
make_transcript "$DEFAULT_CRITICAL_PCT"
OUT=$(PATH="$TMP/bin:$PATH" ORCA_TERMINAL_HANDLE=term_characterization run_hook)
[ "$(printf '%s' "$OUT" | jq -r .decision)" = block ] || fail "inside an Orca terminal the critical threshold should still block: $OUT"
[ "$(printf '%s' "$OUT" | jq -r .reason)" = "$NO_PLAN_REASON" ] || fail "inside an Orca terminal the reason should be unchanged: $OUT"
[ ! -e "$TMP/orca-calls.log" ] || fail "the hook should not call orca: $(cat "$TMP/orca-calls.log")"
pass "inside an Orca terminal the block is unchanged and orca is not called"

echo "PASS: enforce-clear"
