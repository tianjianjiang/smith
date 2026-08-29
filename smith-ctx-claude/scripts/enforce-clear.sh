#!/bin/bash
#
# enforce-clear.sh - Unified Stop hook for context management
#
# Canonical location: smith-ctx-claude (context management foundation).
# Handles both plan and non-plan contexts (single hook design).
#
# Blocks at 60% context using real token counts from transcript JSONL.
# Uses stop_hook_active (official best practice) for loop prevention.
#
# Session Isolation: Uses PPID:CWD-based flag files so parallel Claude Code
# sessions (even in the same CWD) don't interfere with each other.
#
# Env vars:
#   CTX_CONTEXT_CRITICAL_PCT - Critical threshold in % (default: 60)
#   CONTEXT_WINDOW_TOKENS - Fallback context window size (default: 200000)
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source context functions (canonical location)
source "${SCRIPT_DIR}/lib-context.sh"

# Source plan-claude's lib for plan/Ralph/Orchestrator functions (optional)
PLAN_LIB="${SCRIPT_DIR}/../../smith-plan-claude/scripts/lib-plan.sh"
if [[ -f "$PLAN_LIB" ]]; then
    source "$PLAN_LIB"
    PLAN_LIB_AVAILABLE=true
else
    PLAN_LIB_AVAILABLE=false
fi

require_jq

CRITICAL_PCT=${CTX_CONTEXT_CRITICAL_PCT:-60}

INPUT=$(cat)

# Official best practice: if already continuing from a stop hook, allow stop
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
    exit 0
fi

# Extract fields
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
CWD_KEY=$(session_key "" "${HOOK_CWD:-${PWD:-}}") || {
    echo "Error: session_key failed" >&2
    exit 1
}

# Flag directory (shared constant from lib-context.sh)
FLAGS_DIR="$CTX_FLAGS_DIR"

# CWD-keyed flag file
FLAG_FILE="${FLAGS_DIR}/.pending-reload-${CWD_KEY}"

# If ExitPlanMode just fired, on-plan-exit.sh left a marker. Allow the stop.
EXIT_MARKER="${FLAG_FILE}.exit-marker"
if [[ -f "$EXIT_MARKER" ]]; then
    marker_session=$(sed -n '2p' "$FLAG_FILE" 2>/dev/null || true)
    rm -f "$EXIT_MARKER"
    if [[ "$marker_session" == "$SESSION_ID" ]]; then
        exit 0
    fi
fi

# Ralph/Orchestrator coordination (only if plan lib available)
if [[ "$PLAN_LIB_AVAILABLE" == "true" ]]; then
    RALPH_RESUME="${FLAGS_DIR}/.ralph-resume-${CWD_KEY}"
    if type get_ralph_state &>/dev/null && get_ralph_state "${HOOK_CWD:-.}" 2>/dev/null; then
        exit 0
    fi
    if [[ -f "$RALPH_RESUME" ]]; then
        exit 0
    fi

    ORCH_RESUME="${FLAGS_DIR}/.ralph-orch-resume-${CWD_KEY}"
    if type get_orchestrator_state &>/dev/null && get_orchestrator_state "$CWD_KEY" 2>/dev/null; then
        exit 0
    fi
    if [[ -f "$ORCH_RESUME" ]]; then
        exit 0
    fi
fi

if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    exit 0
fi

# Real context percentage from transcript token usage
CONTEXT_PCT=$(resolve_context_percentage "$TRANSCRIPT_PATH" "$CWD_KEY")

if [[ $CONTEXT_PCT -lt $CRITICAL_PCT ]]; then
    exit 0
fi

STATE_FILE="${FLAGS_DIR}/.plan-state-${CWD_KEY}"

# Check for active plan
ACTIVE_PLAN=""
PENDING=0
if [[ -f "$STATE_FILE" ]]; then
    prev_plan=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
    if [[ -n "$prev_plan" ]] && [[ -f "$prev_plan" ]]; then
        ACTIVE_PLAN="$prev_plan"
        PENDING=$(grep -c '^[[:space:]]*- \[ \]' "$ACTIVE_PLAN" 2>/dev/null || echo 0)
        PENDING=$(echo "$PENDING" | tr -d '[:space:]')
    fi
fi

# Create pending-reload flag
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S%z)
COMPLETED_PLAN=""
if [[ -n "$ACTIVE_PLAN" ]] && [[ $PENDING -gt 0 ]]; then
    FLAG_TYPE="plan-pending"
elif [[ -n "$ACTIVE_PLAN" ]]; then
    FLAG_TYPE="plan-completed"
    COMPLETED_PLAN="$ACTIVE_PLAN"
    ACTIVE_PLAN=""
else
    FLAG_TYPE="no-plan"
fi
printf '%s\n%s\n%s\n%s\n%s\n' "$ACTIVE_PLAN" "$SESSION_ID" "$TIMESTAMP" \
    "${HOOK_CWD:-${PWD:-}}" "$FLAG_TYPE" > "$FLAG_FILE"

# Refresh state file (only if plan lib available)
if [[ "$PLAN_LIB_AVAILABLE" == "true" ]] && type save_state_file &>/dev/null; then
    save_state_file "$STATE_FILE" "$SESSION_ID" "$TRANSCRIPT_PATH" "$ACTIVE_PLAN" \
        "$(scope_key "${HOOK_CWD:-${PWD:-}}")"
fi

# Build message (DRY: common structure, parameterized differences)
# MECE: DO = actions to execute, OUTPUT = text to produce
case "$FLAG_TYPE" in
    plan-pending)
        STATUS="Context at ${CONTEXT_PCT}% (${PENDING} pending). Plan: ${ACTIVE_PLAN}"
        ACTIONS="mark done tasks in plan, commit, write_memory() if Serena"
        RELOAD="plan=\`${ACTIVE_PLAN}\` mem=«name» task=«description»"
        ;;
    plan-completed)
        STATUS="Context at ${CONTEXT_PCT}% (plan completed). Plan: ${COMPLETED_PLAN}"
        ACTIONS="commit, write_memory() if Serena"
        RELOAD="plan=\`${COMPLETED_PLAN}\` (done) mem=«name» task=«summary»"
        ;;
    *)
        STATUS="Context at ${CONTEXT_PCT}%"
        ACTIONS="commit, write_memory() if Serena"
        RELOAD="mem=«name» task=«description»"
        ;;
esac

json_stop_block "${STATUS}

DO: ${ACTIONS}

OUTPUT (fill «placeholders»):
Reload: ${RELOAD}"
