#!/bin/sh
[ -n "$SMITH_PROBE_ARM_FILE" ] && [ -f "$SMITH_PROBE_ARM_FILE" ] || exit 0
. "$(dirname "$0")/../lib/set-aside.sh"
set_aside "$SMITH_PROBE_ARM_FILE"
"${ORCA_CLI_COMMAND:-orca}" terminal send --terminal "$SMITH_PROBE_TERMINAL" --text '/clear' --enter --json > "$SMITH_PROBE_ARM_FILE.sent" 2>&1
