#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat) || exit 0
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[[ -z "$command" ]] && exit 0

[[ "$command" != gh\ * ]] && exit 0
[[ "$command" != *"pr comment"* ]] && [[ "$command" != *"pr review"* ]] && exit 0

BODY=""

if [[ "$command" =~ -F[[:space:]]+\"([^\"]+)\" ]] || [[ "$command" =~ -F[[:space:]]+([^[:space:]]+) ]]; then
    file="${BASH_REMATCH[1]}"
    [[ -f "$file" ]] && BODY=$(cat "$file")
elif [[ "$command" =~ --body-file=\"([^\"]+)\" ]] || [[ "$command" =~ --body-file=([^[:space:]]+) ]]; then
    file="${BASH_REMATCH[1]}"
    [[ -f "$file" ]] && BODY=$(cat "$file")
elif [[ "$command" =~ -b[[:space:]]+\"(.*)\" ]]; then
    BODY="${BASH_REMATCH[1]}"
elif [[ "$command" =~ --body=\"(.*)\" ]]; then
    BODY="${BASH_REMATCH[1]}"
elif [[ "$command" =~ --body=([^[:space:]]+) ]]; then
    BODY="${BASH_REMATCH[1]}"
fi

[[ -z "$BODY" ]] && exit 0

if ! grep -qE 'Assisted-by: Claude:claude-(sonnet|opus|haiku|fable)-[0-9]+-[0-9]+' <<< "$BODY"; then
    echo "Error: Missing or invalid assisted-by attribution" >&2
    echo "" >&2
    echo "Required format:" >&2
    ~/.smith/smith-ctx-claude/scripts/attribution.sh >&2
    echo "" >&2
    echo "NEVER hand-type the attribution - always run the script above" >&2
    exit 2
fi

if grep -qi "on behalf of" <<< "$BODY"; then
    echo "Error: Found forbidden 'on behalf of' pattern" >&2
    echo "Use assisted-by attribution only (run attribution.sh)" >&2
    exit 2
fi

exit 0
