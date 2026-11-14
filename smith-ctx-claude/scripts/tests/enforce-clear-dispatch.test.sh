#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../enforce-clear.sh"
source "$HERE/../lib-plan.sh"

readonly DEFAULT_CRITICAL_PCT=60
readonly SONNET_4_CONTEXT_TOKENS=200000
readonly LABEL=zq_dispatch_probe_label
readonly BACKGROUND_ID=abc12345
readonly OLDER=202601010000.00
readonly NEWER=202601010100.00

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: enforce-clear-dispatch - $1"; }

TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT
mkdir -p "$TMP/plans" "$TMP/bin" "$TMP/failing-bin" "$TMP/silent-bin"
export CLAUDE_CONFIG_DIR="$TMP"
export _SMITH_PPID=12345
export CLAUDE_JOB_DIR="$TMP"
unset CTX_CONTEXT_CRITICAL_PCT CTX_AUTO_RESET_DISPATCH

PHYSICAL_TMP=$(cd "$TMP" && pwd -P)
CWD_KEY=$(session_key "" "$TMP")
PHYSICAL_KEY=$(session_key "" "$PHYSICAL_TMP")
PENDING_RELOAD="$TMP/plans/.pending-reload-$CWD_KEY"
RESTORE_FLAG="$TMP/plans/.pending-memory-restore-20260101T010000-1"
STATE_FILE="$TMP/plans/.plan-state-$(plan_state_key "$TMP")"
CALLS_LOG="$TMP/claude-calls.log"
OTHER_PROGRAMS_LOG="$TMP/other-programs.log"

write_fake_claude() {
  local folder=$1 exit_status=$2 output=$3
  cat > "$folder/claude" <<EOF
#!/bin/bash
stdin_kind=other
[ -p /dev/stdin ] && stdin_kind=pipe
[ -c /dev/stdin ] && stdin_kind=character-device
{ printf 'call cwd=%s stdin=%s\n' "\$PWD" "\$stdin_kind"; printf '%s\n' "\$@"; } >> "$CALLS_LOG"
printf '%s' "\${@: -1}" > "$CALLS_LOG.last"
printf '%s' "\${@: -2:1}" > "$CALLS_LOG.penultimate"
printf '%s\n' "$output"
exit $exit_status
EOF
  chmod +x "$folder/claude"
}

write_fake_other_program() {
  local folder=$1 name=$2
  printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$name" "$OTHER_PROGRAMS_LOG" > "$folder/$name"
  chmod +x "$folder/$name"
}

write_fake_claude "$TMP/bin" 0 "backgrounded · $BACKGROUND_ID"
write_fake_claude "$TMP/failing-bin" 1 "error: background sessions are unavailable"
write_fake_claude "$TMP/silent-bin" 0 "started"
for folder in "$TMP/bin" "$TMP/failing-bin" "$TMP/silent-bin"; do
  for program in orca osascript tmux; do write_fake_other_program "$folder" "$program"; done
done

make_transcript() {
  local pct=$1
  local tokens=$((SONNET_4_CONTEXT_TOKENS * pct / 100))
  printf '%s\n' "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"model\":\"claude-sonnet-4-20250514\",\"usage\":{\"input_tokens\":$tokens,\"output_tokens\":0}}}" > "$TMP/transcript.jsonl"
}

run_hook() {
  printf '%s' "{\"cwd\":\"$TMP\",\"session_id\":\"s1\",\"transcript_path\":\"$TMP/transcript.jsonl\"}" | bash "$HOOK"
}

run_continuing_stop() {
  local permission_mode=${1:-}
  local mode_field=""
  [ -n "$permission_mode" ] && mode_field=",\"permission_mode\":\"$permission_mode\""
  printf '%s' "{\"stop_hook_active\":true,\"cwd\":\"$TMP\",\"session_id\":\"s1\",\"transcript_path\":\"$TMP/transcript.jsonl\"$mode_field}" | bash "$HOOK"
}

write_pending_reload() {
  printf '\ns1\n2026-01-01T00:00:00+0000\n%s\nno-plan\n' "$TMP" > "$PENDING_RELOAD"
  touch -t "$OLDER" "$PENDING_RELOAD"
}

write_restore_flag() {
  local label=$1 key=$2 stamp=${3:-$NEWER}
  printf 'smith-checkpoint\n2026-01-01T01:00:00+0000\n%s\n%s\n%s\n' "$PHYSICAL_TMP" "$label" "$key" > "$RESTORE_FLAG"
  touch -t "$stamp" "$RESTORE_FLAG"
}

