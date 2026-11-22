#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
TMPD="$(mktemp -d)"
fail() { echo "FAIL: $1"; exit 1; }
. "$HERE/lib/set-aside.sh"

quiet_git() {
  git -c user.name=fake -c user.email=fake@example.invalid \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"
}

fake_test() {
  cat > "$1/$2.test.sh" <<EOF
#!/bin/sh
HERE="\$(cd "\$(dirname "\$0")" && pwd)"
$3
echo ran >> "\$RAN_DIR/$2"
exit ${4:-0}
EOF
}

repo_with_fakes() {
  repo="$TMPD/$1"
  tests="$repo/smith-ctx-claude/scripts/tests"
  scripts="$repo/smith-ctx-claude/scripts"
  mkdir -p "$tests/lib" "$scripts/lib" "$repo/smith-other"
  cp "$HERE/run.sh" "$HERE/run-affected.sh" "$HERE/select.mjs" "$HERE/list-folders.sh" \
    "$HERE/verify-self-containedness.sh" "$tests/" || fail "the fake repository must get every tooling file"
  printf '{}\n' > "$tests/hidden-reads.json"
  printf 'helper() { :; }\n' > "$tests/lib/helper.sh"
  printf 'import { x } from "./lib/alpha-lib.mjs";\nconsole.log(x);\n' \
    > "$scripts/alpha-hook.mjs"
  printf 'export const x = 1;\n' > "$scripts/lib/alpha-lib.mjs"
  printf '#!/bin/sh\n. "$(dirname "$0")/beta-lib.sh"\n' > "$scripts/beta-hook.sh"
  printf 'beta() { :; }\n' > "$scripts/beta-lib.sh"
  printf 'notes\n' > "$repo/README.md"
  printf 'skill\n' > "$repo/smith-other/SKILL.md"
  fake_test "$tests" alpha 'HOOK="$HERE/../alpha-hook.mjs"'
  fake_test "$tests" beta 'HOOK="$HERE/../beta-hook.sh"'
  fake_test "$tests" gamma ':'
  quiet_git -C "$repo" init -q
  quiet_git -C "$repo" add -A
  quiet_git -C "$repo" commit -qm base
  quiet_git -C "$repo" branch base
  RAN_DIR="$TMPD/$1.ran"
  mkdir -p "$RAN_DIR"
  export RAN_DIR
}

commit_all() {
  quiet_git -C "$repo" add -A
  quiet_git -C "$repo" commit -qm "$1"
}

affected() {
  out=$(cd "$repo" && sh "$tests/run-affected.sh" "${1:-base}" 2>&1)
  status=$?
}

ran() { [ -f "$RAN_DIR/$1" ]; }

repo_with_fakes direct
printf '#!/bin/sh\necho changed\n' > "$scripts/beta-hook.sh"
commit_all "change beta hook"
affected
[ "$status" = 0 ] || fail "a passing selection must exit zero, got: $out"
ran beta || fail "a committed change to the file a test names must run that test, got: $out"
ran alpha && fail "a change to beta's hook must not run alpha, got: $out"
ran gamma && fail "a change to beta's hook must not run gamma, got: $out"
printf '%s\n' "$out" | grep -q 'beta.test.sh' ||
  fail "the selection must name the test it chose, got: $out"
printf '%s\n' "$out" | grep -q 'beta-hook.sh' ||
  fail "the selection must say which changed file chose the test, got: $out"

repo_with_fakes transitive-import
printf 'export const x = 2;\n' > "$scripts/lib/alpha-lib.mjs"
affected
ran alpha || fail "an unstaged change to a library a hook imports must run the hook's test, got: $out"
ran beta && fail "a change to alpha's library must not run beta, got: $out"

repo_with_fakes transitive-source
printf 'beta() { echo changed; }\n' > "$scripts/beta-lib.sh"
quiet_git -C "$repo" add -A
affected
ran beta || fail "a staged change to a library a hook sources must run the hook's test, got: $out"
ran alpha && fail "a change to beta's library must not run alpha, got: $out"

repo_with_fakes changed-test
fake_test "$tests" gamma 'echo edited'
affected
ran gamma || fail "a changed test file must always run, got: $out"
ran alpha && fail "a change to gamma alone must not run alpha, got: $out"

repo_with_fakes new-test
fake_test "$tests" delta ':'
affected
ran delta || fail "an untracked new test file must run, got: $out"
ran alpha && fail "a new delta test alone must not run alpha, got: $out"

repo_with_fakes unrelated
printf 'other notes\n' > "$repo/README.md"
affected
[ "$status" = 0 ] || fail "a change no test reaches must exit zero, got: $out"
for name in alpha beta gamma; do
  ran "$name" && fail "a change no test reaches must run no test, ran $name: $out"
done
printf '%s\n' "$out" | grep -qi 'no test' ||
  fail "a change no test reaches must say that no test was run, got: $out"
printf '%s\n' "$out" | grep -q 'self-containedness check did not run' ||
  fail "a change no test reaches must say the self-containedness check did not run, got: $out"

for runner_file in run.sh run-affected.sh select.mjs hidden-reads.json lib/helper.sh; do
  name="runner-$(printf '%s' "$runner_file" | tr '/.' '--')"
  repo_with_fakes "$name"
  printf '\n' >> "$tests/$runner_file"
  affected
  for test_name in alpha beta gamma; do
    ran "$test_name" || fail "a change to tests/$runner_file must run the full suite, $test_name did not run: $out"
  done
  printf '%s\n' "$out" | grep -qi 'full suite' ||
    fail "a change to tests/$runner_file must say it runs the full suite, got: $out"
done

repo_with_fakes broken-manifest
printf '{ not json\n' > "$tests/hidden-reads.json"
commit_all "break the manifest"
quiet_git -C "$repo" branch -f base
printf 'other notes\n' > "$repo/README.md"
affected
ran alpha && ran beta && ran gamma ||
  fail "an unparseable manifest must run the full suite, got: $out"
printf '%s\n' "$out" | grep -qi 'hidden-reads.json' ||
  fail "an unparseable manifest must be named as the reason, got: $out"

repo_with_fakes wrong-shape-manifest
printf '{"smith-ctx-claude/scripts/tests/gamma.test.sh": "*/SKILL.md"}\n' > "$tests/hidden-reads.json"
commit_all "a manifest entry that is not a list"
quiet_git -C "$repo" branch -f base
printf 'other notes\n' > "$repo/README.md"
affected
ran alpha && ran beta && ran gamma ||
  fail "a manifest entry that is not a list must run the full suite, got: $out"

repo_with_fakes missing-manifest
set_aside "$tests/hidden-reads.json"
commit_all "drop the manifest"
quiet_git -C "$repo" branch -f base
printf 'other notes\n' > "$repo/README.md"
affected
ran alpha && ran beta && ran gamma ||
  fail "a missing manifest must run the full suite, got: $out"

repo_with_fakes declared-glob
printf '{"smith-ctx-claude/scripts/tests/gamma.test.sh": ["*/SKILL.md"]}\n' > "$tests/hidden-reads.json"
commit_all "declare a glob"
quiet_git -C "$repo" branch -f base
mkdir -p "$repo/smith-new"
printf 'new skill\n' > "$repo/smith-new/SKILL.md"
affected
ran gamma || fail "a new file matching a declared glob must run the test that declared it, got: $out"
ran alpha && fail "a file matching gamma's glob must not run alpha, got: $out"
printf '%s\n' "$out" | grep -q '\*/SKILL.md' ||
  fail "the selection must name the declared glob that chose the test, got: $out"

repo_with_fakes declared-by-hook
printf '{"smith-ctx-claude/scripts/alpha-hook.mjs": ["smith-ctx-claude/alpha-config.json"]}\n' \
  > "$tests/hidden-reads.json"
printf '{}\n' > "$repo/smith-ctx-claude/alpha-config.json"
commit_all "declare a hook's data file"
quiet_git -C "$repo" branch -f base
printf '{"a": 1}\n' > "$repo/smith-ctx-claude/alpha-config.json"
affected
ran alpha || fail "a data file declared by a hook must run the tests that reach the hook, got: $out"
ran beta && fail "alpha's data file must not run beta, got: $out"

repo_with_fakes stale-manifest-key
printf '{"smith-ctx-claude/scripts/gone.mjs": ["README.md"]}\n' > "$tests/hidden-reads.json"
commit_all "a manifest key for a file that does not exist"
quiet_git -C "$repo" branch -f base
printf 'other notes\n' > "$repo/smith-other/SKILL.md"
affected
ran alpha && ran beta && ran gamma ||
  fail "a manifest key naming a missing file must run the full suite, got: $out"

repo_with_fakes bad-base
affected no-such-ref
ran alpha && ran beta && ran gamma ||
  fail "a base ref that does not resolve must run the full suite, got: $out"

