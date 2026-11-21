#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
TMPD="$(mktemp -d)"
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

rendezvous_test() {
  cat > "$1/$2.test.sh" <<EOF
#!/bin/sh
here="\$(dirname "\$0")"
: > "\$here/$2.arrived"
tries=0
until [ -f "\$here/$3.arrived" ]; do
  tries=\$((tries + 1))
  [ "\$tries" -gt 300 ] && { echo "$2 never saw $3"; exit 1; }
  sleep 0.1
done
EOF
}

dir=$(suite parallel)
rendezvous_test "$dir" alpha-waits beta-waits
rendezvous_test "$dir" beta-waits alpha-waits
out=$(RUN_ALL_JOBS=2 sh "$dir/run-all.sh" 2>&1) || fail "tests must run at the same time, so two tests waiting for each other both pass, got: $out"

dir=$(suite grouped)
for name in alpha-talks beta-talks; do
  printf '#!/bin/sh\necho %s-first\nsleep 0.3\necho %s-second\n' "$name" "$name" > "$dir/$name.test.sh"
done
out=$(sh "$dir/run-all.sh" 2>&1)
printf '%s\n' "$out" | grep -A1 'alpha-talks-first' | grep -q 'alpha-talks-second' ||
  fail "a test's output must stay together, not interleave with another test's, got: $out"
first_alpha=$(printf '%s\n' "$out" | grep -n 'alpha-talks-first' | cut -d: -f1)
first_beta=$(printf '%s\n' "$out" | grep -n 'beta-talks-first' | cut -d: -f1)
[ "$first_alpha" -lt "$first_beta" ] || fail "outputs must be printed in name order, got: $out"

dir=$(suite named-failure)
printf '#!/bin/sh\necho boom\nexit 1\n' > "$dir/gamma-breaks.test.sh"
out=$(sh "$dir/run-all.sh" 2>&1) && fail "a failing test must still fail the suite when tests run at the same time"
printf '%s\n' "$out" | grep -q 'FAIL.*gamma-breaks' || fail "the report must name the failing test file, got: $out"
printf '%s\n' "$out" | grep -q 'boom' || fail "the failing test's own output must be shown, got: $out"

dir=$(suite stderr-failure)
printf '#!/bin/sh\necho oops >&2\nexit 3\n' > "$dir/delta-stderr.test.sh"
fake_test "$dir" echo-passes 0
out=$(sh "$dir/run-all.sh" 2>&1) && fail "a test exiting 3 must fail the suite"
printf '%s\n' "$out" | grep -q 'FAIL.*delta-stderr' || fail "a test exiting 3 must be named as failed, got: $out"
printf '%s\n' "$out" | grep -q 'oops' || fail "a failing test's stderr must be shown, got: $out"

dir=$(suite "folder with spaces")
fake_test "$dir" alpha-spaced 0
out=$(sh "$dir/run-all.sh" 2>&1) || fail "a folder path with spaces must still run its tests, got: $out"
[ -f "$dir/alpha-spaced.ran" ] || fail "a folder path with spaces must run every test"

deep="$(printf 'd%.0s' $(seq 1 200))/$(printf 'e%.0s' $(seq 1 100))"
dir=$(suite "$deep")
fake_test "$dir" alpha-deep 0
out=$(sh "$dir/run-all.sh" 2>&1) || fail "a test path longer than 255 bytes must still run, got: $out"
[ -f "$dir/alpha-deep.ran" ] || fail "a test path longer than 255 bytes must run its test"

dir=$(suite serial)
fake_test "$dir" alpha-serial 0
fake_test "$dir" beta-serial 0
out=$(RUN_ALL_JOBS=1 sh "$dir/run-all.sh" 2>&1) || fail "RUN_ALL_JOBS=1 must still run the suite, got: $out"
[ -f "$dir/alpha-serial.ran" ] && [ -f "$dir/beta-serial.ran" ] || fail "RUN_ALL_JOBS=1 must run every test"

dir=$(suite odd-entries)
fake_test "$dir" alpha-real 0
mkdir "$dir/beta-folder.test.sh"
ln -s "$dir/nowhere" "$dir/gamma-dangling.test.sh"
out=$(sh "$dir/run-all.sh" 2>&1) && fail "a *.test.sh that is not a runnable file must fail the suite, got: $out"
printf '%s\n' "$out" | grep -q 'FAIL.*beta-folder' || fail "a folder named *.test.sh must be named as failed, got: $out"
printf '%s\n' "$out" | grep -q 'FAIL.*gamma-dangling' || fail "a dangling *.test.sh link must be named as failed, got: $out"

dir=$(suite bad-jobs)
fake_test "$dir" alpha-jobs 0
for jobs in abc 0 -2; do
  out=$(RUN_ALL_JOBS=$jobs sh "$dir/run-all.sh" 2>&1) && fail "RUN_ALL_JOBS=$jobs must fail the suite"
  printf '%s\n' "$out" | grep -q 'RUN_ALL_JOBS must be a positive whole number' ||
    fail "RUN_ALL_JOBS=$jobs must be reported as the cause, got: $out"
done
[ ! -f "$dir/alpha-jobs.ran" ] || fail "an invalid RUN_ALL_JOBS must run no test"

dir=$(suite explicit-list)
fake_test "$dir" alpha-listed 0
fake_test "$dir" beta-unlisted 0
fake_test "$dir" gamma-listed 0
out=$(sh "$dir/run-all.sh" "$dir/gamma-listed.test.sh" "$dir/alpha-listed.test.sh" 2>&1) ||
  fail "an explicit list of passing tests must exit zero, got: $out"
[ -f "$dir/alpha-listed.ran" ] && [ -f "$dir/gamma-listed.ran" ] || fail "every listed test must run"
[ ! -f "$dir/beta-unlisted.ran" ] || fail "a test that is not listed must not run"
printf '%s\n' "$out" | grep -q 'ALL PASS' || fail "a passing explicit list must report ALL PASS, got: $out"

dir=$(suite explicit-failure)
fake_test "$dir" alpha-listed-fails 1
out=$(sh "$dir/run-all.sh" "$dir/alpha-listed-fails.test.sh" 2>&1) && fail "a failing listed test must fail the run"
printf '%s\n' "$out" | grep -q 'FAIL.*alpha-listed-fails' || fail "a failing listed test must be named, got: $out"
out=$(sh "$dir/run-all.sh" "$dir/missing.test.sh" 2>&1) && fail "a listed test that does not exist must fail the run"
printf '%s\n' "$out" | grep -q 'FAIL.*missing' || fail "a listed test that does not exist must be named, got: $out"

echo "PASS: run-all"
