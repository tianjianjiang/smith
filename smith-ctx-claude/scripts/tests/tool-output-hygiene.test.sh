#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../tool-output-hygiene.mjs"

fail() { echo "FAIL: $1"; exit 1; }

run() { printf '%s' "$2" | node "$HOOK"; }
advises() {
  out=$(run "$1" "$2") || fail "$1: hook crashed"
  echo "$out" | grep -q 'tool-output-hygiene' || fail "$1: expected advisory, got: $out"
  echo "$out" | grep -q '"hookEventName":"PostToolUse"' || fail "$1: missing PostToolUse event, got: $out"
}
silent() {
  out=$(run "$1" "$2") || fail "$1: hook crashed"
  [ -z "$out" ] || fail "$1: expected silent, got: $out"
}

big_stdout=$(node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",tool_response:{stdout:"x".repeat(25000),stderr:""}}))')
advises "Bash stdout over threshold" "$big_stdout"

small_stdout='{"tool_name":"Bash","tool_response":{"stdout":"ok","stderr":""}}'
silent "Bash stdout under threshold" "$small_stdout"

big_stderr=$(node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",tool_response:{stdout:"",stderr:"e".repeat(25000)}}))')
advises "Bash stderr over threshold" "$big_stderr"

big_other=$(node -e 'process.stdout.write(JSON.stringify({tool_name:"Read",tool_response:{content:"x".repeat(25000)}}))')
advises "non-Bash tool_response over threshold" "$big_other"

small_other='{"tool_name":"Read","tool_response":{"content":"ok"}}'
silent "non-Bash tool_response under threshold" "$small_other"

silent "no tool_response key" '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}'
silent "tool_response is null" '{"tool_name":"Bash","tool_response":null}'
silent "malformed stdin is silent" 'not json'
silent "valid JSON null is silent" 'null'
silent "valid JSON non-object is silent" '5'
silent "empty stdin is silent" ''

echo "PASS: tool-output-hygiene"