repo_with_fakes failing-selection
fake_test "$tests" gamma 'echo broken' 1
affected
[ "$status" != 0 ] || fail "a failing selected test must fail the selection, got: $out"
printf '%s\n' "$out" | grep -q 'FAIL.*gamma' ||
  fail "a failing selected test must be named, got: $out"

repo_with_fakes check-missing
fake_test "$tests" gamma 'f="$(git rev-parse --show-toplevel)/smith-other/SKILL.md"; grep -q skill "$f" || exit 1'
fake_test "$tests" alpha '[ -f "$HERE/../alpha-hook.mjs" ] || exit 1'
commit_all "gamma reads a file only by a computed path"
out=$(sh "$tests/verify-self-containedness.sh" 2>&1) &&
  fail "a test whose dependency is not visible must fail the completeness check, got: $out"
printf '%s\n' "$out" | grep -q 'MISSING.*gamma.test.sh' ||
  fail "the check must name the test with an undeclared dependency, got: $out"
printf '%s\n' "$out" | grep -q 'PASS.*alpha.test.sh' ||
  fail "the check must report a test whose dependencies are complete, got: $out"

repo_with_fakes check-declared
fake_test "$tests" gamma 'f="$(git rev-parse --show-toplevel)/smith-other/SKILL.md"; grep -q skill "$f" || exit 1'
printf '{"smith-ctx-claude/scripts/tests/gamma.test.sh": ["*/SKILL.md"]}\n' > "$tests/hidden-reads.json"
commit_all "declare gamma's file"
out=$(sh "$tests/verify-self-containedness.sh" 2>&1) ||
  fail "a test whose dependencies are all declared must pass the check, got: $out"
printf '%s\n' "$out" | grep -q 'PASS.*gamma.test.sh' ||
  fail "the check must report the declared test as passing, got: $out"

repo_with_fakes check-broken-in-repo
fake_test "$tests" gamma 'exit 1'
commit_all "gamma fails everywhere"
out=$(sh "$tests/verify-self-containedness.sh" 2>&1) &&
  fail "a test that fails in the repo must fail the check, got: $out"
printf '%s\n' "$out" | grep -q 'FAILS IN REPO.*gamma.test.sh' ||
  fail "a test that fails in the repo too must not be blamed on a dependency, got: $out"

reach_case() {
  repo_with_fakes "reach-$1"
  mkdir -p "$(dirname "$scripts/$4")"
  printf 'target\n' > "$scripts/$4"
  printf '%s\n' "$3" > "$scripts/$2"
  commit_all "reference by $1"
  quiet_git -C "$repo" branch -f base
  printf 'changed\n' > "$scripts/$4"
  affected
  case "$2" in
    alpha-hook.mjs) reached=alpha other=beta ;;
    *) reached=beta other=alpha ;;
  esac
  ran "$reached" || fail "a change to a file referenced by $1 must run $reached, got: $out"
  ran "$other" && fail "a change to a file referenced by $1 must not run $other, got: $out"
}

reach_case bash-source beta-hook.sh '. "$(dirname "${BASH_SOURCE[0]}")/target.sh"' target.sh
reach_case braced-variable beta-hook.sh 'DIR="$(cd "$(dirname "$0")" && pwd)"
. "${DIR}/target.sh"' target.sh
reach_case pwd-physical beta-hook.sh 'DIR="$(cd "$(dirname "$0")" && pwd -P)"
. "$DIR/target.sh"' target.sh
reach_case dirname-variable beta-hook.sh 'DIR=$(dirname "$0")
. "$DIR/target.sh"' target.sh
reach_case dynamic-import alpha-hook.mjs 'await import("./lib/target.mjs");' lib/target.mjs
reach_case bare-import alpha-hook.mjs 'import "./lib/target.mjs";' lib/target.mjs
reach_case require alpha-hook.mjs 'require("./lib/target.cjs");' lib/target.cjs
reach_case extensionless-require alpha-hook.mjs 'require("./lib/target");' lib/target.js
reach_case folder-require alpha-hook.mjs 'require("./lib/target");' lib/target/index.js
reach_case url alpha-hook.mjs 'new URL("./lib/target.json", import.meta.url);' lib/target.json
reach_case join-self-dir alpha-hook.mjs \
  'join(dirname(fileURLToPath(import.meta.url)), "lib", "target.json");' lib/target.json
reach_case resolve-self-dir-variable alpha-hook.mjs 'const here = dirname(fileURLToPath(import.meta.url));
resolve(here, "lib/target.json");' lib/target.json

reach_case quoted-anchor beta-hook.sh '. "$(dirname "$0")"/target.sh' target.sh
reach_case spliced-quotes beta-hook.sh 'DIR="$(cd "$(dirname "$0")" && pwd)"
node -e '"'"'import("'"'"'"$DIR"'"'"'/target.mjs")'"'"'' target.mjs
reach_case chained-variable beta-hook.sh 'DIR="$(cd "$(dirname "$0")" && pwd)"
SUB="$DIR/sub"
. "$SUB/target.sh"' sub/target.sh
reach_case cd-subfolder beta-hook.sh 'SUB="$(cd "$(dirname "$0")/sub" && pwd)"
. "$SUB/target.sh"' sub/target.sh
reach_case concatenated-variable beta-hook.sh 'f="$(dirname "$0")/tar"
. "${f}get.sh"' target.sh
reach_case variable-tail beta-hook.sh 'name=target
. "$(dirname "$0")/$name.sh"' target.sh
reach_case folder-glob beta-hook.sh 'for f in "$(dirname "$0")/plugins"/*.sh; do . "$f"; done' plugins/target.sh
reach_case bare-anchor beta-hook.sh 'DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR" && . ./target.sh' target.sh
reach_case nested-dirname beta-hook.sh 'sh "$(dirname "$(dirname "$0")")/outside.sh"' ../outside.sh
reach_case dirname-of-variable beta-hook.sh 'HERE="$(cd "$(dirname "$0")" && pwd)"
UP="$(dirname "$HERE")"
sh "$UP/outside.sh"' ../outside.sh
reach_case trimmed-variable beta-hook.sh 'HERE="$(cd "$(dirname "$0")" && pwd)"
sh "${HERE%/*}/outside.sh"' ../outside.sh
reach_case trimmed-zero beta-hook.sh 'sh "${0%/*}/target.sh"' target.sh
reach_case dotted-dirname-variable alpha-hook.mjs 'const here = path.dirname(url.fileURLToPath(import.meta.url));
readFileSync(path.join(here, "lib", "target.json"));' lib/target.json
reach_case url-folder alpha-hook.mjs 'readdirSync(new URL(".", import.meta.url));' target.json
reach_case url-no-prefix alpha-hook.mjs 'new URL("lib/target.json", import.meta.url);' lib/target.json
reach_case dirname-double-dash beta-hook.sh 'HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/../outside.sh"' ../outside.sh
reach_case realpath-wrapped beta-hook.sh 'HERE="$(dirname "$(realpath "$0")")"
. "$HERE/../outside.sh"' ../outside.sh
reach_case declare-flag beta-hook.sh 'declare -r HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../outside.sh"' ../outside.sh
reach_case local-flag-inline beta-hook.sh 'f() { local -r HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/../outside.sh"; }; f' ../outside.sh
reach_case template-import alpha-hook.mjs 'await import(`./lib/target.mjs`);' lib/target.mjs
reach_case template-import-variable alpha-hook.mjs 'await import(`./lib/${name}.mjs`);' lib/target.mjs
reach_case meta-resolve alpha-hook.mjs 'fileURLToPath(import.meta.resolve("./lib/target.mjs"));' lib/target.mjs
reach_case dirname-filename alpha-hook.mjs 'readFileSync(join(dirname(__filename), "lib", "target.json"));' lib/target.json
reach_case backtick-dirname beta-hook.sh 'HERE=`dirname "$0"`
. "$HERE/../outside.sh"' ../outside.sh
reach_case partial-name-variable beta-hook.sh 'name=get
. "$(dirname "$0")/tar$name.sh"' target.sh
reach_case partial-name-glob beta-hook.sh '. "$(dirname "$0")/tar"*.sh' target.sh
reach_case meta-filename alpha-hook.mjs 'const here = dirname(import.meta.filename);
await import(join(here, "..", "outside.mjs"));' ../outside.mjs
reach_case url-pathname alpha-hook.mjs 'const here = dirname(new URL(import.meta.url).pathname);
await import(join(here, "..", "outside.mjs"));' ../outside.mjs
reach_case template-self-dir alpha-hook.mjs 'readFileSync(`${import.meta.dirname}/../outside.json`);' ../outside.json
reach_case bare-self-dir-variable alpha-hook.mjs 'const here = dirname(fileURLToPath(import.meta.url));
readdirSync(here + "/..");' ../outside.json
reach_case spaced-name beta-hook.sh '. "$(dirname "$0")/my helper.sh"' "my helper.sh"
reach_case escaping-variable beta-hook.sh 'name=../outside.json
cat "$(dirname "$0")/$name"' ../outside.json
reach_case join-absolute-part alpha-hook.mjs 'readFileSync(join(import.meta.dirname, "/lib/target.json"));' lib/target.json
reach_case constructed-require alpha-hook.mjs 'require(path.join(__dirname, "lib", "util"));' lib/util.js
reach_case js-escaping-variable alpha-hook.mjs 'const name = "../outside.json";
readFileSync(join(import.meta.dirname, name));' ../outside.json
reach_case cdpath-prefix beta-hook.sh 'HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/../outside.sh"' ../outside.sh
reach_case builtin-cd beta-hook.sh 'HERE="$(builtin cd "$(dirname "$0")" && pwd)"
. "$HERE/../outside.sh"' ../outside.sh
reach_case url-percent alpha-hook.mjs 'readFileSync(new URL("./lib/data%20file.json", import.meta.url));' "lib/data file.json"
reach_case template-escape alpha-hook.mjs 'const name = "../outside";
await import(`./lib/${name}.mjs`);' ../outside.mjs
reach_case dirname-expression-variable alpha-hook.mjs 'const here = __dirname + "/..";
readFileSync(join(here, "outside.json"));' ../outside.json
reach_case parent-import alpha-hook.mjs 'import { y } from "../outside.mjs";' ../outside.mjs
reach_case multiline-resolve alpha-hook.mjs 'const C = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "outside.json",
);' ../outside.json
reach_case import-with-options alpha-hook.mjs 'await import("./lib/data.json", { with: { type: "json" } });' lib/data.json
reach_case import-meta-dirname alpha-hook.mjs 'join(import.meta.dirname, "lib", "target.json");' lib/target.json
reach_case dunder-dirname alpha-hook.mjs 'require(path.join(__dirname, "lib", "target.cjs"));' lib/target.cjs
reach_case join-variable-part alpha-hook.mjs 'const name = "target.json";
join(dirname(fileURLToPath(import.meta.url)), "lib", name);' lib/target.json
reach_case read-folder alpha-hook.mjs 'readdirSync(join(import.meta.dirname, "lib"));' lib/target.json

