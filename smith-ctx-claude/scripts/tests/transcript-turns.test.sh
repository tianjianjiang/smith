#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
MODULE="$HERE/../lib/transcript-turns.mjs"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

assert_json() {
  got=$(node --input-type=module -e "
    import { $2 } from \"$MODULE\";
    console.log(JSON.stringify($3));
  ")
  [ "$got" = "$4" ] || fail "$1 (expected $4, got $got)"
}

assert_json "hasBlockType: match present" hasBlockType \
  'hasBlockType([{"type":"tool_use"},{"type":"text"}], "tool_use")' 'true'
assert_json "hasBlockType: match absent" hasBlockType \
  'hasBlockType([{"type":"text"}], "tool_use")' 'false'
assert_json "hasBlockType: non-array content" hasBlockType \
  'hasBlockType("just a string", "tool_use")' 'false'

assert_json "toolUseNames: extracts names" toolUseNames \
  'toolUseNames([{"type":"tool_use","name":"Write"},{"type":"text"},{"type":"tool_use","name":"ExitPlanMode"}])' \
  '["Write","ExitPlanMode"]'
assert_json "toolUseNames: none present" toolUseNames \
  'toolUseNames([{"type":"text"}])' '[]'
assert_json "toolUseNames: non-array content" toolUseNames \
  'toolUseNames(null)' '[]'

assert_json "isGenuineNewUserTurn: real user text" isGenuineNewUserTurn \
  'isGenuineNewUserTurn({"type":"user","message":{"content":"go"}})' 'true'
assert_json "isGenuineNewUserTurn: tool_result continuation" isGenuineNewUserTurn \
  'isGenuineNewUserTurn({"type":"user","message":{"content":[{"type":"tool_result"}]}})' 'false'
assert_json "isGenuineNewUserTurn: isMeta system-reminder" isGenuineNewUserTurn \
  'isGenuineNewUserTurn({"type":"user","isMeta":true,"message":{"content":"<system-reminder>...</system-reminder>"}})' \
  'false'
assert_json "isGenuineNewUserTurn: assistant event" isGenuineNewUserTurn \
  'isGenuineNewUserTurn({"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}})' 'false'
assert_json "isGenuineNewUserTurn: null event" isGenuineNewUserTurn \
  'isGenuineNewUserTurn(null)' 'false'

fixture="$TMPD/transcript.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":"go"}}' \
  '' \
  'not json' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}' \
  > "$fixture"

got=$(node --input-type=module -e "
  import { readTranscriptEvents } from \"$MODULE\";
  const events = [];
  for await (const e of readTranscriptEvents(\"$fixture\")) events.push(e.type);
  console.log(JSON.stringify(events));
")
[ "$got" = '["user","assistant"]' ] || fail "readTranscriptEvents: expected 2 valid events skipping blank/malformed lines, got $got"

got=$(node --input-type=module -e "
  import { readTranscriptEvents } from \"$MODULE\";
  const events = [];
  for await (const e of readTranscriptEvents(\"$TMPD/does-not-exist.jsonl\")) events.push(e);
  console.log(JSON.stringify(events));
" 2>&1) && fail "readTranscriptEvents: missing file should reject, not resolve silently"

echo "PASS: transcript-turns"
