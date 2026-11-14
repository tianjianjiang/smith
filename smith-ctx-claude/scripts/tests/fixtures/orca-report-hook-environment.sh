#!/bin/sh
[ -n "$SMITH_PROBE_REPORT_FILE" ] || exit 0
{
  echo "names=$(env | grep '^ORCA_' | cut -d= -f1 | sort | tr '\n' ' ')"
  echo "handle=$ORCA_TERMINAL_HANDLE"
  echo "job=${CLAUDE_JOB_DIR:+set}"
} > "$SMITH_PROBE_REPORT_FILE"
