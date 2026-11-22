#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../enforce-clear.sh"
STATE_SCRIPT="$HERE/../ctx-reset-state.sh"
source "$HERE/../lib-context.sh"

readonly CRITICAL_PCT=60
readonly SONNET_4_CONTEXT_TOKENS=200000
readonly LABEL=zq_label
readonly SUCCESSOR=abc12345

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: enforce-clear-state-dispatch - $1"; }

new_sandbox() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/plans" "$TMP/bin"
  export CLAUDE_CONFIG_DIR="$TMP"
  export _SMITH_PPID=12345
  export CLAUDE_JOB_DIR="$TMP"
  unset CTX_CONTEXT_CRITICAL_PCT CTX_AUTO_RESET_DISPATCH
  CALLS_LOG="$TMP/claude-calls.log"
  RESTORE_FLAG="$TMP/plans/.pending-memory-restore-20260101T010000-1"
  PHYSICAL_KEY=$(session_key "" "$(cd "$TMP" && pwd -P)")
}

write_fake_claude() {
  local exit_status=$1 output=$2
  cat > "$TMP/bin/claude" <<FAKE
#!/bin/bash
{ echo call; printf '%s\n' "\$@"; } >> "$CALLS_LOG"
printf '%s\n' "$output"
exit $exit_status
FAKE
  chmod +x "$TMP/bin/claude"
}

call_count() {
  [ -f "$CALLS_LOG" ] || { echo 0; return; }
  grep -c '^call$' "$CALLS_LOG"
}

call_arguments() {
  sed -n '2,$p' "$CALLS_LOG"
}

make_transcript() {
  local tokens=$((SONNET_4_CONTEXT_TOKENS * $1 / 100))
  printf '%s\n' "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"model\":\"claude-sonnet-4-20250514\",\"usage\":{\"input_tokens\":$tokens,\"output_tokens\":0}}}" > "$TMP/transcript.jsonl"
}

stop_of() {
  local session=$1 active=$2
  printf '%s' "{\"stop_hook_active\":$active,\"cwd\":\"$TMP\",\"session_id\":\"$session\",\"transcript_path\":\"$TMP/transcript.jsonl\"}" | PATH="$TMP/bin:$PATH" bash "$HOOK"
}

state_of() {
  "$STATE_SCRIPT" "$1" show
}

write_restore_flag() {
  local label=$1 key=$2
  printf 'smith-checkpoint\n2026-01-01T01:00:00+0000\n%s\n%s\n%s\n' "$(cd "$TMP" && pwd -P)" "$label" "$key" > "$RESTORE_FLAG"
}

reach_checkpointed_by_the_hook() {
  make_transcript "$CRITICAL_PCT"
  stop_of s1 false > /dev/null
  write_restore_flag "$LABEL" "$PHYSICAL_KEY"
  "$STATE_SCRIPT" s1 checkpoint-written "label=$LABEL" "flag=$RESTORE_FLAG" > /dev/null
}

message_of() {
  printf '%s' "$1" | jq -r '.systemMessage // empty' 2>/dev/null
}

for active in true false; do
  new_sandbox
  write_fake_claude 0 "backgrounded · $SUCCESSOR"
  reach_checkpointed_by_the_hook
  OUT=$(stop_of s1 "$active")
  [ "$(call_count)" -eq 1 ] || fail "stop_hook_active $active: a stop after the checkpoint should call claude once, got $(call_count): $OUT"
  args=()
  while IFS= read -r line; do args+=("$line"); done < <(call_arguments)
  [ "${args[0]}" = --bg ] && [ "${args[1]}" = --name ] || fail "stop_hook_active $active: claude should get --bg --name: ${args[*]}"
  [ "${args[2]}" = "2026-01-01T01:00 $LABEL" ] || fail "stop_hook_active $active: the name should be the checkpoint time to the minute, then the label: ${args[2]}"
  [ "${args[3]}" = -- ] || fail "stop_hook_active $active: -- should follow the name: ${args[*]}"
  [ "$(printf '%s' "$OUT" | jq -r .decision)" = block ] || fail "stop_hook_active $active: a recognized launch should block once: $OUT"
  case "$(printf '%s' "$OUT" | jq -r .reason)" in
    "[SMITH_CTX_CONTINUED] "*"$SUCCESSOR"*) ;;
    *) fail "stop_hook_active $active: the block reason should start with its code and name the successor: $OUT" ;;
  esac
  [ "$(state_of s1)" = "state=continued" ] || fail "stop_hook_active $active: the session should be continued, got $(state_of s1)"
  [ "$("$STATE_SCRIPT" s1 show-field successor)" = "$SUCCESSOR" ] || fail "stop_hook_active $active: the successor should be recorded"
  [ ! -e "$RESTORE_FLAG" ] || fail "stop_hook_active $active: the restore flag should no longer match the pending restore glob"
  [ -f "$TMP/plans/.consumed-memory-restore-20260101T010000-1" ] || fail "stop_hook_active $active: the restore flag should be renamed to its consumed name"
  OUT=$(stop_of s1 true)
  [ "$(call_count)" -eq 1 ] || fail "stop_hook_active $active: a later stop should not call claude again"
  [ "$(printf '%s' "$OUT" | jq -r 'has("decision")')" = false ] || fail "stop_hook_active $active: a later stop must not block: $OUT"
  case "$(message_of "$OUT")" in "[SMITH_CTX_ALREADY_CONTINUED] "*) ;; *) fail "stop_hook_active $active: a later stop should give the already-continued notice: $OUT" ;; esac
