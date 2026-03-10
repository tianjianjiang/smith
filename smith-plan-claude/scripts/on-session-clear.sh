#!/bin/bash
#
# on-session-clear.sh - SessionStart:clear hook for plan injection
#
# Fires after manual /clear. Reads plan from .plan-state-<session-hash>
# and injects plan content with skill/todo instructions.
#
# This is the reliable injection point for post-/clear plan restoration.
# Unlike UserPromptSubmit heuristics, this fires exactly once after /clear.
#
# Known limitation: Does NOT fire when plan mode exits via "clear context
# and auto-accept edits" (upstream bug #20900). The inject-plan.sh
# heuristic detection remains as fallback for that case.
#
# Session Isolation: Uses PPID:CWD-based state files so parallel Claude Code
# sessions (even in the same CWD) don't interfere with each other.
#

source "$(dirname "$0")/lib-common.sh"
require_jq

INPUT=$(cat)

# Extract CWD from hook input
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
CWD_KEY=$(session_key "" "${HOOK_CWD:-${PWD:-}}") || {
    echo "Error: session_key failed" >&2; exit 1
}
STATE_FILE="${PLANS_DIR}/.plan-state-${CWD_KEY}"
FLAG_FILE="${PLANS_DIR}/.pending-reload-${CWD_KEY}"

# Try to find plan from state file
PLAN_FILE=""
if [[ -f "$STATE_FILE" ]]; then
    # 24h freshness: PPID-keyed state is process-scoped, so stale = process restarted.
    # 60 min was too short — UserPromptSubmit stops firing mid-session (known bug),
    # so state may not be refreshed. enforce-clear.sh now refreshes on block.
    # Validate STATE_FRESHNESS_MIN: must be a positive integer, default 1440 (24h)
    _sfm="${STATE_FRESHNESS_MIN:-1440}"
    [[ "$_sfm" =~ ^[0-9]+$ ]] || _sfm=1440
    STATE_FRESH=$(find "$STATE_FILE" -mmin -"${_sfm}" 2>/dev/null)
    if [[ -n "$STATE_FRESH" ]]; then
        PLAN_FILE=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
        if [[ -n "$PLAN_FILE" ]] && [[ ! -f "$PLAN_FILE" ]]; then
            PLAN_FILE=""
        fi
    fi
fi

# Read flag type (line 5) if flag exists. Old flags without line 5 default to
# "plan-pending" for backward compatibility.
FLAG_TYPE=""
if [[ -f "$FLAG_FILE" ]]; then
    FLAG_TYPE=$(sed -n '5p' "$FLAG_FILE" 2>/dev/null)
    FLAG_TYPE=${FLAG_TYPE:-plan-pending}
fi

# Only auto-load plan if a flag file exists (explicit reload intent from
# enforce-clear or on-plan-exit). The state file alone is informational —
# it records which plan was active but does NOT mean the user wants to resume.
# Without this gate, every /clear for 24 hours forces plan resume, even when
# the user wants to work on something else.
if [[ -n "$PLAN_FILE" ]] && [[ ! -f "$FLAG_FILE" ]]; then
    PLAN_FILE=""  # No flag = no auto-resume. Fall through to no-plan path.
fi

