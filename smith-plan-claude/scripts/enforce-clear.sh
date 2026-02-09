#!/bin/bash
#
# enforce-clear.sh - Unified stop hook for context management
#
# Blocks at 60% context (matching smith-ctx spec).
# Uses real token counts from transcript JSONL (same as statusline).
# Uses stop_hook_active (official best practice) for loop prevention.
#
# Session Isolation: Uses CWD-based flag files so parallel Claude Code
# sessions (in different worktrees) don't interfere with each other.
#
# Conditions to block:
#   1. stop_hook_active is false (not already continuing from a stop hook)
#   2. Context >= critical threshold (real token %)
#   3. For plan context: active plan has pending tasks
#   4. For non-plan context: always block above threshold
#
# Env vars:
#   PLAN_CONTEXT_CRITICAL_PCT - Critical threshold in % (default: 60)
#   CONTEXT_WINDOW_TOKENS - Context window size in tokens (default: 200000)
#

source "$(dirname "$0")/lib-common.sh"
require_jq

CRITICAL_PCT=${PLAN_CONTEXT_CRITICAL_PCT:-60}

INPUT=$(cat)

# Official best practice: if already continuing from a stop hook, allow stop
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
    exit 0
fi

# Ralph coordination: defer to inject-plan.sh + Ralph's own stop hook.
# inject-plan.sh already saved resume state and set max_iterations.
# We MUST NOT double-block or we create a deadlock.
RALPH_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
RALPH_RESUME="${PLANS_DIR}/.ralph-resume-$(cwd_key "${RALPH_CWD:-${PWD:-}}")"

if [[ -f "${RALPH_CWD:-.}/.claude/${RALPH_STATE_FILENAME}" ]] || [[ -f "$RALPH_RESUME" ]]; then
    exit 0
fi

# Orchestrator coordination: defer to inject-plan.sh for context management.
# inject-plan.sh saves orchestrator resume state at warning/critical thresholds.
ORCH_CWD_KEY=$(cwd_key "${RALPH_CWD:-${PWD:-}}")
ORCH_STATE="${PLANS_DIR}/${ORCH_STATE_PREFIX}${ORCH_CWD_KEY}"
ORCH_RESUME="${PLANS_DIR}/.ralph-orch-resume-${ORCH_CWD_KEY}"

if [[ -f "$ORCH_STATE" ]] || [[ -f "$ORCH_RESUME" ]]; then
    exit 0
fi

# Extract fields
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")

if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    exit 0
fi

# Real context percentage from transcript token usage
CONTEXT_PCT=$(get_context_percentage "$TRANSCRIPT_PATH" "$CONTEXT_WINDOW_TOKENS")

if [[ $CONTEXT_PCT -lt $CRITICAL_PCT ]]; then
    exit 0
fi

# CWD-keyed identifiers
CWD_KEY=$(cwd_key "${HOOK_CWD:-${PWD:-}}")
FLAG_FILE="${PLANS_DIR}/.pending-reload-${CWD_KEY}"
STATE_FILE="${PLANS_DIR}/.plan-state-${CWD_KEY}"

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

# Create pending-reload flag if plan active with pending tasks
if [[ -n "$ACTIVE_PLAN" ]] && [[ $PENDING -gt 0 ]]; then
    TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S%z)
    printf '%s\n%s\n%s\n%s\n' "$ACTIVE_PLAN" "$SESSION_ID" "$TIMESTAMP" \
        "${HOOK_CWD:-${PWD:-}}" > "$FLAG_FILE"
fi

# Build message (plan-first, Serena optional)
if [[ -n "$ACTIVE_PLAN" ]] && [[ $PENDING -gt 0 ]]; then
    json_stop_block "Context at ${CONTEXT_PCT}% with ${PENDING} pending tasks.

**YOU MUST do these steps NOW (before user runs /clear):**
1. Update plan: mark completed tasks (- [ ] -> - [x]) in plan file
2. Commit uncommitted work
3. If Serena MCP available: write_memory() with descriptive name (task, decisions, next steps, file:line refs)
4. AFTER all tool calls complete, output this block:

**Reload with:**
- Plan: \`${ACTIVE_PLAN}\`
- Memory: \`<name from step 3>\` (read via read_memory() after /clear)
- Resume: <describe current task>"
elif [[ -n "$ACTIVE_PLAN" ]]; then
    # Plan exists but no pending tasks
    json_stop_block "Context at ${CONTEXT_PCT}%. Plan completed.

**YOU MUST do these steps NOW:**
1. Commit uncommitted work
2. If Serena MCP available: write_memory() with descriptive name (summary of completed work)
3. AFTER all tool calls complete, output this block:

**Reload with:**
- Plan: \`${ACTIVE_PLAN}\` (completed)
- Memory: \`<name from step 3>\` (read via read_memory() after /clear)
- Resume: <describe completed work>"
else
    # No plan context
    json_stop_block "Context at ${CONTEXT_PCT}%.

**YOU MUST do these steps NOW:**
1. Commit uncommitted work
2. If Serena MCP available: write_memory() with descriptive name (task, decisions, next steps, file:line refs)
3. AFTER all tool calls complete, output this block:

**Reload with:**
- Memory: \`<name from step 3>\` (read via read_memory() after /clear)
- Resume: <describe current task>"
fi
