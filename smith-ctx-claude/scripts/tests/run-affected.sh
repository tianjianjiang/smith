#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
TESTS="$HERE"
if [ "$#" != 1 ]; then
  echo "usage: sh run-affected.sh BASE_REF"
  exit 2
fi
BASE="$1"
WORK="$(mktemp -d)"

full_suite() {
  echo "run-affected: running the full suite, because $1"
  sh "$HERE/run.sh"
  exit "$?"
}

ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" ||
  full_suite "$HERE is not inside a git checkout"
MERGE_BASE="$(git -C "$ROOT" merge-base "$BASE" HEAD 2>/dev/null)" ||
  full_suite "the base ref $BASE has no merge base with HEAD"
echo "run-affected: comparing against $BASE (merge base $MERGE_BASE)"
{
  git -C "$ROOT" diff -z --name-only --no-renames --no-relative "$MERGE_BASE" &&
    git -C "$ROOT" ls-files -z --others --exclude-standard
} > "$WORK/changed" || full_suite "git could not list the changed files"

node "$HERE/select.mjs" tests "$ROOT" "$TESTS" "$WORK/changed" "$WORK/selected"
selection_status=$?
if [ "$selection_status" = 3 ]; then
  sh "$HERE/run.sh"
  exit "$?"
fi
[ "$selection_status" = 0 ] ||
  full_suite "the selector exited with status $selection_status"
[ -s "$WORK/selected" ] || exit 0
set --
while IFS= read -r test_file; do
  set -- "$@" "$test_file"
done < "$WORK/selected"
sh "$HERE/run.sh" "$@"
