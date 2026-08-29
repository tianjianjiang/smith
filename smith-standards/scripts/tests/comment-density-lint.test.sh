#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../comment-density-lint.mjs"

fail() { echo "FAIL: $1"; exit 1; }
run() { printf '%s' "$1" | node "$HOOK"; }
fires() { run "$2" | grep -q 'comment-density-lint' || fail "$1: expected advisory"; }
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
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"const a = 1;\n// one\n// two\n// three"}}'
silent "js trailing comments are not counted (full-line only)" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"const a = 1; // set a\nconst b = 2; // set b\nconst c = 3; // set c"}}'
fires  "edit new_string comments" \
  '{"tool_name":"Edit","tool_input":{"file_path":"/x/foo.ts","new_string":"// one\n// two\n// three\nconst a = 1;"}}'
fires  "shell hash comments" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.sh","content":"#!/bin/sh\n# one\n# two\n# three\necho a"}}'
silent "python trailing comments are not counted (full-line only)" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.py","content":"x = 1  # init x\ny = 2  # init y\nz = 3  # init z"}}'
fires  "jsdoc block comment" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"/**\n * a\n * b\n */\nconst x = 1;"}}'
fires  "notebook python comments" \
  '{"tool_name":"NotebookEdit","tool_input":{"new_source":"# a\n# b\n# c\nx = 1"}}'

silent "js self-documenting" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"const total = a + b;\nreturn total;\nfunction add(x, y) { return x + y; }"}}'
silent "below line threshold" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"const a = 1;\nconst b = 2;\nconst c = 3;\nconst d = 4;\n// one\n// two"}}'
silent "ratio exactly at 25 percent" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"// a\n// b\n// c\nconst a=1;\nconst b=2;\nconst c=3;\nconst d=4;\nconst e=5;\nconst f=6;\nconst g=7;\nconst h=8;\nconst i=9;"}}'
silent "machine directives not counted (eslint)" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"// eslint-disable-next-line\n// @ts-ignore\n// prettier-ignore\nconst a = 1;"}}'
silent "machine directives SPDX pragma" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"// SPDX-License-Identifier: MIT\n// pragma once\nconst a = 1;"}}'
silent "machine directives istanbul c8" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"// istanbul ignore next\n// c8 ignore next\nconst a = 1;"}}'
silent "machine directive type:ignore" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.ts","content":"// type: ignore\nconst a = 1;"}}'
silent "machine directive noqa case-insensitive" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.py","content":"# noqa\n# NOQA\nx = 1"}}'
silent "python machine directives" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.py","content":"# type: ignore\n# pragma: no cover\nx = 1"}}'
fires  "TODO/FIXME are comments (no exception)" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"// TODO: x\n// FIXME: y\n// HACK: z\nconst a = 1;"}}'
fires  "prose mentioning type ignore not a directive" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.ts","content":"// check the type: ignore this\n// another comment\n// third comment\nconst a = 1;"}}'
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
silent "malformed stdin" 'not json'

exits_zero "json null fails open" 'null'
exits_zero "json number fails open" '5'
exits_zero "json array fails open" '[]'

echo "PASS: comment-density-lint"
