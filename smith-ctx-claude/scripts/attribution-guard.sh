#!/usr/bin/env bash
input=$(cat)
if ! command -v node >/dev/null 2>&1; then
    subject=$(printf '%s' "$input" | jq -r '(.tool_input.command // .tool_name) // empty' 2>/dev/null) || subject="$input"
    [[ "$subject" == *git* || "$subject" == *gh* || "$subject" == *slack_send_message_draft* ]] || exit 0
    echo "attribution-guard: node not found, so the call is blocked" >&2
    exit 2
fi
printf '%s' "$input" | node "$(dirname "$0")/attribution-guard.mjs"
status=$?
if [[ $status -ne 0 && $status -ne 2 ]]; then
    echo "attribution-guard: the guard failed (exit $status), so the call is blocked" >&2
    exit 2
fi
exit "$status"
