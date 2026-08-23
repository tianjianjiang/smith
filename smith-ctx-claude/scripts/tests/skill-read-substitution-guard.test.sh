#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../skill-read-substitution-guard.mjs"

fail() { echo "FAIL: $1"; exit 1; }
run() { printf '%s' "$1" | node "$HOOK"; }
advises() { run "$2" | grep -q 'skill-read-substitution-guard' || fail "$1: expected advisory"; }
silent() {
  out=$(run "$2") || fail "$1: hook crashed"
  [ -z "$out" ] || fail "$1: expected silent, got: $out"
}

advises "reading a skills-root SKILL.md" \
  '{"tool_name":"Read","tool_input":{"file_path":"/Users/x/.claude/skills/smith-review/SKILL.md"}}'
advises "reading a .smith SKILL.md" \
  '{"tool_name":"Read","tool_input":{"file_path":"/Users/x/.smith/smith-ship/SKILL.md"}}'

silent "reading a non-skill markdown file" \
  '{"tool_name":"Read","tool_input":{"file_path":"/Users/x/project/README.md"}}'
silent "SKILL.md outside any skills root" \
  '{"tool_name":"Read","tool_input":{"file_path":"/Users/x/docs/SKILL.md"}}'
silent "editing a SKILL.md is allowed" \
  '{"tool_name":"Edit","tool_input":{"file_path":"/Users/x/.claude/skills/smith-review/SKILL.md"}}'
silent "missing file_path" \
  '{"tool_name":"Read","tool_input":{}}'
silent "json null" 'null'
silent "malformed stdin" 'not json'

echo "PASS: skill-read-substitution-guard"
