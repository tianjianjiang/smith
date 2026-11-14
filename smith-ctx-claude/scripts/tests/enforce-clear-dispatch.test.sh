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
mkdir -p "$TMP/scripted-bin"
FAKE_STDOUT="$TMP/fake-stdout"
FAKE_STDERR="$TMP/fake-stderr"
cat > "$TMP/scripted-bin/claude" <<EOF
#!/bin/bash
printf 'call cwd=%s\n' "\$PWD" >> "$CALLS_LOG"
printf '%s\n' "\$@" >> "$CALLS_LOG"
[ -f "$FAKE_STDOUT" ] && cat "$FAKE_STDOUT"
[ -f "$FAKE_STDERR" ] && cat "$FAKE_STDERR" >&2
exit 1
EOF
chmod +x "$TMP/scripted-bin/claude"
for folder in "$TMP/bin" "$TMP/failing-bin" "$TMP/silent-bin" "$TMP/scripted-bin"; do
  for program in orca osascript tmux; do write_fake_other_program "$folder" "$program"; done
done

make_transcript() {
  local pct=$1
  local tokens=$((SONNET_4_CONTEXT_TOKENS * pct / 100))
  printf '%s\n' "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"model\":\"claude-sonnet-4-20250514\",\"usage\":{\"input_tokens\":$tokens,\"output_tokens\":0}}}" > "$TMP/transcript.jsonl"
}

HOOK_ENV=()

run_hook() {
  printf '%s' "{\"cwd\":\"$TMP\",\"session_id\":\"s1\",\"transcript_path\":\"$TMP/transcript.jsonl\"}" | env "${HOOK_ENV[@]}" bash "$HOOK"
}

run_continuing_stop() {
  local permission_mode=${1:-}
  local mode_field=""
  [ -n "$permission_mode" ] && mode_field=",\"permission_mode\":\"$permission_mode\""
  printf '%s' "{\"stop_hook_active\":true,\"cwd\":\"$TMP\",\"session_id\":\"s1\",\"transcript_path\":\"$TMP/transcript.jsonl\"$mode_field}" | env "${HOOK_ENV[@]}" bash "$HOOK"
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
  rm -f "$TMP"/plans/.[!.]* "$CALLS_LOG" "$CALLS_LOG.last" "$CALLS_LOG.penultimate" "$OTHER_PROGRAMS_LOG"
  make_transcript "$DEFAULT_CRITICAL_PCT"
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

expect_no_checkpoint_notice() {
  local description=$1 output=$2 status=$3
  [ "$status" -eq 0 ] || fail "$description: exit status should be 0, got $status"
  [ "$(call_count)" -eq 0 ] || fail "$description: claude should not be called: $(cat "$CALLS_LOG")"
  [ ! -e "$OTHER_PROGRAMS_LOG" ] || fail "$description: no other program should be called: $(cat "$OTHER_PROGRAMS_LOG")"
  [ "$(printf '%s' "$output" | jq -r 'has("decision")' 2>/dev/null)" = false ] || fail "$description: the notice must not block: $output"
  local message
  message=$(printf '%s' "$output" | jq -r '.systemMessage // empty' 2>/dev/null)
  case "$message" in
    *"no checkpoint"*"/clear"*) ;;
    *) fail "$description: should say that no checkpoint was written and that /clear still works: $output" ;;
  esac
}

readonly UNCHANGED_REASON="Context at ${DEFAULT_CRITICAL_PCT}%. Checkpoint this session, then /clear."
readonly MISSING_PLAN_LIB="$TMP/missing-lib-plan.sh"

expect_step_off() {
  local description=$1
  shift
  HOOK_ENV=("$@")
  reset_state
  make_transcript "$DEFAULT_CRITICAL_PCT"
  write_pending_reload
  write_restore_flag "$LABEL" "$PHYSICAL_KEY"
  OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
  STATUS=$?
  expect_no_dispatch "$description, matching fresh flag" "$OUT" "$STATUS"
  [ -f "$RESTORE_FLAG" ] || fail "$description: the restore flag should stay"
  rm -f "$RESTORE_FLAG"
  OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
  STATUS=$?
  expect_no_dispatch "$description, no checkpoint after the block" "$OUT" "$STATUS"
  OUT=$(PATH="$TMP/bin:$PATH" run_hook)
  [ "$(printf '%s' "$OUT" | jq -r .reason)" = "$UNCHANGED_REASON" ] || fail "$description: the block reason should be unchanged: $OUT"
  [ "$(call_count)" -eq 0 ] || fail "$description: a block should not call claude"
  rm -f "/tmp/session-facts-$CWD_KEY.md"
  HOOK_ENV=()
}

