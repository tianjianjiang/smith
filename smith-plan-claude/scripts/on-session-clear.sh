#!/bin/bash
#
# on-session-clear.sh - SessionStart:clear hook for plan injection
#
# Fires after manual /clear. Reads plan from .plan-state-<cwd-hash>
# and injects plan content with skill/todo instructions.
#
# This is the reliable injection point for post-/clear plan restoration.
# Unlike UserPromptSubmit heuristics, this fires exactly once after /clear.
#
# Known limitation: Does NOT fire when plan mode exits via "clear context
# and auto-accept edits" (upstream bug #20900). The inject-plan.sh
# heuristic detection remains as fallback for that case.
#
# Session Isolation: Uses CWD-based state files so parallel Claude Code
# sessions (in different worktrees) don't interfere with each other.
#

source "$(dirname "$0")/lib-common.sh"
require_jq

INPUT=$(cat)

# Extract CWD from hook input
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
CWD_KEY=$(cwd_key "${HOOK_CWD:-${PWD:-}}")
STATE_FILE="${PLANS_DIR}/.plan-state-${CWD_KEY}"
FLAG_FILE="${PLANS_DIR}/.pending-reload-${CWD_KEY}"

# Try to find plan from state file
PLAN_FILE=""
if [[ -f "$STATE_FILE" ]]; then
    STATE_FRESH=$(find "$STATE_FILE" -mmin -60 2>/dev/null)
    if [[ -n "$STATE_FRESH" ]]; then
        PLAN_FILE=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
        if [[ -n "$PLAN_FILE" ]] && [[ ! -f "$PLAN_FILE" ]]; then
            PLAN_FILE=""
        fi
    fi
fi

# --- Ralph resume detection (shared by both plan and no-plan paths) ---
RALPH_RESUME_DIRECTIVE=""
if read_ralph_resume "$CWD_KEY"; then
    # Calculate remaining iterations (min 10 if exhausted)
    RALPH_REMAINING=10
    if [[ -n "$RALPH_RESUME_MAX_ITER" ]] && [[ "$RALPH_RESUME_MAX_ITER" =~ ^[0-9]+$ ]] && \
       [[ -n "$RALPH_RESUME_ITERATION" ]] && [[ "$RALPH_RESUME_ITERATION" =~ ^[0-9]+$ ]]; then
        RALPH_REMAINING=$(( RALPH_RESUME_MAX_ITER - RALPH_RESUME_ITERATION ))
        if [[ $RALPH_REMAINING -lt 10 ]]; then
            RALPH_REMAINING=10
        fi
    fi

    # Build Skill tool args: prompt --completion-promise 'promise' --max-iterations N
    RALPH_SKILL_ARGS="${RALPH_RESUME_PROMPT:-continue}"
    if [[ -n "$RALPH_RESUME_PROMISE" ]]; then
        RALPH_SKILL_ARGS+=" --completion-promise '${RALPH_RESUME_PROMISE}'"
    fi
    RALPH_SKILL_ARGS+=" --max-iterations ${RALPH_REMAINING}"

    RALPH_RESUME_DIRECTIVE="\n\n**RALPH LOOP AUTO-RESUME:**"
    RALPH_RESUME_DIRECTIVE+="\n1. If Serena MCP available: read_memory() for ralph_*_state"
    RALPH_RESUME_DIRECTIVE+="\n2. Restore iteration context from memory"
    RALPH_RESUME_DIRECTIVE+="\n3. Auto-start Ralph loop NOW using Skill tool:"
    RALPH_RESUME_DIRECTIVE+="\n   Skill(skill: \"ralph-loop:ralph-loop\", args: \"${RALPH_SKILL_ARGS}\")"
    RALPH_RESUME_DIRECTIVE+="\n4. Do NOT ask user for permission - auto-invoke immediately after memory restore"

    # Clean up resume files (consumed)
    rm -f "${PLANS_DIR}/.ralph-resume-${CWD_KEY}" "${PLANS_DIR}/.ralph-resume-${CWD_KEY}.prompt" 2>/dev/null
fi

# Proactive phase resume: Ralph state file exists but no resume files.
# This covers the phase-boundary exit path where the agent exited Ralph
# normally (via promise) and no context threshold was hit.
if [[ -z "$RALPH_RESUME_DIRECTIVE" ]]; then
    if check_ralph_recently_active "${HOOK_CWD:-${PWD:-.}}"; then
        RALPH_RESUME_DIRECTIVE="\n\n**RALPH LOOP PHASE RESUME:**"
        RALPH_RESUME_DIRECTIVE+="\nPrevious session used ralph-loop (state file found in CWD)."
        RALPH_RESUME_DIRECTIVE+="\n1. read_memory() for ralph_* state (phase progress, iteration context)"
        RALPH_RESUME_DIRECTIVE+="\n2. If phase work remains: auto-invoke Skill(skill: \"ralph-loop:ralph-loop\")"
        RALPH_RESUME_DIRECTIVE+="\n   Pass the original prompt and remaining iterations from memory"
        RALPH_RESUME_DIRECTIVE+="\n3. Do NOT ask user for permission - auto-invoke if ralph state found in memory"
    fi