done
pass "a stop after the checkpoint dispatches once, blocks with the successor and consumes the restore flag"

new_sandbox
write_fake_claude 1 "error: background sessions are unavailable"
reach_checkpointed_by_the_hook
OUT=$(stop_of s1 true)
[ "$(call_count)" -eq 1 ] || fail "unrecognized launch: claude should be called once, got $(call_count)"
[ "$(printf '%s' "$OUT" | jq -r 'has("decision")')" = false ] || fail "unrecognized launch: the stop must be allowed: $OUT"
MESSAGE=$(message_of "$OUT")
case "$MESSAGE" in "[SMITH_CTX_DISPATCH_FAILED] "*) ;; *) fail "unrecognized launch: the notice should start with its code: $OUT" ;; esac
case "$MESSAGE" in *"$LABEL"*"error: background sessions are unavailable"*"/clear"*) ;; *) fail "unrecognized launch: the notice should name the label, the launch output and /clear: $OUT" ;; esac
[ "$(state_of s1)" = "state=continued" ] || fail "unrecognized launch: the session should be continued, got $(state_of s1)"
[ -f "$RESTORE_FLAG" ] || fail "unrecognized launch: the restore flag should stay for /clear"
OUT=$(stop_of s1 true)
[ "$(call_count)" -eq 1 ] || fail "unrecognized launch: a later stop should never retry"
MESSAGE=$(message_of "$OUT")
case "$MESSAGE" in "[SMITH_CTX_ALREADY_CONTINUED] "*"is not tried again"*) ;; *) fail "unrecognized launch: a later stop should say the launch is not tried again: $OUT" ;; esac
pass "an unrecognized launch is reported, keeps the restore flag and is never retried"

for active in true false; do
  new_sandbox
  write_fake_claude 0 "backgrounded · $SUCCESSOR"
  reach_checkpointed_by_the_hook
  "$STATE_SCRIPT" s1 stop high=1 active=0 dispatch=on worked=0 > /dev/null
  OUT=$(stop_of s1 "$active")
  [ "$(call_count)" -eq 0 ] || fail "launch never reported, stop_hook_active $active: claude should not be called"
  case "$(message_of "$OUT")" in "[SMITH_CTX_ALREADY_CONTINUED] "*"is not tried again"*) ;; *) fail "launch never reported, stop_hook_active $active: the stop should say the launch is not tried again: $OUT" ;; esac
  [ "$(state_of s1)" = "state=continued" ] || fail "launch never reported, stop_hook_active $active: the session should stay continued, got $(state_of s1)"
done
pass "a session recorded as continued whose launch was never reported is not launched again"

new_sandbox
write_fake_claude 0 "usage: claude [options]"
reach_checkpointed_by_the_hook
OUT=$(stop_of s1 true)
case "$(message_of "$OUT")" in "[SMITH_CTX_DISPATCH_FAILED] "*) ;; *) fail "exit 0 with an unrecognized output: the launch should be reported as failed: $OUT" ;; esac
new_sandbox
write_fake_claude 1 "backgrounded · $SUCCESSOR"
reach_checkpointed_by_the_hook
OUT=$(stop_of s1 true)
[ "$(printf '%s' "$OUT" | jq -r .decision)" = block ] || fail "exit 1 with a recognized output: the launch should block as continued: $OUT"
case "$(printf '%s' "$OUT" | jq -r .reason)" in "[SMITH_CTX_CONTINUED] "*"$SUCCESSOR"*) ;; *) fail "exit 1 with a recognized output: the block reason should name the successor: $OUT" ;; esac
pass "a launch is recognized by its output, not by its exit status"

new_sandbox
write_fake_claude 0 "backgrounded · $SUCCESSOR"
make_transcript "$CRITICAL_PCT"
stop_of s1 false > /dev/null
"$STATE_SCRIPT" s1 checkpoint-written "label=$LABEL" flag= > /dev/null
OUT=$(stop_of s1 true)
[ "$(call_count)" -eq 1 ] || fail "no restore flag: claude should be called once, got $(call_count): $OUT"
args=()
while IFS= read -r line; do args+=("$line"); done < <(call_arguments)
[ "${args[2]}" = "$LABEL" ] || fail "no restore flag: the name should be the label alone, got '${args[2]}'"
pass "without a restore flag the background session is named by the label alone"