repo_with_fakes substitution-argument
printf '#!/bin/sh\nLIB="$(dirname "$0")/beta-lib.sh"\nout=$(printf x | sh "$LIB")\necho "$out"\n' > "$scripts/beta-hook.sh"
commit_all "beta runs its library inside a command substitution"
quiet_git -C "$repo" branch -f base
printf 'other notes\n' > "$repo/README.md"
affected
ran beta && fail "an anchor that ends a command substitution must not make the test read the whole repository, got: $out"

repo_with_fakes basename-of-zero
printf '#!/bin/sh\necho "usage: $(basename "$0")"\n' > "$scripts/beta-hook.sh"
commit_all "beta prints its own name"
quiet_git -C "$repo" branch -f base
printf 'other notes\n' > "$repo/README.md"
affected
ran beta && fail "the basename of the script must not make the test read the whole repository, got: $out"

repo_with_fakes closed-quote-then-braces
printf '#!/bin/sh\nLIB="$(dirname "$0")/beta-lib.sh"\nsh "$LIB" > /dev/null || { echo "failed"; }\n' > "$scripts/beta-hook.sh"
commit_all "beta runs its library and then opens a brace group"
quiet_git -C "$repo" branch -f base
printf 'other notes\n' > "$repo/README.md"
affected
[ "$status" = 0 ] || fail "the selection must succeed before its choice is judged, got: $out"
ran beta && fail "a quoted path variable followed by a space and a brace must not make the test read the whole repository, got: $out"
printf 'beta() { echo changed; }\n' > "$scripts/beta-lib.sh"
affected
[ "$status" = 0 ] || fail "the selection must succeed before its choice is judged, got: $out"
ran beta || fail "a change to the library behind a quoted path variable must still run the test, got: $out"

still_wide_case() {
  repo_with_fakes "still-wide-$1"
  printf '#!/bin/sh\nsh "$(dirname "$0")/lib/helper.sh"\n' > "$scripts/beta-hook.sh"
  printf '#!/bin/sh\nDIR="$(dirname "$0")"\nNAME=notes\n%s\n' "$2" > "$scripts/lib/helper.sh"
  commit_all "beta's helper has $1"
  quiet_git -C "$repo" branch -f base
  printf 'other notes\n' > "$repo/README.md"
  affected
  [ "$status" = 0 ] || fail "the selection must succeed before its choice is judged, got: $out"
  ran beta || fail "a helper with $1 must still make the test read the whole repository, got: $out"
}
still_wide_case a-quoted-string-joined-onto-a-path-variable 'cat "$DIR"" $NAME/x"'
still_wide_case a-literal-single-quote-after-a-path-variable 'cat "$DIR'"'"' $NAME/x"'
still_wide_case a-quote-opening-after-a-path-variable 'cat "$(echo $DIR" $NAME")"'
still_wide_case its-own-path-after-a-hash-that-starts-no-comment '[ $# -gt 0 ] || run=$0'
still_wide_case its-own-path-on-a-hash-line-of-a-multi-line-string 'title="
# $(cat "$0.title")
"'
still_wide_case its-own-path-on-a-hash-line-of-a-here-document 'cat <<EOF
# written by $0
EOF'
still_wide_case its-own-path-on-a-hash-line-of-the-second-of-two-here-documents 'cat <<A <<B
a
A
# written by $0
B'
still_wide_case its-own-path-on-a-hash-line-after-an-indented-here-document-end 'cat <<EOF
  EOF
# written by $0
EOF'
still_wide_case its-own-path-on-a-hash-line-that-continues-a-word 'payload=prefix\
#$(cat "$0.data")'
still_wide_case its-own-path-on-a-hash-line-of-a-string-after-a-quoted-double-quote 'printf x '"'"'"'"'"'
title="
# $(cat "$0.data")
"'
still_wide_case its-own-path-after-a-comment-line '# reads its own name
run=$0'
still_wide_case its-own-path-on-a-hash-line-of-an-unclosed-expansion 'payload=${option:-
#$(cat "$0.data")
}'

repo_with_fakes comment-in-sourced-library
printf '# usage: . "$(dirname "$0")/beta-lib.sh"\nbeta() { :; }\n' > "$scripts/beta-lib.sh"
commit_all "beta's library documents how to source it"
quiet_git -C "$repo" branch -f base
printf 'other notes\n' > "$repo/README.md"
affected
[ "$status" = 0 ] || fail "the selection must succeed before its choice is judged, got: $out"
ran beta && fail "a comment line in a sourced file must not make the test read the whole repository, got: $out"

repo_with_fakes comment-names-the-script
printf '#!/bin/sh\n# usage: $0 FILE\n. "$(dirname "$0")/beta-lib.sh"\n' > "$scripts/beta-hook.sh"
commit_all "beta documents its usage"
quiet_git -C "$repo" branch -f base
printf 'other notes\n' > "$repo/README.md"
affected
[ "$status" = 0 ] || fail "the selection must succeed before its choice is judged, got: $out"
ran beta && fail "a comment line that names the script must not make the test read the whole repository, got: $out"

repo_with_fakes trailing-comment-names-the-script
printf '#!/bin/sh\n. "$(dirname "$0")/beta-lib.sh"\nrun=$0 # the script itself\n' > "$scripts/beta-hook.sh"
commit_all "beta keeps its own path"
quiet_git -C "$repo" branch -f base
printf 'other notes\n' > "$repo/README.md"
affected
[ "$status" = 0 ] || fail "the selection must succeed before its choice is judged, got: $out"
ran beta || fail "the script's own path outside a comment line must still make the test read the whole repository, got: $out"

repo_with_fakes main-guard
printf 'import { pathToFileURL } from "node:url";\nif (import.meta.url === pathToFileURL(process.argv[1]).href) console.log(1);\n' > "$scripts/alpha-hook.mjs"
commit_all "alpha guards its main entry"
quiet_git -C "$repo" branch -f base
printf 'other notes\n' > "$repo/README.md"
affected
ran alpha && fail "a main-entry guard must not make the test read the whole repository, got: $out"

repo_with_fakes defaulted-path
printf '#!/bin/sh\nDIR="$(cd "$(dirname "$0")" && pwd)"\nLIB="${BETA_LIB:-${DIR}/beta-lib.sh}"\n. "$LIB"\n' > "$scripts/beta-hook.sh"
commit_all "beta sources a library path with an override"
quiet_git -C "$repo" branch -f base
printf 'beta() { echo changed; }\n' > "$scripts/beta-lib.sh"
affected
ran beta || fail "a defaulted path must still reach its default file, got: $out"
printf 'other notes\n' > "$repo/README.md"
RAN_DIR="$(mktemp -d)" || fail "mktemp -d did not create a fresh folder for the run markers"
quiet_git -C "$repo" checkout -q -- "smith-ctx-claude/scripts/beta-lib.sh"
affected
ran beta && fail "a defaulted path must not make the test read the whole repository, got: $out"

