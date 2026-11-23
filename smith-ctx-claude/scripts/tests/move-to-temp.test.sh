#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib-context.sh"
HOOKS=("$HERE/../inject-plan.sh" "$HERE/../enforce-clear.sh" "$HERE/../on-session-clear.sh")
TMPD="$(mktemp -d)"
fail() { printf 'FAIL: %s\n' "$1"; exit 1; }
[ -f "$LIB" ] || fail "the library under test does not exist: $LIB"
for hook in "${HOOKS[@]}"; do [ -f "$hook" ] || fail "a hook that calls the library does not exist: $hook"; done
export CLAUDE_CONFIG_DIR="$TMPD/config"
source "$LIB"

mkdir "$TMPD/fakebin" "$TMPD/brokenbin" "$TMPD/aside"
cat > "$TMPD/fakebin/mktemp" <<EOF
#!/bin/sh
[ "\$#" = 1 ] && [ "\$1" = "-d" ] || { echo "unexpected mktemp arguments: \$*" >&2; exit 2; }
folder="$TMPD/aside/\$(ls "$TMPD/aside" | wc -l | tr -d ' ')"
mkdir "\$folder" && echo "\$folder"
EOF
printf '#!/bin/sh\nexit 1\n' > "$TMPD/brokenbin/mktemp"
chmod +x "$TMPD/fakebin/mktemp" "$TMPD/brokenbin/mktemp"
with_fake_mktemp() { PATH="$TMPD/fakebin:$PATH" "$@"; }
with_broken_mktemp() { PATH="$TMPD/brokenbin:$PATH" "$@"; }
aside_copies() { find "$TMPD/aside" -name "$1" | wc -l | tr -d ' '; }
expired() { touch -h -t 202601010000 "$@"; }

mkdir "$TMPD/plain"
printf 'kept\n' > "$TMPD/plain/flag"
with_fake_mktemp move_file_to_temp "$TMPD/plain/flag" || fail "a plain file: move_file_to_temp must succeed"
[ ! -e "$TMPD/plain/flag" ] || fail "a plain file: it must be gone from its place"
[ "$(cat "$(find "$TMPD/aside" -name flag)")" = kept ] || fail "a plain file: it must sit, unchanged, in a folder mktemp -d made"

out=$(with_fake_mktemp move_file_to_temp "$TMPD/plain/absent" 2>&1) || fail "an absent file: move_file_to_temp must succeed like rm -f, got: $out"
[ -z "$out" ] || fail "an absent file: move_file_to_temp must print nothing, got: $out"

ln -s "$TMPD/nowhere" "$TMPD/plain/dangling"
with_fake_mktemp move_file_to_temp "$TMPD/plain/dangling" || fail "a dangling link: move_file_to_temp must succeed"
[ ! -L "$TMPD/plain/dangling" ] && [ "$(aside_copies dangling)" = 1 ] || fail "a dangling link: the link itself must be moved"

mkdir "$TMPD/stuck"
printf 'still here\n' > "$TMPD/stuck/flag"
out=$(with_broken_mktemp move_file_to_temp "$TMPD/stuck/flag" 2>&1) || fail "mktemp -d fails: move_file_to_temp must still succeed, got: $out"
[ -z "$out" ] || fail "mktemp -d fails: move_file_to_temp must print nothing, got: $out"
[ ! -e "$TMPD/stuck/flag" ] || fail "mktemp -d fails: the file must no longer answer to its name, or a one-shot flag is consumed again"
[ "$(cat "$TMPD/stuck"/.set-aside.flag.*)" = "still here" ] || fail "mktemp -d fails: the file must be kept, unchanged, under a set-aside name beside its old place"

mkdir -p "$TMPD/sweep/inner" "$TMPD/sweep/.model-folder"
printf 'first\n' > "$TMPD/sweep/.model-same"
printf 'second\n' > "$TMPD/sweep/inner/.model-same"
: > "$TMPD/sweep/.model-fresh"
: > "$TMPD/sweep/unrelated"
: > "$TMPD/sweep/.model-folder/inside"
expired "$TMPD/sweep/.model-same" "$TMPD/sweep/inner/.model-same" "$TMPD/sweep/unrelated" "$TMPD/sweep/.model-folder"
with_fake_mktemp move_matching_to_temp "$TMPD/sweep" -name ".model-*" -mmin +1440 || fail "a sweep: move_matching_to_temp must succeed"
[ ! -e "$TMPD/sweep/.model-same" ] && [ ! -e "$TMPD/sweep/inner/.model-same" ] || fail "a sweep: every expired match must be gone from its place"
[ "$(aside_copies .model-same)" = 2 ] || fail "a sweep: two matches with one name must both be kept, got $(aside_copies .model-same)"
[ "$(find "$TMPD/aside" -name .model-same -exec cat {} + | sort | tr '\n' ' ')" = "first second " ] || fail "a sweep: neither same-named match may overwrite the other"
[ -e "$TMPD/sweep/.model-fresh" ] || fail "a sweep: a match younger than the limit must stay"
[ -e "$TMPD/sweep/unrelated" ] || fail "a sweep: an expired file with another name must stay"
[ -e "$TMPD/sweep/.model-folder/inside" ] || fail "a sweep: a matching folder must stay with its content"

out=$(with_fake_mktemp move_matching_to_temp "$TMPD/sweep" -name ".never-*" -mmin +1 2>&1) || fail "a sweep with no match: move_matching_to_temp must succeed, got: $out"
[ -z "$out" ] || fail "a sweep with no match: move_matching_to_temp must print nothing, got: $out"

ERASING='(^|[^a-zA-Z_])(rm|rmdir|unlink)([^a-zA-Z_]|$)|-delete([^a-zA-Z_-]|$)'
grep -nE -e "$ERASING" "$LIB" && fail "lib-context.sh must not erase anything"
for hook in "${HOOKS[@]}"; do grep -nE -e "$ERASING" "$hook" && fail "$hook must not erase anything"; done

echo "PASS: move-to-temp"
