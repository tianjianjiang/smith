#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/lib/move-aside.mjs"
TMPD="$(mktemp -d)" || { echo "FAIL: setup: mktemp"; exit 2; }
[ -f "$LIB" ] || { echo "FAIL: the helper under test does not exist: $LIB"; exit 1; }

failures=0
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
move_aside() { TMPDIR="$TMPD/aside" node --input-type=module -e 'const { moveAside } = await import(process.argv[1]); console.log(moveAside(process.argv[2]) ?? "ABSENT");' "$LIB" "$1"; }

mkdir "$TMPD/aside" "$TMPD/plain"
printf 'kept\n' > "$TMPD/plain/flag"
moved=$(move_aside "$TMPD/plain/flag") || fail "a plain file: moveAside must succeed, got: $moved"
[ ! -e "$TMPD/plain/flag" ] || fail "a plain file: it must be gone from its place"
[ "$(cat "$moved" 2>/dev/null)" = kept ] || fail "a plain file: it must sit, unchanged, at the path moveAside returns, got: $moved"
case "$moved" in
  "$TMPD/aside/"*) ;;
  *) fail "a plain file: it must move into a fresh folder under the temporary folder, got: $moved" ;;
esac

mkdir -p "$TMPD/plain/tree/inner"
printf 'leaf\n' > "$TMPD/plain/tree/inner/leaf"
moved=$(move_aside "$TMPD/plain/tree") || fail "a folder: moveAside must succeed, got: $moved"
[ ! -e "$TMPD/plain/tree" ] || fail "a folder: it must be gone from its place"
[ "$(cat "$moved/inner/leaf" 2>/dev/null)" = leaf ] || fail "a folder: its content must move with it, got: $moved"

ln -s "$TMPD/plain/nowhere" "$TMPD/plain/dangling"
moved=$(move_aside "$TMPD/plain/dangling") || fail "a dangling link: moveAside must succeed, got: $moved"
[ ! -L "$TMPD/plain/dangling" ] || fail "a dangling link: it must be gone from its place"
[ "$(readlink "$moved" 2>/dev/null)" = "$TMPD/plain/nowhere" ] || fail "a dangling link: it must move as a link, its target kept, got: $moved"

mkdir "$TMPD/plain/first" "$TMPD/plain/second"
printf 'one\n' > "$TMPD/plain/first/same"
printf 'two\n' > "$TMPD/plain/second/same"
first=$(move_aside "$TMPD/plain/first/same") || fail "two files with one name: the first move must succeed, got: $first"
second=$(move_aside "$TMPD/plain/second/same") || fail "two files with one name: the second move must succeed, got: $second"
[ "$(cat "$first" 2>/dev/null)" = one ] && [ "$(cat "$second" 2>/dev/null)" = two ] || fail "two files with one name: each must keep its own content, got: $first and $second"

out=$(move_aside "$TMPD/plain/absent") || fail "an absent path: moveAside must succeed, got: $out"
[ "$out" = ABSENT ] || fail "an absent path: moveAside must return undefined, got: $out"

printf 'x\n' > "$TMPD/plain/not-a-folder"
move_aside "$TMPD/plain/not-a-folder/child" > /dev/null 2>&1 && fail "a path under a file: moveAside must throw, not report it absent"

[ "$failures" = 0 ] || exit 1
echo "move-aside: PASS"