expect_step_off "foreground session" -u CLAUDE_JOB_DIR
pass "a foreground session dispatches nothing, keeps the block reason and prints no notice"
expect_step_off "background session with the switch set to 0" CTX_AUTO_RESET_DISPATCH=0
pass "the switch set to 0 turns the step off in a background session"
expect_step_off "missing plan library" SMITH_PLAN_LIB="$MISSING_PLAN_LIB"
pass "without the shared restore wording the step stays off"

for value in "" 1 true; do
  reset_state
  write_pending_reload
  write_restore_flag "$LABEL" "$PHYSICAL_KEY"
  if [ -z "$value" ]; then
    OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
  else
    OUT=$(PATH="$TMP/bin:$PATH" CTX_AUTO_RESET_DISPATCH=$value run_continuing_stop acceptEdits)
  fi
  [ "$(call_count)" -eq 1 ] || fail "switch ${value:-unset}: a background session should dispatch, got $(call_count) calls: $OUT"
done
pass "unset, 1 and true all leave the step on in a background session"

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
[ "${args[2]}" = "continue: $LABEL" ] || fail "the name should be exactly continue: «label»: ${args[2]}"
[ "${args[3]}" = --permission-mode ] && [ "${args[4]}" = acceptEdits ] || fail "the permission mode of the input should be passed on: ${args[*]}"
[ "${args[5]}" = -- ] || fail "-- should follow the options: ${args[*]}"
[ "$(cat "$CALLS_LOG.penultimate")" = -- ] || fail "-- should come immediately before the prompt: $(cat "$CALLS_LOG.penultimate")"
PROMPT=$(cat "$CALLS_LOG.last")
case "$PROMPT" in *"$LABEL"*) ;; *) fail "the prompt should name the label: $PROMPT" ;; esac
case "$PROMPT" in *"$CHECKPOINT_READ_ONE_BACKEND"*) ;; *) fail "the prompt should carry the shared one-backend wording: $PROMPT" ;; esac
case "$PROMPT" in *"continue the work thread.") ;; *) fail "the prompt should end by telling the session to continue the work thread: $PROMPT" ;; esac
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
OLDER_MATCHING_FLAG="$TMP/plans/.pending-memory-restore-20260101T090000-9"
mv "$RESTORE_FLAG" "$OLDER_MATCHING_FLAG"
write_named_flag() {
  local path=$1 label=$2 key=$3 stamp=$4
  printf 'smith-checkpoint\n2026-01-01T00:00:00+0000\n%s\n%s\n%s\n' "$PHYSICAL_TMP" "$label" "$key" > "$path"
  touch -t "$stamp" "$path"
}
FIRST_IN_GLOB_ORDER_FLAG="$TMP/plans/.pending-memory-restore-20260101T000000-1"
write_named_flag "$FIRST_IN_GLOB_ORDER_FLAG" zq_first_in_glob_order_label "$PHYSICAL_KEY" 202601010130.00
NEWEST_FLAG="$TMP/plans/.pending-memory-restore-20260101T040000-4"
write_named_flag "$NEWEST_FLAG" zq_newest_label "$PHYSICAL_KEY" 202601010200.00
write_named_flag "$TMP/plans/.pending-memory-restore-20260101T030000-3" zq_other_session_label notmykey12345678 202601010300.00
write_named_flag "$TMP/plans/.pending-memory-restore-20260101T060000-6" "" "$PHYSICAL_KEY" 202601010400.00
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
[ "$(call_count)" -eq 1 ] || fail "several matching flags should dispatch once, got $(call_count) calls: $OUT"
args=()
while IFS= read -r line; do args+=("$line"); done < <(call_arguments)
[ "${args[2]}" = "continue: zq_newest_label" ] || fail "the newest matching flag should win over glob order and over newer flags that do not match: ${args[2]}"
[ ! -e "$NEWEST_FLAG" ] || fail "the dispatched flag should be consumed"
[ -f "$OLDER_MATCHING_FLAG" ] && [ -f "$FIRST_IN_GLOB_ORDER_FLAG" ] || fail "the older flags should stay"
pass "the newest of several matching fresh flags is dispatched and consumed"
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
[ "$(call_count)" -eq 1 ] || fail "older flags superseded by a dispatched one should not start a second continuation, got $(call_count) calls: $OUT"
[ -f "$OLDER_MATCHING_FLAG" ] && [ -f "$FIRST_IN_GLOB_ORDER_FLAG" ] || fail "superseded older flags should stay in place"
pass "older fresh flags are superseded by the dispatched newest one"

