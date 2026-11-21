#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/lib/set-aside.sh"
TMPD="$(mktemp -d)"
fail() { printf 'FAIL: %s\n' "$1"; exit 1; }
[ -f "$LIB" ] || fail "the helper under test does not exist: $LIB"
. "$LIB"

mkdir "$TMPD/fakebin" "$TMPD/aside"
cat > "$TMPD/fakebin/mktemp" <<EOF
#!/bin/sh
[ "\$#" = 1 ] && [ "\$1" = "-d" ] || { echo "unexpected mktemp arguments: \$*" >&2; exit 2; }
folder="$TMPD/aside/\$(ls "$TMPD/aside" | wc -l | tr -d ' ')"
mkdir "\$folder" && echo "\$folder"
EOF
chmod +x "$TMPD/fakebin/mktemp"
with_fake_mktemp() { PATH="$TMPD/fakebin:$PATH" "$@"; }
aside_holds() { find "$TMPD/aside" -path "*/$1" | grep -q .; }

mkdir "$TMPD/plain"
printf 'kept\n' > "$TMPD/plain/flag"
with_fake_mktemp set_aside "$TMPD/plain/flag" || fail "a plain file: set_aside must succeed"
[ ! -e "$TMPD/plain/flag" ] || fail "a plain file: it must be gone from its place"
[ "$(cat "$(find "$TMPD/aside" -name flag)")" = kept ] || fail "a plain file: it must sit, unchanged, in a folder mktemp -d made"

out=$(with_fake_mktemp set_aside "$TMPD/plain"/.pending-* 2>&1) || fail "an unmatched glob: set_aside must succeed like rm -f, got: $out"
[ -z "$out" ] || fail "an unmatched glob: set_aside must print nothing, got: $out"

mkdir -p "$TMPD/tree/inner"
: > "$TMPD/tree/inner/leaf"
with_fake_mktemp set_aside "$TMPD/tree" || fail "a folder: set_aside must succeed"
[ ! -e "$TMPD/tree" ] && aside_holds tree/inner/leaf || fail "a folder: it must be moved aside with its content"

mkdir "$TMPD/with space"
: > "$TMPD/with space/a file"
with_fake_mktemp set_aside "$TMPD/with space/a file" || fail "a path with spaces: set_aside must succeed"
[ ! -e "$TMPD/with space/a file" ] && aside_holds "a file" || fail "a path with spaces: it must be moved aside"

mkdir "$TMPD/one" "$TMPD/two"
printf 'first\n' > "$TMPD/one/same"
printf 'second\n' > "$TMPD/two/same"
with_fake_mktemp set_aside "$TMPD/one/same" "$TMPD/two/same" || fail "two files with one name: set_aside must succeed"
contents=$(find "$TMPD/aside" -name same -exec cat {} + | LC_ALL=C sort | tr '\n' ' ')
[ "$contents" = "first second " ] || fail "two files with one name: both must survive, got: $contents"

ln -s "$TMPD/nowhere" "$TMPD/plain/dangling"
with_fake_mktemp set_aside "$TMPD/plain/dangling" || fail "a dangling link: set_aside must succeed"
[ ! -L "$TMPD/plain/dangling" ] && aside_holds dangling || fail "a dangling link: it must be moved aside, as rm -f would have removed it"

mkdir "$TMPD/target"
: > "$TMPD/target/inside"
ln -s "$TMPD/target" "$TMPD/plain/folder-link"
with_fake_mktemp set_aside "$TMPD/plain/folder-link//" || fail "a link to a folder named with a slash: set_aside must succeed"
[ -e "$TMPD/target/inside" ] || fail "a link to a folder named with a slash: the folder it points to must stay in place"
[ ! -L "$TMPD/plain/folder-link" ] && aside_holds folder-link || fail "a link to a folder named with a slash: the link itself must be moved aside"

mkdir "$TMPD/-dash"
: > "$TMPD/-dash/-flag"
(cd "$TMPD/-dash" && with_fake_mktemp set_aside -flag) || fail "a name starting with a dash: set_aside must succeed"
[ ! -e "$TMPD/-dash/-flag" ] && aside_holds -flag || fail "a name starting with a dash: it must be moved aside, not read as an option"