reset_state() {
  rm -f "$TMP"/plans/.pending-* "$TMP"/plans/.plan-state-* "$CALLS_LOG" "$CALLS_LOG.last" "$CALLS_LOG.penultimate" "$OTHER_PROGRAMS_LOG"
}

call_count() {
  [ -f "$CALLS_LOG" ] || { echo 0; return; }
  grep -c '^call cwd=' "$CALLS_LOG"
}

call_arguments() {
  sed -n '2,$p' "$CALLS_LOG"
}

expect_no_dispatch() {
  local description=$1 output=$2 status=$3
  [ "$status" -eq 0 ] || fail "$description: exit status should be 0, got $status"
  [ -z "$output" ] || fail "$description: should print nothing: $output"
  [ "$(call_count)" -eq 0 ] || fail "$description: claude should not be called: $(cat "$CALLS_LOG")"
  [ ! -e "$OTHER_PROGRAMS_LOG" ] || fail "$description: no other program should be called: $(cat "$OTHER_PROGRAMS_LOG")"
}

reset_state
make_transcript "$DEFAULT_CRITICAL_PCT"
write_pending_reload
write_restore_flag "$LABEL" "$PHYSICAL_KEY"
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
STATUS=$?
expect_no_dispatch "switch absent" "$OUT" "$STATUS"
[ -f "$RESTORE_FLAG" ] || fail "switch absent: the restore flag should stay"
pass "switch absent: a matching fresh flag dispatches nothing and stays silent"

for value in 0 true yes; do
  OUT=$(PATH="$TMP/bin:$PATH" CTX_AUTO_RESET_DISPATCH=$value run_continuing_stop acceptEdits)
  STATUS=$?
  expect_no_dispatch "switch set to $value" "$OUT" "$STATUS"
  [ -f "$RESTORE_FLAG" ] || fail "switch set to $value: the restore flag should stay"
done
pass "switch values other than 1 dispatch nothing"

export CTX_AUTO_RESET_DISPATCH=1

reset_state
make_transcript "$DEFAULT_CRITICAL_PCT"
OUT=$(PATH="$TMP/bin:$PATH" run_hook)
STATUS=$?
[ "$STATUS" -eq 0 ] || fail "switch on, block should exit 0, got $STATUS"
[ "$(printf '%s' "$OUT" | jq -r .decision)" = block ] || fail "switch on, the critical threshold should still block: $OUT"
[ "$(printf '%s' "$OUT" | jq -r .reason)" = "Context at ${DEFAULT_CRITICAL_PCT}%. Checkpoint this session; a fresh background session then continues from the checkpoint." ] || fail "switch on, unexpected reason: $OUT"
[ "$(printf '%s' "$OUT" | jq -c 'keys')" = '["decision","hookSpecificOutput","reason"]' ] || fail "switch on, unexpected block keys: $OUT"
[ -f "$PENDING_RELOAD" ] || fail "switch on, a block should still write the pending reload flag"
[ "$(call_count)" -eq 0 ] || fail "switch on, a block should not call claude: $(cat "$CALLS_LOG")"
pass "switch on: the block names the background continuation and dispatches nothing"

reset_state
make_transcript "$DEFAULT_CRITICAL_PCT"
open_items=("- [ ] top-level open" "  - [ ] nested open")
{ printf '# Plan\n\n- [x] done\n'; printf '%s\n' "${open_items[@]}"; } > "$TMP/plan.md"
printf 's1\n%s\n0\n\n%s\n' "$TMP/transcript.jsonl" "$TMP/plan.md" > "$STATE_FILE"
OUT=$(PATH="$TMP/bin:$PATH" run_hook)
[ "$(printf '%s' "$OUT" | jq -r .reason)" = "Context at ${DEFAULT_CRITICAL_PCT}% (${#open_items[@]} pending). Checkpoint this session; a fresh background session then continues from the checkpoint." ] || fail "switch on, pending plan reason: $OUT"
printf '# Plan\n\n- [x] done\n' > "$TMP/plan.md"
OUT=$(PATH="$TMP/bin:$PATH" run_hook)
[ "$(printf '%s' "$OUT" | jq -r .reason)" = "Context at ${DEFAULT_CRITICAL_PCT}% (plan completed). Checkpoint this session; a fresh background session then continues from the checkpoint." ] || fail "switch on, completed plan reason: $OUT"
pass "switch on: the plan forms of the status stay as today"

