#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../skill-claim-lint.mjs"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

run() {
  printf '{"last_assistant_message":%s,"transcript_path":"%s"}' "$2" "$3" | node "$HOOK"
}
advises() { run "$1" "$2" "$3" | grep -q 'skill-claim-lint' || fail "$1: expected advisory"; }
silent() {
  out=$(run "$1" "$2" "$3") || fail "$1: hook crashed"
  [ -z "$out" ] || fail "$1: expected silent, got: $out"
}

with_skill_call="$TMPD/with-skill-call.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"smith-review"}}]}}' \
  > "$with_skill_call"

without_skill_call="$TMPD/without-skill-call.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}' \
  > "$without_skill_call"

invoked_then_tool_result="$TMPD/invoked-then-tool-result.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"smith-review"}}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"x","content":"loaded"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}' \
  > "$invoked_then_tool_result"

prior_turn_invocation="$TMPD/prior-turn-invocation.jsonl"
printf '%s\n' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"smith-review"}}]}}' \
  '{"type":"user","message":{"content":"next task"}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}' \
  > "$prior_turn_invocation"

silent  "claimed and invoked" \
  '"using @smith-review (marshalling reviewers)"' "$with_skill_call"
advises "claimed but not invoked" \
  '"using @smith-validation (adversarial)"' "$without_skill_call"
advises "claimed one, invoked another" \
  '"using @smith-validation"' "$with_skill_call"
silent  "invoked, then a tool_result user event, then claim" \
  '"using @smith-review (marshalling reviewers)"' "$invoked_then_tool_result"
advises "prior-turn invocation cleared by a genuine user prompt" \
  '"using @smith-review"' "$prior_turn_invocation"
silent  "no claim in message" \
  '"just some prose with no skill mention"' "$without_skill_call"
silent  "missing transcript" \
  '"using @smith-review"' "$TMPD/does-not-exist.jsonl"
silent  "null message" \
  'null' "$without_skill_call"

out=$(printf 'not json' | node "$HOOK") || fail "malformed stdin: hook crashed"
[ -z "$out" ] || fail "malformed stdin should be silent"

echo "PASS: skill-claim-lint"