reported() { printf '%s\n' "$1" | grep -qF "set_aside: could not move $2 into a fresh mktemp -d folder: $3"; }

: > "$TMPD/plain/not-a-folder"
out=$(with_fake_mktemp set_aside "$TMPD/plain/not-a-folder/" 2>&1) && fail "a file named with a slash: set_aside must fail, as rm -f does"
[ -e "$TMPD/plain/not-a-folder" ] || fail "a file named with a slash: it must stay in place"
reported "$out" "$TMPD/plain/not-a-folder/" "it was named with a trailing slash but is not a folder" \
  || fail "a file named with a slash: the message must say why, got: $out"

mkdir -p "$TMPD/slashed/inner"
with_fake_mktemp set_aside "$TMPD/slashed//" || fail "a folder named with slashes: set_aside must succeed"
[ ! -e "$TMPD/slashed" ] && aside_holds slashed/inner || fail "a folder named with slashes: it must be moved aside"

ln -s "$TMPD/nowhere" "$TMPD/plain/dangling-slashed"
out=$(with_fake_mktemp set_aside "$TMPD/plain/dangling-slashed/" 2>&1) || fail "a dangling link named with a slash: set_aside must succeed, as rm -f finds nothing there, got: $out"
[ -z "$out" ] && [ -L "$TMPD/plain/dangling-slashed" ] || fail "a dangling link named with a slash: it must be left alone with no message, got: $out"

: > "$TMPD/plain/a-file"
chmod 755 "$TMPD/plain/a-file"
: > "$TMPD/plain/b-file"
out=$(with_fake_mktemp set_aside "$TMPD/plain/a-file/child" "$TMPD/plain/b-file/child" 2>&1) && fail "a path under a file: set_aside must fail, as rm -f does"
reported "$out" "$TMPD/plain/a-file/child" "$TMPD/plain/a-file is not a folder" \
  && reported "$out" "$TMPD/plain/b-file/child" "$TMPD/plain/b-file is not a folder" \
  || fail "a path under a file: the message must say the file is not a folder, got: $out"

if [ "$(id -u)" = 0 ]; then
  echo "SKIP: running as root, which ignores folder permissions, so the permission cases were not run"
else
  mkdir -p "$TMPD/sealed/deeper" "$TMPD/open"
  : > "$TMPD/sealed/hidden"
  : > "$TMPD/sealed/deeper/hidden"
  : > "$TMPD/open/after-sealed"
  chmod 000 "$TMPD/sealed"
  out=$(with_fake_mktemp set_aside "$TMPD/sealed/hidden" "$TMPD/sealed/deeper/hidden" "$TMPD/open/after-sealed" 2>&1)
  sealed_status=$?
  chmod 755 "$TMPD/sealed"
  [ "$sealed_status" != 0 ] || fail "a folder that cannot be searched: set_aside must fail, as rm -f does"
  [ -e "$TMPD/sealed/hidden" ] && [ -e "$TMPD/sealed/deeper/hidden" ] || fail "a folder that cannot be searched: its files must stay in place"
  reported "$out" "$TMPD/sealed/hidden" "$TMPD/sealed cannot be searched" \
    && reported "$out" "$TMPD/sealed/deeper/hidden" "$TMPD/sealed cannot be searched" \
    || fail "a folder that cannot be searched: the message must name each path and the folder, got: $out"
  [ ! -e "$TMPD/open/after-sealed" ] && aside_holds after-sealed || fail "a folder that cannot be searched: the paths after it must still be moved aside"

  mkdir "$TMPD/locked"
  : > "$TMPD/locked/stuck"
  : > "$TMPD/open/free"
  chmod 555 "$TMPD/locked"
  out=$(with_fake_mktemp set_aside "$TMPD/locked/stuck" "$TMPD/open/free" 2>&1)
  locked_status=$?
  chmod 755 "$TMPD/locked"
  [ "$locked_status" != 0 ] || fail "a move that fails: set_aside must fail"
  [ -e "$TMPD/locked/stuck" ] || fail "a move that fails: the file must stay in place"
  reported "$out" "$TMPD/locked/stuck" "the move failed" || fail "a move that fails: the message must name the path, got: $out"
  [ ! -e "$TMPD/open/free" ] && aside_holds free || fail "a move that fails: the paths after it must still be moved aside"
