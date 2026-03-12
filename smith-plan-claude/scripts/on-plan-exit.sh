#!/bin/bash
#
# on-plan-exit.sh - PostToolUse hook for ExitPlanMode
#
# Creates a CWD-specific .pending-reload flag file when Claude exits plan mode,
# enabling auto-reload of the plan after /clear.
#
# Session Isolation: Uses PPID:CWD-based flag files so parallel Claude Code
# sessions (even in the same CWD) don't interfere with each other.
#

source "$(dirname "$0")/lib-common.sh"
require_jq

INPUT=$(cat)

# Extract session ID and CWD
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")

# Session-keyed flag file (survives /clear; PPID:CWD persists, session_id does not)
CWD_KEY=$(session_key "" "${HOOK_CWD:-${PWD:-}}") || {
    echo "Error: session_key failed" >&2; exit 1
}
FLAG_FILE="${PLANS_DIR}/.pending-reload-${CWD_KEY}"

# Session-keyed state file (survives /clear; tracks plan, transcript state)
STATE_FILE="${PLANS_DIR}/.plan-state-${CWD_KEY}"
ACTIVE_PLAN=""
if [[ -f "$STATE_FILE" ]]; then
    prev_plan=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
    if [[ -n "$prev_plan" ]] && [[ -f "$prev_plan" ]]; then
        ACTIVE_PLAN="$prev_plan"
    fi
fi
if [[ -z "$ACTIVE_PLAN" ]]; then
    ACTIVE_PLAN=$(ls -t "$PLANS_DIR"/*.md 2>/dev/null | head -1) || ACTIVE_PLAN=""
fi
if [[ -z "$ACTIVE_PLAN" ]] || [[ ! -f "$ACTIVE_PLAN" ]]; then
    exit 0
fi

# Write flag file (5 lines: plan path, session ID, timestamp, CWD, flag type)
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S%z)
PENDING=$(grep -c '^[[:space:]]*- \[ \]' "$ACTIVE_PLAN" 2>/dev/null || echo 0)
FLAG_TYPE=$([[ "$PENDING" -gt 0 ]] && echo "plan-pending" || echo "plan-completed")
printf '%s\n%s\n%s\n%s\n%s\n' "$ACTIVE_PLAN" "$SESSION_ID" "$TIMESTAMP" "${HOOK_CWD:-${PWD:-}}" "$FLAG_TYPE" > "$FLAG_FILE"

# Write state file so future hooks find the active plan via session-keyed state
save_state_file "$STATE_FILE" "${SESSION_ID:-unknown}" "unknown" "$ACTIVE_PLAN"

# Exit-marker: signals enforce-clear.sh to allow the stop (defense-in-depth)
touch "${FLAG_FILE}.exit-marker"

json_post_tool_output "PLAN EXIT registered. Auto-resume flag created for /clear."

exit 0
