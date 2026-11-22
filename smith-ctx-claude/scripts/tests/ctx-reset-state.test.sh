#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
STATE_SCRIPT="$HERE/../ctx-reset-state.sh"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: ctx-reset-state - $1"; }

[ -x "$STATE_SCRIPT" ] || fail "ctx-reset-state.sh is missing or not executable: $STATE_SCRIPT"

TMP=$(mktemp -d)
mkdir -p "$TMP/plans"
export CLAUDE_CONFIG_DIR="$TMP"

readonly LABEL=zq_state_probe_label
readonly RESTORE_FLAG_PATH="$TMP/plans/.pending-memory-restore-20260101T010000-1"
readonly SUCCESSOR=abc12345

send() {
  "$STATE_SCRIPT" "$@"
}

expect() {
  local description=$1 wanted=$2
  shift 2
  local got
  got=$(send "$@") || fail "$description: exit status $? from: $*"
  [ "$got" = "$wanted" ] || fail "$description: wanted '$wanted', got '$got' from: $*"
}

reach_checkpointing() {
  send "$1" checkpoint-started > /dev/null
}

reach_checkpointed() {
  reach_checkpointing "$1"
  send "$1" checkpoint-written "label=$LABEL" "flag=$RESTORE_FLAG_PATH" > /dev/null
}

reach_continued() {
  reach_checkpointed "$1"
  send "$1" stop high=1 active=0 dispatch=on worked=0 > /dev/null
}

expect "a session never seen" "state=idle" unseen show
pass "a session with no record is idle"

expect "idle, stop below the threshold" "allow - idle" row-idle-low stop high=0 active=0 dispatch=on worked=0
pass "idle: a stop below the threshold is allowed"

expect "idle, stop at the threshold, dispatch on" "block SMITH_CTX_AUTO_RESET_BLOCKED idle" row-idle-high stop high=1 active=0 dispatch=on worked=0
expect "idle, a second stop at the threshold" "block SMITH_CTX_AUTO_RESET_BLOCKED idle" row-idle-high stop high=1 active=0 dispatch=on worked=0
expect "idle, stop at the threshold, dispatch off" "block - idle" row-idle-high-off stop high=1 active=0 dispatch=off worked=0
expect "idle, after a block" "no" row-idle-high known
expect "idle, after a block with dispatch off" "no" row-idle-high-off known
pass "idle: a stop at the threshold blocks, coded only with dispatch on, and records nothing"

for high in 0 1; do
  expect "idle, continuation stop with high $high" "unspecified - idle" row-idle-active stop high=$high active=1 dispatch=on worked=0
done
expect "idle, after a continuation stop" "no" row-idle-active known
pass "idle: a continuation stop is left to the older path and records nothing"

expect "idle, the checkpoint procedure starts" "record - checkpointing" row-idle-started checkpoint-started
expect "idle, after the start" "state=checkpointing" row-idle-started show
pass "idle: a started checkpoint makes the session checkpointing"

expect "idle, a checkpoint written with no recorded start" "record - checkpointed" row-idle-written checkpoint-written "label=$LABEL" "flag=$RESTORE_FLAG_PATH"
[ "$(send row-idle-written show-field label)" = "$LABEL" ] || fail "idle, checkpoint written: the label should be recorded"
pass "idle: a written checkpoint makes the session checkpointed"

reach_checkpointing row-checkpointing-stop
for high in 0 1; do
  for active in 0 1; do
    expect "checkpointing, stop with high $high and stop_hook_active $active" "allow SMITH_CTX_CHECKPOINT_IN_PROGRESS checkpointing" row-checkpointing-stop stop high=$high active=$active dispatch=on worked=0
  done
done
pass "checkpointing: every stop is allowed with the in-progress notice"

reach_checkpointing row-started-again
expect "checkpointing, the checkpoint procedure starts again" "record - checkpointing" row-started-again checkpoint-started
pass "checkpointing: a repeated start changes nothing"