fi

# --- Orchestrator resume detection (Pattern B) ---
ORCH_RESUME_DIRECTIVE=""
if read_orchestrator_resume "$CWD_KEY"; then
    ORCH_RESUME_DIRECTIVE="\n\n**RALPH ORCHESTRATOR AUTO-RESUME (Pattern B):**"
    ORCH_RESUME_DIRECTIVE+="\nPrevious session was running orchestration mode."
    ORCH_RESUME_DIRECTIVE+="\n1. If Serena MCP available: read_memory() for orchestrator state"
    ORCH_RESUME_DIRECTIVE+="\n2. Read plan file: \`${ORCH_RESUME_PLAN_PATH:-unknown}\`"
    ORCH_RESUME_DIRECTIVE+=$(printf '\n3. Resume from iteration %s, task: %s' "${ORCH_RESUME_ITERATION:-?}" "${ORCH_RESUME_CURRENT_TASK:-unknown}")
    ORCH_RESUME_DIRECTIVE+="\n4. Continue orchestration: parse remaining \`- [ ]\` tasks, spawn workers via Task tool"
    ORCH_RESUME_DIRECTIVE+="\n5. Do NOT ask user for permission - auto-resume orchestration"

    # Clean up resume file (consumed)
    rm -f "${PLANS_DIR}/.ralph-orch-resume-${CWD_KEY}" 2>/dev/null
fi

