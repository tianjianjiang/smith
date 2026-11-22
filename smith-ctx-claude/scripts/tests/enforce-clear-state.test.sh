#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../enforce-clear.sh"
STATE_SCRIPT="$HERE/../ctx-reset-state.sh"

readonly CRITICAL_PCT=60
readonly SONNET_4_CONTEXT_TOKENS=200000

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: enforce-clear-state - $1"; }

new_sandbox() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/plans"
  export CLAUDE_CONFIG_DIR="$TMP"
  export _SMITH_PPID=12345
  unset CTX_CONTEXT_CRITICAL_PCT CTX_AUTO_RESET_DISPATCH CLAUDE_JOB_DIR
}

make_transcript() {
  local tokens=$((SONNET_4_CONTEXT_TOKENS * $1 / 100))
  printf '%s\n' "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"model\":\"claude-sonnet-4-20250514\",\"usage\":{\"input_tokens\":$tokens,\"output_tokens\":0}}}" > "$TMP/transcript.jsonl"
}

readonly BEFORE_ANY_WRITE=2000-01-01T00:00:00.000Z
readonly AFTER_ANY_WRITE=2099-01-01T00:00:00.000Z

prepend_to_transcript() {
  printf '%s\n' "$1" | cat - "$TMP/transcript.jsonl" > "$TMP/transcript.jsonl.new"
  mv "$TMP/transcript.jsonl.new" "$TMP/transcript.jsonl"
}

add_tool_call_at() {
  prepend_to_transcript "{\"type\":\"assistant\",\"timestamp\":\"$1\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"input\":{}}]}}"
}

add_machine_message_at() {
  prepend_to_transcript "{\"type\":\"user\",\"timestamp\":\"$1\",\"message\":{\"role\":\"user\",\"content\":\"<task-notification>placeholder</task-notification>\"}}"
  prepend_to_transcript "{\"type\":\"assistant\",\"timestamp\":\"$1\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"noted\"}]}}"
}

write_checkpoint_of() {
  "$STATE_SCRIPT" "$1" checkpoint-written label=zq_label "flag=${2-$TMP/plans/.pending-memory-restore-x}" > /dev/null
}

stop_of() {
  local session=$1 active=$2
  printf '%s' "{\"stop_hook_active\":$active,\"cwd\":\"$TMP\",\"session_id\":\"$session\",\"transcript_path\":\"$TMP/transcript.jsonl\"}" | bash "$HOOK"
}

state_of() {
  "$STATE_SCRIPT" "$1" show
}

new_sandbox
make_transcript $((CRITICAL_PCT - 1))
OUT=$(stop_of s1 false)
[ -z "$OUT" ] || fail "a stop below the threshold should print nothing: $OUT"
[ "$(state_of s1)" = "state=idle" ] || fail "a stop below the threshold should leave the session idle, got $(state_of s1)"
pass "a stop below the threshold is allowed as before and the session stays idle"

new_sandbox
make_transcript "$CRITICAL_PCT"
OUT=$(stop_of s1 false)
[ "$(printf '%s' "$OUT" | jq -r .decision)" = block ] || fail "a stop at the threshold should block as before: $OUT"
[ "$(state_of s1)" = "state=idle" ] || fail "a blocked stop should leave the session idle, got $(state_of s1)"
[ "$("$STATE_SCRIPT" s1 known)" = no ] || fail "a blocked stop should write no state record"
OUT=$(stop_of s1 false)
[ "$(printf '%s' "$OUT" | jq -r .decision)" = block ] || fail "a second stop at the threshold should block as before: $OUT"
pass "a stop at the threshold blocks every time and leaves the session idle with no record"

new_sandbox
make_transcript "$CRITICAL_PCT"
printf '%s' "{\"cwd\":\"$TMP\",\"transcript_path\":\"$TMP/transcript.jsonl\"}" | bash "$HOOK" > /dev/null
[ -z "$(find "$TMP/plans" -name '.ctx-reset-state-*')" ] || fail "a stop without a session id should record nothing"
pass "a stop without a session id records nothing"

