#!/bin/bash
#
# on-plan-exit.sh - PostToolUse hook for ExitPlanMode
#
# Creates a CWD-specific .pending-reload flag file when Claude exits plan mode,
# enabling auto-reload of the plan after /clear.
#
# Session Isolation: Uses CWD-based flag files so parallel Claude Code
# sessions (in different worktrees) don't interfere with each other.
#

source "$(dirname "$0")/lib-common.sh"
require_jq

INPUT=$(cat)

# Extract session ID and CWD
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")

# CWD-keyed flag file (survives /clear; CWD persists, session_id does not)
CWD_KEY=$(cwd_key "${HOOK_CWD:-${PWD:-}}")
FLAG_FILE="${PLANS_DIR}/.pending-reload-${CWD_KEY}"

# CWD-keyed state file (survives /clear; tracks plan, transcript state)
STATE_FILE="${PLANS_DIR}/.plan-state-${CWD_KEY}"
ACTIVE_PLAN=""
if [[ -f "$STATE_FILE" ]]; then
    prev_plan=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
    if [[ -n "$prev_plan" ]] && [[ -f "$prev_plan" ]]; then
        ACTIVE_PLAN="$prev_plan"
    fi
fi
if [[ -z "$ACTIVE_PLAN" ]]; then
    ACTIVE_PLAN=$(ls -t "$PLANS_DIR"/*.md 2>/dev/null | head -1)
fi
if [[ -z "$ACTIVE_PLAN" ]] || [[ ! -f "$ACTIVE_PLAN" ]]; then
    exit 0
fi

# Write flag file (4 lines: plan path, session ID, timestamp, CWD)
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S%z)
printf '%s\n%s\n%s\n%s\n' "$ACTIVE_PLAN" "$SESSION_ID" "$TIMESTAMP" "${HOOK_CWD:-${PWD:-}}" > "$FLAG_FILE"

# Write state file so future hooks find the active plan via CWD-keyed state
printf '%s\n%s\n%s\n%s\n%s\n' \
    "${SESSION_ID:-unknown}" \
    "unknown" \
    "0" \
    "$TIMESTAMP" \
    "$ACTIVE_PLAN" > "$STATE_FILE"

BASENAME=$(basename "$ACTIVE_PLAN")
MSG=$(printf 'Plan `%s` flagged for auto-reload (cwd: `%s`).\n\nRun `/clear` to free context, then type any prompt to continue with the plan.' \
    "$BASENAME" "$CWD_KEY")

json_post_tool_output "$MSG"

exit 0
