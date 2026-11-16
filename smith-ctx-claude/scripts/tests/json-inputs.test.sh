#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/json-inputs.sh"
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

mkdir "$TMPD/mixed"
printf '{"a":1}' > "$TMPD/mixed/good-input"
printf '{"a":' > "$TMPD/mixed/truncated-input"
out=$(json_files_are_valid "$TMPD/mixed") && fail "a folder with a truncated file must fail"
printf '%s\n' "$out" | grep -q 'truncated-input' || fail "the report must name the broken file, got: $out"
printf '%s\n' "$out" | grep -q 'good-input' && fail "the report must not name a valid file, got: $out"

mkdir "$TMPD/valid"
printf '{"a":1}' > "$TMPD/valid/one"
printf '[1,"two"]' > "$TMPD/valid/two"
out=$(json_files_are_valid "$TMPD/valid") || fail "a folder of valid files must pass, got: $out"

mkdir "$TMPD/empty"
out=$(json_files_are_valid "$TMPD/empty") && fail "an empty folder must fail, since no input was checked"
printf '%s\n' "$out" | grep -q 'no input was recorded' || fail "an empty folder must say so, got: $out"

out=$(json_files_are_valid "$TMPD/missing") && fail "a missing folder must fail"
printf '%s\n' "$out" | grep -q 'cannot read the input folder' || fail "a missing folder must say so, got: $out"

echo "PASS: json-inputs"
