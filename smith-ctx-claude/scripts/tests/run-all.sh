#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
JOBS="${RUN_ALL_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
case "$JOBS" in
  '' | *[!0-9]* | 0)
    echo "RUN_ALL_JOBS must be a positive whole number, got: $JOBS"
    exit 1
    ;;
esac
LOGS="$(mktemp -d)"
trap 'rm -rf "$LOGS"' EXIT
for test_file in "$HERE"/*.test.sh; do
  [ -f "$test_file" ] || continue
  printf '%s\n' "$test_file"
done > "$LOGS/tests"
if [ ! -s "$LOGS/tests" ]; then
  echo "NO TESTS FOUND in $HERE"
  exit 1
fi
tr '\n' '\0' < "$LOGS/tests" | xargs -0 -n 1 -P "$JOBS" sh -c '
  log="$1/$(basename "$2").log"
  bash "$2" > "$log" 2>&1
  echo "$?" > "$log.status"
' run-one "$LOGS"
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