write_fake_claude() {
  mkdir -p "$TMP/bin"
  printf '#!/bin/sh\necho call >> "%s"\nprintf "%%s\\n" "%s"\nexit %s\n' "$TMP/claude-calls.log" "$1" "$2" > "$TMP/bin/claude"
  chmod +x "$TMP/bin/claude"
}

claude_calls() {
  [ -f "$TMP/claude-calls.log" ] || { echo 0; return; }
  grep -c '^call$' "$TMP/claude-calls.log"
}

new_sandbox
make_transcript "$CRITICAL_PCT"
stop_of s1 true > /dev/null
[ "$(state_of s1)" = "state=idle" ] || fail "a continuation stop of a session never blocked should leave it idle, got $(state_of s1)"
pass "a continuation stop of a session never blocked leaves it idle"

new_sandbox
make_transcript "$CRITICAL_PCT"
"$STATE_SCRIPT" s1 checkpoint-started > /dev/null
stop_of s1 true > /dev/null
[ "$(state_of s1)" = "state=checkpointing" ] || fail "a continuation stop during the checkpoint should keep the session checkpointing, got $(state_of s1)"
pass "a continuation stop during the checkpoint keeps the session checkpointing"

expect_allowed_with_code() {
  local description=$1 code=$2 output=$3
  [ "$(printf '%s' "$output" | jq -r 'has("decision")' 2>/dev/null)" = false ] || fail "$description: the stop must be allowed: $output"
  case "$(printf '%s' "$output" | jq -r '.systemMessage // empty' 2>/dev/null)" in
    "[$code] "*) ;;
    *) fail "$description: the system message should start with [$code]: $output" ;;
  esac
}

for job_dir in set unset; do
  new_sandbox
  [ "$job_dir" = set ] && export CLAUDE_JOB_DIR="$TMP"
  write_fake_claude "backgrounded · abc12345" 0
  make_transcript "$CRITICAL_PCT"
  "$STATE_SCRIPT" s1 checkpoint-started > /dev/null
  for active in false true; do
    OUT=$(PATH="$TMP/bin:$PATH" stop_of s1 "$active")
    expect_allowed_with_code "job folder $job_dir, stop_hook_active $active, during the checkpoint" SMITH_CTX_CHECKPOINT_IN_PROGRESS "$OUT"
  done
  [ "$(state_of s1)" = "state=checkpointing" ] || fail "job folder $job_dir: a stop during the checkpoint should keep the session checkpointing, got $(state_of s1)"
  [ "$(claude_calls)" -eq 0 ] || fail "job folder $job_dir: a stop during the checkpoint should not call claude"
done
pass "a stop during the checkpoint is allowed with the in-progress notice"

new_sandbox
make_transcript "$CRITICAL_PCT"
write_checkpoint_of s1
OUT=$(stop_of s1 false)
expect_allowed_with_code "dispatch off, a stop after the checkpoint" SMITH_CTX_CHECKPOINT_WRITTEN "$OUT"
case "$(printf '%s' "$OUT" | jq -r .systemMessage)" in
  *zq_label*/clear*) ;;
  *) fail "dispatch off: the notice should name the label and /clear: $OUT" ;;
esac
[ "$(state_of s1)" = "state=checkpointed" ] || fail "dispatch off: the session should stay checkpointed, got $(state_of s1)"
pass "with dispatch off a stop after the checkpoint is allowed and names the label and /clear"

new_sandbox
make_transcript "$CRITICAL_PCT"
write_checkpoint_of s1
"$STATE_SCRIPT" s1 stop high=1 active=0 dispatch=on worked=0 > /dev/null
"$STATE_SCRIPT" s1 dispatched successor=abc12345 > /dev/null
export CLAUDE_JOB_DIR="$TMP"
write_fake_claude "backgrounded · abc99999" 0
for active in false true; do
  OUT=$(PATH="$TMP/bin:$PATH" stop_of s1 "$active")
  expect_allowed_with_code "continued, stop_hook_active $active" SMITH_CTX_ALREADY_CONTINUED "$OUT"
  case "$(printf '%s' "$OUT" | jq -r .systemMessage)" in
    *abc12345*) ;;
    *) fail "continued: the notice should name the successor: $OUT" ;;
  esac