repo_with_fakes file-before-index
mkdir -p "$scripts/lib/util"
printf 'u\n' > "$scripts/lib/util.js"
printf 'export {};\n' > "$scripts/lib/util/index.mjs"
printf 'require("./lib/util");\n' > "$scripts/alpha-hook.mjs"
commit_all "alpha requires util, which exists as a file and as a folder"
quiet_git -C "$repo" branch -f base
printf 'changed\n' > "$scripts/lib/util.js"
affected
ran alpha || fail "a change to the file Node loads before a folder index must run the test, got: $out"

repo_with_fakes check-symlinked-test-alias
fake_test "$repo/smith-other" delta 'grep -q skill "$(git rev-parse --show-toplevel)/smith-other/SKILL.md" || exit 1'
ln -s ../../../smith-other/delta.test.sh "$tests/delta.test.sh"
printf '{"smith-ctx-claude/scripts/tests/delta.test.sh": ["smith-other/SKILL.md"]}\n' > "$tests/hidden-reads.json"
commit_all "a symlinked test declares its dependency under its own name"
out=$(sh "$tests/verify-self-containedness.sh" "$tests/delta.test.sh" 2>&1) ||
  fail "a declaration made under a symlinked test's name must count in the check, got: $out"

repo_with_fakes check-symlinked-test-fixture
printf 'fixture\n' > "$tests/fixture.txt"
fake_test "$repo/smith-other" delta 'grep -q fixture "$(dirname "$0")/fixture.txt" || exit 1'
ln -s ../../../smith-other/delta.test.sh "$tests/delta.test.sh"
commit_all "a symlinked test reads a fixture beside its link"
out=$(sh "$tests/verify-self-containedness.sh" "$tests/delta.test.sh" 2>&1) ||
  fail "a symlinked test must run in the tree under its own name, got: $out"

repo_with_fakes check-keeps-links
printf 'real() { :; }\n' > "$scripts/real-target.sh"
ln -s real-target.sh "$scripts/linked.sh"
printf '#!/bin/sh\n. "$(dirname "$0")/linked.sh"\n' > "$scripts/beta-hook.sh"
fake_test "$tests" beta 'HOOK="$HERE/../beta-hook.sh"; [ -L "$HERE/../linked.sh" ] || exit 1'
commit_all "beta needs its link to stay a link"
out=$(sh "$tests/verify-self-containedness.sh" "$tests/beta.test.sh" 2>&1) ||
  fail "the tree of a test must keep symbolic links as links, got: $out"

repo_with_fakes node-shebang-script
printf '#!/usr/bin/env node\nimport { x } from "./lib/alpha-lib.mjs";\n' > "$scripts/alpha-tool"
printf 'import "./alpha-tool";\n' > "$scripts/alpha-hook.mjs"
commit_all "alpha runs an extensionless node script"
quiet_git -C "$repo" branch -f base
printf 'export const x = 3;\n' > "$scripts/lib/alpha-lib.mjs"
affected
ran alpha || fail "a library an extensionless node script imports must run the test, got: $out"

repo_with_fakes unknown-script
printf 'import helper\n' > "$scripts/alpha-tool.py"
printf 'x = 1\n' > "$scripts/helper.py"
printf 'import "./alpha-tool.py";\n' > "$scripts/alpha-hook.mjs"
commit_all "alpha runs a python script"
quiet_git -C "$repo" branch -f base
printf 'x = 2\n' > "$scripts/helper.py"
affected
ran alpha || fail "a script in a language the scan does not read must make its test read the whole repository, got: $out"

repo_with_fakes renamed-dependency
quiet_git -C "$repo" mv smith-ctx-claude/scripts/beta-lib.sh smith-ctx-claude/scripts/beta-lib-moved.sh
affected
ran beta || fail "a renamed dependency must still run the test that reached its old path, got: $out"
ran alpha && fail "a renamed dependency of beta must not run alpha, got: $out"

repo_with_fakes renamed-out-of-glob
printf '{"smith-ctx-claude/scripts/tests/gamma.test.sh": ["*/SKILL.md"]}\n' > "$tests/hidden-reads.json"
mkdir -p "$repo/smith-another" && printf 'x\n' > "$repo/smith-another/SKILL.md"
commit_all "declare a glob with a second match"
quiet_git -C "$repo" branch -f base
quiet_git -C "$repo" mv smith-other/SKILL.md smith-other/NOTES.md
affected
ran gamma || fail "a file renamed out of a declared glob must run the test that declared it, got: $out"

repo_with_fakes sourced-zero
mkdir -p "$scripts/deep" "$repo/smith-ctx-claude/fx"
printf 'hi\n' > "$repo/smith-ctx-claude/fx/data.txt"
printf 'check() { cat "$(dirname "$0")/../fx/data.txt"; }\n' > "$scripts/deep/helper.sh"
printf '#!/bin/sh\n. "$(dirname "$0")/deep/helper.sh"\ncheck\n' > "$scripts/beta-hook.sh"
commit_all "beta sources a helper that uses its caller's path"
quiet_git -C "$repo" branch -f base
printf 'changed\n' > "$repo/smith-ctx-claude/fx/data.txt"
affected
ran beta || fail "\$0 in a sourced file names the caller, so a change it reaches must run the test, got: $out"

repo_with_fakes sourced-no-extension
printf '. "$(dirname "${BASH_SOURCE[0]}")/inner.sh"\n' > "$scripts/common"
printf 'inner() { :; }\n' > "$scripts/inner.sh"
printf '#!/bin/sh\n. "$(dirname "$0")/common"\n' > "$scripts/beta-hook.sh"
commit_all "beta sources a file with no extension"
quiet_git -C "$repo" branch -f base
printf 'inner() { echo changed; }\n' > "$scripts/inner.sh"
affected
ran beta || fail "a sourced file with no extension must be scanned as shell, got: $out"

repo_with_fakes sibling-folder-import
mkdir -p "$repo/smith-other/lib"
printf 'export const z = 1;\n' > "$repo/smith-other/lib/shared.mjs"
printf 'import { z } from "../../smith-other/lib/shared.mjs";\nconsole.log(z);\n' > "$scripts/alpha-hook.mjs"
commit_all "alpha imports a library from a sibling top-level folder"
quiet_git -C "$repo" branch -f base
printf 'export const z = 2;\n' > "$repo/smith-other/lib/shared.mjs"
affected
ran alpha || fail "a change to a library imported from a sibling folder must run the test, got: $out"
ran beta && fail "a change to alpha's sibling library must not run beta, got: $out"
printf '%s\n' "$out" | grep -qi 'full suite' && fail "a sibling-folder import must not fall back to the full suite, got: $out"

repo_with_fakes sourced-variable-no-extension
printf '. "$(dirname "${BASH_SOURCE[0]}")/inner.sh"\n' > "$scripts/common"
printf 'inner() { :; }\n' > "$scripts/inner.sh"
printf '#!/bin/sh\nLIB="$(dirname "$0")/common"\n. "$LIB"\n' > "$scripts/beta-hook.sh"
commit_all "beta sources an extensionless file through a variable"
quiet_git -C "$repo" branch -f base
printf 'inner() { echo changed; }\n' > "$scripts/inner.sh"
affected
ran beta || fail "a file sourced through a variable must be scanned as sourced, got: $out"

repo_with_fakes retargeted-folder-link
mkdir -p "$scripts/real-a" "$scripts/real-b"
printf 'a() { :; }\n' > "$scripts/real-a/target.sh"
printf 'a() { :; }\n' > "$scripts/real-b/target.sh"
ln -s real-a "$scripts/linked-folder"
printf '#!/bin/sh\n. "$(dirname "$0")/linked-folder/target.sh"\n' > "$scripts/beta-hook.sh"
commit_all "beta sources through a folder link"
quiet_git -C "$repo" branch -f base
set_aside "$scripts/linked-folder" && ln -s real-b "$scripts/linked-folder"
affected
ran beta || fail "retargeting a folder link on a dependency path must run the test, got: $out"

repo_with_fakes deleted-file-before-index
mkdir -p "$scripts/lib/util"
printf 'u\n' > "$scripts/lib/util.js"
printf 'module.exports = 1;\n' > "$scripts/lib/util/index.js"
printf 'require("./lib/util");\n' > "$scripts/alpha-hook.mjs"
commit_all "alpha requires util, which exists as a file and as a folder index"
quiet_git -C "$repo" branch -f base
set_aside "$scripts/lib/util.js"
quiet_git -C "$repo" add -A
affected
ran alpha || fail "deleting the file Node loads before a folder index must run the test, got: $out"

repo_with_fakes check-skip-in-both
fake_test "$tests" gamma 'echo "SKIP: always skipped"'
commit_all "gamma always skips"
out=$(sh "$tests/verify-self-containedness.sh" 2>&1) ||
  fail "a SKIP printed in both the repository and the tree must not fail the check, got: $out"
