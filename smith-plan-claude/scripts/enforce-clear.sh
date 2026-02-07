#!/bin/bash
#
# enforce-clear.sh - Stop hook for plan-sync skill
#
# Blocks the agent from stopping when context is high and
# clear-and-reload hasn't been initiated. Ensures progress
# is saved before context is lost.
#
# Session Isolation: Uses CWD-based flag files so parallel Claude Code
# sessions (in different worktrees) don't interfere with each other.
#
# Conditions to block:
#   1. Transcript size > threshold
#   2. Active plan has pending tasks
#   3. No session-specific .pending-reload flag file (clear not yet initiated)
#
# Env vars:
#   PLAN_CONTEXT_THRESHOLD_KB - Threshold in KB (default: 500)
#

source "$(dirname "$0")/lib-common.sh"
require_jq

THRESHOLD_KB=${PLAN_CONTEXT_THRESHOLD_KB:-500}
THRESHOLD_BYTES=$((THRESHOLD_KB * 1024))

INPUT=$(cat)

# Extract session ID and CWD
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")

# CWD-keyed flag file (survives /clear; CWD persists, session_id does not)
CWD_KEY=$(cwd_key "${HOOK_CWD:-${PWD:-}}")
FLAG_FILE="${PLANS_DIR}/.pending-reload-${CWD_KEY}"

# If CWD-specific flag file exists, clear-and-reload was already initiated -> allow stop
if [[ -f "$FLAG_FILE" ]]; then
    exit 0
fi

# Check transcript size
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    exit 0
fi

TRANSCRIPT_SIZE=$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)
TRANSCRIPT_SIZE=$(echo "$TRANSCRIPT_SIZE" | tr -d '[:space:]')
if [[ $TRANSCRIPT_SIZE -le $THRESHOLD_BYTES ]]; then
    exit 0
fi

# Check if active plan has pending tasks (CWD-keyed state, no fallback)
STATE_FILE="${PLANS_DIR}/.plan-state-${CWD_KEY}"
ACTIVE_PLAN=""
if [[ -f "$STATE_FILE" ]]; then
    prev_plan=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
    if [[ -n "$prev_plan" ]] && [[ -f "$prev_plan" ]]; then
        ACTIVE_PLAN="$prev_plan"
    fi
fi
if [[ -z "$ACTIVE_PLAN" ]]; then
    exit 0
fi
PENDING=$(grep -c '^[[:space:]]*- \[ \]' "$ACTIVE_PLAN" 2>/dev/null || echo 0)
PENDING=$(echo "$PENDING" | tr -d '[:space:]')
if [[ $PENDING -eq 0 ]]; then
    exit 0
fi

# BLOCK: context is high, plan has pending tasks, clear not yet initiated
SIZE_KB=$((TRANSCRIPT_SIZE / 1024))

# Auto-create flag to break the loop.
# First block: flag created + block returned (agent gets one turn to save state).
# Second stop: flag exists -> allowed.
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S%z)
printf '%s\n%s\n%s\n%s\n' "$ACTIVE_PLAN" "$SESSION_ID" "$TIMESTAMP" "${HOOK_CWD:-${PWD:-}}" > "$FLAG_FILE"

json_stop_block "Context at ${SIZE_KB}KB with ${PENDING} pending plan tasks. Flag set for auto-reload after /clear. Before stopping: (1) Update plan file with current progress, (2) Write Serena memory with session state. Plan will auto-reload after /clear."