done
[ -z "$(find "$TMP/plans" -name '.pending-reload-*')" ] || fail "continued: a stop should write no pending reload"
[ "$(claude_calls)" -eq 0 ] || fail "continued: a stop should not call claude"
[ "$(state_of s1)" = "state=continued" ] || fail "continued: the session should stay continued, got $(state_of s1)"
pass "a stop of a continued session is allowed, names the successor and neither blocks nor dispatches"

new_sandbox
"$STATE_SCRIPT" s1 checkpoint-started > /dev/null
make_transcript $((CRITICAL_PCT - 1))
for active in false true; do
  OUT=$(stop_of s1 "$active")
  expect_allowed_with_code "below the threshold, stop_hook_active $active, during the checkpoint" SMITH_CTX_CHECKPOINT_IN_PROGRESS "$OUT"
done
pass "a stop below the threshold during the checkpoint is allowed with the in-progress notice"

new_sandbox
make_transcript "$CRITICAL_PCT"
write_checkpoint_of s1
OUT=$(stop_of s1 true)
expect_allowed_with_code "dispatch off, a continuation stop after the checkpoint" SMITH_CTX_CHECKPOINT_WRITTEN "$OUT"
case "$(printf '%s' "$OUT" | jq -r .systemMessage)" in
  *zq_label*/clear*) ;;
  *) fail "dispatch off, continuation stop: the notice should name the label and /clear: $OUT" ;;
esac
pass "with dispatch off a continuation stop after the checkpoint is allowed and names the label and /clear"

new_sandbox
make_transcript "$CRITICAL_PCT"
write_checkpoint_of s1 ""
OUT=$(stop_of s1 false)
expect_allowed_with_code "dispatch off, a checkpoint without a restore flag" SMITH_CTX_CHECKPOINT_WRITTEN "$OUT"
MESSAGE=$(printf '%s' "$OUT" | jq -r .systemMessage)
case "$MESSAGE" in
  *zq_label*"no restore flag was written"*) ;;
  *) fail "no restore flag: the notice should name the label and say no restore flag was written: $OUT" ;;
esac
case "$MESSAGE" in
  *"/clear to continue"*|*"/clear still restores"*) fail "no restore flag: the notice must not say /clear restores the checkpoint: $OUT" ;;
esac
pass "with dispatch off a checkpoint without a restore flag is named and not said to be restored by /clear"

copy_hook_without_state_script() {
  TREE=$(mktemp -d)
  mkdir -p "$TREE/smith-ctx-claude/scripts"
  cp "$HOOK" "$HERE/../lib-context.sh" "$HERE/../lib-plan.sh" "$TREE/smith-ctx-claude/scripts/"
}

stop_of_copied_hook() {
  printf '%s' "{\"stop_hook_active\":false,\"cwd\":\"$TMP\",\"session_id\":\"s1\",\"transcript_path\":\"$TMP/transcript.jsonl\"}" | bash "$TREE/smith-ctx-claude/scripts/enforce-clear.sh"
}

new_sandbox
make_transcript "$CRITICAL_PCT"
copy_hook_without_state_script
OUT=$(stop_of_copied_hook)
[ "$(printf '%s' "$OUT" | jq -r .decision)" = block ] || fail "missing state script: a stop at the threshold should block on the older path: $OUT"
[ -n "$(find "$TMP/plans" -name '.pending-reload-*')" ] || fail "missing state script: the older path should write the pending reload"
[ -z "$(find "$TMP/plans" -name '.ctx-reset-state-*')" ] || fail "missing state script: nothing should record a state"
pass "a missing state script falls back to the older path"