reach_checkpointing row-checkpointing-written
expect "checkpointing, checkpoint written" "record - checkpointed" row-checkpointing-written checkpoint-written "label=$LABEL" "flag=$RESTORE_FLAG_PATH"
[ "$(send row-checkpointing-written show-field label)" = "$LABEL" ] || fail "checkpointing, checkpoint written: the label should be recorded"
[ "$(send row-checkpointing-written show-field flag)" = "$RESTORE_FLAG_PATH" ] || fail "checkpointing, checkpoint written: the restore flag should be recorded"
[[ "$(send row-checkpointing-written show-field written_at)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$ ]] || fail "checkpointing, checkpoint written: the write time should be recorded with its offset: $(send row-checkpointing-written show-field written_at)"
pass "checkpointing: a written checkpoint records the label, the restore flag and the write time"

reach_checkpointed row-worked-high
expect "checkpointed, worked, stop at the threshold" "block SMITH_CTX_AUTO_RESET_BLOCKED idle" row-worked-high stop high=1 active=0 dispatch=on worked=1
expect "checkpointed, worked, the state afterwards" "state=idle" row-worked-high show
for dropped in label flag written_at; do
  [ -z "$(send row-worked-high show-field "$dropped")" ] || fail "checkpointed, worked: $dropped should be dropped"
done
expect "checkpointed, worked, the record afterwards" "yes" row-worked-high known
reach_checkpointed row-worked-low
expect "checkpointed, worked, stop below the threshold" "allow - idle" row-worked-low stop high=0 active=0 dispatch=on worked=1
reach_checkpointed row-worked-active
expect "checkpointed, worked, continuation stop at the threshold" "block SMITH_CTX_AUTO_RESET_BLOCKED idle" row-worked-active stop high=1 active=1 dispatch=on worked=1
expect "checkpointed, worked, continuation stop, the state afterwards" "state=idle" row-worked-active show
reach_checkpointed row-worked-active-low
expect "checkpointed, worked, continuation stop below the threshold" "unspecified - idle" row-worked-active-low stop high=0 active=1 dispatch=on worked=1
reach_checkpointed row-worked-off
expect "checkpointed, worked, stop at the threshold, dispatch off" "block - idle" row-worked-off stop high=1 active=0 dispatch=off worked=1
reach_checkpointed row-worked-unstated
expect "checkpointed, a stop that does not say whether the session worked" "block SMITH_CTX_AUTO_RESET_BLOCKED idle" row-worked-unstated stop high=1 active=0 dispatch=on
pass "checkpointed: a stop after work since the write is answered as idle and drops the checkpoint"

reach_checkpointed row-checkpointed-low
for active in 0 1; do
  expect "checkpointed, not worked, stop below the threshold with stop_hook_active $active" "allow - checkpointed" row-checkpointed-low stop high=0 active=$active dispatch=on worked=0
done
[ "$(send row-checkpointed-low show-field label)" = "$LABEL" ] || fail "checkpointed: a stop below the threshold should keep the label"
pass "checkpointed: a stop below the threshold with no work since the write keeps the checkpoint"

for active in 0 1; do
  reach_checkpointed "row-dispatch-$active"
  expect "checkpointed, not worked, stop at the threshold with stop_hook_active $active" "dispatch - continued" "row-dispatch-$active" stop high=1 active=$active dispatch=on worked=0
  expect "checkpointed, after the dispatch answer" "state=continued" "row-dispatch-$active" show
  [ "$(send "row-dispatch-$active" show-field label)" = "$LABEL" ] || fail "continued: the label should be kept for the launch"
  [ "$(send "row-dispatch-$active" show-field flag)" = "$RESTORE_FLAG_PATH" ] || fail "continued: the restore flag should be kept for the launch"
done
pass "checkpointed: a stop at the threshold with no work since the write becomes continued before the launch"

reach_checkpointed row-dispatch-off
expect "checkpointed, not worked, stop at the threshold, dispatch off" "allow SMITH_CTX_CHECKPOINT_WRITTEN checkpointed" row-dispatch-off stop high=1 active=0 dispatch=off worked=0
expect "checkpointed, dispatch off, the state afterwards" "state=checkpointed" row-dispatch-off show
pass "checkpointed: with dispatch off a stop at the threshold is allowed with the written notice"

reach_checkpointed row-checkpointed-started
expect "checkpointed, the checkpoint procedure starts again" "record - checkpointing" row-checkpointed-started checkpoint-started
for dropped in label flag written_at; do
  [ -z "$(send row-checkpointed-started show-field "$dropped")" ] || fail "checkpointed, new start: $dropped should be dropped"
done
pass "checkpointed: a new start makes the session checkpointing and drops the earlier checkpoint"

reach_checkpointed row-written-again
expect "checkpointed, a second checkpoint written" "record - checkpointed" row-written-again checkpoint-written "label=zq_second_label" "flag=$TMP/plans/.pending-memory-restore-20260101T020000-1"
[ "$(send row-written-again show-field label)" = zq_second_label ] || fail "checkpointed, second write: the label should be replaced"
[ "$(send row-written-again show-field flag)" = "$TMP/plans/.pending-memory-restore-20260101T020000-1" ] || fail "checkpointed, second write: the restore flag should be replaced"
pass "checkpointed: a second written checkpoint replaces the label and the restore flag"

reach_continued row-continued-stop
for high in 0 1; do
  for active in 0 1; do
    expect "continued, stop with high $high and stop_hook_active $active" "allow SMITH_CTX_ALREADY_CONTINUED continued" row-continued-stop stop high=$high active=$active dispatch=on worked=1
  done
done
pass "continued: every stop is allowed with the already-continued notice"

reach_continued row-launch-recognized
expect "continued, launch recognized" "block SMITH_CTX_CONTINUED continued" row-launch-recognized dispatched "successor=$SUCCESSOR"
[ "$(send row-launch-recognized show-field successor)" = "$SUCCESSOR" ] || fail "continued: the successor should be recorded"
expect "continued, a second launch report" "unspecified - continued" row-launch-recognized dispatched "successor=other"
[ "$(send row-launch-recognized show-field successor)" = "$SUCCESSOR" ] || fail "continued: a second launch report should not replace the successor"
pass "continued: a recognized launch blocks once and records the successor"

reach_continued row-launch-unrecognized
expect "continued, launch output not recognized" "allow SMITH_CTX_DISPATCH_FAILED continued" row-launch-unrecognized dispatch-unrecognized
expect "continued, the stop after a failed launch" "allow SMITH_CTX_ALREADY_CONTINUED continued" row-launch-unrecognized stop high=1 active=0 dispatch=on worked=0
expect "continued, a launch report after a failed launch" "unspecified - continued" row-launch-unrecognized dispatched "successor=$SUCCESSOR"
pass "continued: an unrecognized launch is reported and never retried"

reach_continued row-continued-events
expect "continued, the checkpoint procedure starts" "unspecified - continued" row-continued-events checkpoint-started
expect "continued, a checkpoint written" "unspecified - continued" row-continued-events checkpoint-written "label=zq_second_label" "flag=$RESTORE_FLAG_PATH"
[ "$(send row-continued-events show-field label)" = "$LABEL" ] || fail "continued: a later write should not replace the label"
pass "continued: a later start or write is unspecified and changes nothing"

for state in idle checkpointing checkpointed; do
  case "$state" in
    checkpointing) reach_checkpointing "row-report-$state" ;;
    checkpointed) reach_checkpointed "row-report-$state" ;;
  esac
  expect "$state, a launch report with no launch" "unspecified - $state" "row-report-$state" dispatched "successor=$SUCCESSOR"
  expect "$state, a failed-launch report with no launch" "unspecified - $state" "row-report-$state" dispatch-unrecognized
