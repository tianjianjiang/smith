#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
status=0
for check in \
  inline-comment-lint
do
  sh "$HERE/$check.test.sh" || status=1
done
[ "$status" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$status"