new_sandbox
make_transcript "$CRITICAL_PCT"
copy_hook_without_state_script
printf '#!/bin/bash\necho "allow - idle"\nexit 1\n' > "$TREE/smith-ctx-claude/scripts/ctx-reset-state.sh"
chmod +x "$TREE/smith-ctx-claude/scripts/ctx-reset-state.sh"
OUT=$(stop_of_copied_hook)
[ "$(printf '%s' "$OUT" | jq -r .decision)" = block ] || fail "failing state script: a stop at the threshold should block on the older path, whatever the script printed: $OUT"
[ -n "$(find "$TMP/plans" -name '.pending-reload-*')" ] || fail "failing state script: the older path should write the pending reload"
pass "a state script that exits non-zero falls back to the older path"

new_sandbox
make_transcript "$CRITICAL_PCT"
OUT=$(stop_of s1 false)
[ "$(printf '%s' "$OUT" | jq -r .decision)" = block ] || fail "dispatch off: a stop at the threshold should block: $OUT"
REASON=$(printf '%s' "$OUT" | jq -r .reason)
case "$REASON" in
  "["*) fail "dispatch off: the block reason should carry no code: $REASON" ;;
  *"Checkpoint this session, then /clear.") ;;
  *) fail "dispatch off: the block reason should end with the uncoded request: $REASON" ;;
esac
OUT=$(stop_of s1 false)
case "$(printf '%s' "$OUT" | jq -r .reason)" in
  "["*) fail "dispatch off: a repeated block reason should carry no code: $OUT" ;;
  *"Checkpoint this session, then /clear.") ;;
  *) fail "dispatch off: a repeated block reason should end with the uncoded request: $OUT" ;;
esac
pass "with dispatch off the block reason is uncoded"

dispatch_sandbox() {
  new_sandbox
  export CLAUDE_JOB_DIR="$TMP"
  write_fake_claude "backgrounded · abc12345" 0
  make_transcript "$CRITICAL_PCT"
}

for active in false true; do
  dispatch_sandbox
  add_tool_call_at "$BEFORE_ANY_WRITE"
  write_checkpoint_of s1
  PATH="$TMP/bin:$PATH" stop_of s1 "$active" > /dev/null
  [ "$(state_of s1)" = "state=continued" ] || fail "stop_hook_active $active, no tool call after the write: the session should be continued, got $(state_of s1)"
  [ "$(claude_calls)" -eq 1 ] || fail "stop_hook_active $active, no tool call after the write: claude should be called once, got $(claude_calls)"
done
pass "a checkpoint with no tool call after its write is handed on at the threshold"

dispatch_sandbox
write_checkpoint_of s1
add_tool_call_at "$AFTER_ANY_WRITE"
OUT=$(PATH="$TMP/bin:$PATH" stop_of s1 false)
[ "$(printf '%s' "$OUT" | jq -r .decision)" = block ] || fail "a tool call after the write: the stop at the threshold should block and ask again: $OUT"
case "$(printf '%s' "$OUT" | jq -r .reason)" in
  "[SMITH_CTX_AUTO_RESET_BLOCKED] "*) ;;
  *) fail "a tool call after the write: the block should be the checkpoint request: $OUT" ;;
esac
case "$(printf '%s' "$OUT" | jq -r .reason)" in
  *"tool call followed the earlier checkpoint"*) ;;
  *) fail "a tool call after the write: the block should say why it asks again: $OUT" ;;
esac
[ "$(state_of s1)" = "state=idle" ] || fail "a tool call after the write: the session should be idle, got $(state_of s1)"
[ "$(claude_calls)" -eq 0 ] || fail "a tool call after the write: claude should not be called"
pass "a checkpoint followed by a tool call is not handed on: the stop at the threshold asks for a new one"

