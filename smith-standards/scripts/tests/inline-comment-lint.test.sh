#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../inline-comment-lint.mjs"

fail() { echo "FAIL: $1"; exit 1; }
run() { printf '%s' "$1" | node "$HOOK"; }
fires() { run "$2" | grep -q 'inline-comment-lint' || fail "$1: expected advisory"; }
silent() {
  out=$(run "$2") || fail "$1: hook crashed"
  [ -z "$out" ] || fail "$1: expected silent, got: $out"
}
exits_zero() {
  printf '%s' "$2" | node "$HOOK" >/dev/null 2>&1
  got=$?
  [ "$got" = 0 ] || fail "$1: expected exit 0, got $got"
}

fires  "js full-line comments" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"const a = 1;\n// one\n// two\n// three\n// four"}}'
silent "js trailing comments are not counted (full-line only)" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"const a = 1; // set a\nconst b = 2; // set b\nconst c = 3; // set c"}}'
fires  "edit new_string comments" \
  '{"tool_name":"Edit","tool_input":{"file_path":"/x/foo.ts","new_string":"// one\n// two\n// three\n// four\nconst a = 1;"}}'
fires  "shell hash comments" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.sh","content":"#!/bin/sh\n# one\n# two\n# three\n# four\necho a"}}'
silent "python trailing comments are not counted (full-line only)" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.py","content":"x = 1
fires  "jsdoc block comment" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"/**\n * a\n * b\n * c\n */\nconst x = 1;"}}'
fires  "notebook python comments" \
  '{"tool_name":"NotebookEdit","tool_input":{"new_source":"# a\n# b\n# c\n# d\nx = 1"}}'

silent "js self-documenting" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"const total = a + b;\nreturn total;\nfunction add(x, y) { return x + y; }"}}'
silent "url in string not a comment" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"const u = \"https://example.com/x\";\nconst v = \"a\";\nconst w = \"b\";"}}'
silent "non-code extension" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.md","content":"// one\n// two\n// three\ntext"}}'
silent "c pointer deref not comments" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/p.c","content":"*a = 1;\n*b = 2;\n*c = 3;"}}'
silent "shell dollar-hash not comments" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/n.sh","content":"n=$#\nx=${#arr}\ny=foo$#bar"}}'
silent "escaped quote inside string" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/s.mjs","content":"const a = \"x \\\" // p\";\nconst b = \"y \\\" // q\";\nconst c = \"z \\\" // r\";"}}'
silent "lone shebang not a comment" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/a.sh","content":"#!/bin/sh\necho hi"}}'

fires  "1 block (single line)" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.js","content":"// a\nconst x=1;"}}'
fires  "1 block (consecutive lines)" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.js","content":"// a\n// b\n// c\nconst x=1;"}}'
fires  "2 blocks (separated by blank)" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.js","content":"// a\n// b\n\n// c\n// d\nconst x=1;"}}'
fires  "2 blocks (separated by code)" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.js","content":"// a\n// b\nconst x=1;\n// c\n// d\nconst y=2;"}}'
silent "empty content" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.js","content":""}}'
silent "whitespace only content" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.js","content":"\n\n\n"}}'
fires  "pure comments no code" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.js","content":"// a\n// b\n// c"}}'
silent "missing file_path" \
  '{"tool_name":"Write","tool_input":{"content":"// a\n// b\n// c\ncode;"}}'
silent "missing tool_input" \
  '{"tool_name":"Write"}'
exits_zero "advisory path exits 0" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.js","content":"const a = 1;\n// one\n// two\n// three\n// four"}}'
silent "malformed stdin" 'not json'

exits_zero "json null fails open" 'null'
exits_zero "json number fails open" '5'
exits_zero "json array fails open" '[]'

echo "PASS: inline-comment-lint"
