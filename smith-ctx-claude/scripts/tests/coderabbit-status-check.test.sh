#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../coderabbit-status-check.mjs"

fail() { echo "FAIL: $1"; exit 1; }

run() { printf '%s' "$2" | node "$HOOK"; }
advises() {
  out=$(run "$1" "$2") || fail "$1: hook crashed"
  echo "$out" | grep -q 'coderabbit-status-check' || fail "$1: expected advisory, got: $out"
  echo "$out" | grep -q '"hookEventName":"PostToolUse"' || fail "$1: missing PostToolUse event, got: $out"
  echo "$out" | grep -q 'status.*review_completed' || fail "$1: missing status validation guidance, got: $out"
  echo "$out" | grep -q 'reviewedFiles' || fail "$1: missing reviewedFiles guidance, got: $out"
  echo "$out" | grep -q 'rate_limit' || fail "$1: missing rate_limit warning, got: $out"
}
silent() {
  out=$(run "$1" "$2") || fail "$1: hook crashed"
  [ -z "$out" ] || fail "$1: expected silent, got: $out"
}

advises "plain coderabbit review --agent" \
  '{"tool_name":"Bash","tool_input":{"command":"coderabbit review --agent"}}'
advises "coderabbit review --agent with type flag" \
  '{"tool_name":"Bash","tool_input":{"command":"coderabbit review --agent -t committed"}}'
advises "coderabbit review with agent flag at end" \
  '{"tool_name":"Bash","tool_input":{"command":"coderabbit review -t uncommitted --agent"}}'
advises "coderabbit review --agent with base" \
  '{"tool_name":"Bash","tool_input":{"command":"coderabbit review --agent --base main"}}'
advises "cr alias with --agent" \
  '{"tool_name":"Bash","tool_input":{"command":"cr review --agent"}}'
advises "cr review --agent with dir" \
  '{"tool_name":"Bash","tool_input":{"command":"cr review --agent --dir /path/to/repo"}}'
advises "chained after cd" \
  '{"tool_name":"Bash","tool_input":{"command":"cd /repo && coderabbit review --agent"}}'
advises "env-prefixed coderabbit review --agent" \
  '{"tool_name":"Bash","tool_input":{"command":"CODERABBIT_API_KEY=xxx coderabbit review --agent"}}'
advises "chained commands with one --agent review" \
  '{"tool_name":"Bash","tool_input":{"command":"git status && coderabbit review --agent"}}'

silent "coderabbit review without --agent" \
  '{"tool_name":"Bash","tool_input":{"command":"coderabbit review"}}'
silent "cr review without --agent" \
  '{"tool_name":"Bash","tool_input":{"command":"cr review -t committed"}}'
silent "coderabbit --help" \
  '{"tool_name":"Bash","tool_input":{"command":"coderabbit --help"}}'
silent "coderabbit review --help" \
  '{"tool_name":"Bash","tool_input":{"command":"coderabbit review --help"}}'
silent "coderabbit review -h" \
  '{"tool_name":"Bash","tool_input":{"command":"coderabbit review -h"}}'
silent "coderabbit --version" \
  '{"tool_name":"Bash","tool_input":{"command":"coderabbit --version"}}'
silent "coderabbit -V" \
  '{"tool_name":"Bash","tool_input":{"command":"coderabbit -V"}}'
silent "coderabbit auth status" \
  '{"tool_name":"Bash","tool_input":{"command":"coderabbit auth status"}}'
silent "coderabbit findings" \
  '{"tool_name":"Bash","tool_input":{"command":"coderabbit findings"}}'
silent "unrelated command" \
  '{"tool_name":"Bash","tool_input":{"command":"git status"}}'
silent "echoed coderabbit is not an invocation" \
  '{"tool_name":"Bash","tool_input":{"command":"echo coderabbit review --agent"}}'
silent "non-Bash tool is silent" \
  '{"tool_name":"Read","tool_input":{"file_path":"/x"}}'
silent "malformed stdin is silent" 'not json'
silent "valid JSON null is silent" 'null'
silent "valid JSON non-object is silent" '5'
silent "missing command is silent" \
  '{"tool_name":"Bash","tool_input":{}}'

echo "PASS: coderabbit-status-check"
