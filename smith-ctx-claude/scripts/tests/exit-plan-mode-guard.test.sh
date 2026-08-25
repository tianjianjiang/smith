#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../exit-plan-mode-guard.mjs"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

run() {
  printf '{"last_assistant_message":%s,"transcript_path":"%s"}' "$1" "$2" | node "$HOOK"
}
blocks() {
  out=$(run "$1" "$2" 2>&1)
  code=$?
  [ "$code" = 2 ] || fail "$3: expected block (exit 2), got exit $code"
  echo "$out" | grep -q 'Blocked: ExitPlanMode' || fail "$3: expected block message, got: $out"
}
allows() {
  out=$(run "$1" "$2") || fail "$3: hook crashed"
  [ -z "$out" ] || fail "$3: expected silent allow, got: $out"
}

LONG_TEXT="This is a substantial plain-text elaboration of the plan that exceeds the minimum character threshold for what counts as a real explanation turn."

prior_elaboration="$TMPD/prior-elaboration.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$LONG_TEXT\"}]}}" \
  > "$prior_elaboration"

no_prior_message="$TMPD/no-prior-message.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  > "$no_prior_message"

prior_was_tool_call="$TMPD/prior-was-tool-call.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"plan.md"}}]}}' \
  > "$prior_was_tool_call"

prior_too_short="$TMPD/prior-too-short.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"ok, proceeding now"}]}}' \
  > "$prior_too_short"

text_and_tool_same_message="$TMPD/text-and-tool-same-message.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$LONG_TEXT\"},{\"type\":\"tool_use\",\"name\":\"ExitPlanMode\",\"input\":{}}]}}" \
  > "$text_and_tool_same_message"

elaboration_cleared_by_new_turn="$TMPD/elaboration-cleared-by-new-turn.jsonl"
printf '%s\n' \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$LONG_TEXT\"}]}}" \
  '{"type":"user","message":{"content":"actually, change the approach"}}' \
  > "$elaboration_cleared_by_new_turn"

elaboration_survives_tool_result="$TMPD/elaboration-survives-tool-result.jsonl"
printf '%s\n' \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$LONG_TEXT\"}]}}" \
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"x","content":"loaded"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"x"}}]}}' \
  > "$elaboration_survives_tool_result"

split_across_blocks="$TMPD/split-across-blocks.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$LONG_TEXT\"},{\"type\":\"text\",\"text\":\"more.\"}]}}" \
  > "$split_across_blocks"

allows 'null' "$prior_elaboration" \
  "clean call after a genuine prior elaboration turn"
allows 'null' "$elaboration_survives_tool_result" \
  "prior elaboration survives an intervening tool_result (not a real user turn)"
allows 'null' "$split_across_blocks" \
  "prior elaboration text split across multiple text blocks"
allows '""' "$prior_elaboration" \
  "empty-string last_assistant_message treated as no same-turn text"
allows '"   "' "$prior_elaboration" \
  "whitespace-only last_assistant_message treated as no same-turn text"

blocks '"here is why I picked this plan:"' "$prior_elaboration" \
  "same-turn text before the tool call, even with valid prior elaboration"
blocks 'null' "$no_prior_message" \
  "no prior assistant message at all"
blocks 'null' "$prior_was_tool_call" \
  "prior assistant message was a tool call, not text"
blocks 'null' "$prior_too_short" \
  "prior assistant text below the minimum length"
blocks 'null' "$text_and_tool_same_message" \
  "elaboration text bundled into the same message as the ExitPlanMode call"
blocks 'null' "$elaboration_cleared_by_new_turn" \
  "elaboration cleared by a genuine new user turn since then"

allows 'null' "$TMPD/does-not-exist.jsonl" \
  "missing transcript file fails open"

out=$(printf '{"last_assistant_message":null}' | node "$HOOK") || fail "missing transcript_path: hook crashed"
[ -z "$out" ] || fail "missing transcript_path should fail open, got: $out"

out=$(printf 'not json' | node "$HOOK") || fail "malformed stdin: hook crashed"
[ -z "$out" ] || fail "malformed stdin should fail open, got: $out"

echo "PASS: exit-plan-mode-guard"
