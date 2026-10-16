#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
status=0
for check in \
  audit-checkpoint \
  write-checkpoint
do
  sh "$HERE/$check.test.sh" > /dev/null 2>&1 && echo "PASS: $check" || { echo "FAIL: $check (rerun sh $HERE/$check.test.sh)"; status=1; }
done
[ "$status" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$status"