printf '%s\n' "$out" | grep -q 'SKIPPED.*gamma.test.sh' ||
  fail "a test that skips in both runs must be reported as skipped, got: $out"
printf '%s\n' "$out" | grep -q 'PASS.*gamma.test.sh' &&
  fail "a test that skips in both runs was never checked, so it must not be reported as passing, got: $out"
printf '%s\n' "$out" | grep -q 'EVERY TEST PASSES' &&
  fail "the summary must not claim every test passed when one was skipped, got: $out"

repo_with_fakes deleted-extensionless
printf 'u\n' > "$scripts/lib/util.js"
printf 'require("./lib/util");\n' > "$scripts/alpha-hook.mjs"
commit_all "alpha requires util without an extension"
quiet_git -C "$repo" branch -f base
set_aside "$scripts/lib/util.js"
quiet_git -C "$repo" add -A
affected
ran alpha || fail "deleting a module required without its extension must run the test, got: $out"

repo_with_fakes deleted-glob-match
printf '{"smith-ctx-claude/scripts/tests/gamma.test.sh": ["*/SKILL.md"]}\n' > "$tests/hidden-reads.json"
mkdir -p "$repo/smith-extra" && printf 'x\n' > "$repo/smith-extra/SKILL.md"
commit_all "declare a glob with a second match"
quiet_git -C "$repo" branch -f base
set_aside "$repo/smith-extra/SKILL.md"
quiet_git -C "$repo" add -A
affected
ran gamma || fail "a deleted file matching a declared glob must run the test that declared it, got: $out"
printf '%s\n' "$out" | grep -q 'declares \*/SKILL.md, which matches smith-extra/SKILL.md' ||
  fail "the reason must name the glob, got: $out"
ran alpha && fail "a deleted file matching gamma's glob must not run alpha, got: $out"

repo_with_fakes two-selected
printf '{"smith-ctx-claude/scripts/alpha-hook.mjs": ["README.md"], "smith-ctx-claude/scripts/beta-hook.sh": ["README.md"]}\n' > "$tests/hidden-reads.json"
commit_all "two hooks share a file"
quiet_git -C "$repo" branch -f base
printf 'other notes\n' > "$repo/README.md"
affected
ran alpha && ran beta || fail "a file reached by two tests must run both, got: $out"
ran gamma && fail "a file reached by alpha and beta must not run gamma, got: $out"
printf '%s\n' "$out" | grep -qi 'full suite' && fail "two selected tests must not fall back to the full suite, got: $out"

repo_with_fakes selector-crash
printf 'other notes\n' > "$repo/README.md"
printf 'if (process.argv[1] && process.argv[1].endsWith("select.mjs")) throw new Error("injected selector crash");\n' > "$TMPD/crash.cjs"
out=$(cd "$repo" && NODE_OPTIONS="--require $TMPD/crash.cjs" sh "$tests/run-affected.sh" base 2>&1)
ran alpha && ran beta && ran gamma || fail "a selector crash must run the full suite, got: $out"
printf '%s\n' "$out" | grep -q 'selector exited with status' || fail "a selector crash must be named, got: $out"

repo_with_fakes symlinked-dependency
printf 'real() { :; }\n' > "$scripts/real-target.sh"
ln -s real-target.sh "$scripts/linked.sh"
printf '#!/bin/sh\n. "$(dirname "$0")/linked.sh"\n' > "$scripts/beta-hook.sh"
commit_all "beta sources a symlink"
quiet_git -C "$repo" branch -f base
printf 'real() { echo changed; }\n' > "$scripts/real-target.sh"
affected
ran beta || fail "a change to the target of a symlinked dependency must run the test, got: $out"

repo_with_fakes symlinked-declared-target
printf 'real() { :; }\n' > "$scripts/real-target.sh"
ln -s real-target.sh "$scripts/linked.sh"
printf '#!/bin/sh\n. "$(dirname "$0")/linked.sh"\n' > "$scripts/beta-hook.sh"
printf '{}\n' > "$repo/smith-ctx-claude/real-data.json"
printf '{"smith-ctx-claude/scripts/real-target.sh": ["smith-ctx-claude/real-data.json"]}\n' > "$tests/hidden-reads.json"
commit_all "a symlink target declares a data file"
quiet_git -C "$repo" branch -f base
printf '{"a": 1}\n' > "$repo/smith-ctx-claude/real-data.json"
affected
ran beta || fail "a data file declared for a symlink target must run the test that reaches the link, got: $out"
printf '%s\n' "$out" | grep -qi 'full suite' && fail "a declared symlink target must count as reached, got: $out"

repo_with_fakes symlinked-folder
mkdir -p "$scripts/real-folder"
printf 'real() { :; }\n' > "$scripts/real-folder/target.sh"
ln -s real-folder "$scripts/linked-folder"
printf '#!/bin/sh\n. "$(dirname "$0")/linked-folder/target.sh"\n' > "$scripts/beta-hook.sh"
commit_all "beta sources a file through a linked folder"
quiet_git -C "$repo" branch -f base
printf 'real() { echo changed; }\n' > "$scripts/real-folder/target.sh"
affected
ran beta || fail "a change to a file reached through a symlinked folder must run the test, got: $out"

repo_with_fakes symlinked-test
fake_test "$repo/smith-other" delta ':'
ln -s ../../../smith-other/delta.test.sh "$tests/delta.test.sh"
commit_all "a symlinked test"
quiet_git -C "$repo" branch -f base
fake_test "$repo/smith-other" delta 'echo edited'
affected
ran delta || fail "a change to the target of a symlinked test must run the test, got: $out"
printf '%s\n' "$out" | grep -q 'PASS: smith-ctx-claude/scripts/tests/delta.test.sh' ||
  fail "a change to the target of a symlinked test must check that test, got: $out"

repo_with_fakes deleted-dependency
set_aside "$scripts/beta-lib.sh"
quiet_git -C "$repo" add -A
affected
ran beta || fail "a deleted dependency must still run the test that reached it, got: $out"
ran alpha && fail "a deleted dependency of beta must not run alpha, got: $out"

repo_with_fakes deleted-test
set_aside "$tests/gamma.test.sh"
quiet_git -C "$repo" add -A
affected
[ "$status" = 0 ] || fail "a deleted test alone must exit zero, got: $out"
printf '%s\n' "$out" | grep -q 'gamma.test.sh was deleted' ||
  fail "a deleted test must be named as deleted, got: $out"
printf '%s\n' "$out" | grep -qi 'full suite' &&
  fail "a deleted test alone must not run the full suite, got: $out"
for name in alpha beta; do
  ran "$name" && fail "a deleted test alone must run no other test, ran $name: $out"
done

repo_with_fakes failing-full-suite-bad-base
fake_test "$tests" gamma 'echo broken' 1
commit_all "gamma fails"
affected no-such-ref
[ "$status" != 0 ] || fail "a failing test in the full suite after a bad base ref must fail, got: $out"

repo_with_fakes failing-full-suite-runner
fake_test "$tests" gamma 'echo broken' 1
commit_all "gamma fails"
quiet_git -C "$repo" branch -f base
printf '\n' >> "$tests/run.sh"
affected
[ "$status" != 0 ] || fail "a failing test in the full suite after a runner change must fail, got: $out"

repo_with_fakes check-node-stderr
printf 'require("fs").writeSync(2, "node-preload-noise\\n");\n' > "$TMPD/noise.cjs"
out=$(NODE_OPTIONS="--require $TMPD/noise.cjs" sh "$tests/verify-self-containedness.sh" 2>&1) ||
  fail "node output on stderr must not fail the completeness check, got: $out"
printf '%s\n' "$out" | grep -q 'cp:.*node-preload-noise' &&
  fail "node output on stderr must not be read as a dependency file, got: $out"

full_suite_case() {
  repo_with_fakes "$1"
  printf '%s\n' "$2" > "$tests/hidden-reads.json"
  commit_all "$1"
  quiet_git -C "$repo" branch -f base
  printf 'other notes\n' > "$repo/README.md"
  affected
  ran alpha && ran beta && ran gamma ||
    fail "$3 must run the full suite, got: $out"
  printf '%s\n' "$out" | grep -qi 'full suite' ||
    fail "$3 must say it runs the full suite, got: $out"
}

full_suite_case missing-declared-file \
  '{"smith-ctx-claude/scripts/tests/gamma.test.sh": ["smith-other/gone.md"]}' \
  "a declared dependency that is not a file"
full_suite_case empty-glob \
  '{"smith-ctx-claude/scripts/tests/gamma.test.sh": ["*/NOTHING.md"]}' \
  "a declared glob that matches no file"
full_suite_case unreached-key \
  '{"smith-other/SKILL.md": ["README.md"]}' \
  "a manifest key that no test reaches"