reset_state
write_pending_reload
write_named_flag "$RESTORE_FLAG" "$LABEL" "" "$NEWER"
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
STATUS=$?
expect_no_checkpoint_notice "fresh flag with an empty session key" "$OUT" "$STATUS"
[ -f "$RESTORE_FLAG" ] || fail "a fresh flag with an empty session key should stay"
pass "a fresh flag with an empty session key never dispatches"

reset_state
write_pending_reload
write_restore_flag "$LABEL" notmykey12345678
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
STATUS=$?
expect_no_checkpoint_notice "flag of another session" "$OUT" "$STATUS"
[ -f "$RESTORE_FLAG" ] || fail "flag of another session should stay"
pass "a flag of another session key dispatches nothing and the notice says no checkpoint was written"

reset_state
write_pending_reload
write_restore_flag "$LABEL" "$PHYSICAL_KEY" 202512312300.00
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
STATUS=$?
expect_no_checkpoint_notice "flag older than the pending reload file" "$OUT" "$STATUS"
[ -f "$RESTORE_FLAG" ] || fail "an older flag should stay"
pass "a flag older than the pending reload file dispatches nothing and the notice says no checkpoint was written"

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
expect_no_checkpoint_notice "empty label" "$OUT" "$STATUS"
[ -f "$RESTORE_FLAG" ] || fail "a flag with an empty label should stay"
pass "a flag with an empty label dispatches nothing and the notice says no checkpoint was written"

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
  MESSAGE=$(printf '%s' "$OUT" | jq -r .systemMessage)
  case "$MESSAGE" in
    *"/clear"*) ;;
    *) fail "$variant: the system message should say that /clear still restores the checkpoint: $OUT" ;;
  esac
  case "$MESSAGE" in *"$LABEL"*) ;; *) fail "$variant: the system message should name the label: $OUT" ;; esac
  case "$variant" in
    failing-bin) FIRST_OUTPUT_LINE="error: background sessions are unavailable" ;;
    silent-bin) FIRST_OUTPUT_LINE="started" ;;
  esac
  case "$MESSAGE" in *"$FIRST_OUTPUT_LINE"*) ;; *) fail "$variant: the system message should carry the first line of the claude output: $OUT" ;; esac
  OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
  STATUS=$?
  [ "$STATUS" -eq 0 ] || fail "$variant: a later stop after a failed dispatch should exit 0, got $STATUS"
  [ "$(call_count)" -eq 1 ] || fail "$variant: a later stop should not try the same flag again, got $(call_count) calls: $OUT"
  [ -f "$RESTORE_FLAG" ] || fail "$variant: the flag should stay after the later stop so /clear can restore it"
  [ "$(printf '%s' "$OUT" | jq -r 'has("decision")' 2>/dev/null)" != true ] || fail "$variant: a later stop must not block: $OUT"
done
pass "a failing claude or one that prints no id keeps the flag and reports the label, the first output line and that /clear still restores it"
pass "a flag whose dispatch failed is not tried again on a later stop and stays for /clear"

reset_state
write_pending_reload
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
STATUS=$?
expect_no_checkpoint_notice "pending reload file without a restore flag" "$OUT" "$STATUS"
pass "a continuing stop after a block without a new checkpoint says no background session was started"