fi

mkdir "$TMPD/decoy"
: > "$TMPD/plain/stays"
printf '#!/bin/sh\necho "%s/decoy"\nexit 1\n' "$TMPD" > "$TMPD/fakebin/mktemp"
out=$(with_fake_mktemp set_aside "$TMPD/plain/stays" 2>&1) && fail "a failing mktemp: set_aside must fail"
[ -e "$TMPD/plain/stays" ] && [ ! -e "$TMPD/decoy/stays" ] || fail "a failing mktemp: the file must stay in place, not go to the folder it printed"
reported "$out" "$TMPD/plain/stays" "mktemp -d failed" || fail "a failing mktemp: the message must name the path and the cause, got: $out"

mkdir -p "$TMPD/stays-folder/inner"
printf '#!/bin/sh\necho "%s/ghost"\n' "$TMPD" > "$TMPD/fakebin/mktemp"
out=$(with_fake_mktemp set_aside "$TMPD/plain/stays" "$TMPD/stays-folder" 2>&1) && fail "a mktemp that names no folder: set_aside must fail"
[ -e "$TMPD/plain/stays" ] && [ -e "$TMPD/stays-folder/inner" ] && [ ! -e "$TMPD/ghost" ] \
  || fail "a mktemp that names no folder: the file and the folder must stay in place, not be renamed to the printed path"
reported "$out" "$TMPD/plain/stays" "mktemp -d named no folder: $TMPD/ghost" \
  && reported "$out" "$TMPD/stays-folder" "mktemp -d named no folder: $TMPD/ghost" \
  || fail "a mktemp that names no folder: the message must name each path and the cause, got: $out"

SYSTEM_TEMP=$(dirname "$TMPD")
UNIQUE=$(basename "$TMPD")
in_system_temp() { find "$SYSTEM_TEMP" -mindepth 2 -maxdepth 2 -name "$1" 2>/dev/null | grep -q .; }
path=caller-path
status=caller-status
folder=caller-folder
: > "$TMPD/plain/real-mktemp-$UNIQUE"
set_aside "$TMPD/plain/real-mktemp-$UNIQUE" || fail "the real mktemp: set_aside must succeed"
[ ! -e "$TMPD/plain/real-mktemp-$UNIQUE" ] && in_system_temp "real-mktemp-$UNIQUE" \
  || fail "the real mktemp: the file must be moved into a folder mktemp -d made, not erased"
[ "$path $status $folder" = "caller-path caller-status caller-folder" ] \
  || fail "the caller's variables must not change, got: $path $status $folder"

for shell in dash bash; do
  if ! command -v "$shell" >/dev/null; then
    echo "SKIP: $shell is not installed, so set_aside was not run under it"
    continue
  fi
  : > "$TMPD/plain/under-$shell-$UNIQUE"
  out=$("$shell" -c '. "$1" && set_aside "$2"/.none-* "$2/under-$3-$4"' _ "$LIB" "$TMPD/plain" "$shell" "$UNIQUE" 2>&1) || fail "under $shell: set_aside must succeed, got: $out"
  [ -z "$out" ] || fail "under $shell: set_aside must print nothing, got: $out"
  [ ! -e "$TMPD/plain/under-$shell-$UNIQUE" ] && in_system_temp "under-$shell-$UNIQUE" \
    || fail "under $shell: the file must be moved into a folder mktemp -d made, not erased"
  : > "$TMPD/plain/back\\tslash"
  out=$("$shell" -c '. "$1" && set_aside "$2/"' _ "$LIB" "$TMPD/plain/back\\tslash" 2>&1) \
    && fail "under $shell: a file named with a slash must make set_aside fail"
  reported "$out" "$TMPD/plain/back\\tslash/" "it was named with a trailing slash but is not a folder" \
    || fail "under $shell: the message must name a path with a backslash as given, got: $out"
done

grep -nwE 'rm|unlink|rmdir' "$LIB" && fail "the helper must not erase anything"

echo "PASS: set-aside"
