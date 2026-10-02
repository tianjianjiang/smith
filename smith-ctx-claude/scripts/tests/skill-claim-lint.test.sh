#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../skill-claim-lint.mjs"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

run() {
  printf '{"last_assistant_message":%s,"transcript_path":"%s"%s}' "$2" "$3" "$4" | node "$HOOK"
}
refuses() {
  out=$(run "$1" "$2" "$3" "") || fail "$1: hook crashed"
  echo "$out" | grep -q '"decision":"block"' || fail "$1: expected a refusal, got: $out"
  echo "$out" | grep -q "@$4" || fail "$1: refusal should name @$4, got: $out"
}
silent() {
  out=$(run "$1" "$2" "$3" "$4") || fail "$1: hook crashed"
  [ -z "$out" ] || fail "$1: expected silent, got: $out"
}

with_skill_call="$TMPD/with-skill-call.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"call-1","name":"Skill","input":{"skill":"smith-review"}}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"call-1","content":"Launching skill"}]}}' \
  > "$with_skill_call"

without_skill_call="$TMPD/without-skill-call.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}' \
  > "$without_skill_call"

invoked_then_tool_result="$TMPD/invoked-then-tool-result.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"call-1","name":"Skill","input":{"skill":"smith-review"}}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"call-1","content":"Launching skill"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}' \
  > "$invoked_then_tool_result"

earlier_turn_invocation="$TMPD/earlier-turn-invocation.jsonl"
printf '%s\n' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"call-1","name":"Skill","input":{"skill":"smith-review"}}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"call-1","content":"Launching skill"}]}}' \
  '{"type":"user","message":{"content":"next task"}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}' \
  > "$earlier_turn_invocation"

slash_command_load="$TMPD/slash-command-load.jsonl"
printf '%s\n' \
  '{"type":"user","isMeta":true,"message":{"content":[{"type":"text","text":"Base directory for this skill: /home/someone/.claude/skills/smith-review\n\n# review"}]}}' \
  > "$slash_command_load"

plugin_skill_call="$TMPD/plugin-skill-call.jsonl"
printf '%s\n' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"call-1","name":"Skill","input":{"skill":"pr-review-toolkit:review-pr"}}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"call-1","content":"Launching skill"}]}}' \
  > "$plugin_skill_call"

silent  "claimed and loaded" \
  '"using @smith-review (marshalling reviewers)"' "$with_skill_call" ""
silent  "namespaced plugin skill claimed and loaded" \
  '"using @pr-review-toolkit:review-pr (multi-agent pass)"' "$plugin_skill_call" ""
refuses "claim followed by a colon and a space" \
  '"using @smith-validation: round 9"' "$without_skill_call" smith-validation
refuses "claimed but not loaded" \
  '"using @smith-validation (adversarial)"' "$without_skill_call" smith-validation
refuses "claimed one, loaded another" \
  '"using @smith-validation"' "$with_skill_call" smith-validation
silent  "loaded, then a tool_result user event, then claim" \
  '"using @smith-review (marshalling reviewers)"' "$invoked_then_tool_result" ""
silent  "loaded in an earlier turn of the session" \
  '"using @smith-review"' "$earlier_turn_invocation" ""
silent  "loaded by a slash command" \
  '"using @smith-review"' "$slash_command_load" ""
silent  "claim of a skill the entry file always loads" \
  '"using @smith-guidance (external write)"' "$without_skill_call" ""
silent  "turn already continuing after a refusal" \
  '"using @smith-validation"' "$without_skill_call" ',"stop_hook_active":true'
silent  "no claim in message" \
  '"just some prose with no skill mention"' "$without_skill_call" ""
silent  "missing transcript" \
  '"using @smith-review"' "$TMPD/does-not-exist.jsonl" ""
silent  "null message" \
  'null' "$without_skill_call" ""

advises() {
  out=$(run "$1" "$2" "$3" "") || fail "$1: hook crashed"
  echo "$out" | grep -q '"systemMessage"' || fail "$1: expected an advisory, got: $out"
  echo "$out" | grep -q '"decision"' && fail "$1: an advisory must not block, got: $out"
  return 0
}
advises "claim of a name that is no skill of this repository" \
  '"using @review-pr for the multi-agent pass"' "$without_skill_call"
