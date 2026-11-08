#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
NEW_BODY="$HERE/../new-body-file.sh"

WORK="$(mktemp -d)"
CREATED=""
trap 'rm -rf "$WORK" ${CREATED:+"$CREATED"}' EXIT
fail() { echo "FAIL: $1"; exit 1; }

owner_only() { [ "$(ls -l "$1" | cut -c1-10)" = "-rw-------" ]; }

mkdir -p "$WORK/job" "$WORK/tmpdir"

path=$(env CLAUDE_JOB_DIR="$WORK/job" TMPDIR="$WORK/tmpdir" sh "$NEW_BODY") || fail "job dir: nonzero exit"
case "$path" in "$WORK/job/checkpoint-body."*) ;; *) fail "job dir must win over TMPDIR, got: $path" ;; esac
[ -f "$path" ] || fail "job dir: printed path is not a file: $path"
[ ! -s "$path" ] || fail "job dir: new body file must start empty"
owner_only "$path" || fail "job dir: body file must be owner-only, got: $(ls -l "$path")"

path=$(env -u CLAUDE_JOB_DIR TMPDIR="$WORK/tmpdir/" sh "$NEW_BODY") || fail "TMPDIR: nonzero exit"
case "$path" in "$WORK/tmpdir/checkpoint-body."*) ;; *) fail "without a job dir TMPDIR must be used, got: $path" ;; esac
case "$path" in *//*) fail "a trailing slash in TMPDIR must not double the separator: $path" ;; esac
owner_only "$path" || fail "TMPDIR: body file must be owner-only, got: $(ls -l "$path")"

second=$(env -u CLAUDE_JOB_DIR TMPDIR="$WORK/tmpdir" sh "$NEW_BODY") || fail "second call: nonzero exit"
[ "$second" != "$path" ] || fail "two calls must give two different files: $path"

path=$(env CLAUDE_JOB_DIR= TMPDIR="$WORK/tmpdir" sh "$NEW_BODY") || fail "empty job dir: nonzero exit"
case "$path" in "$WORK/tmpdir/checkpoint-body."*) ;; *) fail "an empty CLAUDE_JOB_DIR must fall back to TMPDIR, got: $path" ;; esac

path=$(env CLAUDE_JOB_DIR="$WORK/job" "$NEW_BODY") || fail "direct call: the script must be executable, as SKILL.md runs it without sh"
case "$path" in "$WORK/job/checkpoint-body."*) ;; *) fail "direct call: got: $path" ;; esac

path=$(umask 000; env CLAUDE_JOB_DIR="$WORK/job" sh "$NEW_BODY") || fail "umask 000: nonzero exit"
owner_only "$path" || fail "umask 000: body file must stay owner-only, got: $(ls -l "$path")"

CREATED=$(env -u CLAUDE_JOB_DIR -u TMPDIR sh "$NEW_BODY") || fail "/tmp fallback: nonzero exit"
case "$CREATED" in /tmp/checkpoint-body.*) ;; *) fail "without a job dir or TMPDIR /tmp must be used, got: $CREATED" ;; esac
owner_only "$CREATED" || fail "/tmp fallback: body file must be owner-only, got: $(ls -l "$CREATED")"

mkdir -p "$WORK/fallback"
out=$(env CLAUDE_JOB_DIR="$WORK/missing" TMPDIR="$WORK/fallback" sh "$NEW_BODY" 2>/dev/null) && fail "missing directory: must exit nonzero"
[ -z "$out" ] || fail "missing directory: must print no path, got: $out"
[ -z "$(ls -A "$WORK/fallback")" ] || fail "missing directory: must not fall back to TMPDIR: $(ls -A "$WORK/fallback")"

echo "PASS"
