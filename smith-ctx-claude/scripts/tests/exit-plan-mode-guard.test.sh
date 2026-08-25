#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../exit-plan-mode-guard.mjs"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

run() {
  printf '{"transcript_path":"%s"}' "$1" | node "$HOOK"
}
blocks() {
  out=$(run "$1" 2>&1)
  code=$?
  [ "$code" = 2 ] || fail "$2: expected block (exit 2), got exit $code"
  echo "$out" | grep -q 'Blocked: ExitPlanMode' || fail "$2: expected block message, got: $out"
}
allows() {
  out=$(run "$1") || fail "$2: hook crashed"
  [ -z "$out" ] || fail "$2: expected silent allow, got: $out"
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

elaboration_survives_system_reminder="$TMPD/elaboration-survives-system-reminder.jsonl"
printf '%s\n' \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$LONG_TEXT\"}]}}" \
  '{"type":"user","isMeta":true,"message":{"content":"<system-reminder>...</system-reminder>"}}' \
  > "$elaboration_survives_system_reminder"

sidechain_text_does_not_count="$TMPD/sidechain-text-does-not-count.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  "{\"type\":\"assistant\",\"isSidechain\":true,\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$LONG_TEXT\"}]}}" \
  > "$sidechain_text_does_not_count"

rejected_then_recalled_with_no_new_elaboration="$TMPD/rejected-then-recalled.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$LONG_TEXT\"}]}}" \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"ExitPlanMode","input":{"plan":"v1"}}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"x","content":"rejected: use a different approach"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"plan.md"}}]}}' \
  > "$rejected_then_recalled_with_no_new_elaboration"

rejected_then_re_elaborated="$TMPD/rejected-then-re-elaborated.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$LONG_TEXT\"}]}}" \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"ExitPlanMode","input":{"plan":"v1"}}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"x","content":"rejected: use a different approach"}]}}' \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$LONG_TEXT revised.\"}]}}" \
  > "$rejected_then_re_elaborated"

current_call_flushed_with_prior_elaboration="$TMPD/current-call-flushed-with-prior-elaboration.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$LONG_TEXT\"}]}}" \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"ExitPlanMode","input":{"plan":"v1"}}]}}' \
  > "$current_call_flushed_with_prior_elaboration"

current_call_flushed_bundled_no_prior_elaboration="$TMPD/current-call-flushed-bundled-no-prior-elaboration.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$LONG_TEXT\"},{\"type\":\"tool_use\",\"name\":\"ExitPlanMode\",\"input\":{}}]}}" \
  > "$current_call_flushed_bundled_no_prior_elaboration"

current_call_flushed_bundled_after_prior_elaboration="$TMPD/current-call-flushed-bundled-after-prior-elaboration.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$LONG_TEXT\"}]}}" \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"trivial trailing remark"},{"type":"tool_use","name":"ExitPlanMode","input":{}}]}}' \
  > "$current_call_flushed_bundled_after_prior_elaboration"

current_call_flushed_substantial_bundle_after_prior_elaboration="$TMPD/current-call-flushed-substantial-bundle-after-prior-elaboration.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$LONG_TEXT\"}]}}" \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$LONG_TEXT revised again with unrelated new reasoning.\"},{\"type\":\"tool_use\",\"name\":\"ExitPlanMode\",\"input\":{}}]}}" \
  > "$current_call_flushed_substantial_bundle_after_prior_elaboration"

allows "$prior_elaboration" \
  "clean call after a genuine prior elaboration turn"
allows "$elaboration_survives_tool_result" \
  "prior elaboration survives an intervening tool_result (not a real user turn)"
allows "$split_across_blocks" \
  "prior elaboration text split across multiple text blocks"
allows "$elaboration_survives_system_reminder" \
  "prior elaboration survives an isMeta system-reminder injection"
allows "$rejected_then_re_elaborated" \
  "re-elaborated after a rejected ExitPlanMode attempt"
allows "$current_call_flushed_with_prior_elaboration" \
  "the current call's own transcript line is already flushed, after genuine prior elaboration"
allows "$current_call_flushed_bundled_after_prior_elaboration" \
  "the current call is flushed with trivial bundled text, but genuine prior elaboration already exists"

blocks "$no_prior_message" \
  "no prior assistant message at all"
blocks "$prior_was_tool_call" \
  "prior assistant message was a tool call, not text"
blocks "$prior_too_short" \
  "prior assistant text below the minimum length"
blocks "$text_and_tool_same_message" \
  "elaboration text bundled into the same message as the ExitPlanMode call"
blocks "$elaboration_cleared_by_new_turn" \
  "elaboration cleared by a genuine new user turn since then"
blocks "$sidechain_text_does_not_count" \
  "a subagent sidechain's text does not count as main-thread elaboration"
blocks "$rejected_then_recalled_with_no_new_elaboration" \
  "recalled after a rejected ExitPlanMode attempt with no fresh elaboration"
blocks "$current_call_flushed_bundled_no_prior_elaboration" \
  "the current call is flushed, bundling text with the tool call, with no genuine prior elaboration"
blocks "$current_call_flushed_substantial_bundle_after_prior_elaboration" \
  "the current call is flushed bundling SUBSTANTIAL new text, even though earlier elaboration exists"

allows "$TMPD/does-not-exist.jsonl" \
  "missing transcript file fails open"

out=$(printf '{}' | node "$HOOK") || fail "missing transcript_path: hook crashed"
[ -z "$out" ] || fail "missing transcript_path should fail open, got: $out"

out=$(printf 'not json' | node "$HOOK") || fail "malformed stdin: hook crashed"
[ -z "$out" ] || fail "malformed stdin should fail open, got: $out"

echo "PASS: exit-plan-mode-guard"
