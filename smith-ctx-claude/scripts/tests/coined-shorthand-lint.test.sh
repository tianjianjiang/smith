#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../coined-shorthand-lint.mjs"

fail() { echo "FAIL: $1"; exit 1; }
run() { printf '%s' "$1" | node "$HOOK"; }
advises() { run "$2" | grep -q 'coined-shorthand-lint' || fail "$1: expected advisory"; }
silent() {
  out=$(run "$2") || fail "$1: hook crashed"
  [ -z "$out" ] || fail "$1: expected silent, got: $out"
}

advises "clustered fixture labels" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/t.sh","content":"T1=a\nT2=b\nT3=c"}}'
advises "index codes in prose" \
  '{"tool_name":"Edit","tool_input":{"file_path":"/x/t.md","new_string":"See S5 and M1 for details."}}'

silent "single label below threshold" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/t.mjs","content":"const heading = \"H1\";"}}'
silent "descriptive names only" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/t.mjs","content":"const writeToTmp = 1;\nconst bashReadOfTmp = 2;"}}'
silent "lowercase identifiers are fine" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/t.mjs","content":"const v2 = 1;\nconst step3 = 2;"}}'
silent "no content" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/t.mjs"}}'
silent "non-edit tool" \
  '{"tool_name":"Read","tool_input":{"file_path":"/x"}}'
silent "json null" 'null'
silent "malformed stdin" 'not json'

echo "PASS: coined-shorthand-lint"