repo_with_fakes check-same-name
mkdir -p "$repo/other-tests"
fake_test "$repo/other-tests" alpha 'f="$(git rev-parse --show-toplevel)/smith-other/SKILL.md"; grep -q skill "$f" || exit 1'
commit_all "a second alpha test in another folder"
out=$(sh "$tests/verify-self-containedness.sh" "$tests/alpha.test.sh" "$repo/other-tests/alpha.test.sh" 2>&1) &&
  fail "a same-named test with a missing dependency must fail the check, got: $out"
printf '%s\n' "$out" | grep -q 'PASS.*smith-ctx-claude/scripts/tests/alpha.test.sh' ||
  fail "the check must report each same-named test by its own path, got: $out"
printf '%s\n' "$out" | grep -q 'MISSING.*other-tests/alpha.test.sh' ||
  fail "the check must keep the result of each same-named test apart, got: $out"

repo_with_fakes check-skip-only-in-tree
fake_test "$tests" gamma '[ -f "$(git rev-parse --show-toplevel)/smith-other/SKILL.md" ] || { echo "SKIP: no skill file"; exit 0; }'
commit_all "gamma skips without its file"
out=$(sh "$tests/verify-self-containedness.sh" 2>&1) &&
  fail "a test that skips only in the tree of its dependencies must fail the check, got: $out"
printf '%s\n' "$out" | grep -q 'MISSING.*gamma.test.sh' ||
  fail "a SKIP seen only in the tree must count as a missing dependency, got: $out"

repo_with_fakes check-tree-not-built
out=$(GIT_INDEX_FILE="$TMPD/no-such-folder/index" sh "$tests/verify-self-containedness.sh" 2>&1) &&
  fail "a tree that could not be built must fail the check, got: $out"
printf '%s\n' "$out" | grep -q 'TREE NOT BUILT.*gamma.test.sh' ||
  fail "a tree that could not be built must be reported as its own result, got: $out"

default_run() {
  out=$(cd "$repo" && sh "$tests/run.sh" 2>&1)
  status=$?
}

repo_with_fakes default-base
quiet_git -C "$repo" update-ref refs/remotes/origin/main base
printf '#!/bin/sh\necho changed\n' > "$scripts/beta-hook.sh"
default_run
[ "$status" = 0 ] || fail "run.sh with no arguments must select against origin/main and pass, got: $out"
ran beta || fail "run.sh with no arguments must run the test a change reaches, got: $out"
ran alpha && fail "run.sh with no arguments must not run a test the change does not reach, got: $out"
printf '%s\n' "$out" | grep -q 'origin/main' ||
  fail "run.sh with no arguments must name origin/main as the base, got: $out"

repo_with_fakes default-base-missing
printf '#!/bin/sh\necho changed\n' > "$scripts/beta-hook.sh"
default_run
ran alpha && ran beta && ran gamma ||
  fail "run.sh with no arguments and no origin/main must run the full suite, got: $out"
printf '%s\n' "$out" | grep -qi 'full suite' ||
  fail "run.sh with no arguments and no origin/main must say it runs the full suite, got: $out"

repo_with_fakes check-new-test-hidden-read
fake_test "$tests" delta 'f="$(git rev-parse --show-toplevel)/smith-other/SKILL.md"; grep -q skill "$f" || exit 1'
affected
[ "$status" != 0 ] || fail "a new test with a read the scan cannot see must fail the run, got: $out"
printf '%s\n' "$out" | grep -q 'MISSING DEPENDENCY.*delta.test.sh' ||
  fail "a new test with a hidden read must be named by the self-containedness check, got: $out"

repo_with_fakes check-changed-test-only
fake_test "$tests" gamma 'echo edited'
affected
[ "$status" = 0 ] || fail "a changed test whose dependencies are complete must pass, got: $out"
printf '%s\n' "$out" | grep -q 'PASS: smith-ctx-claude/scripts/tests/gamma.test.sh' ||
  fail "a changed test must go through the self-containedness check, got: $out"
printf '%s\n' "$out" | grep -q 'alpha.test.sh' &&
  fail "the self-containedness check must cover only new or changed tests, got: $out"

repo_with_fakes check-skipped-for-unchanged-tests
printf '#!/bin/sh\necho changed\n' > "$scripts/beta-hook.sh"
affected
printf '%s\n' "$out" | grep -q 'DEPENDENCIES ALONE' &&
  fail "a change that touches no test must not run the self-containedness check, got: $out"
printf '%s\n' "$out" | grep -q 'no new or changed test, so the self-containedness check did not run' ||
  fail "a change that touches no test must say the self-containedness check did not run, got: $out"

for scan_file in select.mjs hidden-reads.json; do
  repo_with_fakes "check-every-test-$scan_file"
  printf '\n' >> "$tests/run.sh"
  if [ "$scan_file" = select.mjs ]; then
    printf '\n' >> "$tests/select.mjs"
  else
    printf '{ }\n' > "$tests/hidden-reads.json"
  fi
  affected
  [ "$status" = 0 ] || fail "a change to $scan_file with complete dependencies must pass, got: $out"
  for name in alpha beta gamma; do
    printf '%s\n' "$out" | grep -q "PASS: smith-ctx-claude/scripts/tests/$name.test.sh" ||
      fail "a change to $scan_file beside a runner change must check every test, $name was not checked: $out"
  done
done

repo_with_fakes check-new-test-beside-runner-change
printf '\n' >> "$tests/run.sh"
fake_test "$tests" delta 'f="$(git rev-parse --show-toplevel)/smith-other/SKILL.md"; grep -q skill "$f" || exit 1'
affected
[ "$status" != 0 ] || fail "a new test with a hidden read beside a runner change must fail the run, got: $out"
printf '%s\n' "$out" | grep -q 'MISSING DEPENDENCY.*delta.test.sh' ||
  fail "a new test beside a runner change must still be checked, got: $out"

repo_with_fakes check-fails-after-selector-change
fake_test "$tests" gamma 'f="$(git rev-parse --show-toplevel)/smith-other/SKILL.md"; grep -q skill "$f" || exit 1'
commit_all "gamma reads a file the scan cannot see"
quiet_git -C "$repo" branch -f base
printf '\n' >> "$tests/select.mjs"
affected
[ "$status" != 0 ] || fail "a failing check after a full-suite fallback must fail the run, got: $out"
printf '%s\n' "$out" | grep -q 'MISSING DEPENDENCY.*gamma.test.sh' ||
  fail "a selector change must check every test and name the one that fails, got: $out"

repo_with_fakes check-after-selector-crash
printf 'other notes\n' > "$repo/README.md"
out=$(cd "$repo" && NODE_OPTIONS="--require $TMPD/crash.cjs" sh "$tests/run-affected.sh" base 2>&1)
status=$?
[ "$status" != 0 ] || fail "a selector crash must fail the run, because the self-containedness check could not run, got: $out"
printf '%s\n' "$out" | grep -q 'self-containedness check did not run' ||
  fail "a selector crash must say the self-containedness check did not run, got: $out"

repo_with_fakes check-every-test-after-bad-base
affected no-such-ref
[ "$status" = 0 ] || fail "a bad base with complete dependencies must pass, got: $out"
for name in alpha beta gamma; do
  printf '%s\n' "$out" | grep -q "PASS: smith-ctx-claude/scripts/tests/$name.test.sh" ||
    fail "a base that does not resolve must check every test, $name was not checked: $out"
done

real_git="$(command -v git)"
failing_diff="$(mktemp -d)"
printf '#!/bin/sh\nfor arg in "$@"; do [ "$arg" = diff ] && exit 1; done\nexec "%s" "$@"\n' "$real_git" > "$failing_diff/git"
chmod +x "$failing_diff/git"
repo_with_fakes check-every-test-when-git-cannot-list
fake_test "$tests" gamma 'f="$(git rev-parse --show-toplevel)/smith-other/SKILL.md"; grep -q skill "$f" || exit 1'
commit_all "gamma reads a file the scan cannot see"
quiet_git -C "$repo" branch -f base
out=$(cd "$repo" && PATH="$failing_diff:$PATH" sh "$tests/run-affected.sh" base 2>&1)
status=$?
printf '%s\n' "$out" | grep -q 'git could not list the changed files' ||
  fail "a failing git diff must be named as the reason for the full suite, got: $out"
[ "$status" != 0 ] || fail "when git cannot list the changes, a test with a hidden read must fail the run, got: $out"
printf '%s\n' "$out" | grep -q 'MISSING DEPENDENCY.*gamma.test.sh' ||
  fail "when git cannot list the changes, every test must be checked, got: $out"

failing_mktemp="$(mktemp -d)"
printf '#!/bin/sh\nexit 1\n' > "$failing_mktemp/mktemp"
chmod +x "$failing_mktemp/mktemp"
repo_with_fakes check-new-link-to-unchanged-target
fake_test "$repo/smith-other" delta ':'
commit_all "a test outside the tests folder"
quiet_git -C "$repo" branch -f base
ln -s ../../../smith-other/delta.test.sh "$tests/delta.test.sh"
affected
printf '%s\n' "$out" | grep -q 'PASS: smith-ctx-claude/scripts/tests/delta.test.sh' ||
  fail "a new link to an unchanged test must check that test, got: $out"

