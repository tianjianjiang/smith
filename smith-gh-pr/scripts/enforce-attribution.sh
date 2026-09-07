#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="$1"
shift
TOOL_ARGS="$*"

[[ "$TOOL_NAME" != "gh" ]] && exit 0
[[ "$TOOL_ARGS" != *"pr comment"* ]] && [[ "$TOOL_ARGS" != *"pr review"* ]] && exit 0

BODY=""
if [[ "$TOOL_ARGS" =~ -b\ (.+) ]]; then
    BODY="${BASH_REMATCH[1]}"
    BODY="${BODY#\"}"
    BODY="${BODY%\"}"
    BODY="${BODY#\'}"
    BODY="${BODY%\'}"
elif [[ "$TOOL_ARGS" =~ -F\ ([^\ ]+) ]]; then
    FILE="${BASH_REMATCH[1]}"
    [[ -f "$FILE" ]] && BODY=$(cat "$FILE")
fi

[[ -z "$BODY" ]] && exit 0

if ! grep -qE 'Assisted-by: Claude:claude-(sonnet|opus|haiku|fable)-[0-9]+-[0-9]+' <<< "$BODY"; then
    echo "Error: Missing or invalid assisted-by attribution" >&2
    echo "" >&2
    echo "Required format:" >&2
    ~/.smith/smith-ctx-claude/scripts/attribution.sh >&2
    echo "" >&2
    echo "NEVER hand-type the attribution - always run the script above" >&2
    exit 1
fi

if grep -qi "on behalf of" <<< "$BODY"; then
    echo "Error: Found forbidden 'on behalf of' pattern" >&2
    echo "Use assisted-by attribution only (run attribution.sh)" >&2
    exit 1
fi

exit 0