new_sandbox
write_fake_claude 1 "error: background sessions are unavailable"
make_transcript "$CRITICAL_PCT"
stop_of s1 false > /dev/null
"$STATE_SCRIPT" s1 checkpoint-written "label=$LABEL" flag= > /dev/null
MESSAGE=$(message_of "$(stop_of s1 true)")
case "$MESSAGE" in "[SMITH_CTX_DISPATCH_FAILED] "*"$LABEL"*"restore it by its label in a new session"*) ;; *) fail "failed launch without a restore flag: the notice should say to restore by the label: $MESSAGE" ;; esac
case "$MESSAGE" in *"/clear"*) fail "failed launch without a restore flag: the notice must not say /clear restores the checkpoint: $MESSAGE" ;; esac
pass "a failed launch of a checkpoint without a restore flag says to restore it by its label"

new_sandbox
cat > "$TMP/bin/claude" <<FAKE
#!/bin/bash
echo call >> "$CALLS_LOG"
chmod 555 "$TMP/plans"
printf '%s\n' "backgrounded · $SUCCESSOR"
FAKE
chmod +x "$TMP/bin/claude"
reach_checkpointed_by_the_hook
OUT=$(stop_of s1 true 2>"$TMP/stderr")
chmod 755 "$TMP/plans"
[ "$(call_count)" -eq 1 ] || fail "state write failing after the launch: claude should be called once, got $(call_count)"
[ "$(printf '%s' "$OUT" | jq -r .decision)" = block ] || fail "state write failing after the launch: the stop should still block once: $OUT"
case "$(printf '%s' "$OUT" | jq -r .reason)" in "[SMITH_CTX_CONTINUED] "*"$SUCCESSOR"*) ;; *) fail "state write failing after the launch: the block reason should name the successor: $OUT" ;; esac
grep -qF "$RESTORE_FLAG" "$TMP/stderr" || fail "state write failing after the launch: the failed set-aside of the restore flag should be reported on stderr: $(cat "$TMP/stderr")"
pass "a recognized launch is reported with the successor even when the state cannot record it, and a failed set-aside is reported"

new_sandbox
cat > "$TMP/bin/claude" <<FAKE
#!/bin/bash
echo call >> "$CALLS_LOG"
chmod 555 "$TMP/plans"
printf '%s\n' "error: background sessions are unavailable"
FAKE
chmod +x "$TMP/bin/claude"
reach_checkpointed_by_the_hook
OUT=$(stop_of s1 true 2>"$TMP/stderr")
chmod 755 "$TMP/plans"
[ "$(call_count)" -eq 1 ] || fail "state write failing after an unrecognized launch: claude should be called once, got $(call_count)"
[ "$(printf '%s' "$OUT" | jq -r 'has("decision")')" = false ] || fail "state write failing after an unrecognized launch: the stop must be allowed: $OUT"
MESSAGE=$(message_of "$OUT")
case "$MESSAGE" in "[SMITH_CTX_DISPATCH_FAILED] "*"$LABEL"*"error: background sessions are unavailable"*) ;; *) fail "state write failing after an unrecognized launch: the failure should still be reported: $OUT" ;; esac
pass "an unrecognized launch is reported even when the state cannot record it"

make_the_restore_flag_newest() {
  touch -t 203001010000.00 "$RESTORE_FLAG"
}

add_tool_call_after_the_write() {
  printf '%s\n' '{"type":"assistant","timestamp":"2099-01-01T00:00:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{}}]}}' | cat - "$TMP/transcript.jsonl" > "$TMP/transcript.jsonl.new"
  mv "$TMP/transcript.jsonl.new" "$TMP/transcript.jsonl"
}

for active in true false; do
  new_sandbox
  write_fake_claude 0 "backgrounded · $SUCCESSOR"
  reach_checkpointed_by_the_hook
  make_the_restore_flag_newest
  add_tool_call_after_the_write
  OUT=$(stop_of s1 "$active")
  [ "$(call_count)" -eq 0 ] || fail "a tool call after the write, stop_hook_active $active: neither the state nor the older path should call claude, got $(call_count): $OUT"
  [ "$(state_of s1)" = "state=idle" ] || fail "a tool call after the write, stop_hook_active $active: the session should be idle, got $(state_of s1)"
  [ -f "$RESTORE_FLAG" ] || fail "a tool call after the write, stop_hook_active $active: the restore flag should stay for /clear"
  stop_of s1 true > /dev/null
  [ "$(call_count)" -eq 0 ] || fail "a tool call after the write, stop_hook_active $active: a later continuation stop should not let the older path dispatch the restore flag, got $(call_count)"
done
pass "a checkpoint followed by a tool call is dispatched by neither the state nor the older path, and its restore flag stays"

echo "PASS: enforce-clear-state-dispatch"