repo_with_fakes dangling-link-during-selection
ln -s ../../../smith-other/gone.test.sh "$tests/dangling.test.sh"
commit_all "a dangling test link"
quiet_git -C "$repo" branch -f base
printf '#!/bin/sh\necho changed\n' > "$scripts/beta-hook.sh"
affected
printf '%s\n' "$out" | grep -q 'selector failed' &&
  fail "a dangling test link must not make the selector fail, got: $out"
ran beta || fail "a dangling test link must not stop the selected test from running, got: $out"

repo_with_fakes check-new-test-beside-manifest-fallback
printf '{"smith-other/SKILL.md": ["README.md"]}\n' > "$tests/hidden-reads.json"
commit_all "a manifest key no test reaches"
quiet_git -C "$repo" branch -f base
fake_test "$tests" delta 'f="$(git rev-parse --show-toplevel)/smith-other/SKILL.md"; grep -q skill "$f" || exit 1'
affected
printf '%s\n' "$out" | grep -qi 'full suite' ||
  fail "a manifest key no test reaches must run the full suite, got: $out"
[ "$status" != 0 ] || fail "a new test with a hidden read beside a manifest fallback must fail the run, got: $out"
printf '%s\n' "$out" | grep -q 'MISSING DEPENDENCY.*delta.test.sh' ||
  fail "a new test beside a manifest fallback must still be checked, got: $out"

refusing_git="$(mktemp -d)"
printf '#!/bin/sh\necho "fatal: detected dubious ownership in repository" >&2\nexit 128\n' > "$refusing_git/git"
chmod +x "$refusing_git/git"
repo_with_fakes git-refuses-the-checkout
out=$(cd "$repo" && PATH="$refusing_git:$PATH" sh "$tests/run-affected.sh" base 2>&1)
printf '%s\n' "$out" | grep -q 'detected dubious ownership' ||
  fail "a git refusal must be shown as the reason, got: $out"

repo_with_fakes no-scratch-folder
out=$(cd "$repo" && PATH="$failing_mktemp:$PATH" sh "$tests/run-affected.sh" no-such-ref 2>&1)
[ "$?" = 1 ] || fail "a scratch folder that cannot be made must exit 1, got: $out"
printf '%s\n' "$out" | grep -q 'could not make a scratch folder' ||
  fail "a scratch folder that cannot be made must be named, got: $out"
ran alpha && fail "a scratch folder that cannot be made must run no test, got: $out"

repo_with_two_folders() {
  repo="$TMPD/$1"
  tooling="$repo/tools/test"
  one="$repo/smith-one/scripts/tests"
  two="$repo/smith-two/scripts/tests"
  mkdir -p "$tooling/lib" "$one" "$two"
  cp "$HERE/run.sh" "$HERE/run-affected.sh" "$HERE/select.mjs" "$HERE/list-folders.sh" \
    "$HERE/verify-self-containedness.sh" "$tooling/" || fail "the fake repository must get every tooling file"
  manifest='{}'
  [ -z "$2" ] || manifest="$2"
  printf '%s\n' "$manifest" > "$tooling/hidden-reads.json"
  printf 'helper() { :; }\n' > "$tooling/lib/helper.sh"
  printf '#!/bin/sh\necho one\n' > "$repo/smith-one/scripts/one-hook.sh"
  printf '#!/bin/sh\necho two\n' > "$repo/smith-two/scripts/two-hook.sh"
  printf 'notes\n' > "$repo/README.md"
  fake_test "$one" alpha 'HOOK="$HERE/../one-hook.sh"; echo ran >> "$RAN_DIR/alpha-one"'
  fake_test "$two" alpha 'HOOK="$HERE/../two-hook.sh"; echo ran >> "$RAN_DIR/alpha-two"'
  fake_test "$two" beta ':'
  quiet_git -C "$repo" init -q
  quiet_git -C "$repo" add -A
  quiet_git -C "$repo" commit -qm base
  quiet_git -C "$repo" branch base
  RAN_DIR="$TMPD/$1.ran"
  mkdir -p "$RAN_DIR"
  export RAN_DIR
}

affected_apart() {
  out=$(cd "$repo" && sh "$tooling/run-affected.sh" base 2>&1)
  status=$?
}

repo_with_two_folders second-folder-selected
printf '#!/bin/sh\necho changed\n' > "$repo/smith-two/scripts/two-hook.sh"
affected_apart
[ "$status" = 0 ] || fail "a change that a test in a second tests folder reaches must pass, got: $out"
ran alpha-two || fail "a change must run the test that reaches it in a second tests folder, got: $out"
ran alpha-one && fail "a change must not run the same-named test of another tests folder, got: $out"
ran beta && fail "a change must not run a test of the second folder that it does not reach, got: $out"
printf '%s\n' "$out" | grep -q 'smith-two/scripts/tests/alpha.test.sh' ||
  fail "the selection must name a test by its path from the repository root, got: $out"

repo_with_two_folders same-name-both-run
printf '#!/bin/sh\necho changed\n' > "$repo/smith-one/scripts/one-hook.sh"
printf '#!/bin/sh\necho changed\n' > "$repo/smith-two/scripts/two-hook.sh"
fake_test "$two" alpha 'HOOK="$HERE/../two-hook.sh"; echo ran >> "$RAN_DIR/alpha-two"' 1
affected_apart
[ "$status" != 0 ] || fail "a failing test in a second tests folder must fail the run, got: $out"
ran alpha-one && ran alpha-two || fail "two tests with one name in two folders must both run, got: $out"
printf '%s\n' "$out" | grep -q 'FAIL: smith-two/scripts/tests/alpha.test.sh' ||
  fail "a failing test must be named by its path from the repository root, got: $out"
printf '%s\n' "$out" | grep -q 'FAIL: smith-one/scripts/tests/alpha.test.sh' &&
  fail "the passing test of the same name must not be reported as failing, got: $out"

repo_with_two_folders key-reached-from-one-folder '{"smith-two/scripts/two-hook.sh": ["README.md"]}'
printf 'other notes\n' > "$repo/README.md"
affected_apart
[ "$status" = 0 ] || fail "a declared read reached from one tests folder must pass, got: $out"
printf '%s\n' "$out" | grep -qi 'full suite' &&
  fail "a manifest key reached from only one of several tests folders must not ask for the full suite, got: $out"
ran alpha-two || fail "a declared read must select the test that reaches its key, got: $out"
ran alpha-one && fail "a declared read must not select a test of another folder, got: $out"

repo_with_two_folders deleted-test-in-second-folder
set_aside "$two/beta.test.sh"
quiet_git -C "$repo" add -A
affected_apart
[ "$status" = 0 ] || fail "a test deleted from a second tests folder must exit zero, got: $out"
printf '%s\n' "$out" | grep -q 'smith-two/scripts/tests/beta.test.sh was deleted' ||
  fail "a test deleted from a second tests folder must be named as deleted, got: $out"

for tooling_file in run.sh run-affected.sh select.mjs list-folders.sh hidden-reads.json lib/helper.sh; do
  repo_with_two_folders "tooling-apart-$(printf '%s' "$tooling_file" | tr '/.' '--')"
  printf '\n' >> "$tooling/$tooling_file"
  affected_apart
  ran alpha-one && ran alpha-two && ran beta ||
    fail "a change to the tooling file $tooling_file must run every test of every tests folder, got: $out"
  printf '%s\n' "$out" | grep -qi 'full suite' ||
    fail "a change to the tooling file $tooling_file must say it runs the full suite, got: $out"
done

repo_with_two_folders helper-folder-inside-a-tests-folder
mkdir -p "$two/lib"
printf 'helper() { :; }\n' > "$two/lib/local-helper.sh"
affected_apart
[ "$status" = 0 ] || fail "a lib folder inside a tests folder that no test reaches must pass, got: $out"
printf '%s\n' "$out" | grep -qi 'full suite' &&
  fail "a lib folder inside a tests folder is not the tooling's shared helpers, got: $out"

repo_with_two_folders new-test-in-second-folder
fake_test "$two" gamma ':'
affected_apart
[ "$status" = 0 ] || fail "a new test in a second tests folder must pass, got: $out"
printf '%s\n' "$out" | grep -q 'PASS: smith-two/scripts/tests/gamma.test.sh' ||
  fail "a new test in a second tests folder must go through the self-containedness check, got: $out"

repo_with_two_folders check-every-folder
out=$(sh "$tooling/verify-self-containedness.sh" 2>&1) ||
  fail "the self-containedness check with no argument must pass over every tests folder, got: $out"
