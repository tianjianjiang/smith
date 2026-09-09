#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat) || exit 0
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[[ -z "$command" ]] && exit 0

[[ "$command" != *"git commit"* ]] && exit 0

BODY=""

if [[ "$command" =~ \<\<-?[\'\"]?([A-Za-z_][A-Za-z0-9_]*)[\'\"]? ]]; then
    delim="${BASH_REMATCH[1]}"
    BODY=$(awk -v d="$delim" '
        found { if ($0 == d) { exit } print; next }
        index($0, "<<") && index($0, d) { found=1 }
    ' <<< "$command")
fi

if [[ -z "$BODY" ]]; then
    if [[ "$command" =~ -F[[:space:]]+\"([^\"]+)\" ]] || [[ "$command" =~ -F[[:space:]]+([^[:space:]]+) ]]; then
        file="${BASH_REMATCH[1]}"
        [[ -f "$file" ]] && BODY=$(cat "$file")
    elif [[ "$command" =~ --file=\"([^\"]+)\" ]] || [[ "$command" =~ --file=([^[:space:]]+) ]]; then
        file="${BASH_REMATCH[1]}"
        [[ -f "$file" ]] && BODY=$(cat "$file")
    fi
fi

if [[ -z "$BODY" ]]; then
    scan="$command"
    while [[ "$scan" =~ (-m|--message)[[:space:]=]+\"([^\"]*)\" ]]; do
        BODY+="${BASH_REMATCH[2]}"$'\n'
        scan="${scan/${BASH_REMATCH[0]}/}"
    done
fi

[[ -z "$BODY" ]] && exit 0

source "$(dirname "$0")/../../../smith-ctx-claude/scripts/attribution-lib.sh"
attribution_check_body "$BODY" || exit 2

exit 0
