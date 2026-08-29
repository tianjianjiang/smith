#!/bin/bash
#
# context-warning.sh - UserPromptSubmit hook for 50% context warning
#
# Injects a warning into additionalContext when context usage exceeds 50%.
# Uses lib-context.sh for token-based percentage calculation (DRY).
#
# Canonical location: smith-ctx-claude (context management foundation).
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib-context.sh"

require_jq

WARNING_PCT=${CTX_CONTEXT_WARNING_PCT:-50}
CRITICAL_PCT=${CTX_CONTEXT_CRITICAL_PCT:-60}

INPUT=$(cat)

HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")

if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    exit 0
fi

CWD_KEY=$(session_key "" "${HOOK_CWD:-${PWD:-}}") || exit 0

CONTEXT_PCT=$(resolve_context_percentage "$TRANSCRIPT_PATH" "$CWD_KEY")

if [[ $CONTEXT_PCT -lt $WARNING_PCT ]]; then
    exit 0
fi

if [[ $CONTEXT_PCT -ge $CRITICAL_PCT ]]; then
    MSG="Context at ${CONTEXT_PCT}% (critical). Checkpoint work, then /clear."
else
    MSG="Context at ${CONTEXT_PCT}% (warning). Consider /compact or prepare for /clear."
fi

jq -n --arg msg "$MSG" '{
    hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: $msg
    }
}'
