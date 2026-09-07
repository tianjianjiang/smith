#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
    exit 0
fi

TOOL_NAME="$1"
shift

[[ "$TOOL_NAME" != "gh" ]] && exit 0

ARGS_STR="$*"
[[ "$ARGS_STR" != *"pr comment"* ]] && [[ "$ARGS_STR" != *"pr review"* ]] && exit 0

BODY=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--body)
            shift
            [[ $# -gt 0 ]] && BODY="$1"
            break
            ;;
        -F|--body-file)
            shift
            if [[ $# -gt 0 && -f "$1" ]]; then
                BODY=$(cat "$1")
            fi
            break
            ;;
    esac
    shift
done

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
