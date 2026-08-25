#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
MODULE="$HERE/../lib/git-command-tokenizer.mjs"

fail() { echo "FAIL: $1"; exit 1; }

assert_json() {
  got=$(node --input-type=module -e "
    import { $2 } from \"$MODULE\";
    console.log(JSON.stringify($2($3)));
  ")
  [ "$got" = "$4" ] || fail "$1 (expected $4, got $got)"
}

assert_json "single segment, no separators" commandSegments '"git status"' \
  '[["git","status"]]'
assert_json "semicolon-chained segments" commandSegments '"git status; git branch"' \
  '[["git","status"],["git","branch"]]'
assert_json "double-ampersand-chained segments" commandSegments '"git status && git branch"' \
  '[["git","status"],["git","branch"]]'
assert_json "a separator character inside quotes does not split the segment" commandSegments \
  '"git commit -m \"fix; thing\""' \
  '[["git","commit","-m","fix; thing"]]'
assert_json "quotes are stripped from a whole token" commandSegments '"git checkout -b \"feat/x\""' \
  '[["git","checkout","-b","feat/x"]]'
assert_json "whitespace inside quotes stays in one token" commandSegments \
  '"git -C \"/repo with spaces\" branch x"' \
  '[["git","-C","/repo with spaces","branch","x"]]'
assert_json "leading env assignments are stripped" commandSegments '"FOO=bar BAZ=qux git status"' \
  '[["git","status"]]'
assert_json "empty segments from repeated separators are dropped" commandSegments '"git status ;; git branch"' \
  '[["git","status"],["git","branch"]]'
assert_json "a backslash-escaped space keeps a global option's value in one token" commandSegments \
  '"git -C /repo\\ with\\ spaces branch x"' \
  '[["git","-C","/repo with spaces","branch","x"]]'
assert_json "a backslash-escaped separator does not split the segment" commandSegments \
  '"git branch feat/valid\\;kept-literal"' \
  '[["git","branch","feat/valid;kept-literal"]]'
assert_json "a backslash-escaped newline joins a continued command with no gap" commandSegments \
  '"git checkout -b \\\nfeat/x"' \
  '[["git","checkout","-b","feat/x"]]'
assert_json "a backslash-escaped quote inside a quoted token does not end it early" commandSegments \
  '`git commit -m "fix \\"quoted\\" thing"`' \
  '[["git","commit","-m","fix \"quoted\" thing"]]'

assert_json "global -C option is skipped" gitSubcommandArguments '["git","-C","/repo","branch","x"]' \
  '{"subcommand":"branch","args":["x"]}'
assert_json "global -c key=value option is skipped" gitSubcommandArguments '["git","-c","user.name=x","branch","y"]' \
  '{"subcommand":"branch","args":["y"]}'
assert_json "global --config-env option is skipped" gitSubcommandArguments \
  '["git","--config-env","core.pager=X","branch","y"]' \
  '{"subcommand":"branch","args":["y"]}'
assert_json "non-git first token returns null" gitSubcommandArguments '["echo","git","branch"]' \
  'null'
assert_json "git with no subcommand returns null" gitSubcommandArguments '["git"]' \
  'null'

echo "PASS: git-command-tokenizer"
