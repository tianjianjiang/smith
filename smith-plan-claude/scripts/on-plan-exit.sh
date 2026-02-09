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
    ACTIVE_PLAN=$(ls -t "$PLANS_DIR"/*.md 2>/dev/null | head -1) || ACTIVE_PLAN=""
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
MSG=$(printf '**PLAN EXIT - CLEAR-AND-RESUME READY**\n\nPlan: `%s`\nFile: `%s`\n\n**Next steps:**\n1. Update plan if needed: `%s`\n2. Commit uncommitted work\n3. If Serena MCP available: write_memory() with descriptive name (task, decisions, next steps)\n4. AFTER all tool calls complete, output this block:\n\n**Reload with:**\n- Plan: `%s`\n- Resume: <describe current task>\n\n5. Run /clear to free context\n6. Type any prompt - plan auto-reloads with todos and skills, Serena memory auto-restores via list_memories()\n\n**Note:** If you selected "clear context and auto-accept edits", plan will auto-reload on next prompt.' \
    "$BASENAME" "$ACTIVE_PLAN" "$ACTIVE_PLAN" "$ACTIVE_PLAN")

json_post_tool_output "$MSG"

exit 0