OUT=$(PATH="$TMP/bin:$PATH" CTX_AUTO_RESET_DISPATCH=0 run_continuing_stop acceptEdits)
STATUS=$?
expect_no_dispatch "switch off, pending reload file without a restore flag" "$OUT" "$STATUS"
pass "switch off: a pending reload file without a restore flag stays silent"

reset_state
write_pending_reload
write_restore_flag "$LABEL" "$PHYSICAL_KEY"
OUT=$(PATH="$TMP/failing-bin:$PATH" run_continuing_stop acceptEdits)
[ "$(call_count)" -eq 1 ] || fail "flag A should be tried once, got $(call_count): $OUT"
FLAG_B="$TMP/plans/.pending-memory-restore-20260101T000000-0"
write_named_flag "$FLAG_B" zq_flag_b_label "$PHYSICAL_KEY" 202601010200.00
OUT=$(PATH="$TMP/failing-bin:$PATH" run_continuing_stop acceptEdits)
[ "$(call_count)" -eq 2 ] || fail "a newer flag B after a failed flag A should be tried, got $(call_count) calls: $OUT"
[ "$(grep -c '^continue: zq_flag_b_label$' "$CALLS_LOG")" -eq 1 ] || fail "the second call should be for flag B: $(cat "$CALLS_LOG")"
OUT=$(PATH="$TMP/failing-bin:$PATH" run_continuing_stop acceptEdits)
[ "$(call_count)" -eq 2 ] || fail "after A and B both failed, a later stop should make no call, got $(call_count) calls: $OUT"
[ -f "$RESTORE_FLAG" ] && [ -f "$FLAG_B" ] || fail "both failed flags should stay for /clear"
pass "every failed flag is skipped later, and a newer flag is still tried"

reset_state
write_pending_reload
write_restore_flag "$LABEL" "$PHYSICAL_KEY"
write_named_flag "$FLAG_B" zq_flag_b_label "$PHYSICAL_KEY" 202601010200.00
OUT=$(PATH="$TMP/failing-bin:$PATH" run_continuing_stop acceptEdits)
[ "$(call_count)" -eq 1 ] && [ "$(grep -c '^continue: zq_flag_b_label$' "$CALLS_LOG")" -eq 1 ] || fail "with two eligible flags the first stop should try B only: $(cat "$CALLS_LOG")"
for later_stop in second third; do
  OUT=$(PATH="$TMP/failing-bin:$PATH" run_continuing_stop acceptEdits)
  [ "$(call_count)" -eq 1 ] || fail "the $later_stop stop after B failed should make no call, got $(call_count) calls: $OUT"
done
[ -f "$RESTORE_FLAG" ] && [ -f "$FLAG_B" ] || fail "both flags should stay for /clear"
pass "with two eligible flags a failed attempt on the newest supersedes the older one"

expect_failure_reason() {
  local description=$1 expected=$2
  reset_state
  write_pending_reload
  write_restore_flag "$LABEL" "$PHYSICAL_KEY"
  OUT=$(PATH="$TMP/scripted-bin:$PATH" run_continuing_stop acceptEdits)
  STATUS=$?
  [ "$STATUS" -eq 0 ] || fail "$description: exit status should be 0, got $STATUS"
  MESSAGE=$(printf '%s' "$OUT" | jq -r .systemMessage)
  [ "$MESSAGE" = "Context reset: dispatching a background session for checkpoint \"$LABEL\" failed${expected}; /clear still restores the checkpoint." ] || fail "$description: unexpected failure message: $MESSAGE"
  rm -f "$FAKE_STDOUT" "$FAKE_STDERR"
}

printf 'error: written to stderr only\n' > "$FAKE_STDERR"
expect_failure_reason "stderr only" " (error: written to stderr only)"
pass "a failure written only to stderr is reported"

printf '\n   \n   padded reason with spaces   \nsecond line\n' > "$FAKE_STDOUT"
expect_failure_reason "leading blank lines" " (padded reason with spaces)"
pass "the reported line skips blank lines and is trimmed"

LONG_LINE=$(printf 'x%.0s' $(seq 1 250))
printf '%s\n' "$LONG_LINE" > "$FAKE_STDOUT"
expect_failure_reason "long line" " (${LONG_LINE:0:200})"
pass "a reported line longer than 200 characters is cut to 200"

