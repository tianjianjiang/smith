#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
SCAN="$HERE/../behaviour-eval-leak-scan.mjs"

TMPD="$(mktemp -d)"
trap 'chmod -R u+rwx "$TMPD" 2>/dev/null; rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

[ -f "$SCAN" ] || fail "the script under test does not exist: $SCAN"
[ "$(id -u)" != 0 ] || fail "the unreadable-file case needs a non-root user"

random_word() { head -c 45 /dev/urandom | base64 | tr -d '=+/\n'; }
mode_of() { node -e 'process.stdout.write((require("fs").statSync(process.argv[1]).mode & 0o777).toString(8))' "$1"; }
base64_form() {
  node -e '
    const leadingBytes = Number(process.argv[2]);
    const skippedChars = [0, 2, 3][leadingBytes];
    const encoded = Buffer.concat([Buffer.alloc(leadingBytes, "x"), Buffer.from(process.argv[1])])
      .toString("base64").replace(/=+$/, "");
    process.stdout.write(encoded.slice(skippedChars, -4));
  ' "$NEEDLE" "$1"
}
fingerprint() {
  (
    cd "$1" || exit 1
    find . -name LEAK-FOUND -prune -o -print | LC_ALL=C sort
    find . -type f ! -name LEAK-FOUND -exec shasum -a 256 {} + | LC_ALL=C sort
    find . -type l -exec sh -c 'for link; do printf "%s -> %s\n" "$link" "$(readlink "$link")"; done' sh {} + | LC_ALL=C sort
  )
}
report_has() {
  [ -f "$1" ] || return 1
  awk -F '[[:space:],:;=|]+' -v wanted_path="$2" -v wanted_form="$3" -v wanted_offset="$4" '
    {
      has_path = 0
      has_form = 0
      has_offset = (wanted_offset == "")
      for (i = 1; i <= NF; i++) {
        if ($i == wanted_path) has_path = 1
        if ($i == wanted_form) has_form = 1
        if (wanted_offset != "" && $i == wanted_offset) has_offset = 1
      }
      if (has_path && has_form && has_offset) found = 1
    }
    END { exit !found }
  ' "$1"
}
make_root() {
  ROOT="$TMPD/$1"
  mkdir -p "$ROOT"
  chmod 755 "$ROOT"
}
scan() {
  CASE="$1"
  STDIN_FILE="$2"
  shift 2
  REPORT="$TMPD/$CASE.report"
  node "$SCAN" --report "$REPORT" "$@" <"$STDIN_FILE" >"$TMPD/$CASE.out" 2>"$TMPD/$CASE.err"
  STATUS=$?
}
expect_status() { [ "$STATUS" = "$1" ] || fail "$2, got status $STATUS"; }

NEEDLE="$(random_word)\"$(random_word)\\$(random_word)"
JSON_NEEDLE="$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]).slice(1,-1))' "$NEEDLE")"
[ "$JSON_NEEDLE" != "$NEEDLE" ] || fail "the dummy needle must differ from its JSON-escaped form"
BASE64_FORMS_0="$(base64_form 0)"
BASE64_FORMS_1="$(base64_form 1)"
BASE64_FORMS_2="$(base64_form 2)"

KEY_VENDOR="sk-"
KEY_KIND="ant-"
KEY_TAIL="$(random_word)"
KEY="${KEY_VENDOR}${KEY_KIND}$(printf '%s' "$KEY_TAIL" | cut -c1-24)"
KEY_AT_LOWER_BOUND="${KEY_VENDOR}${KEY_KIND}$(printf '%s' "$KEY_TAIL" | cut -c1-20)"
KEY_BELOW_LOWER_BOUND="${KEY_VENDOR}${KEY_KIND}$(printf '%s' "$KEY_TAIL" | cut -c1-19)"

printf '%s\n' "$NEEDLE" > "$TMPD/needle.stdin"
printf '%s\n%s\n' "$(random_word)" "$NEEDLE" > "$TMPD/needle-on-second-line.stdin"
: > "$TMPD/empty.stdin"

leading_bytes() {
  case "$1" in
    0) ;;
    1) printf x ;;
    2) printf xx ;;
  esac
}
write_base64_file() {
  { leading_bytes "$1"; printf '%s' "$NEEDLE"; printf zzzzzzzz; } | base64 | tr -d '\n' > "$2"
}

make_root raw
mkdir "$ROOT/sub"
printf '%s%s%s' 'lead-' "$NEEDLE" '-trail' > "$ROOT/sub/raw.txt"
printf 'unrelated text\n' > "$ROOT/sub/clean.txt"
scan raw "$TMPD/needle.stdin" "$ROOT"
expect_status 1 "raw hit: a root holding the needle must exit 1"
report_has "$REPORT" sub/raw.txt raw 5 || fail "raw hit: the report must give the relative path, the form raw and the byte offset 5"
grep -q 'clean.txt' "$REPORT" && fail "raw hit: a file without the needle must not be reported"

