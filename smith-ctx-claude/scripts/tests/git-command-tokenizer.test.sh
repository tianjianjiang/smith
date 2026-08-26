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

assert_json "unwrapped: plain command passes through" unwrappedCommandSegments '"git status"' \
  '[["git","status"]]'
assert_json "unwrapped: eval-wrapped command is unwrapped" unwrappedCommandSegments \
  '"eval \"git branch bad_name\""' \
  '[["git","branch","bad_name"]]'
assert_json "unwrapped: sh -c wrapped command is unwrapped" unwrappedCommandSegments \
  '"sh -c \"git branch bad_name\""' \
  '[["git","branch","bad_name"]]'
assert_json "unwrapped: bash -c wrapped command is unwrapped" unwrappedCommandSegments \
  '"bash -c \"git branch bad_name\""' \
  '[["git","branch","bad_name"]]'
assert_json "unwrapped: bash -e -c (option flags before -c) is still unwrapped" unwrappedCommandSegments \
  '"bash -e -c \"git branch bad_name\""' \
  '[["git","branch","bad_name"]]'
assert_json "unwrapped: bash -ec (clustered short flags ending in c) is still unwrapped" unwrappedCommandSegments \
  '"bash -ec \"git branch bad_name\""' \
  '[["git","branch","bad_name"]]'
assert_json "unwrapped: sh -xc (clustered short flags ending in c) is still unwrapped" unwrappedCommandSegments \
  '"sh -xc \"git branch bad_name\""' \
  '[["git","branch","bad_name"]]'
assert_json "unwrapped: bash -O extglob -c (value-taking shell option before -c) is still unwrapped" unwrappedCommandSegments \
  '"bash -O extglob -c \"git branch bad_name\""' \
  '[["git","branch","bad_name"]]'
assert_json "unwrapped: bash -o pipefail -c (value-taking shell option before -c) is still unwrapped" unwrappedCommandSegments \
  '"bash -o pipefail -c \"git branch bad_name\""' \
  '[["git","branch","bad_name"]]'
assert_json "unwrapped: command-prefixed invocation strips the prefix" unwrappedCommandSegments \
  '"command git branch bad_name"' \
  '[["git","branch","bad_name"]]'
assert_json "unwrapped: command -p (POSIX default-PATH flag) is also stripped" unwrappedCommandSegments \
  '"command -p git branch bad_name"' \
  '[["git","branch","bad_name"]]'
assert_json "unwrapped: absolute-path invocation is normalized to its basename" unwrappedCommandSegments \
  '"/usr/bin/git branch bad_name"' \
  '[["git","branch","bad_name"]]'
assert_json "unwrapped: nested eval inside sh -c is unwrapped recursively" unwrappedCommandSegments \
  '"sh -c \"eval \\\"git branch bad_name\\\"\""' \
  '[["git","branch","bad_name"]]'

depth_exceeded=$(node --input-type=module -e "
  import { UNWRAP_DEPTH_EXCEEDED, unwrappedCommandSegments } from \"$MODULE\";
  let cmd = 'echo done';
  for (let i = 0; i < 9; i++) cmd = 'eval ' + JSON.stringify(cmd);
  const segments = unwrappedCommandSegments(cmd);
  console.log(String(segments[UNWRAP_DEPTH_EXCEEDED] === true));
")
[ "$depth_exceeded" = "true" ] || fail "unwrapped: exceeding MAX_UNWRAP_DEPTH sets the UNWRAP_DEPTH_EXCEEDED signal (got $depth_exceeded)"

shallow_not_exceeded=$(node --input-type=module -e "
  import { UNWRAP_DEPTH_EXCEEDED, unwrappedCommandSegments } from \"$MODULE\";
  const segments = unwrappedCommandSegments('eval \"git branch bad_name\"');
  console.log(String(segments[UNWRAP_DEPTH_EXCEEDED] === undefined));
")
[ "$shallow_not_exceeded" = "true" ] || fail "unwrapped: a shallow eval does not set UNWRAP_DEPTH_EXCEEDED (got $shallow_not_exceeded)"

echo "PASS: git-command-tokenizer"