expect_failure_reason "empty output" ""
pass "an empty output gives the failure message without an empty parenthesis"

OWN_MARKER="$TMP/plans/.auto-reset-attempt-$CWD_KEY"
OTHER_MARKER="$TMP/plans/.auto-reset-attempt-notmykey12345678"
reset_state
write_pending_reload
write_restore_flag "$LABEL" "$PHYSICAL_KEY"
OUT=$(PATH="$TMP/failing-bin:$PATH" run_continuing_stop acceptEdits)
[ -f "$OWN_MARKER" ] || fail "a failed dispatch should leave this session's attempt marker: $(ls -a "$TMP/plans")"
rm -f "$PENDING_RELOAD"
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
[ ! -e "$OWN_MARKER" ] || fail "a stop without a pending reload file should remove this session's marker"
pass "a stop without a pending reload file removes this session's marker"

reset_state
write_pending_reload
write_restore_flag "$LABEL" "$PHYSICAL_KEY"
OUT=$(PATH="$TMP/failing-bin:$PATH" run_continuing_stop acceptEdits)
printf '%s\n' "$TMP/plans/.pending-memory-restore-gone" > "$OTHER_MARKER"
touch -t 202601010030.00 "$OWN_MARKER" "$OTHER_MARKER"
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
[ ! -e "$OTHER_MARKER" ] || fail "an attempt marker of another key older than an hour should be deleted"
[ -f "$OWN_MARKER" ] || fail "this session's old marker should stay while its pending reload file exists"
[ "$(call_count)" -eq 1 ] || fail "the failed flag should not be tried again after the sweep, got $(call_count) calls: $OUT"
pass "the hourly sweep deletes old markers of other keys and keeps this session's own"

reset_state
write_pending_reload
write_restore_flag "$LABEL" "$PHYSICAL_KEY"
make_transcript $((DEFAULT_CRITICAL_PCT - 1))
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
STATUS=$?
expect_no_dispatch "below the threshold with a matching fresh flag" "$OUT" "$STATUS"
[ -f "$RESTORE_FLAG" ] || fail "below the threshold the restore flag should stay"
rm -f "$RESTORE_FLAG"
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
STATUS=$?
expect_no_dispatch "below the threshold without a flag" "$OUT" "$STATUS"
pass "a continuing stop below the critical threshold neither dispatches nor prints a notice"

readonly RAISED_CRITICAL_PCT=$((DEFAULT_CRITICAL_PCT + 20))
readonly LOWERED_CRITICAL_PCT=$((DEFAULT_CRITICAL_PCT - 20))
HOOK_ENV=(CTX_CONTEXT_CRITICAL_PCT=$RAISED_CRITICAL_PCT)
reset_state
write_pending_reload
write_restore_flag "$LABEL" "$PHYSICAL_KEY"
make_transcript "$DEFAULT_CRITICAL_PCT"
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
STATUS=$?
expect_no_dispatch "raised threshold, context at the default threshold" "$OUT" "$STATUS"
[ -f "$RESTORE_FLAG" ] || fail "below a raised threshold the restore flag should stay"
make_transcript "$RAISED_CRITICAL_PCT"
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
[ "$(call_count)" -eq 1 ] || fail "at a raised threshold a continuing stop should dispatch, got $(call_count) calls: $OUT"
HOOK_ENV=(CTX_CONTEXT_CRITICAL_PCT=$LOWERED_CRITICAL_PCT)
reset_state
write_pending_reload
write_restore_flag "$LABEL" "$PHYSICAL_KEY"
make_transcript $((DEFAULT_CRITICAL_PCT - 1))
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
[ "$(call_count)" -eq 1 ] || fail "at a lowered threshold a continuing stop below the default should dispatch, got $(call_count) calls: $OUT"
HOOK_ENV=()
pass "a continuing stop compares the context with the configured critical threshold"