# Compute state/flag metadata for directive output (replaces "may be STALE" guessing)
STATE_META_STATE=""
if [[ -f "$STATE_FILE" ]]; then
    _state_plan=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
    _state_mtime=$(stat -f %m "$STATE_FILE" 2>/dev/null) || \
        _state_mtime=$(stat -c %Y "$STATE_FILE" 2>/dev/null) || _state_mtime=""
    _state_age="?"
    if [[ -n "$_state_mtime" ]] && [[ "$_state_mtime" =~ ^[0-9]+$ ]]; then
        _state_age=$(( ($(date +%s) - _state_mtime) / 60 ))
    fi
    if [[ -n "$PLAN_FILE" ]]; then
        _pending=$(grep -c '^[[:space:]]*- \[ \]' "$PLAN_FILE" 2>/dev/null || true)
        _pending=$(echo "$_pending" | tr -d '[:space:]')
        STATE_META_STATE="- State file: found (plan: \`$(basename "${_state_plan:-unknown}")\`, pending: ${_pending} tasks, age: ${_state_age}m)"
    elif [[ -n "$_state_plan" ]] && [[ -f "$_state_plan" ]]; then
        _pending=$(grep -c '^[[:space:]]*- \[ \]' "$_state_plan" 2>/dev/null || true)
        _pending=$(echo "$_pending" | tr -d '[:space:]')
        STATE_META_STATE="- State file: found (plan: \`$(basename "${_state_plan}")\`, pending: ${_pending} tasks — not loaded, age: ${_state_age}m)"
    elif [[ -n "$_state_plan" ]]; then
        STATE_META_STATE="- State file: found (plan: \`$(basename "${_state_plan}")\` — file missing, age: ${_state_age}m)"
    else
        STATE_META_STATE="- State file: found (no plan recorded, age: ${_state_age}m)"
    fi
else
    STATE_META_STATE="- State file: not found"
fi
STATE_META_FLAG="- Flag file: $([ -f "$FLAG_FILE" ] && echo "found" || echo "not found")"

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