advises "placeholder of the notification format" \
  '"emit one line: using @skill-name (reason)"' "$without_skill_call"
silent  "scoped package name is not a claim" \
  '"installed the client using @anthropic-ai/sdk and @types/node"' "$without_skill_call" ""
silent  "a word that only ends in using" \
  '"focusing @smith-validation on the diff"' "$without_skill_call" ""
silent  "claim quoted in a code span" \
  '"the format is `using @smith-validation (reason)`"' "$without_skill_call" ""
refuses "real claim after a negated one" \
  '"I am not using @smith-review here; using @smith-validation for the check"' "$without_skill_call" smith-validation
refuses "grouped claim with a reason after each name" \
  '"using @smith-review (review), @smith-validation (adversarial)"' "$with_skill_call" smith-validation
refuses "grouped claim with a reason after each name joined by and" \
  '"using @smith-review (review) and @smith-validation (adversarial)"' "$with_skill_call" smith-validation
refuses "grouped claim with full-width reasons" \
  '"using @smith-review（審查）、@smith-validation（驗證）"' "$with_skill_call" smith-validation
silent  "a name inside a reason is not a claim" \
  '"using @smith-review (as @smith-validation suggests)"' "$with_skill_call" ""
refuses "claim whose skill name alone is in a code span" \
  '"I am using `@smith-validation` here"' "$without_skill_call" smith-validation
silent  "claim inside quotation marks" \
  '"the hook looks for \"using @smith-validation\" in the last message"' "$without_skill_call" ""
refuses "one repository skill and one unknown name" \
  '"using @smith-validation, @nope-skill"' "$without_skill_call" smith-validation
echo "$out" | grep -q "@nope-skill" && fail "a refusal should name repository skills only"
refuses "last of a list joined by a comma and and" \
  '"using @smith-review, @smith-validation, and @smith-clarity"' "$with_skill_call" smith-clarity
silent  "statement that a skill is not being used" \
  '"I am not using @smith-validation here"' "$without_skill_call" ""
silent  "statement that something was done without a skill" \
  '"I did this without using @smith-validation."' "$without_skill_call" ""
silent  "claim inside single quotation marks" \
  "\"the hook looks for 'using @smith-validation' in the last message\"" "$without_skill_call" ""
silent  "claim inside curly single quotation marks" \
  '"the hook looks for ‘using @smith-validation’ here"' "$without_skill_call" ""
refuses "claim between two contractions" \
  "\"I don't think so; I'm using @smith-validation and it's fine\"" "$without_skill_call" smith-validation
refuses "claim after a contraction, before another" \
  "\"I don't know; using @smith-validation, it's fine\"" "$without_skill_call" smith-validation
refuses "claim between a contraction and a possessive" \
  "\"I don't agree, so using @smith-validation for the users' sake\"" "$without_skill_call" smith-validation
refuses "claim after an opening quotation mark that never closes" \
  "\"the 'x and using @smith-validation it's fine\"" "$without_skill_call" smith-validation
silent  "negation with an adverb before the claim" \
  '"I am not currently using @smith-validation"' "$without_skill_call" ""
refuses "claim after not only" \
  '"I am not only using @smith-validation but also tests"' "$without_skill_call" smith-validation
silent  "claim that is no longer made" \
  '"I am no longer using @smith-validation"' "$without_skill_call" ""
silent  "negation followed by two spaces" \
  '"We are not  using @smith-validation"' "$without_skill_call" ""
refuses "claim that ends the sentence" \
  '"I am using @smith-validation."' "$without_skill_call" smith-validation
refuses "claims joined by and" \
  '"using @smith-review and @smith-clarity"' "$with_skill_call" smith-clarity

both=$(run "two unloaded" '"using @smith-validation, @smith-clarity"' "$without_skill_call" "")
echo "$both" | grep -q '"decision":"block"' || fail "two claims: expected a refusal"
echo "$both" | grep -q '@smith-validation' || fail "two claims: first not named"
echo "$both" | grep -q '@smith-clarity' || fail "two claims: second skill on the same line not named"

out=$(printf 'not json' | node "$HOOK") || fail "malformed stdin: hook crashed"
[ -z "$out" ] || fail "malformed stdin should be silent"

echo "PASS: skill-claim-lint"