make_root json-escaped
header='{"token":"'
printf '%s%s"}' "$header" "$JSON_NEEDLE" > "$ROOT/payload.json"
scan json-escaped "$TMPD/needle.stdin" "$ROOT"
expect_status 1 "json-escaped hit: a root holding the escaped needle must exit 1"
report_has "$REPORT" payload.json json-escaped "${#header}" || fail "json-escaped hit: the report must give the path, the form json-escaped and the byte offset of the escaped text"

for alignment in 0 1 2; do
  make_root "base64-$alignment"
  write_base64_file "$alignment" "$ROOT/encoded.txt"
  scan "base64-$alignment" "$TMPD/needle.stdin" "$ROOT"
  expect_status 1 "base64 hit at alignment $alignment: a root holding the encoded needle must exit 1"
  report_has "$REPORT" encoded.txt base64 || fail "base64 hit at alignment $alignment: the report must give the path and the form base64"
done

make_root key-shaped
printf 'lead-%s trail\n' "$KEY" > "$ROOT/key.txt"
scan key-shaped "$TMPD/needle.stdin" "$ROOT"
expect_status 1 "key-shaped hit: vendor-key-shaped text must exit 1 although no needle is in the root"
report_has "$REPORT" key.txt key-shaped 5 || fail "key-shaped hit: the report must give the path, the class key-shaped and the byte offset"

make_root key-at-lower-bound
printf 'lead-%s"\n' "$KEY_AT_LOWER_BOUND" > "$ROOT/key.txt"
scan key-at-lower-bound "$TMPD/needle.stdin" "$ROOT"
expect_status 1 "key-shaped lower bound: the shortest qualifying tail must exit 1"
report_has "$REPORT" key.txt key-shaped 5 || fail "key-shaped lower bound: the shortest qualifying tail must be reported"

make_root needle-on-second-line
printf '%s' "$NEEDLE" > "$ROOT/raw.txt"
scan needle-on-second-line "$TMPD/needle-on-second-line.stdin" "$ROOT"
expect_status 1 "needles on stdin: a needle on a later line must be scanned for"
report_has "$REPORT" raw.txt raw 0 || fail "needles on stdin: the hit of a later needle must be reported"

make_root linked-inside
mkdir "$ROOT/real"
printf '%s' "$NEEDLE" > "$ROOT/real/n.txt"
ln -s real "$ROOT/linked"
scan linked-inside "$TMPD/needle.stdin" "$ROOT"
expect_status 1 "link inside the root: the needle behind it must exit 1"
report_has "$REPORT" linked/n.txt raw 0 || fail "link inside the root: the hit must be reported under the link's own path"

OUTSIDE="$TMPD/outside-target"
mkdir "$OUTSIDE"
chmod 755 "$OUTSIDE"
printf '%s' "$NEEDLE" > "$OUTSIDE/n.txt"
OUTSIDE_BEFORE="$(fingerprint "$OUTSIDE")"
make_root link-leaving
printf 'unrelated text\n' > "$ROOT/clean.txt"
ln -s "$OUTSIDE" "$ROOT/leaving-dir"
ln -s "$OUTSIDE/n.txt" "$ROOT/leaving-file"
scan link-leaving "$TMPD/needle.stdin" "$ROOT"
report_has "$REPORT" leaving-dir not-scanned || fail "link leaving the root: a linked folder outside the root must be listed as not-scanned"
report_has "$REPORT" leaving-file not-scanned || fail "link leaving the root: a linked file outside the root must be listed as not-scanned"
grep -q 'n.txt' "$REPORT" && fail "link leaving the root: nothing behind the link may be reported as a hit"
[ "$(fingerprint "$OUTSIDE")" = "$OUTSIDE_BEFORE" ] || fail "link leaving the root: the target must stay unchanged"
[ "$(mode_of "$OUTSIDE")" = 755 ] || fail "link leaving the root: the target's mode must stay unchanged"
[ ! -e "$OUTSIDE/LEAK-FOUND" ] || fail "link leaving the root: no marker may be written into the target"

make_root clean
mkdir -p "$ROOT/deep/er"
printf 'plain words\n' > "$ROOT/deep/er/a.txt"
printf 'lead-%s trail\n' "$KEY_BELOW_LOWER_BOUND" > "$ROOT/deep/short-key.txt"
CLEAN_ROOT="$ROOT"
CLEAN_BEFORE="$(fingerprint "$CLEAN_ROOT")"
scan clean "$TMPD/needle.stdin" "$CLEAN_ROOT"
expect_status 0 "clean tree: a root without the needle must exit 0"
grep -q '^files-read: yes$' "$REPORT" || fail "clean tree: the report must say files-read: yes"
report_has "$REPORT" deep/short-key.txt key-shaped && fail "clean tree: a tail below the lower bound must not be key-shaped"
[ ! -e "$CLEAN_ROOT/LEAK-FOUND" ] || fail "clean tree: no marker may be written"
[ "$(mode_of "$CLEAN_ROOT")" = 755 ] || fail "clean tree: the root's mode must stay unchanged"
[ "$(fingerprint "$CLEAN_ROOT")" = "$CLEAN_BEFORE" ] || fail "clean tree: no file may change"

