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
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.py","content":"x = 1  # init x\ny = 2  # init y\nz = 3  # init z"}}'
fires  "jsdoc block comment" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"/**\n * a\n * b\n * c\n */\nconst x = 1;"}}'
fires  "notebook python comments" \
  '{"tool_name":"NotebookEdit","tool_input":{"new_source":"# a\n# b\n# c\n# d\nx = 1"}}'

silent "js self-documenting" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"const total = a + b;\nreturn total;\nfunction add(x, y) { return x + y; }"}}'
silent "eslint-disable directive exempt" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"// eslint-disable\n// eslint-disable\n// eslint-disable\nconst a = 1;"}}'
silent "eslint-enable directive exempt" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"// eslint-enable\n// eslint-enable\n// eslint-enable\nconst a = 1;"}}'
silent "typescript directives exempt" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.ts","content":"// @ts-ignore\n// @ts-expect-error\n// @ts-nocheck\nconst a = 1;"}}'
silent "prettier directives exempt" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"// prettier-ignore\n// prettier-ignore\n// prettier-ignore\nconst a = 1;"}}'
silent "uppercase noqa exempt (case-insensitive)" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.py","content":"# NOQA: E501\n# NOQA\n# NoQa\n# noqa\nfoo = 1"}}'
silent "uppercase eslint exempt (case-insensitive)" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.py","content":"# ESLINT-DISABLE\n# Eslint-disable\n# ESLint-Disable\n# eslint-disable\nfoo = 1"}}'
silent "uppercase typescript exempt (case-insensitive)" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.ts","content":"// @TS-IGNORE\n// @Ts-Ignore\n// @TS-NOCHECK\n// @ts-ignore\nconst a = 1;"}}'
silent "SPDX directive exempt" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"// SPDX-License-Identifier: MIT\n// SPDX-FileCopyrightText: 2024\n// SPDX: tag\nconst a = 1;"}}'
silent "pragma directive exempt" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"// pragma: no-cache\n// pragma once\n// pragma mark\nconst a = 1;"}}'
silent "istanbul ignore exempt" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"// istanbul ignore next\n// istanbul ignore if\n// istanbul ignore else\nconst a = 1;"}}'
silent "c8 ignore exempt" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"// c8 ignore next\n// c8 ignore start\n// c8 ignore stop\nconst a = 1;"}}'
silent "type colon ignore exempt" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.py","content":"# type: ignore\n# type: ignore[arg-type]\n# type:  ignore\n# type:ignore\nfoo = 1"}}'
silent "directive without space after marker exempt" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.py","content":"#noqa\n#noqa\n#noqa\nfoo = 1"}}'
silent "block continuation directive exempt" \
  '{"tool_name":"Edit","tool_input":{"file_path":"/x/foo.mjs","new_string":" * eslint-disable\n * eslint-disable\n * eslint-disable\nconst a = 1;"}}'
fires  "directive name inside a longer word is not a directive" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"// pragmatic approach\n// pragmatic solution\n// pragmatic idea\n// pragmatic design\nconst a = 1;"}}'
fires  "TODO/FIXME are comments (no exception)" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.mjs","content":"// TODO: x\n// FIXME: y\n// HACK: z\n// NOTE: w\nconst a = 1;"}}'
fires  "prose mentioning type ignore not a directive" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.ts","content":"// check the type: ignore this\n// another comment\n// third comment\n// fourth comment\nconst a = 1;"}}'
fires  "mid-line directive prose not exempt (anchor test)" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.py","content":"# see https://ex.com/#noqa\n# link: example.com/#pragma\n# docs at site.com/#type:ignore\nfoo = 1"}}'
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

fires  "1 comment line triggers" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.js","content":"// a\nconst x=1;"}}'
fires  "2 comment lines trigger" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.js","content":"// a\n// b\nconst x=1;"}}'
fires  "3 comment lines trigger" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x/foo.js","content":"// a\n// b\n// c\nconst x=1;\nconst y=2;\nconst z=3;"}}'
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
