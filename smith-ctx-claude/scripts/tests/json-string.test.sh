#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/json-string.sh"
fail() { echo "FAIL: $1"; exit 1; }

matches_node() {
  shell=$(json_string "$2")
  expected=$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$2")
  [ "$shell" = "$expected" ] || fail "$1: shell gives $shell, JSON.stringify gives $expected"
}

matches_node "plain text" 'git commit -m message'
matches_node "double quotes" 'gh pr comment 1 --body "lgtm"'
matches_node "backslashes" 'back\slash \\ two'
matches_node "tab" "$(printf 'a\tb')"
matches_node "carriage return" "$(printf 'a\rb')"
matches_node "inner newlines" "$(printf 'line1\nline2\n\nline4')"
matches_node "trailing newline" "$(printf 'cat <<EOF\nbody\nEOF\nX')"
matches_node "empty string" ''
matches_node "shell syntax" '$(pwd) `x` ${y} it'"'"'s'
matches_node "control characters" "$(printf 'a\001b\002c\033d\fe\bf\037g')"
matches_node "delete character" "$(printf 'a\177b')"
matches_node "non-ASCII text" '日本語 café'

matches_node "trailing newline" 'tail
'
matches_node "only newlines" '

'
matches_node "percent signs" '100% done %s %d'

echo "PASS: json-string"