dispatch_sandbox
write_checkpoint_of s1
add_tool_call_at "$AFTER_ANY_WRITE"
OUT=$(PATH="$TMP/bin:$PATH" stop_of s1 true)
[ "$(printf '%s' "$OUT" | jq -r .decision)" = block ] || fail "a tool call after the write, continuation stop: the stop should block and ask again: $OUT"
case "$(printf '%s' "$OUT" | jq -r .reason)" in
  "[SMITH_CTX_AUTO_RESET_BLOCKED] "*"tool call followed the earlier checkpoint"*) ;;
  *) fail "a tool call after the write, continuation stop: the block should be the checkpoint request and say why: $OUT" ;;
esac
[ "$(state_of s1)" = "state=idle" ] || fail "a tool call after the write, continuation stop: the session should be idle, got $(state_of s1)"
[ "$(claude_calls)" -eq 0 ] || fail "a tool call after the write, continuation stop: neither path should call claude"
OUT=$(PATH="$TMP/bin:$PATH" stop_of s1 true)
[ -z "$OUT" ] || fail "a continuation stop after that request, with no new checkpoint: nothing should be printed: $OUT"
pass "a checkpoint followed by a tool call is asked for again by a continuation stop too, once"

dispatch_sandbox
write_checkpoint_of s1
add_machine_message_at "$AFTER_ANY_WRITE"
PATH="$TMP/bin:$PATH" stop_of s1 false > /dev/null
[ "$(state_of s1)" = "state=continued" ] || fail "a machine message after the write: the session should be continued, got $(state_of s1)"
[ "$(claude_calls)" -eq 1 ] || fail "a machine message after the write: claude should be called once"
pass "a message after the write with no tool call leaves the checkpoint current"

dispatch_sandbox
printf 'state=checkpointed\nlabel=zq_label\nflag=\n' > "$TMP/plans/.ctx-reset-state-s1"
OUT=$(PATH="$TMP/bin:$PATH" stop_of s1 false)
[ "$(printf '%s' "$OUT" | jq -r .decision)" = block ] || fail "no recorded write time: the stop at the threshold should block: $OUT"
[ "$(claude_calls)" -eq 0 ] || fail "no recorded write time: claude should not be called"
pass "a checkpoint with no recorded write time counts as worked on"

dispatch_sandbox
write_checkpoint_of s1
mv "$TMP/transcript.jsonl" "$TMP/transcript-elsewhere.jsonl"
for active in false true; do
  OUT=$(PATH="$TMP/bin:$PATH" stop_of s1 "$active")
  [ -z "$OUT" ] || fail "a transcript that cannot be read, stop_hook_active $active: the stop should be allowed with no output: $OUT"
done
[ "$(claude_calls)" -eq 0 ] || fail "a transcript that cannot be read: claude should not be called"
[ "$(state_of s1)" = "state=checkpointed" ] || fail "a transcript that cannot be read: the session should stay checkpointed, got $(state_of s1)"
pass "a checkpoint is not handed on while the transcript cannot be read"

new_sandbox
make_transcript $((CRITICAL_PCT - 1))
write_checkpoint_of s1
OUT=$(stop_of s1 false)
[ -z "$OUT" ] || fail "below the threshold, no tool call after the write: nothing should be printed: $OUT"
[ "$(state_of s1)" = "state=checkpointed" ] || fail "below the threshold, no tool call after the write: the session should stay checkpointed, got $(state_of s1)"
add_tool_call_at "$AFTER_ANY_WRITE"
OUT=$(stop_of s1 false)
[ -z "$OUT" ] || fail "below the threshold, a tool call after the write: nothing should be printed: $OUT"
[ "$(state_of s1)" = "state=idle" ] || fail "below the threshold, a tool call after the write: the session should be idle, got $(state_of s1)"
pass "below the threshold a checkpoint is kept until a tool call follows it"

record_checkpoint_written_at() {
  printf 'state=checkpointed\nlabel=zq_label\nflag=\nwritten_at=%s\n' "$1" > "$TMP/plans/.ctx-reset-state-s1"
}

add_line_to_transcript() {
  prepend_to_transcript "$1"
}

