#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../review-orchestration-guard.mjs"

fail() { echo "FAIL: $1"; exit 1; }
run() { printf '%s' "$1" | node "$HOOK"; }
advises() { run "$2" | grep -q 'review-orchestration-guard' || fail "$1: expected advisory"; }
silent() {
  out=$(run "$2") || fail "$1: hook crashed"
  [ -z "$out" ] || fail "$1: expected silent, got: $out"
}

advises "Agent spawns pr-review-toolkit code-reviewer" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"pr-review-toolkit:code-reviewer"}}'
advises "Task spawns pr-review-toolkit silent-failure-hunter" \
  '{"tool_name":"Task","tool_input":{"subagent_type":"pr-review-toolkit:silent-failure-hunter"}}'

silent "Explore agent allowed" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore"}}'
silent "general-purpose agent allowed" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose"}}'
silent "missing subagent_type" \
  '{"tool_name":"Agent","tool_input":{}}'
silent "non-spawn tool" \
  '{"tool_name":"Read","tool_input":{"file_path":"/x"}}'
silent "json null" 'null'
silent "malformed stdin" 'not json'

echo "PASS: review-orchestration-guard"
