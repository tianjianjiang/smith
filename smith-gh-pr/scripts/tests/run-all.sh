#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
status=0
for check in \
  pr-body-template \
  media-and-reading
do
  sh "$HERE/$check.test.sh" || status=1
done
[ "$status" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$status"