done
pass "a launch report outside continued is unspecified"

reach_checkpointed sequence-idle-after-write
expect "no work since the write, stop below the threshold" "allow - checkpointed" sequence-idle-after-write stop high=0 active=0 dispatch=on worked=0
expect "no work since the write, the first stop at the threshold" "dispatch - continued" sequence-idle-after-write stop high=1 active=0 dispatch=on worked=0
expect "no work since the write, the stop after the launch" "allow SMITH_CTX_ALREADY_CONTINUED continued" sequence-idle-after-write stop high=1 active=1 dispatch=on worked=0
pass "sequence: a checkpoint written below the threshold with no later work is handed on at the first stop at the threshold, once"

reach_checkpointed sequence-work-after-write
expect "work since the write, the first stop at the threshold, a continuation" "block SMITH_CTX_AUTO_RESET_BLOCKED idle" sequence-work-after-write stop high=1 active=1 dispatch=on worked=1
expect "work since the write, the new checkpoint starts" "record - checkpointing" sequence-work-after-write checkpoint-started
expect "work since the write, a stop during the new audit" "allow SMITH_CTX_CHECKPOINT_IN_PROGRESS checkpointing" sequence-work-after-write stop high=1 active=1 dispatch=on worked=1
send sequence-work-after-write checkpoint-written "label=zq_second_label" "flag=$RESTORE_FLAG_PATH" > /dev/null
expect "work since the write, the stop after the new write" "dispatch - continued" sequence-work-after-write stop high=1 active=1 dispatch=on worked=0
[ "$(send sequence-work-after-write show-field label)" = zq_second_label ] || fail "work since the write: the new checkpoint should be the one handed on"
pass "sequence: a checkpoint followed by work is asked for again, and the new one is handed on"