for checked in smith-one/scripts/tests/alpha.test.sh smith-two/scripts/tests/alpha.test.sh smith-two/scripts/tests/beta.test.sh; do
  printf '%s\n' "$out" | grep -q "PASS: $checked" ||
    fail "the self-containedness check with no argument must cover $checked, got: $out"
done

repo_with_two_folders files-command
out=$(node "$tooling/select.mjs" files "$repo" "$two/alpha.test.sh" 2>&1) ||
  fail "the files command must take a root and a test, got: $out"
printf '%s\n' "$out" | grep -qx 'smith-two/scripts/two-hook.sh' ||
  fail "the files command must list what the test reaches, got: $out"
out=$(node "$tooling/select.mjs" files "$repo" "$two" "$two/alpha.test.sh" 2>&1)
[ "$?" = 2 ] || fail "the files command must refuse a tests folder argument with status 2, got: $out"

repo_with_two_folders all-argument
out=$(cd "$repo" && sh "$tooling/run.sh" --all 2>&1) ||
  fail "--all must pass when every test of every tests folder passes, got: $out"
ran alpha-one && ran alpha-two && ran beta || fail "--all must run every test of every tests folder, got: $out"

repo_with_two_folders folder-argument
out=$(cd "$repo" && sh "$tooling/run.sh" "$one" 2>&1) ||
  fail "a tests folder given as an argument must pass when its tests pass, got: $out"
ran alpha-one || fail "a tests folder given as an argument must run its tests, got: $out"
ran alpha-two && fail "a tests folder given as an argument must not run another folder's tests, got: $out"
printf '%s\n' "$out" | grep -q 'ALL PASS' || fail "a passing tests folder must report ALL PASS, got: $out"
mkdir -p "$repo/smith-three/scripts/tests"
out=$(cd "$repo" && sh "$tooling/run.sh" "$repo/smith-three/scripts/tests" 2>&1) &&
  fail "a folder argument that holds no test must fail the run, got: $out"
printf '%s\n' "$out" | grep -q 'NO TESTS FOUND in .*smith-three/scripts/tests' ||
  fail "a folder argument that holds no test must be named, got: $out"

repo_with_two_folders tooling-outside-the-repository
mkdir -p "$TMPD/outside-tooling"
cp "$tooling/select.mjs" "$tooling/hidden-reads.json" "$TMPD/outside-tooling/" ||
  fail "the selector must be copied outside the repository"
printf 'README.md\0' > "$TMPD/outside-changed"
out=$(node "$TMPD/outside-tooling/select.mjs" tests "$repo" "$TMPD/outside-changed" \
  "$TMPD/outside-selected" "$TMPD/outside-check" "$one" "$two" 2>&1)
[ "$?" = 3 ] ||
  fail "a selector outside the repository cannot see edits to itself, so it must ask for the full suite, got: $out"

repo_with_two_folders no-tests-folder
printf 'README.md\0' > "$TMPD/no-folder-changed"
out=$(node "$tooling/select.mjs" tests "$repo" "$TMPD/no-folder-changed" \
  "$TMPD/no-folder-selected" "$TMPD/no-folder-check" 2>&1)
[ "$?" = 3 ] || fail "a selector given no tests folder must ask for the full suite, got: $out"
printf '%s\n' "$out" | grep -q 'no tests folder was given' ||
  fail "a selector given no tests folder must say so, got: $out"

repo_with_two_folders test-outside-the-repository
mkdir -p "$TMPD/outside-tests"
fake_test "$TMPD/outside-tests" stray ':' 1
out=$(cd "$repo" && sh "$tooling/run.sh" "$TMPD/outside-tests/stray.test.sh" 2>&1) &&
  fail "a failing test outside the repository must fail the run, got: $out"
printf '%s\n' "$out" | grep -q 'FAIL: /.*/outside-tests/stray.test.sh' ||
  fail "a failing test outside the repository must be named by its full path, got: $out"

repo_with_two_folders test-listed-twice
fake_test "$one" alpha '[ ! -f "$RAN_DIR/alpha-first" ] || exit 0; echo ran >> "$RAN_DIR/alpha-first"' 1
out=$(cd "$repo" && SMITH_TEST_JOBS=1 sh "$tooling/run.sh" "$one" "$one/alpha.test.sh" 2>&1) &&
  fail "a test listed twice whose first run fails must fail the run, got: $out"

repo_with_two_folders empty-argument
cp "$two/beta.test.sh" "$TMPD/beta-before"
out=$(cd "$repo" && sh "$tooling/run.sh" "$one/alpha.test.sh" "" "$two/beta.test.sh" 2>&1)
[ "$?" = 2 ] || fail "an empty argument must be refused with status 2, got: $out"
cmp -s "$two/beta.test.sh" "$TMPD/beta-before" || fail "an empty argument must leave every test file as it was"
ran alpha-one && fail "an empty argument must run no test, got: $out"

repo_with_two_folders listing-refused-by-git
mkdir -p "$TMPD/refusing-git"
printf '#!/bin/sh\necho "fatal: detected dubious ownership in repository" >&2\nexit 128\n' > "$TMPD/refusing-git/git"
chmod +x "$TMPD/refusing-git/git"
out=$(cd "$repo" && PATH="$TMPD/refusing-git:$PATH" sh "$tooling/run.sh" --all 2>&1) &&
  fail "--all must fail when git cannot name the checkout, got: $out"
printf '%s\n' "$out" | grep -q 'dubious ownership' ||
  fail "a git failure that is not a missing checkout must be shown, got: $out"
ran alpha-one && fail "no test may run when the tests folders cannot be listed, got: $out"
out=$(cd "$repo" && PATH="$TMPD/refusing-git:$PATH" sh "$tooling/run-affected.sh" base 2>&1)
[ "$?" = 1 ] || fail "a change-based run must exit 1 when git cannot name the checkout, got: $out"
printf '%s\n' "$out" | grep -q 'dubious ownership' ||
  fail "a change-based run must show why git refused the checkout, got: $out"
ran alpha-one && fail "a change-based run must run no test when git refuses the checkout, got: $out"

repo_with_two_folders line-break-in-a-folder-name
broken="$repo/smith
three/scripts/tests"
mkdir -p "$broken"
fake_test "$broken" gamma ':'
out=$(cd "$repo" && sh "$tooling/run.sh" --all 2>&1) &&
  fail "--all must fail when a tests folder cannot be listed on one line, got: $out"
printf '%s\n' "$out" | grep -q 'holds a line break' ||
  fail "a tests folder whose path holds a line break must be named, got: $out"
ran alpha-one && fail "no test may run when a tests folder cannot be listed, got: $out"

for locked_folder in smith-two/scripts/tests smith-two/scripts smith-two; do
  repo_with_two_folders "unreadable-$(printf '%s' "$locked_folder" | tr '/' '-')"
  chmod 000 "$repo/$locked_folder"
  if [ -r "$repo/$locked_folder" ]; then
    chmod 755 "$repo/$locked_folder"
    echo "SKIPPED: $locked_folder stays readable after chmod 000, so the refusal cannot be checked"
    continue
  fi
  out=$(cd "$repo" && sh "$tooling/run.sh" --all 2>&1)
  status=$?
  chmod 755 "$repo/$locked_folder"
  [ "$status" != 0 ] || fail "--all must fail when $locked_folder cannot be read, got: $out"
  printf '%s\n' "$out" | grep -q "$locked_folder cannot be read" ||
    fail "the folder $locked_folder that cannot be read must be named, got: $out"
  ran alpha-one && fail "no test may run when $locked_folder cannot be read, got: $out"
done

repo_with_two_folders relative-git-dir
fake_test "$two" beta ':' 1
out=$(cd "$repo" && GIT_DIR=.git sh "$tooling/run.sh" --all 2>&1) &&
  fail "--all must still reach every tests folder when GIT_DIR is a relative path, got: $out"
printf '%s\n' "$out" | grep -q 'FAIL: smith-two/scripts/tests/beta.test.sh' ||
  fail "a relative GIT_DIR must not hide a failing test of another tests folder, got: $out"

mkdir -p "$TMPD/plain
folder"
cp "$HERE/list-folders.sh" "$TMPD/plain
folder/"
out=$(sh "$TMPD/plain
folder/list-folders.sh" 2>&1) &&
  fail "a tooling folder outside a checkout whose path holds a line break must be refused, got: $out"
printf '%s\n' "$out" | grep -q 'holds a line break' ||
  fail "a tooling folder whose path holds a line break must be named, got: $out"

repo_with_two_folders checkout-hidden-from-git
out=$(cd "$repo" && GIT_CEILING_DIRECTORIES="$(pwd -P)" sh "$tooling/run.sh" --all 2>&1) &&
  fail "--all must fail when git cannot see the checkout that holds the tooling, got: $out"
printf '%s\n' "$out" | grep -q 'git could not name the checkout' ||
  fail "a checkout that git cannot see must be reported, got: $out"
ran alpha-one && fail "no test may run when git cannot see the checkout that holds the tooling, got: $out"

echo "PASS: run-affected"
