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
if [ "$#" = 0 ]; then
  for test_file in "$HERE"/*.test.sh; do
    if [ -e "$test_file" ] || [ -L "$test_file" ]; then
      set -- "$@" "$test_file"
    fi
  done
fi
if [ "$#" = 0 ]; then
  echo "NO TESTS FOUND in $HERE"
  exit 1
fi
printf '%s\0' "$@" | xargs -0 -n 1 -P "$JOBS" sh -c '
  log="$1/$(basename "$2").log"
  bash "$2" < /dev/null > "$log" 2>&1
  echo "$?" > "$log.status"
' run-one "$LOGS"
status=0
for test_file in "$@"; do
  log="$LOGS/$(basename "$test_file").log"
  cat "$log"
  if [ "$(cat "$log.status" 2>/dev/null)" != 0 ]; then
    echo "FAIL: $(basename "$test_file") (rerun bash $test_file)"
    status=1
  fi
done
[ "$status" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$status"
