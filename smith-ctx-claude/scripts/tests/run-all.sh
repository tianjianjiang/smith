#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
JOBS="${RUN_ALL_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
LOGS="$(mktemp -d)"
trap 'rm -rf "$LOGS"' EXIT
found=0
for test_file in "$HERE"/*.test.sh; do
  [ -f "$test_file" ] || continue
  found=1
  printf '%s\n' "$test_file"
done > "$LOGS/tests"
if [ "$found" = 0 ]; then
  echo "NO TESTS FOUND in $HERE"
  exit 1
fi
xargs -P "$JOBS" -I{} sh -c '
  log="$2/$(basename "$1").log"
  bash "$1" > "$log" 2>&1
  echo "$?" > "$log.status"
' run-one {} "$LOGS" < "$LOGS/tests"
status=0
while IFS= read -r test_file; do
  log="$LOGS/$(basename "$test_file").log"
  cat "$log"
  if [ "$(cat "$log.status" 2>/dev/null)" != 0 ]; then
    echo "FAIL: $(basename "$test_file") (rerun bash $test_file)"
    status=1
  fi
done < "$LOGS/tests"
[ "$status" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$status"