# No plan found — output state data for SKILL.md to interpret
if [[ -z "$PLAN_FILE" ]]; then
    # List only the 5 most recent plans (not 100+)
    AVAILABLE_PLANS=""
    PLAN_COUNT=0
    if [[ -d "$PLANS_DIR" ]]; then
        while IFS= read -r f; do
            AVAILABLE_PLANS+="\n  - \`$(basename "$f")\` (\`$f\`)"
            PLAN_COUNT=$((PLAN_COUNT + 1))
            [[ $PLAN_COUNT -ge 5 ]] && break
        done < <(ls -t "$PLANS_DIR"/*.md 2>/dev/null)
    fi

    # Determine signal: flag or Ralph/orchestrator resume means reload intent
    if [[ -n "$FLAG_TYPE" ]] || [[ -n "$RALPH_RESUME_DIRECTIVE" ]] || [[ -n "$ORCH_RESUME_DIRECTIVE" ]]; then
        SIGNAL="resume"
    else
        SIGNAL="fresh-start"
    fi

    STATE_OUTPUT="**State check (session-keyed):**"
    STATE_OUTPUT+="\n${STATE_META_STATE}"
    STATE_OUTPUT+="\n${STATE_META_FLAG}"
    STATE_OUTPUT+="\n- Flag type: ${FLAG_TYPE:-none}"
    STATE_OUTPUT+="\n- Signal: ${SIGNAL}"
    if [[ -n "$AVAILABLE_PLANS" ]]; then
        STATE_OUTPUT+="\n\nRecent plans (for reference if user asks):"
        STATE_OUTPUT+="${AVAILABLE_PLANS}"
    fi
    if [[ -n "$RALPH_RESUME_DIRECTIVE" ]]; then
        STATE_OUTPUT+="$RALPH_RESUME_DIRECTIVE"
    fi
    if [[ -n "$ORCH_RESUME_DIRECTIVE" ]]; then
        STATE_OUTPUT+="$ORCH_RESUME_DIRECTIVE"
    fi

    rm -f "$FLAG_FILE" 2>/dev/null
    json_session_start_output "$(printf '%b' "$STATE_OUTPUT")"
    exit 0
fi

# Read plan content fresh from disk
if ! PLAN_CONTENT=$(cat "$PLAN_FILE" 2>/dev/null); then
    # Plan file unreadable — output state data with plan path hint
    STATE_OUTPUT="**State check (session-keyed):**"
    STATE_OUTPUT+="\n${STATE_META_STATE}"
    STATE_OUTPUT+="\n${STATE_META_FLAG}"
    STATE_OUTPUT+="\n- Flag type: ${FLAG_TYPE:-plan-pending}"
    STATE_OUTPUT+="\n- Signal: resume"
    STATE_OUTPUT+="\n- Plan file: \`${PLAN_FILE}\` (unreadable)"
    STATE_OUTPUT+="\n- Plans directory: \`${PLANS_DIR}\`"
    if [[ -n "$RALPH_RESUME_DIRECTIVE" ]]; then
        STATE_OUTPUT+="$RALPH_RESUME_DIRECTIVE"
    fi
    if [[ -n "$ORCH_RESUME_DIRECTIVE" ]]; then
        STATE_OUTPUT+="$ORCH_RESUME_DIRECTIVE"
    fi
    rm -f "$FLAG_FILE" 2>/dev/null
    json_session_start_output "$(printf '%b' "$STATE_OUTPUT")"
    exit 0
fi
PLAN_BASENAME=$(basename "$PLAN_FILE")

# Get modification time (macOS first, then Linux fallback)
PLAN_MODIFIED=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$PLAN_FILE" 2>/dev/null) || \
    PLAN_MODIFIED=$(stat -c %y "$PLAN_FILE" 2>/dev/null | cut -d'.' -f1) || \
    PLAN_MODIFIED="unknown"

# Calculate progress
TOTAL=$(echo "$PLAN_CONTENT" | grep -c '^[[:space:]]*- \[.\]' || true)
COMPLETED=$(echo "$PLAN_CONTENT" | grep -c '^[[:space:]]*- \[x\]' || true)

if [[ $TOTAL -gt 0 ]]; then
    PERCENT=$((COMPLETED * 100 / TOTAL))
    PROGRESS="${COMPLETED}/${TOTAL} tasks (${PERCENT}%)"
else
    PROGRESS="No trackable tasks found"
fi

CURRENT_TASK=$(echo "$PLAN_CONTENT" | grep -m1 '^[[:space:]]*- \[ \]' | sed 's/^[[:space:]]*- \[ \] //') || CURRENT_TASK=""
CURRENT_TASK=${CURRENT_TASK:-None}
PENDING=$((TOTAL - COMPLETED))

# Build injection content — state data + plan content (Ralph/orchestrator directives appended below if active)
STATE_OUTPUT="**State check (session-keyed):**"
STATE_OUTPUT+="\n${STATE_META_STATE}"
STATE_OUTPUT+="\n${STATE_META_FLAG}"
STATE_OUTPUT+="\n- Flag type: ${FLAG_TYPE:-plan-pending}"
STATE_OUTPUT+="\n- Signal: resume"

FULL_CONTENT=$(printf '%b\n\n---\n\n## Plan: `%s`\n\n**File:** `%s`\n**Modified:** %s\n**Progress:** %s\n**Current task:** %s\n\n**IMPORTANT:** After completing tasks, UPDATE this plan file at `%s` to track progress.\n\n---\n\n%s' \
    "$STATE_OUTPUT" "$PLAN_BASENAME" "$PLAN_FILE" "$PLAN_MODIFIED" "$PROGRESS" "$CURRENT_TASK" "$PLAN_FILE" "$PLAN_CONTENT")

# Add ACTION REQUIRED directive for plan-pending (mirrors inject-plan.sh lines 473-494)
if [[ "$FLAG_TYPE" == "plan-pending" ]] && [[ $PENDING -gt 0 ]]; then
    ACTION_DIRECTIVE="**ACTION REQUIRED - POST-CLEAR RESUME:**"
    ACTION_DIRECTIVE+="\n\n1. Reconstruct todos from plan checkboxes:"
    ACTION_DIRECTIVE+="\n   - For each \`- [ ]\` task: TaskCreate(subject=task_text, description=\"From plan\", activeForm=\"Working on ...\")"
    ACTION_DIRECTIVE+="\n   - Set first task: TaskUpdate(taskId, status=\"in_progress\")"
    ACTION_DIRECTIVE+="\n2. Load skills: @smith-plan, @smith-plan-claude, @smith-ctx-claude"
    ACTION_DIRECTIVE+="\n3. If Serena MCP available: list_memories() then read_memory() for session state"
    ACTION_DIRECTIVE+="\n4. Resume current task: ${CURRENT_TASK}"
    ACTION_DIRECTIVE+="\n\nIf user's message contains a different request, address that first."
    FULL_CONTENT=$(printf '%b\n\n%s' "$ACTION_DIRECTIVE" "$FULL_CONTENT")
fi

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