# No plan found -- still offer plan listing + Serena memory restoration
if [[ -z "$PLAN_FILE" ]]; then
    # List available plans so the agent knows what exists
    AVAILABLE_PLANS=""
    if [[ -d "$PLANS_DIR" ]]; then
        while IFS= read -r f; do
            AVAILABLE_PLANS+="\n  - \`$(basename "$f")\` (\`$f\`)"
        done < <(ls -t "$PLANS_DIR"/*.md 2>/dev/null)
    fi

    ACTION_DIRECTIVE="**ACTION REQUIRED - POST-CLEAR RESUME:**"
    ACTION_DIRECTIVE+="\n\nYou MUST check for previous session state before responding."
    if [[ -n "$AVAILABLE_PLANS" ]]; then
        ACTION_DIRECTIVE+="\n\n**Available plans in \`${PLANS_DIR}\`:**${AVAILABLE_PLANS}"
    else
        ACTION_DIRECTIVE+="\n\n**Plans directory:** \`${PLANS_DIR}\` (no plan files found)"
    fi
    ACTION_DIRECTIVE+="\n\n1. If Serena MCP available: call list_memories() IMMEDIATELY"
    ACTION_DIRECTIVE+="\n2. Scan memory names for recent session context (session, task, plan keywords)"
    ACTION_DIRECTIVE+="\n3. Read relevant memories and report restored context to user"
    ACTION_DIRECTIVE+="\n4. Offer to continue previous work or await new instructions"
    if [[ -n "$RALPH_RESUME_DIRECTIVE" ]]; then
        ACTION_DIRECTIVE+="$RALPH_RESUME_DIRECTIVE"
    fi
    if [[ -n "$ORCH_RESUME_DIRECTIVE" ]]; then
        ACTION_DIRECTIVE+="$ORCH_RESUME_DIRECTIVE"
    fi
    ACTION_DIRECTIVE+="\n\nDo NOT skip this. Do NOT respond with \"Ready for your next task.\""
    ACTION_DIRECTIVE+="\nIf user's message contains a specific request, address that first but still restore context."
    rm -f "$FLAG_FILE" 2>/dev/null

    json_session_start_output "$(printf '%b' "$ACTION_DIRECTIVE")"
    exit 0
fi

# Read plan content fresh from disk
if ! PLAN_CONTENT=$(cat "$PLAN_FILE" 2>/dev/null); then
    # Plan file unreadable -- fall through with plan path hint + Serena directive
    ACTION_DIRECTIVE="**ACTION REQUIRED - POST-CLEAR RESUME:**"
    ACTION_DIRECTIVE+="\n\nYou MUST check for previous session state before responding."
    ACTION_DIRECTIVE+="\n\n**Expected plan:** \`${PLAN_FILE}\` (unreadable)"
    ACTION_DIRECTIVE+="\n**Plans directory:** \`${PLANS_DIR}\`"
    ACTION_DIRECTIVE+="\n\n1. If Serena MCP available: call list_memories() IMMEDIATELY"
    ACTION_DIRECTIVE+="\n2. Scan memory names for recent session context (session, task, plan keywords)"
    ACTION_DIRECTIVE+="\n3. Read relevant memories and report restored context to user"
    ACTION_DIRECTIVE+="\n4. Offer to continue previous work or await new instructions"
    if [[ -n "$RALPH_RESUME_DIRECTIVE" ]]; then
        ACTION_DIRECTIVE+="$RALPH_RESUME_DIRECTIVE"
    fi
    if [[ -n "$ORCH_RESUME_DIRECTIVE" ]]; then
        ACTION_DIRECTIVE+="$ORCH_RESUME_DIRECTIVE"
    fi
    ACTION_DIRECTIVE+="\n\nDo NOT skip this. Do NOT respond with \"Ready for your next task.\""
    ACTION_DIRECTIVE+="\nIf user's message contains a specific request, address that first but still restore context."
    rm -f "$FLAG_FILE" 2>/dev/null
    json_session_start_output "$(printf '%b' "$ACTION_DIRECTIVE")"
    exit 0
fi
PLAN_BASENAME=$(basename "$PLAN_FILE")

# Get modification time (macOS first, then Linux fallback)
PLAN_MODIFIED=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$PLAN_FILE" 2>/dev/null) || \
    PLAN_MODIFIED=$(stat -c %y "$PLAN_FILE" 2>/dev/null | cut -d'.' -f1) || \
    PLAN_MODIFIED="unknown"

# Calculate progress
TOTAL=$(echo "$PLAN_CONTENT" | grep -c '^[[:space:]]*- \[.\]' || true)
TOTAL=${TOTAL:-0}
COMPLETED=$(echo "$PLAN_CONTENT" | grep -c '^[[:space:]]*- \[x\]' || true)
COMPLETED=${COMPLETED:-0}

if [[ $TOTAL -gt 0 ]]; then
    PERCENT=$((COMPLETED * 100 / TOTAL))
    PROGRESS="${COMPLETED}/${TOTAL} tasks (${PERCENT}%)"
else
    PROGRESS="No trackable tasks found"
fi

CURRENT_TASK=$(echo "$PLAN_CONTENT" | grep -m1 '^[[:space:]]*- \[ \]' | sed 's/^[[:space:]]*- \[ \] //') || CURRENT_TASK=""
CURRENT_TASK=${CURRENT_TASK:-None}

# Build injection content
ACTION_DIRECTIVE="**ACTION REQUIRED - POST-CLEAR RESUME:**"
ACTION_DIRECTIVE+="\n\n1. Reconstruct todos from plan checkboxes:"
ACTION_DIRECTIVE+="\n   - For each \`- [ ]\` task: TaskCreate(subject=task_text, description=\"From plan\", activeForm=\"Working on ...\")"
ACTION_DIRECTIVE+="\n   - Set first task: TaskUpdate(taskId, status=\"in_progress\")"
ACTION_DIRECTIVE+="\n2. Load skills: @smith-plan, @smith-plan-claude, @smith-ctx-claude"
ACTION_DIRECTIVE+="\n3. If Serena MCP available: list_memories() then read_memory() for session state"
ACTION_DIRECTIVE+="\n4. Resume current task: ${CURRENT_TASK}"
ACTION_DIRECTIVE+="\n\nIf user's message contains a different request, address that first."

FULL_CONTENT=$(printf '%b\n\n## Plan: `%s`\n\n**File:** `%s`\n**Modified:** %s\n**Progress:** %s\n**Current task:** %s\n\n---\n\n**IMPORTANT:** After completing tasks, UPDATE this plan file at `%s` to track progress.\n\n---\n\n%s' \
    "$ACTION_DIRECTIVE" "$PLAN_BASENAME" "$PLAN_FILE" "$PLAN_MODIFIED" "$PROGRESS" "$CURRENT_TASK" "$PLAN_FILE" "$PLAN_CONTENT")

# Append Ralph resume directive if present
if [[ -n "$RALPH_RESUME_DIRECTIVE" ]]; then
    FULL_CONTENT+=$(printf '%b' "$RALPH_RESUME_DIRECTIVE")
fi

# Append orchestrator resume directive if present
if [[ -n "$ORCH_RESUME_DIRECTIVE" ]]; then
    FULL_CONTENT+=$(printf '%b' "$ORCH_RESUME_DIRECTIVE")
fi

# Clean up the pending-reload flag if it exists (SessionStart:clear handles it now)
rm -f "$FLAG_FILE" 2>/dev/null

json_session_start_output "$FULL_CONTENT"

exit 0
