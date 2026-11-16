#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

suite() {
  dir="$TMPD/$1"
  mkdir -p "$dir"
  cp "$HERE/run-all.sh" "$dir/run-all.sh"
  echo "$dir"
}

fake_test() {
  printf '#!/bin/sh\necho ran >> "$(dirname "$0")/%s.ran"\nexit %s\n' "$2" "$3" > "$1/$2.test.sh"
}

dir=$(suite discovered)
fake_test "$dir" alpha-new 0
fake_test "$dir" beta-new 0
printf '#!/bin/sh\necho ran >> "$(dirname "$0")/helper.ran"\n' > "$dir/helper.sh"
printf 'console.log(1)\n' > "$dir/unit.test.mjs"
out=$(sh "$dir/run-all.sh" 2>&1) || fail "a suite whose tests pass must exit zero, got: $out"
[ -f "$dir/alpha-new.ran" ] || fail "a test file not named in run-all.sh must still run"
[ -f "$dir/beta-new.ran" ] || fail "every *.test.sh in the folder must run"
[ ! -f "$dir/helper.ran" ] || fail "a file that is not *.test.sh must not run"
printf '%s\n' "$out" | grep -q 'ALL PASS' || fail "a passing suite must report ALL PASS, got: $out"

dir=$(suite failing)
fake_test "$dir" alpha-fails 1
fake_test "$dir" beta-passes 0
out=$(sh "$dir/run-all.sh" 2>&1) && fail "a suite with a failing test must exit non-zero"
[ -f "$dir/beta-passes.ran" ] || fail "a failing test must not stop the tests after it"
printf '%s\n' "$out" | grep -q 'SOME FAILED' || fail "a failing suite must report SOME FAILED, got: $out"

dir=$(suite empty)
out=$(sh "$dir/run-all.sh" 2>&1) && fail "a folder with no *.test.sh must exit non-zero, got: $out"
printf '%s\n' "$out" | grep -q 'ALL PASS' && fail "a folder with no *.test.sh must not report ALL PASS"

echo "PASS: run-all"
