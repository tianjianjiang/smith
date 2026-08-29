#!/bin/bash
#
# mark-session-restart.sh - SessionStart hook recording that the conversation
# actually restarted, and by which route.
#
# Register for BOTH `clear` and `compact`. Writes nothing to stdout.
# Rationale and the gate it feeds: references/HOOKS.md, "Session-restart marker".
#

source "$(dirname "$0")/lib-plan.sh"
require_jq

INPUT=$(cat)

HOOK_SOURCE=$(echo "$INPUT" | jq -r '.source // empty' 2>/dev/null || echo "")
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")

case "$HOOK_SOURCE" in
    clear|compact) ;;
    *) exit 0 ;;
esac

RESTART_CWD="${HOOK_CWD:-${PWD:-}}"
CWD_KEY=$(session_key "" "$RESTART_CWD") || {
    echo "Error: session_key failed" >&2; exit 1
}
MARKER_FILE="${PLANS_DIR}/.session-restart-${CWD_KEY}"

mkdir -p "$PLANS_DIR" 2>/dev/null || {
    echo "Error: cannot create plans directory: $PLANS_DIR" >&2; exit 1
}

TMP=$(mktemp "${PLANS_DIR}/.sr-tmp.XXXXXX") || {
    echo "Error: cannot create temp file in $PLANS_DIR" >&2; exit 1
}
if ! printf '%s\n%s\n%s\n' \
        "$HOOK_SOURCE" \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" \
        "$RESTART_CWD" > "$TMP" || ! mv -f "$TMP" "$MARKER_FILE"; then
    echo "Error: cannot write session-restart marker: $MARKER_FILE" >&2
    rm -f "$TMP" 2>/dev/null
    exit 1
fi

SENTINEL_FILE="${PLANS_DIR}/.sr-hook-installed"
if [[ "$HOOK_SOURCE" == "clear" ]] || [[ -e "$SENTINEL_FILE" ]]; then
    if STMP=$(mktemp "${PLANS_DIR}/.sr-tmp.XXXXXX" 2>/dev/null); then
        mv -f "$STMP" "$SENTINEL_FILE" 2>/dev/null || rm -f "$STMP" 2>/dev/null
    fi
fi

exit 0
