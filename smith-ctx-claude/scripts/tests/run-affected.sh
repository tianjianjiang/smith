#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ "$#" != 1 ]; then
  echo "usage: sh run-affected.sh BASE_REF"
  exit 2
fi
BASE="$1"
WORK="$(mktemp -d)" || {
  echo "run-affected: could not make a scratch folder"
  exit 1
}
sh "$HERE/list-folders.sh" > "$WORK/folders" || {
  echo "run-affected: could not list the tests folders"
  exit 1
}

list_every_test() {
  while IFS= read -r folder; do
    for test_file in "$folder"/*.test.sh; do
      if [ -e "$test_file" ] || [ -L "$test_file" ]; then
        printf '%s\n' "$test_file"
      fi
    done
  done < "$WORK/folders" > "$WORK/check"
}

check_listed_tests() {
  if [ ! -s "$WORK/check" ]; then
    echo "run-affected: no new or changed test, so the self-containedness check did not run"
    return 0
  fi
  set --
  while IFS= read -r test_file; do
    set -- "$@" "$test_file"
  done < "$WORK/check"
  echo "run-affected: checking that each listed test passes with its dependencies alone"
  sh "$HERE/verify-self-containedness.sh" "$@"
}

finish() {
  tests_status=$1
  check_listed_tests
  check_status=$?
  [ "$tests_status" = 0 ] && [ "$check_status" = 0 ]
  exit "$?"
}

full_suite() {
  list_every_test || {
    echo "run-affected: could not list every test for the self-containedness check"
    exit 1
  }
  echo "run-affected: running the full suite, because $1"
  sh "$HERE/run.sh" --all
  finish "$?"
}

ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>"$WORK/git-error")" || {
  echo "run-affected: running the full suite, because git found no checkout at $HERE: $(cat "$WORK/git-error")"
  sh "$HERE/run.sh" --all
  tests_status=$?
  echo "run-affected: the self-containedness check cannot run outside a git checkout"
  exit "$tests_status"
}
MERGE_BASE="$(git -C "$ROOT" merge-base "$BASE" HEAD 2>/dev/null)" ||
  full_suite "the base ref $BASE has no merge base with HEAD"
echo "run-affected: comparing against $BASE (merge base $MERGE_BASE)"
{
  git -C "$ROOT" diff -z --name-only --no-renames --no-relative "$MERGE_BASE" &&
    git -C "$ROOT" ls-files -z --others --exclude-standard
} > "$WORK/changed" || full_suite "git could not list the changed files"

set --
while IFS= read -r folder; do
  set -- "$@" "$folder"
done < "$WORK/folders"
node "$HERE/select.mjs" tests "$ROOT" "$WORK/changed" "$WORK/selected" "$WORK/check" "$@"
selection_status=$?
if [ "$selection_status" = 3 ]; then
  sh "$HERE/run.sh" --all
  finish "$?"
fi
if [ "$selection_status" != 0 ]; then
  echo "run-affected: running the full suite, because the selector exited with status $selection_status"
  sh "$HERE/run.sh" --all
  echo "run-affected: the self-containedness check did not run, because the selector failed"
  exit 1
fi
[ -s "$WORK/selected" ] || finish 0
set --
while IFS= read -r test_file; do
  set -- "$@" "$test_file"
done < "$WORK/selected"
sh "$HERE/run.sh" "$@"
finish "$?"