reset_state
write_pending_reload
write_restore_flag "$LABEL" "$PHYSICAL_KEY"
OUT=$(printf '%s' "{\"stop_hook_active\":true,\"cwd\":\"$TMP\",\"session_id\":\"s1\",\"permission_mode\":\"acceptEdits\"}" | PATH="$TMP/bin:$PATH" bash "$HOOK")
STATUS=$?
expect_no_dispatch "no transcript path with a matching fresh flag" "$OUT" "$STATUS"
[ -f "$RESTORE_FLAG" ] || fail "without a transcript path the restore flag should stay"
OUT=$(printf '%s' "{\"stop_hook_active\":true,\"cwd\":\"$TMP\",\"session_id\":\"s1\",\"transcript_path\":\"$TMP/missing.jsonl\"}" | PATH="$TMP/bin:$PATH" bash "$HOOK")
STATUS=$?
expect_no_dispatch "missing transcript file with a matching fresh flag" "$OUT" "$STATUS"
rm -f "$RESTORE_FLAG"
OUT=$(printf '%s' "{\"stop_hook_active\":true,\"cwd\":\"$TMP\",\"session_id\":\"s1\"}" | PATH="$TMP/bin:$PATH" bash "$HOOK")
STATUS=$?
expect_no_dispatch "no transcript path without a flag" "$OUT" "$STATUS"
pass "a continuing stop without a readable transcript neither dispatches nor prints a notice"

reset_state
write_pending_reload
write_restore_flag "$LABEL" "$PHYSICAL_KEY"
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
[ "$(call_count)" -eq 1 ] || fail "at the critical threshold a continuing stop should still dispatch, got $(call_count) calls: $OUT"
pass "at the critical threshold a continuing stop still dispatches"

reset_state
write_pending_reload
printf '%s\n' "$TMP/plans/.pending-memory-restore-from-an-earlier-block" > "$OWN_MARKER"
touch -t 202512312300.00 "$OWN_MARKER"
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
STATUS=$?
expect_no_checkpoint_notice "attempt marker older than the pending reload file" "$OUT" "$STATUS"
pass "an attempt marker from an earlier block does not silence the no-checkpoint notice"

reset_state
write_pending_reload
printf '%s\n' "$TMP/plans/.pending-memory-restore-of-another-session" > "$OTHER_MARKER"
FIVE_MINUTES_AGO=$(date -v-5M +%Y%m%d%H%M.%S 2>/dev/null || date -d '-5 minutes' +%Y%m%d%H%M.%S)
touch -t "$FIVE_MINUTES_AGO" "$OTHER_MARKER"
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
[ -f "$OTHER_MARKER" ] || fail "a fresh attempt marker of another key should survive a stop"
pass "a fresh attempt marker of another key survives the sweep"

reset_state
write_pending_reload
OTHER_PENDING_RELOAD="$TMP/plans/.pending-reload-notmykey12345678"
printf '\ns2\n2026-01-01T00:00:00+0000\n%s\nno-plan\n' "$TMP" > "$OTHER_PENDING_RELOAD"
printf '%s\n' "$TMP/plans/.pending-memory-restore-of-another-session" > "$OTHER_MARKER"
touch -t 202601010030.00 "$OTHER_MARKER"
OUT=$(PATH="$TMP/bin:$PATH" run_continuing_stop acceptEdits)
[ -f "$OTHER_MARKER" ] || fail "an old attempt marker of another key should survive while that key's pending reload file exists"
pass "an old attempt marker of another key survives while its pending reload file exists"

mkdir -p "$TMP/odd-id-bin"
readonly ODD_BACKGROUND_ID=Ab_12-cd
write_fake_claude "$TMP/odd-id-bin" 0 "backgrounded · $ODD_BACKGROUND_ID"
reset_state
write_pending_reload
write_restore_flag "$LABEL" "$PHYSICAL_KEY"
OUT=$(PATH="$TMP/odd-id-bin:$PATH" run_continuing_stop acceptEdits)
case "$(printf '%s' "$OUT" | jq -r .systemMessage)" in
  *"background session $ODD_BACKGROUND_ID named"*) ;;
  *) fail "the success message should carry the whole id with uppercase letters, underscores and hyphens: $OUT" ;;
esac
pass "an id with uppercase letters, an underscore and a hyphen is reported whole"

echo "PASS: enforce-clear-dispatch"