expect_handed_on() {
  PATH="$TMP/bin:$PATH" stop_of s1 false > /dev/null
  [ "$(state_of s1)" = "state=continued" ] || fail "$1: the checkpoint should be handed on, got $(state_of s1)"
}

expect_asked_again() {
  local out
  out=$(PATH="$TMP/bin:$PATH" stop_of s1 false)
  [ "$(printf '%s' "$out" | jq -r .decision)" = block ] || fail "$1: the stop should block and ask again: $out"
  [ "$(claude_calls)" -eq 0 ] || fail "$1: claude should not be called"
}

dispatch_sandbox
record_checkpoint_written_at 2026-11-22T08:00:00-05:00
add_tool_call_at 2026-11-22T12:59:59.000Z
expect_handed_on "a write time west of Greenwich, a tool call one second before it"
dispatch_sandbox
record_checkpoint_written_at 2026-11-22T08:00:00-05:00
add_tool_call_at 2026-11-22T13:00:01.000Z
expect_asked_again "a write time west of Greenwich, a tool call one second after it"
dispatch_sandbox
record_checkpoint_written_at 2026-11-22T18:30:00+05:30
add_tool_call_at 2026-11-22T12:59:59.000Z
expect_handed_on "a write time east of Greenwich with a half hour, a tool call one second before it"
dispatch_sandbox
record_checkpoint_written_at 2026-11-22T18:30:00+05:30
add_tool_call_at 2026-11-22T13:00:01.000Z
expect_asked_again "a write time east of Greenwich with a half hour, a tool call one second after it"
pass "the write time is compared as an instant, whatever its offset"

dispatch_sandbox
record_checkpoint_written_at 2026-11-22T08:00:00-05:00
add_tool_call_at 2026-11-22T13:00:00.900Z
expect_asked_again "a tool call in the same second as the write"
pass "a tool call in the same second as the write counts as work, since the write time holds no fraction"

dispatch_sandbox
record_checkpoint_written_at 2026-11-22T08:00:00-05:00
add_line_to_transcript '{"type":"assistant","timestamp":"2026-11-22T13:00:00.100Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"\"$HOME/.claude/skills/smith-checkpoint/scripts/write-checkpoint.sh\" zq_label"}}]}}'
expect_asked_again "a call of write-checkpoint.sh in the same second as the recorded write"
dispatch_sandbox
record_checkpoint_written_at 2026-11-22T08:00:00-05:00
add_line_to_transcript '{"type":"assistant","timestamp":"2026-11-22T13:00:01.000Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"\"$HOME/.claude/skills/smith-checkpoint/scripts/write-checkpoint.sh\" zq_label"}}]}}'
expect_asked_again "a call of write-checkpoint.sh dated after the recorded write"
pass "a call of write-checkpoint.sh counts as the write only when it is dated before the second of the recorded write"

add_write_call_at() {
  add_line_to_transcript "{\"type\":\"assistant\",\"timestamp\":\"$1\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"input\":{\"command\":\"\\\"\$HOME/.claude/skills/smith-checkpoint/scripts/write-checkpoint.sh\\\" zq_label\"}}]}}"
}

dispatch_sandbox
record_checkpoint_written_at 2026-11-22T08:00:20-05:00
add_tool_call_at 2026-11-22T13:00:00.200Z
add_write_call_at 2026-11-22T13:00:00.100Z
expect_asked_again "a tool call sent with the write, after it, and dated before the write finished"
dispatch_sandbox
record_checkpoint_written_at 2026-11-22T08:00:20-05:00
add_write_call_at 2026-11-22T13:00:00.200Z
add_tool_call_at 2026-11-22T13:00:00.100Z
expect_handed_on "a tool call sent with the write, before it"
dispatch_sandbox
record_checkpoint_written_at 2026-11-22T08:00:20-05:00
add_line_to_transcript '{"type":"assistant","timestamp":"2026-11-22T13:00:00.100Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"sh write-checkpoint.sh zq_label"}},{"type":"tool_use","name":"Edit","input":{}}]}}'
expect_asked_again "a tool call in the same transcript line as the write, after it"
dispatch_sandbox
record_checkpoint_written_at 2026-11-22T08:00:20-05:00
add_write_call_at 2026-11-22T13:00:00.100Z
add_tool_call_at 2026-11-22T12:59:00.000Z
add_write_call_at 2026-11-22T12:58:00.000Z
expect_handed_on "an earlier checkpoint write, a tool call, then the write that was recorded"
pass "a tool call that comes after the call of write-checkpoint.sh in the transcript counts as work, whatever its timestamp"

