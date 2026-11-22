#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
JOBS="${SMITH_TEST_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
case "$JOBS" in
  '' | *[!0-9]* | 0)
    echo "SMITH_TEST_JOBS must be a positive whole number, got: $JOBS"
    exit 1
    ;;
esac
DEFAULT_BASE=origin/main
usage() {
  echo "usage: sh run.sh [--all | TEST_FILE_OR_FOLDER...]"
  echo "  no arguments   run the tests that changes since $DEFAULT_BASE reach, through run-affected.sh"
  echo "  --all          run every *.test.sh in every tests folder that list-folders.sh prints"
  echo "  TEST_FILE      run exactly that test"
  echo "  FOLDER         run every *.test.sh in that folder"
  exit 2
}
case "$1" in
  '')
    [ "$#" = 0 ] || usage
    exec sh "$HERE/run-affected.sh" "$DEFAULT_BASE"
    ;;
  --all)
    [ "$#" = 1 ] || usage
    shift
    ;;
  -*) usage ;;
esac
LOGS="$(mktemp -d)"
if [ "$#" = 0 ]; then
  sh "$HERE/list-folders.sh" > "$LOGS/folders" || {
    echo "run: could not list the tests folders"
    exit 1
  }
  while IFS= read -r folder; do
    set -- "$@" "$folder"
  done < "$LOGS/folders"
  if [ "$#" = 0 ]; then
    echo "NO TESTS FOUND in any tests folder"
    exit 1
  fi
fi
for argument in "$@"; do
  shift
  [ -n "$argument" ] || usage
  if [ ! -d "$argument" ]; then
    set -- "$@" "$argument"
    continue
  fi
  found=
  for test_file in "$argument"/*.test.sh; do
    if [ -e "$test_file" ] || [ -L "$test_file" ]; then
      set -- "$@" "$test_file"
      found=1
    fi
  done
  if [ -z "$found" ]; then
    echo "NO TESTS FOUND in $argument"
    exit 1
  fi
done
ROOT="$(unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR; git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)"
path_from_root() {
  folder="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || {
    printf '%s\n' "$1"
    return
  }
  path="$folder/$(basename "$1")"
  if [ -n "$ROOT" ] && [ "${path#"$ROOT"/}" != "$path" ]; then
    printf '%s\n' "${path#"$ROOT"/}"
  else
    printf '%s\n' "$path"
  fi
}
mkdir -p "$LOGS/logs"
index=0
for test_file in "$@"; do
  index=$((index + 1))
  printf '%s\0%s\0' "$LOGS/logs/$index.log" "$test_file"
done | xargs -0 -n 2 -P "$JOBS" sh -c '
  bash "$2" < /dev/null > "$1" 2>&1
  echo "$?" > "$1.status"
' run-one
status=0
index=0
for test_file in "$@"; do
  index=$((index + 1))
  log="$LOGS/logs/$index.log"
  cat "$log"
  if [ "$(cat "$log.status" 2>/dev/null)" != 0 ]; then
    echo "FAIL: $(path_from_root "$test_file") (rerun bash $test_file)"
    status=1
  fi
done
[ "$status" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$status"