make_root all-forms
HIT_ROOT="$ROOT"
mkdir "$HIT_ROOT/nested"
printf '%s' "$NEEDLE" > "$HIT_ROOT/raw.txt"
printf '%s%s"}' "$header" "$JSON_NEEDLE" > "$HIT_ROOT/nested/payload.json"
for alignment in 0 1 2; do
  write_base64_file "$alignment" "$HIT_ROOT/encoded-$alignment.txt"
done
printf 'lead-%s trail\n' "$KEY" > "$HIT_ROOT/key.txt"
printf 'unrelated text\n' > "$HIT_ROOT/clean.txt"
ln -s nested "$HIT_ROOT/linked"
HIT_BEFORE="$(fingerprint "$HIT_ROOT")"
scan all-forms "$TMPD/needle.stdin" "$HIT_ROOT" "$CLEAN_ROOT"
expect_status 1 "hit beside a clean root: the status must be 1"
[ "$(fingerprint "$HIT_ROOT")" = "$HIT_BEFORE" ] || fail "files after a hit: nothing may be changed, moved or deleted"
[ "$(fingerprint "$CLEAN_ROOT")" = "$CLEAN_BEFORE" ] || fail "files after a hit: the clean root must stay unchanged"
[ -f "$HIT_ROOT/LEAK-FOUND" ] || fail "marker after a hit: LEAK-FOUND must be written into the root that had a hit"
[ ! -e "$CLEAN_ROOT/LEAK-FOUND" ] || fail "marker after a hit: no marker may be written into a root without a hit"
[ "$(mode_of "$HIT_ROOT")" = 700 ] || fail "mode after a hit: the root with a hit must become owner-only"
[ "$(mode_of "$CLEAN_ROOT")" = 755 ] || fail "mode after a hit: a root without a hit must keep its mode"
tail -n 1 "$TMPD/all-forms.out" | grep -qi 'revoke' || fail "revoke line: the last stdout line must tell the reader to revoke the key"
tail -n 1 "$TMPD/all-forms.out" | grep -qi 'console' || fail "revoke line: the last stdout line must name the vendor console"

make_root no-needle-on-stdin
printf '%s' "$NEEDLE" > "$ROOT/raw.txt"
scan empty-stdin "$TMPD/empty.stdin" "$ROOT"
expect_status 3 "empty stdin: the scan must report not run"
grep -q '^files-read: no$' "$REPORT" || fail "empty stdin: the report must say files-read: no"
[ ! -e "$ROOT/LEAK-FOUND" ] || fail "empty stdin: no marker may be written"

printf '\n\n\n' > "$TMPD/blank-lines.stdin"
scan blank-stdin "$TMPD/blank-lines.stdin" "$ROOT"
expect_status 3 "blank-only stdin: an empty needle must never be used, so the scan must report not run"
grep -q '^files-read: no$' "$REPORT" || fail "blank-only stdin: the report must say files-read: no"
[ ! -e "$ROOT/LEAK-FOUND" ] || fail "blank-only stdin: no marker may be written"

make_root empty-file-only
: > "$ROOT/empty.txt"
scan empty-file-only "$TMPD/needle.stdin" "$ROOT"
expect_status 0 "empty regular file: a root whose only file is empty counts as read and must exit 0"
grep -q '^files-read: yes$' "$REPORT" || fail "empty regular file: the report must say files-read: yes"

scan missing-root "$TMPD/needle.stdin" "$TMPD/no-such-root"
expect_status 3 "missing root: the scan must report not run"
grep -q '^files-read: no$' "$REPORT" || fail "missing root: the report must say files-read: no"

scan clean-and-missing-root "$TMPD/needle.stdin" "$CLEAN_ROOT" "$TMPD/no-such-root"
expect_status 3 "a missing root beside a clean one: the scan must report not run"

make_root empty-root
mkdir "$ROOT/empty-subfolder"
scan empty-root "$TMPD/needle.stdin" "$ROOT"
expect_status 3 "empty root: a root holding no file must report not run"
grep -q '^files-read: no$' "$REPORT" || fail "empty root: the report must say files-read: no"

make_root unreadable-file
printf 'unrelated text\n' > "$ROOT/readable.txt"
printf 'unrelated text\n' > "$ROOT/locked.txt"
chmod 000 "$ROOT/locked.txt"
scan unreadable-file "$TMPD/needle.stdin" "$ROOT"
expect_status 3 "unreadable file: a root with a file that cannot be read must report not run"
[ ! -e "$ROOT/LEAK-FOUND" ] || fail "unreadable file: no marker may be written"

assert_absent() {
  for artifact in "$TMPD"/*.report "$TMPD"/*.out "$TMPD"/*.err; do
    grep -F -q -e "$2" "$artifact" && fail "no needle in output: the $1 form is in $(basename "$artifact")"
  done
  return 0
}
assert_absent raw "$NEEDLE"
assert_absent json-escaped "$JSON_NEEDLE"
assert_absent base64-alignment-0 "$BASE64_FORMS_0"
assert_absent base64-alignment-1 "$BASE64_FORMS_1"
assert_absent base64-alignment-2 "$BASE64_FORMS_2"
assert_absent key-shaped "$KEY"

echo "PASS: behaviour-eval-leak-scan"
