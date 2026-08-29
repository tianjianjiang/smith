#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib-context.sh"
source "${SCRIPT_DIR}/lib-context-instructions.sh"

require_jq

WARNING_PCT=${CTX_CONTEXT_WARNING_PCT:-50}
CRITICAL_PCT=${CTX_CONTEXT_CRITICAL_PCT:-60}

INPUT=$(cat)

read -r HOOK_CWD TRANSCRIPT_PATH < <(
    echo "$INPUT" | jq -r '[(.cwd // ""), (.transcript_path // "")] | @tsv' 2>/dev/null
) || { HOOK_CWD=""; TRANSCRIPT_PATH=""; }

if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    exit 0
fi

CWD_KEY=$(session_key "" "${HOOK_CWD:-${PWD:-}}") || exit 0

CONTEXT_PCT=$(resolve_context_percentage "$TRANSCRIPT_PATH" "$CWD_KEY")

if [[ $CONTEXT_PCT -lt $WARNING_PCT ]]; then
    exit 0
fi

if [[ $CONTEXT_PCT -ge $CRITICAL_PCT ]]; then
    MSG="context: ${CONTEXT_PCT}% | warn: ${WARNING_PCT}% | crit: ${CRITICAL_PCT}% | action: save, /clear"
else
    MSG="context: ${CONTEXT_PCT}% | warn: ${WARNING_PCT}% | crit: ${CRITICAL_PCT}%"
fi

if [[ $CONTEXT_PCT -ge $WARNING_PCT ]] && [[ $CONTEXT_PCT -lt $CRITICAL_PCT ]]; then
    FLAGS_DIR="$CTX_FLAGS_DIR"
    STATE_FILE="${FLAGS_DIR}/.plan-state-${CWD_KEY}"
    PLAN_PATH=""
    PENDING=0
    if [[ -f "$STATE_FILE" ]]; then
        prev_plan=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
        if [[ -n "$prev_plan" ]] && [[ -f "$prev_plan" ]]; then
            PLAN_PATH="$prev_plan"
            PENDING=$(grep -c '^[[:space:]]*- \[ \]' "$PLAN_PATH" 2>/dev/null || echo 0)
        fi
    fi

    INSTRUCTIONS=$(render_warning_generic "$PLAN_PATH" "$PENDING" "$CRITICAL_PCT" "$CONTEXT_PCT" "$WARNING_PCT")
    MSG+=$(printf '\n\n%s' "$INSTRUCTIONS")
fi

json_hook_output "UserPromptSubmit" "$MSG"