READ_ONLY_HOME=$(mktemp -d)
mkdir -p "$READ_ONLY_HOME/plans"
chmod 555 "$READ_ONLY_HOME/plans"
STDOUT=$(CLAUDE_CONFIG_DIR="$READ_ONLY_HOME" "$STATE_SCRIPT" row-unwritable checkpoint-started 2>"$READ_ONLY_HOME/stderr")
STATUS=$?
chmod 755 "$READ_ONLY_HOME/plans"
[ "$STATUS" -ne 0 ] || fail "unwritable flags folder: the state script should exit non-zero"
[ -z "$STDOUT" ] || fail "unwritable flags folder: no answer should be printed: $STDOUT"
grep -qF "state write failed: $READ_ONLY_HOME/plans/.ctx-reset-state-row-unwritable" "$READ_ONLY_HOME/stderr" || fail "unwritable flags folder: stderr should name the state file: $(cat "$READ_ONLY_HOME/stderr")"
pass "a state write that fails is reported on stderr, exits non-zero and prints no answer"

expect "known, a session with no record" "no" known-unseen known
[ ! -e "$TMP/plans/.ctx-reset-state-known-unseen" ] || fail "known, a session with no record: asking must write no record"
reach_checkpointing known-seen
expect "known, a session with a record" "yes" known-seen known
expect "known, after asking" "state=checkpointing" known-seen show
pass "known: answers whether a record exists for the session and writes nothing"

reach_checkpointing newline-value
RECORD_BEFORE=$(cat "$TMP/plans/.ctx-reset-state-newline-value")
OUT=$(send newline-value checkpoint-written "label=$(printf 'x\nsuccessor=now')" "flag=$RESTORE_FLAG_PATH" 2>&1)
STATUS=$?
[ "$STATUS" -eq 64 ] || fail "a value with a newline: exit status should be 64, got $STATUS: $OUT"
[ "$(cat "$TMP/plans/.ctx-reset-state-newline-value")" = "$RECORD_BEFORE" ] || fail "a value with a newline: the record should be unchanged"
OUT=$(send newline-unseen stop high=1 "active=$(printf '0\n1')" dispatch=on worked=0 2>&1)
STATUS=$?
[ "$STATUS" -eq 64 ] || fail "a stop argument with a newline: exit status should be 64, got $STATUS: $OUT"
[ ! -e "$TMP/plans/.ctx-reset-state-newline-unseen" ] || fail "a stop argument with a newline: no record should be written"
pass "a name=value argument whose value holds a newline is a usage error and writes nothing"

for session_id in "a/b" ".hidden" ""; do
  OUT=$(send "$session_id" checkpoint-started 2>&1)
  STATUS=$?
  [ "$STATUS" -eq 64 ] || fail "the session id '$session_id': exit status should be 64, got $STATUS: $OUT"
done
[ "$(find "$TMP" -name '.ctx-reset-state-*' -newer "$STATE_SCRIPT" | grep -c 'hidden\|/b$')" -eq 0 ] || fail "a refused session id should write no record"
pass "a session id that is empty, holds a slash or starts with a dot is a usage error"

for removed in checkpoint-requested typed-prompt clear; do
  OUT=$(send row-removed-event "$removed" 2>&1)
  STATUS=$?
  [ "$STATUS" -eq 64 ] || fail "the removed event $removed: exit status should be 64, got $STATUS: $OUT"
done
pass "the events of the earlier design are usage errors"

readonly CHECKPOINT_SKILL="$HERE/../../../smith-checkpoint/SKILL.md"

first_recorded_command_line() {
  grep -m1 -E "ctx-reset-state\.sh\" \"\\\$CLAUDE_CODE_SESSION_ID\" $1\$" "$CHECKPOINT_SKILL" | sed 's/^[[:space:]]*//'
}

correction_paragraph_of_the_audit() {
  awk '/A correction the/ { found = 1 } /^7\. \*\*Call write-checkpoint\.sh/ { exit } found { sub(/^[[:space:]]*/, ""); print }' "$CHECKPOINT_SKILL"
}

START_LINE=$(first_recorded_command_line checkpoint-started)
[ -n "$START_LINE" ] || fail "smith-checkpoint/SKILL.md: the start command should be found before the audit"
[ -n "$(correction_paragraph_of_the_audit)" ] || fail "smith-checkpoint/SKILL.md: the correction paragraph of the audit should be found"
correction_paragraph_of_the_audit | grep -qxF -- "$START_LINE" || fail "smith-checkpoint/SKILL.md: the correction paragraph should carry the start command exactly: $START_LINE"
! grep -qE 'checkpoint-requested|typed-prompt' "$CHECKPOINT_SKILL" || fail "smith-checkpoint/SKILL.md: no command of the earlier design should remain"
pass "smith-checkpoint/SKILL.md: the audit and its re-run after a correction record the start with the same command"
