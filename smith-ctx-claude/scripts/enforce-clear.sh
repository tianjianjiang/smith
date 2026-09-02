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
PLAN_LIB="${SMITH_PLAN_LIB:-${SCRIPT_DIR}/../../smith-plan-claude/scripts/lib-plan.sh}"
if [[ -f "$PLAN_LIB" ]]; then
    source "$PLAN_LIB"
    PLAN_LIB_AVAILABLE=true
else
    PLAN_LIB_AVAILABLE=false
fi

require_jq

CRITICAL_PCT=${CTX_CONTEXT_CRITICAL_PCT:-60}

INPUT=$(cat)

read -r STOP_HOOK_ACTIVE SESSION_ID HOOK_CWD TRANSCRIPT_PATH < <(
    echo "$INPUT" | jq -r '[
        (.stop_hook_active // false | tostring),
        (.session_id // ""),
        (.cwd // ""),
        (.transcript_path // "")
    ] | @tsv' 2>/dev/null
) || { STOP_HOOK_ACTIVE="false"; SESSION_ID=""; HOOK_CWD=""; TRANSCRIPT_PATH=""; }

# Official best practice: if already continuing from a stop hook, allow stop
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
    exit 0
fi
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

check_resume_allowed() {
    local state_fn="$1" state_arg="$2" resume_file="$3"
    { type "$state_fn" &>/dev/null && "$state_fn" "$state_arg" 2>/dev/null; } && return 0
    [[ -f "$resume_file" ]] && return 0
    return 1
}


if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    exit 0
fi

# Real context percentage from transcript token usage
CONTEXT_PCT=$(resolve_context_percentage "$TRANSCRIPT_PATH" "$CWD_KEY")

if [[ $CONTEXT_PCT -lt $CRITICAL_PCT ]]; then
    exit 0
fi

STATE_FILE="${FLAGS_DIR}/.plan-state-${CWD_KEY}"

ACTIVE_PLAN=""
PENDING=0
if [[ -f "$STATE_FILE" ]]; then
    prev_plan=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
    if [[ -n "$prev_plan" ]] && [[ -f "$prev_plan" ]]; then
        ACTIVE_PLAN="$prev_plan"
    fi
fi

if [[ -z "$ACTIVE_PLAN" ]] && [[ "$PLAN_LIB_AVAILABLE" == "true" ]] && type newest_adoptable_plan &>/dev/null; then
    newest_adoptable_plan "" "$(scope_key "${HOOK_CWD:-${PWD:-}}")"
    ACTIVE_PLAN="$NEWEST_ADOPTABLE"
fi

if [[ -n "$ACTIVE_PLAN" ]]; then
    PENDING=$(grep -c '^[[:space:]]*- \[ \]' "$ACTIVE_PLAN" 2>/dev/null || echo 0)
    PENDING=$(echo "$PENDING" | tr -d '[:space:]')
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

generate_checkpoint_label_from_plan() {
    local plan_path="$1"
    basename "$plan_path" .md | tr '[:upper:]' '[:lower:]' | tr '-' '_'
}

generate_checkpoint_label_from_cwd() {
    local cwd="$1"
    local cwd_basename=$(basename "$cwd" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]' '_' | sed 's/__*/_/g;s/^_//;s/_$//')
    echo "${cwd_basename}_checkpoint"
}

CHECKPOINT_LABEL=""
if [[ -n "$ACTIVE_PLAN" ]]; then
    CHECKPOINT_LABEL=$(generate_checkpoint_label_from_plan "$ACTIVE_PLAN")
elif [[ -n "$COMPLETED_PLAN" ]]; then
    CHECKPOINT_LABEL=$(generate_checkpoint_label_from_plan "$COMPLETED_PLAN")
else
    CONSOLIDATED_PLAN="$HOME/.claude/plans/smith-consolidated-plan.md"
    if [[ -f "$CONSOLIDATED_PLAN" ]]; then
        CHECKPOINT_LABEL="consolidated_plan_checkpoint"
        ACTIVE_PLAN="$CONSOLIDATED_PLAN"
        FLAG_TYPE="plan-pending"
        PENDING=$(grep -c '^[[:space:]]*- \[ \]' "$ACTIVE_PLAN" 2>/dev/null || echo 0)
        PENDING=$(echo "$PENDING" | tr -d '[:space:]')
    else
        CHECKPOINT_LABEL=$(generate_checkpoint_label_from_cwd "${HOOK_CWD:-${PWD:-}}")
    fi
fi

case "$FLAG_TYPE" in
    plan-pending)
        STATUS="Context at ${CONTEXT_PCT}% (${PENDING} pending). Plan: ${ACTIVE_PLAN}"
        INVOKE="/smith-checkpoint \"${CHECKPOINT_LABEL}\" plan=\`${ACTIVE_PLAN}\`"
        ;;
    plan-completed)
        STATUS="Context at ${CONTEXT_PCT}% (plan completed). Plan: ${COMPLETED_PLAN}"
        INVOKE="/smith-checkpoint \"${CHECKPOINT_LABEL}\" plan=\`${COMPLETED_PLAN}\`"
        ;;
    *)
        STATUS="Context at ${CONTEXT_PCT}%"
        INVOKE="/smith-checkpoint \"${CHECKPOINT_LABEL}\""
        ;;
esac

json_stop_block "${STATUS}

Invoke: ${INVOKE}"
