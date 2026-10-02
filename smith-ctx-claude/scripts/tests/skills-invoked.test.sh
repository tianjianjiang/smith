#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
MODULE="$HERE/../lib/skills-invoked.mjs"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

loaded() {
  node --input-type=module -e "
    import { skillsLoadedInSession } from \"$MODULE\";
    const names = await skillsLoadedInSession(process.argv[1]);
    console.log([...names].sort().join(','));
  " "$1"
}
assert_loaded() {
  got=$(loaded "$2") || fail "$1: scan crashed"
  [ "$got" = "$3" ] || fail "$1 (expected '$3', got '$got')"
}

skill_call() {
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"%s","name":"Skill","input":{"skill":"%s"}}]}}\n' "$1" "$2"
}
skill_result() {
  printf '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"%s","content":"Launching skill"%s}]}}\n' "$1" "$2"
}

skill_tool_call="$TMPD/skill-tool-call.jsonl"
{
  printf '%s\n' '{"type":"user","message":{"content":"go"}}'
  skill_call call-1 smith-git
  skill_result call-1 ""
} > "$skill_tool_call"
assert_loaded "Skill tool call that succeeded" "$skill_tool_call" "smith-git"

across_turns="$TMPD/across-turns.jsonl"
{
  printf '%s\n' '{"type":"user","message":{"content":"first"}}'
  skill_call call-1 smith-git
  skill_result call-1 ""
  printf '%s\n' '{"type":"user","message":{"content":"second"}}'
  skill_call call-2 Smith-Tests
  skill_result call-2 ""
} > "$across_turns"
assert_loaded "kept across turns, lower-cased" "$across_turns" "smith-git,smith-tests"

failed_call="$TMPD/failed-call.jsonl"
{
  skill_call call-1 smith-git
  skill_result call-1 ',"is_error":true'
  skill_call call-2 smith-tests
  skill_result call-2 ""
} > "$failed_call"
assert_loaded "of two calls only the one that did not fail is loaded" "$failed_call" "smith-tests"

other_namespace="$TMPD/other-namespace.jsonl"
{
  skill_call call-1 other:smith-git
  skill_result call-1 ""
} > "$other_namespace"
assert_loaded "a plugin skill of the same bare name is another skill" "$other_namespace" "other:smith-git"

unanswered_call="$TMPD/unanswered-call.jsonl"
skill_call call-1 smith-git > "$unanswered_call"
assert_loaded "a Skill call with no result yet loads nothing" "$unanswered_call" ""

slash_command="$TMPD/slash-command.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"<command-message>smith-ship</command-message>\n<command-name>/smith-ship</command-name>"}}' \
  '{"type":"user","isMeta":true,"message":{"content":[{"type":"text","text":"Base directory for this skill: /home/someone/.claude/skills/smith-ship\n\n# /smith-ship"}]}}' \
  > "$slash_command"
assert_loaded "skill body delivered by a slash command" "$slash_command" "smith-ship"

plugin_skill="$TMPD/plugin-skill.jsonl"
{
  skill_call call-1 pr-review-toolkit:review-pr
  skill_result call-1 ""
} > "$plugin_skill"
assert_loaded "plugin prefix kept" "$plugin_skill" "pr-review-toolkit:review-pr"

subagent_call="$TMPD/subagent-call.jsonl"
printf '%s\n' \
  '{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"tool_use","id":"call-1","name":"Skill","input":{"skill":"smith-git"}}]}}' \
  '{"type":"user","isSidechain":true,"message":{"content":[{"type":"tool_result","tool_use_id":"call-1","content":"ok"}]}}' \
  > "$subagent_call"
assert_loaded "a subagent's call is not the session's" "$subagent_call" ""

mentions_only="$TMPD/mentions-only.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"Base directory for this skill: /x/smith-git is what the body starts with"}}' \
  '{"type":"user","message":{"content":[{"type":"text","text":"Base directory for this skill: /x/smith-git\n\npasted by the owner"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"using @smith-git"},{"type":"tool_use","id":"read-1","name":"Read","input":{"file_path":"/x/smith-git/SKILL.md"}}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"read-1","content":"file body"}]}}' \
  'not json' \
  > "$mentions_only"
assert_loaded "typed or pasted text, a claim and a Read load nothing" "$mentions_only" ""

loaded "$TMPD/does-not-exist.jsonl" >/dev/null 2>&1 && fail "missing transcript should reject"

echo "PASS: skills-invoked"