dispatch_sandbox
write_checkpoint_of s1
add_line_to_transcript '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{}}]}}'
expect_asked_again "a tool call with no timestamp"
pass "a tool call that carries no timestamp counts as work"

dispatch_sandbox
write_checkpoint_of s1
add_line_to_transcript 'not json {'
expect_handed_on "a line that is not JSON, no tool call after the write"
dispatch_sandbox
write_checkpoint_of s1
add_tool_call_at "$AFTER_ANY_WRITE"
add_line_to_transcript 'not json {'
expect_asked_again "a line that is not JSON, a tool call after the write"
pass "a transcript line that is not JSON is skipped and the other lines still decide"

if [ "$(id -u)" -ne 0 ]; then
  new_sandbox
  make_transcript $((CRITICAL_PCT - 1))
  write_checkpoint_of s1
  chmod 000 "$TMP/transcript.jsonl"
  stop_of s1 false > /dev/null 2>&1
  chmod 644 "$TMP/transcript.jsonl"
  [ "$(state_of s1)" = "state=idle" ] || fail "a transcript that exists but cannot be opened: the checkpoint should count as worked on, got $(state_of s1)"
  pass "a transcript that exists but cannot be opened counts as work"
fi

dispatch_sandbox
record_checkpoint_written_at 2026-11-22T08:00:05-05:00
add_line_to_transcript '{"type":"assistant","timestamp":"2026-11-22T13:00:05.950Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"git add smith-checkpoint/scripts/write-checkpoint.sh"}}]}}'
add_tool_call_at 2026-11-22T13:00:05.900Z
add_write_call_at 2026-11-22T13:00:00.100Z
expect_asked_again "a command that names write-checkpoint.sh in the second of the write, after a tool call that followed the write"
dispatch_sandbox
record_checkpoint_written_at 2026-11-22T08:00:05-05:00
add_line_to_transcript '{"type":"assistant","timestamp":"2026-11-22T13:00:05.900Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"sed -i s/a/b/ src.py; git diff -- write-checkpoint.sh"}}]}}'
add_write_call_at 2026-11-22T13:00:00.100Z
expect_asked_again "a single command that works and names write-checkpoint.sh in the second of the write"
pass "a later command that only names write-checkpoint.sh does not hide a tool call that followed the write"

make_transcript_without_usage() {
  printf '%s\n' '{"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-20250514"}}' > "$TMP/transcript.jsonl"
}

for active in false true; do
  dispatch_sandbox
  write_checkpoint_of s1
  make_transcript_without_usage
  OUT=$(PATH="$TMP/bin:$PATH" stop_of s1 "$active")
  expect_allowed_with_code "stop_hook_active $active, checkpointed, context not measurable" SMITH_CTX_CONTEXT_UNMEASURED "$OUT"
  case "$(printf '%s' "$OUT" | jq -r .systemMessage)" in
    *zq_label*"/clear"*) ;;
    *) fail "stop_hook_active $active, context not measurable: the notice should name the label and /clear: $OUT" ;;
  esac
  [ "$(claude_calls)" -eq 0 ] || fail "stop_hook_active $active, context not measurable: claude should not be called"
  [ "$(state_of s1)" = "state=checkpointed" ] || fail "stop_hook_active $active, context not measurable: the session should stay checkpointed, got $(state_of s1)"
done
pass "a checkpoint whose context level cannot be measured is not handed on, and the stop says so"

echo "PASS: enforce-clear-state"