reset_state
make_transcript "$DEFAULT_CRITICAL_PCT"
write_pending_reload
write_restore_flag "$LABEL" "$PHYSICAL_KEY"
OUT=$(PATH="$TMP/bin:$PATH" run_hook)
[ "$(printf '%s' "$OUT" | jq -r .decision)" = block ] || fail "switch on, stop_hook_active false should block: $OUT"
[ "$(call_count)" -eq 0 ] || fail "switch on, stop_hook_active false should not dispatch: $(cat "$CALLS_LOG")"
[ -f "$RESTORE_FLAG" ] || fail "switch on, stop_hook_active false should keep the restore flag"
make_transcript $((DEFAULT_CRITICAL_PCT - 1))
OUT=$(PATH="$TMP/bin:$PATH" run_hook)
STATUS=$?
expect_no_dispatch "switch on, below the threshold with a fresh flag" "$OUT" "$STATUS"
pass "switch on: a stop that is not a continuation blocks or stays silent and never dispatches"

reset_state
make_transcript "$DEFAULT_CRITICAL_PCT"
write_pending_reload
write_restore_flag "$LABEL" "$PHYSICAL_KEY"
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
STATUS=$?
[ "$STATUS" -eq 0 ] || fail "dispatch should exit 0, got $STATUS"
[ "$(call_count)" -eq 1 ] || fail "dispatch should call claude once, got $(call_count)"
args=()
while IFS= read -r line; do args+=("$line"); done < <(call_arguments)
[ "${args[0]}" = --bg ] || fail "first argument should be --bg: ${args[*]}"
[ "${args[1]}" = --name ] || fail "second argument should be --name: ${args[*]}"
case "${args[2]}" in *"$LABEL"*) ;; *) fail "the name should contain the label: ${args[2]}" ;; esac
[ "${args[2]}" = "continue: $LABEL" ] || fail "the name should be exactly continue: «label»: ${args[2]}"
[ "${args[3]}" = --permission-mode ] && [ "${args[4]}" = acceptEdits ] || fail "the permission mode of the input should be passed on: ${args[*]}"
[ "${args[5]}" = -- ] || fail "-- should follow the options: ${args[*]}"
[ "$(cat "$CALLS_LOG.penultimate")" = -- ] || fail "-- should come immediately before the prompt: $(cat "$CALLS_LOG.penultimate")"
PROMPT=$(cat "$CALLS_LOG.last")
case "$PROMPT" in *"$LABEL"*) ;; *) fail "the prompt should name the label: $PROMPT" ;; esac
case "$PROMPT" in *"$CHECKPOINT_READ_ONE_BACKEND"*) ;; *) fail "the prompt should carry the shared one-backend wording: $PROMPT" ;; esac
case "$(head -1 "$CALLS_LOG")" in
  "call cwd=$TMP "*|"call cwd=$PHYSICAL_TMP "*) ;;
  *) fail "claude should run in the hook's cwd: $(head -1 "$CALLS_LOG")" ;;
esac
case "$(head -1 "$CALLS_LOG")" in *" stdin=character-device") ;; *) fail "claude should read stdin from /dev/null: $(head -1 "$CALLS_LOG")" ;; esac
[ ! -e "$OTHER_PROGRAMS_LOG" ] || fail "no program other than claude should be called: $(cat "$OTHER_PROGRAMS_LOG")"
pass "dispatch runs claude --bg --name «name» --permission-mode «mode» -- «prompt» in the hook's cwd"
[ ! -e "$RESTORE_FLAG" ] || fail "a successful dispatch should consume the restore flag"
[ -f "$PENDING_RELOAD" ] || fail "a successful dispatch should leave the pending reload file alone"
pass "a successful dispatch consumes the restore flag"
[ "$(printf '%s' "$OUT" | jq -r 'has("decision")')" = false ] || fail "a dispatch must not block: $OUT"
MESSAGE=$(printf '%s' "$OUT" | jq -r .systemMessage)
case "$MESSAGE" in *"$BACKGROUND_ID"*) ;; *) fail "the system message should name the background session id: $OUT" ;; esac
case "$MESSAGE" in *"${args[2]}"*) ;; *) fail "the system message should name the session name: $OUT" ;; esac
pass "a successful dispatch reports the id and the name in a system message"

OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
STATUS=$?
[ "$STATUS" -eq 0 ] && [ -z "$OUT" ] || fail "a second continuation stop should be silent: status $STATUS, $OUT"
[ "$(call_count)" -eq 1 ] || fail "a second continuation stop should not dispatch again, got $(call_count) calls"
pass "a second stop after a dispatch dispatches nothing"

reset_state
write_pending_reload
write_restore_flag "$LABEL" "$CWD_KEY"
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop)
[ "$(call_count)" -eq 1 ] || fail "a flag keyed over the hook cwd should dispatch, got $(call_count) calls: $OUT"
args=()
while IFS= read -r line; do args+=("$line"); done < <(call_arguments)
[ "${args[3]}" = -- ] || fail "without a permission mode in the input, -- should follow the name: ${args[*]}"
grep -qx -- --permission-mode "$CALLS_LOG" && fail "without a permission mode in the input none should be passed: ${args[*]}"
pass "a flag keyed over the hook cwd dispatches, without --permission-mode when the input has none"

reset_state
write_pending_reload
write_restore_flag "$LABEL" "$PHYSICAL_KEY"
NEWEST_FLAG="$TMP/plans/.pending-memory-restore-20260101T020000-2"
printf 'smith-checkpoint\n2026-01-01T02:00:00+0000\n%s\nzq_newest_label\n%s\n' "$PHYSICAL_TMP" "$PHYSICAL_KEY" > "$NEWEST_FLAG"
touch -t 202601010200.00 "$NEWEST_FLAG"
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
[ "$(call_count)" -eq 1 ] || fail "several matching flags should dispatch once, got $(call_count) calls: $OUT"
args=()
while IFS= read -r line; do args+=("$line"); done < <(call_arguments)
[ "${args[2]}" = "continue: zq_newest_label" ] || fail "the newest matching flag should win: ${args[2]}"
[ ! -e "$NEWEST_FLAG" ] || fail "the dispatched flag should be consumed"
[ -f "$RESTORE_FLAG" ] || fail "the older flag should stay"
pass "the newest of several matching fresh flags is dispatched and consumed"

reset_state
write_pending_reload
write_restore_flag "$LABEL" notmykey12345678
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
STATUS=$?
expect_no_dispatch "flag of another session" "$OUT" "$STATUS"
[ -f "$RESTORE_FLAG" ] || fail "flag of another session should stay"
pass "a flag of another session key dispatches nothing"

reset_state
write_pending_reload
write_restore_flag "$LABEL" "$PHYSICAL_KEY" 202512312300.00
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
STATUS=$?
expect_no_dispatch "flag older than the pending reload file" "$OUT" "$STATUS"
[ -f "$RESTORE_FLAG" ] || fail "an older flag should stay"
pass "a flag older than the pending reload file dispatches nothing"

reset_state
write_restore_flag "$LABEL" "$PHYSICAL_KEY"
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
STATUS=$?
expect_no_dispatch "no pending reload file" "$OUT" "$STATUS"
[ -f "$RESTORE_FLAG" ] || fail "without a pending reload file the flag should stay"
pass "without a pending reload file nothing is dispatched"

reset_state
write_pending_reload
write_restore_flag "" "$PHYSICAL_KEY"
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
STATUS=$?
expect_no_dispatch "empty label" "$OUT" "$STATUS"
[ -f "$RESTORE_FLAG" ] || fail "a flag with an empty label should stay"
pass "a flag with an empty label dispatches nothing"

for variant in failing-bin silent-bin; do
  reset_state
  write_pending_reload
  write_restore_flag "$LABEL" "$PHYSICAL_KEY"
  OUT=$(PATH="$TMP/$variant:$PATH" run_continuing_stop acceptEdits)
  STATUS=$?
  [ "$STATUS" -eq 0 ] || fail "$variant: a failed dispatch should exit 0, got $STATUS"
  [ "$(call_count)" -eq 1 ] || fail "$variant: claude should be tried once, got $(call_count)"
  [ -f "$RESTORE_FLAG" ] || fail "$variant: a failed dispatch should keep the restore flag"
  [ "$(printf '%s' "$OUT" | jq -r 'has("decision")')" = false ] || fail "$variant: a failed dispatch must not block: $OUT"
  case "$(printf '%s' "$OUT" | jq -r .systemMessage)" in
    *"/clear"*) ;;
    *) fail "$variant: the system message should say that /clear still restores the checkpoint: $OUT" ;;
  esac
done
pass "a failing claude or one that prints no id keeps the flag and reports that /clear still restores it"

echo "PASS: enforce-clear-dispatch"
