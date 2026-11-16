#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
status=0
for test in "$HERE"/*.test.sh; do
  sh "$test" || status=1
done
[ "$status" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$status"
