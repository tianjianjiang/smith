#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
status=0
found=0
for test_file in "$HERE"/*.test.sh; do
  [ -f "$test_file" ] || continue
  found=1
  bash "$test_file" || status=1
done
if [ "$found" = 0 ]; then
  echo "NO TESTS FOUND in $HERE"
  exit 1
fi
[ "$status" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$status"
