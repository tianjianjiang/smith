#!/bin/bash
#
# inject-plan.sh - UserPromptSubmit hook for plan-sync skill
#
# Ralph Loop Compatible: Reads fresh from disk on EVERY invocation.
# This ensures each iteration gets the latest plan with updated progress.
#
# Session Isolation: Uses CWD-based flag files so parallel Claude Code
# sessions (in different worktrees) don't interfere with each other.
# CWD persists across /clear; session_id does not.
#
# Triggers:
#   - "execute-plan", "!load-plan", "!plan"
#   - "execute the plan", "load the plan", "run the plan", "start the plan"
#   - "!plan-status" (shows progress summary)
#
# Auto-load:
#   - Pending-reload flag (<1hr old, CWD-matched): loads flagged plan after /clear
#   - on-session-clear.sh: fires after manual /clear (primary injection point)
#
# Clear-and-Reload:
#   - Auto-reloads plan after /clear when CWD-specific flag file exists
#   - Detects high context (transcript size) and creates flag + warning
#
# For Ralph loop: This hook fires at the start of each iteration,
# loading the updated plan file that Claude wrote in the previous iteration.
#

source "$(dirname "$0")/lib-common.sh"
require_jq

# Read input JSON from stdin
INPUT=$(cat)

# Extract prompt text
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || echo "")

# Exit silently if no prompt
if [[ -z "$PROMPT" ]]; then
    exit 0
fi

# Extract permission_mode for plan mode state saving
PERMISSION_MODE=$(echo "$INPUT" | jq -r '.permission_mode // empty' 2>/dev/null || echo "")

# Extract session ID, transcript path, and CWD
CURRENT_SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")

# CWD-keyed flag file (survives /clear; CWD persists, session_id does not)
CWD_KEY=$(cwd_key "${HOOK_CWD:-${PWD:-}}")
FLAG_FILE="${PLANS_DIR}/.pending-reload-${CWD_KEY}"

# CWD-keyed state file (survives /clear; tracks plan, transcript state)
STATE_FILE="${PLANS_DIR}/.plan-state-${CWD_KEY}"

# Clean up expired flags (>1 hour old) and legacy single-flag format
find "$PLANS_DIR" -name ".pending-reload-*" -mmin +60 -delete 2>/dev/null || true
rm -f "${PLANS_DIR}/.pending-reload" 2>/dev/null || true
find "$PLANS_DIR" -name ".plan-state-*" -mmin +1440 -delete 2>/dev/null || true
find "$PLANS_DIR" -name ".ralph-resume-*" -mmin +60 -delete 2>/dev/null || true
find "$PLANS_DIR" -name ".ralph-orch-resume-*" -mmin +60 -delete 2>/dev/null || true

# --- Plan mode state saving ---
# During plan mode (permission_mode: "plan"), save state on every prompt.
# This ensures the state file has the plan path BEFORE the user exits plan mode.
# Critical because PostToolUse:ExitPlanMode doesn't fire with "clear context
# and auto-accept edits" (upstream bug #20397).
if [[ "$PERMISSION_MODE" == "plan" ]]; then
    CURRENT_PLAN=$(ls -t "$PLANS_DIR"/*.md 2>/dev/null | head -1) || CURRENT_PLAN=""
    if [[ -n "$CURRENT_PLAN" ]] && [[ -f "$CURRENT_PLAN" ]]; then
        PLAN_FILE="$CURRENT_PLAN"
        save_injection_state
    fi
fi

# Convert to lowercase for matching
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Determine action type
ACTION=""
PLAN_FILE=""  # Reset: plan-mode save (above) already persisted; normal flow re-discovers via flag/trigger
CONTEXT_MSG=""
LOAD_REASON=""

# --- Auto-reload: check for CWD-specific pending-reload flag ---
# Each parallel session (worktree) has its own flag file keyed by CWD hash.
# CWD persists across /clear, so the new session finds the flag.
if [[ -f "$FLAG_FILE" ]]; then
    FLAGGED_PLAN=$(sed -n '1p' "$FLAG_FILE")

    # Check flag is less than 60 minutes old
    FLAG_FRESH=$(find "$FLAG_FILE" -mmin -60 2>/dev/null)

    if [[ -n "$FLAG_FRESH" ]] && [[ -n "$FLAGGED_PLAN" ]] && [[ -f "$FLAGGED_PLAN" ]]; then
        rm -f "$FLAG_FILE"
        ACTION="load"
        PLAN_FILE="$FLAGGED_PLAN"
        LOAD_REASON="flag"
    else
        # Expired flag (>1 hour old) or missing plan file -- still offer Serena memory
        rm -f "$FLAG_FILE"
        ACTION="serena_only"
    fi
fi

# --- Trigger word checks (highest priority after flag reload) ---
if [[ -z "$ACTION" ]]; then
    if [[ "$PROMPT_LOWER" == *"!plan-status"* ]] || \
       [[ "$PROMPT_LOWER" == *"plan status"* ]] || \
       [[ "$PROMPT_LOWER" == *"show progress"* ]]; then
        ACTION="status"
    # Check for load request
    elif [[ "$PROMPT_LOWER" == *"execute-plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"!load-plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"!plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"load the plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"execute the plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"run the plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"start the plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"continue with the plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"continue the plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"resume the plan"* ]]; then
        ACTION="load"
        LOAD_REASON="trigger"
    fi
fi

# --- Context threshold detection (percentage-based) ---
WARNING_PCT=${PLAN_CONTEXT_WARNING_PCT:-50}
CRITICAL_PCT=${PLAN_CONTEXT_CRITICAL_PCT:-60}

if [[ -n "$TRANSCRIPT_PATH" ]] && [[ -f "$TRANSCRIPT_PATH" ]] && [[ -z "$ACTION" ]]; then
    CONTEXT_PCT=$(get_context_percentage "$TRANSCRIPT_PATH" "$CONTEXT_WINDOW_TOKENS")

    # Ralph detection (before threshold check -- needed for both warning and critical)
    RALPH_ACTIVE=false
    RALPH_CWD="${HOOK_CWD:-${PWD:-}}"
    if get_ralph_state "$RALPH_CWD"; then
        RALPH_ACTIVE=true
    fi

    # Orchestrator detection (Pattern B)
    ORCH_ACTIVE_MODE=false
    if get_orchestrator_state "$CWD_KEY"; then
        ORCH_ACTIVE_MODE=true
    fi

    if [[ $CONTEXT_PCT -ge $WARNING_PCT ]]; then
        # Prefer the plan recorded in the state file (session-specific)
        ACTIVE_PLAN=""
        if [[ -f "$STATE_FILE" ]]; then
            prev_plan=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
            if [[ -n "$prev_plan" ]] && [[ -f "$prev_plan" ]]; then
                ACTIVE_PLAN="$prev_plan"
            fi
        fi

        PENDING=0
        if [[ -n "$ACTIVE_PLAN" ]]; then
            PENDING=$(grep -c '^[[:space:]]*- \[ \]' "$ACTIVE_PLAN" 2>/dev/null || echo 0)
            PENDING=$(echo "$PENDING" | tr -d '[:space:]')
        fi

        if [[ ! -f "$FLAG_FILE" ]]; then
            # Create flag if plan active with pending tasks
            if [[ -n "$ACTIVE_PLAN" ]] && [[ $PENDING -gt 0 ]]; then
                TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S%z)
                printf '%s\n%s\n%s\n%s\n' "$ACTIVE_PLAN" "$CURRENT_SESSION" "$TIMESTAMP" "${HOOK_CWD:-${PWD:-}}" > "$FLAG_FILE"
            fi

            if [[ $CONTEXT_PCT -ge $CRITICAL_PCT ]] && [[ "$RALPH_ACTIVE" == "true" ]]; then
                # CRITICAL + Ralph: force-exit Ralph and save resume state
                save_ralph_resume "$CWD_KEY" "${RALPH_MAX_ITERATIONS:-0}" "${RALPH_ITERATION:-1}" \
                    "${RALPH_COMPLETION_PROMISE:-}" "${RALPH_PROMPT:-}" "${ACTIVE_PLAN:-}"
                force_ralph_exit "$RALPH_CWD"

                CONTEXT_MSG=$(printf 'CONTEXT CRITICAL: %d%%. Ralph loop auto-exiting (max_iterations set to current).' "$CONTEXT_PCT")
                CONTEXT_MSG+="\n\n**YOU MUST do these steps NOW:**"
                CONTEXT_MSG+="\n1. Save ALL Ralph state to Serena: write_memory() with full iteration context"
                CONTEXT_MSG+="\n2. Update plan file with current progress (if plan active)"
                CONTEXT_MSG+="\n3. Commit uncommitted work"
                CONTEXT_MSG+="\n4. AFTER all tool calls, tell user to run /clear"
                CONTEXT_MSG+="\n\nRalph loop will auto-resume after /clear."
            elif [[ "$RALPH_ACTIVE" == "true" ]]; then
                # WARNING + Ralph: preemptive resume save + advisory
                save_ralph_resume "$CWD_KEY" "${RALPH_MAX_ITERATIONS:-0}" "${RALPH_ITERATION:-1}" \
                    "${RALPH_COMPLETION_PROMISE:-}" "${RALPH_PROMPT:-}" "${ACTIVE_PLAN:-}"

                CONTEXT_MSG=$(printf 'CONTEXT WARNING: %d%% used (warning: %d%%, critical: %d%%).' "$CONTEXT_PCT" "$WARNING_PCT" "$CRITICAL_PCT")
                CONTEXT_MSG+=$(printf '\nRalph loop active (iteration %s). Will auto-exit at critical threshold (%d%%).' "${RALPH_ITERATION:-?}" "$CRITICAL_PCT")
                CONTEXT_MSG+="\nSave iteration state to Serena NOW: write_memory() with ralph_<task>_state."
                if [[ -n "$ACTIVE_PLAN" ]]; then
                    CONTEXT_MSG+=$(printf '\n\nPlan file: `%s` (%d pending tasks)' "$ACTIVE_PLAN" "$PENDING")
                fi
            elif [[ "$ORCH_ACTIVE_MODE" == "true" ]]; then
                # Orchestrator mode: save resume state for post-/clear restoration
                save_orchestrator_resume "$CWD_KEY" "${ORCH_ITERATION:-0}" "${ORCH_MAX_ITERATIONS:-20}" \
                    "${ORCH_PLAN_PATH:-${ACTIVE_PLAN:-}}" "${ORCH_COMPLETION_PROMISE:-}" "${ORCH_CURRENT_TASK:-}"

                if [[ $CONTEXT_PCT -ge $CRITICAL_PCT ]]; then
                    CONTEXT_MSG=$(printf 'CONTEXT CRITICAL: %d%%. Orchestrator mode active (iteration %s).' "$CONTEXT_PCT" "${ORCH_ITERATION:-?}")
                    CONTEXT_MSG+="\n\n**YOU MUST do these steps NOW:**"
                    CONTEXT_MSG+="\n1. Save orchestrator state to Serena: write_memory() with iteration context"
                    CONTEXT_MSG+="\n2. Update plan file with current progress"
                    CONTEXT_MSG+="\n3. Commit uncommitted work"
                    CONTEXT_MSG+="\n4. AFTER all tool calls, tell user to run /clear"
                    CONTEXT_MSG+="\n\nOrchestrator will auto-resume after /clear."
                else
                    CONTEXT_MSG=$(printf 'CONTEXT WARNING: %d%% used (warning: %d%%, critical: %d%%).' "$CONTEXT_PCT" "$WARNING_PCT" "$CRITICAL_PCT")
                    CONTEXT_MSG+=$(printf '\nOrchestrator mode active (iteration %s).' "${ORCH_ITERATION:-?}")
                    CONTEXT_MSG+="\nSave orchestrator state to Serena NOW: write_memory() with orchestrator context."
                    if [[ -n "$ACTIVE_PLAN" ]]; then
                        CONTEXT_MSG+=$(printf '\n\nPlan file: `%s` (%d pending tasks)' "$ACTIVE_PLAN" "$PENDING")
                    fi
                fi
            else
                # Non-Ralph: existing warning behavior
                CONTEXT_MSG=$(printf 'CONTEXT WARNING: %d%% used (warning: %d%%, critical: %d%%).' "$CONTEXT_PCT" "$WARNING_PCT" "$CRITICAL_PCT")
                if [[ -n "$ACTIVE_PLAN" ]]; then
                    CONTEXT_MSG+=$(printf '\n\nPlan file: `%s` (%d pending tasks)' "$ACTIVE_PLAN" "$PENDING")
                fi
                CONTEXT_MSG+=$(printf '\n\n**Recommended:**\n1. Update plan file with current progress (mark completed as [x])\n2. Commit uncommitted work\n3. If Serena MCP available: write_memory() with descriptive name (task, decisions, file:line refs)\n4. AFTER all tool calls complete, output this block:')
                if [[ -n "$ACTIVE_PLAN" ]]; then
                    CONTEXT_MSG+=$(printf '\n\n**Reload with:**\n- Plan: `%s`\n- Memory: \`<name from step 3>\` (read via read_memory() after /clear)\n- Resume: <describe current task>' "$ACTIVE_PLAN")
                else
                    CONTEXT_MSG+=$(printf '\n\n**Reload with:**\n- Memory: \`<name from step 3>\` (read via read_memory() after /clear)\n- Resume: <describe current task>')
                fi
                CONTEXT_MSG+=$(printf '\n\n5. Tell user to run /clear\n\nPlan auto-reloads after /clear.')
            fi
        fi
    fi
fi

# If context warning was generated but no trigger matched, output warning only
if [[ -z "$ACTION" ]] && [[ -n "$CONTEXT_MSG" ]]; then
    json_user_prompt_output "$CONTEXT_MSG"
    exit 0
fi

# Serena-only fallback: flag existed but plan file was missing/expired
if [[ "$ACTION" == "serena_only" ]]; then
    # List available plans so the agent knows what exists
    AVAILABLE_PLANS=""
    if [[ -d "$PLANS_DIR" ]]; then
        while IFS= read -r f; do
            AVAILABLE_PLANS+="\n  - \`$(basename "$f")\` (\`$f\`)"
        done < <(ls -t "$PLANS_DIR"/*.md 2>/dev/null)
    fi

    SERENA_DIRECTIVE="**ACTION REQUIRED - POST-CLEAR RESUME:**"
    SERENA_DIRECTIVE+="\n\nYou MUST check for previous session state before responding."
    if [[ -n "$FLAGGED_PLAN" ]]; then
        SERENA_DIRECTIVE+="\n\n**Expected plan:** \`${FLAGGED_PLAN}\` (missing or expired)"
    fi
    if [[ -n "$AVAILABLE_PLANS" ]]; then
        SERENA_DIRECTIVE+="\n\n**Available plans in \`${PLANS_DIR}\`:**${AVAILABLE_PLANS}"
    else
        SERENA_DIRECTIVE+="\n\n**Plans directory:** \`${PLANS_DIR}\` (no plan files found)"
    fi
    SERENA_DIRECTIVE+="\n\n1. If Serena MCP available: call list_memories() IMMEDIATELY"
    SERENA_DIRECTIVE+="\n2. Scan memory names for recent session context (session, task, plan keywords)"
    SERENA_DIRECTIVE+="\n3. Read relevant memories and report restored context to user"
    SERENA_DIRECTIVE+="\n4. Offer to continue previous work or await new instructions"
    SERENA_DIRECTIVE+="\n\nDo NOT skip this. Do NOT respond with \"Ready for your next task.\""
    SERENA_DIRECTIVE+="\nIf user's message contains a different request, address that first but still restore context."
    json_user_prompt_output "$(printf '%b' "$SERENA_DIRECTIVE")"
    save_injection_state
    exit 0
fi

# Exit if no matching action
if [[ -z "$ACTION" ]]; then
    exit 0
fi

# Extract specific plan name if provided (only for load/status)
PLAN_NAME=""
if [[ "$ACTION" == "load" ]] || [[ "$ACTION" == "status" ]]; then
    if [[ "$PROMPT" =~ !load-plan[[:space:]]+([^[:space:]]+) ]]; then
        PLAN_NAME="${BASH_REMATCH[1]}"
    elif [[ "$PROMPT" =~ !plan[[:space:]]+([^[:space:]]+) ]]; then
        if [[ "${BASH_REMATCH[1]}" != "status" ]] && [[ "${BASH_REMATCH[1]}" != "-status" ]]; then
            PLAN_NAME="${BASH_REMATCH[1]}"
        fi
    elif [[ "$PROMPT_LOWER" =~ (load|execute|run)[[:space:]]+(the[[:space:]]+)?plan[[:space:]]+[\`\'\"]?([a-zA-Z0-9_-]+)[\`\'\"]? ]]; then
        PLAN_NAME="${BASH_REMATCH[3]}"
    fi
fi

# Find the plan file
find_plan_file() {
    local name="$1"

    if [[ -n "$name" ]]; then
        if [[ -f "${PLANS_DIR}/${name}" ]]; then
            echo "${PLANS_DIR}/${name}"
        elif [[ -f "${PLANS_DIR}/${name}.md" ]]; then
            echo "${PLANS_DIR}/${name}.md"
        else
            find "$PLANS_DIR" -maxdepth 1 -name "*${name}*.md" -type f 2>/dev/null | head -1
        fi
    else
        # No name specified -> return most recent plan (only used for explicit trigger words)
        ls -t "$PLANS_DIR"/*.md 2>/dev/null | head -1 || true
    fi
}

# Calculate progress from plan content
calculate_progress() {
    local content="$1"
    local total
    total=$(echo "$content" | grep -c '^[[:space:]]*- \[.\]' || true)
    total=${total:-0}
    local completed
    completed=$(echo "$content" | grep -c '^[[:space:]]*- \[x\]' || true)
    completed=${completed:-0}

    if [[ $total -gt 0 ]]; then
        local percent=$((completed * 100 / total))
        echo "${completed}/${total} tasks (${percent}%)"
    else
        echo "No trackable tasks found"
    fi
}

# Get current task (first unchecked)
get_current_task() {
    local content="$1"
    local task
    task=$(echo "$content" | grep -m1 '^[[:space:]]*- \[ \]' | sed 's/^[[:space:]]*- \[ \] //') || task=""
    echo "${task:-None}"
}

# List available plans
list_plans() {
    if [[ ! -d "$PLANS_DIR" ]] || [[ -z "$(ls -A "$PLANS_DIR"/*.md 2>/dev/null)" ]]; then
        echo "No plans available"
        return
    fi

    local result=""
    while read -r file; do
        local name
        name=$(basename "$file" .md)
        local modified
        modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$file" 2>/dev/null || stat -c %y "$file" 2>/dev/null | cut -d'.' -f1 || echo "unknown")
        result+=$(printf '  - %s (modified: %s)\n' "$name" "$modified")
    done < <(ls -t "$PLANS_DIR"/*.md 2>/dev/null)
    printf '%s' "$result"
}

# Save injection state for post-/clear detection.
# Records session_id, transcript_path, transcript_size, timestamp, and plan_path
# so the next invocation can detect context changes and reload the correct plan.
save_injection_state() {
    local current_size=0
    if [[ -n "$TRANSCRIPT_PATH" ]] && [[ -f "$TRANSCRIPT_PATH" ]]; then
        current_size=$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null | tr -d '[:space:]') || current_size=0
    fi
    printf '%s\n%s\n%s\n%s\n%s\n' \
        "${CURRENT_SESSION:-unknown}" \
        "${TRANSCRIPT_PATH:-unknown}" \
        "$current_size" \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" \
        "${PLAN_FILE:-}" > "$STATE_FILE"
}

# Handle status action
if [[ "$ACTION" == "status" ]]; then
    if [[ -z "$PLAN_FILE" ]]; then
        # Check session state first, then fall back to find_plan_file
        if [[ -z "$PLAN_NAME" ]] && [[ -f "$STATE_FILE" ]]; then
            prev_plan=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
            if [[ -n "$prev_plan" ]] && [[ -f "$prev_plan" ]]; then
                PLAN_FILE="$prev_plan"
            fi
        fi
        if [[ -z "$PLAN_FILE" ]]; then
            PLAN_FILE=$(find_plan_file "$PLAN_NAME")
        fi
    fi

    if [[ -z "$PLAN_FILE" ]] || [[ ! -f "$PLAN_FILE" ]]; then
        AVAILABLE=$(list_plans)
        MSG=$(printf '## Plan Status\n\nNo active plan found.\n\n**Available plans:**\n%s' "$AVAILABLE")
    else
        CONTENT=$(cat "$PLAN_FILE")
        BASENAME=$(basename "$PLAN_FILE")
        PROGRESS=$(calculate_progress "$CONTENT")
        CURRENT=$(get_current_task "$CONTENT")
        MSG=$(printf '## Plan Status: `%s`\n\n**Progress:** %s\n**Current task:** %s\n**File:** `%s`' \
            "$BASENAME" "$PROGRESS" "$CURRENT" "$PLAN_FILE")
    fi

    json_user_prompt_output "$MSG"
    exit 0
fi

# Handle load action
if [[ -z "$PLAN_FILE" ]]; then
    # Check session state first, then fall back to find_plan_file
    if [[ -z "$PLAN_NAME" ]] && [[ -f "$STATE_FILE" ]]; then
        prev_plan=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
        if [[ -n "$prev_plan" ]] && [[ -f "$prev_plan" ]]; then
            PLAN_FILE="$prev_plan"
        fi
    fi
    if [[ -z "$PLAN_FILE" ]]; then
        PLAN_FILE=$(find_plan_file "$PLAN_NAME")
    fi
fi

# If no plan found, output helpful message
if [[ -z "$PLAN_FILE" ]] || [[ ! -f "$PLAN_FILE" ]]; then
    AVAILABLE=$(list_plans)

    if [[ -n "$PLAN_NAME" ]]; then
        MSG=$(printf '**Plan Not Found**\n\nNo plan matching `%s` found.\n\n**Available plans:**\n%s\n\nCreate a plan using plan mode (Shift+Tab) or manually create a file in `~/.claude/plans/`' \
            "$PLAN_NAME" "$AVAILABLE")
    else
        MSG=$(printf '**Plan Not Found**\n\n**Available plans:**\n%s\n\nCreate a plan using plan mode (Shift+Tab) or manually create a file in `~/.claude/plans/`' \
            "$AVAILABLE")
    fi

    json_user_prompt_output "$MSG"
    exit 0
fi

# Read plan content (FRESH from disk - critical for Ralph loop!)
if ! PLAN_CONTENT=$(cat "$PLAN_FILE" 2>/dev/null); then
    json_user_prompt_output "Error: Could not read plan file: $PLAN_FILE"
    exit 0
fi
PLAN_BASENAME=$(basename "$PLAN_FILE")

# Get modification time (macOS first, then Linux fallback)
PLAN_MODIFIED=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$PLAN_FILE" 2>/dev/null) || \
    PLAN_MODIFIED=$(stat -c %y "$PLAN_FILE" 2>/dev/null | cut -d'.' -f1) || \
    PLAN_MODIFIED="unknown"

# Calculate progress
PROGRESS=$(calculate_progress "$PLAN_CONTENT")
CURRENT_TASK=$(get_current_task "$PLAN_CONTENT")

# Build full context with header and plan content
FULL_CONTENT=$(printf '## Plan: `%s`\n\n**File:** `%s`\n**Modified:** %s\n**Progress:** %s\n**Current task:** %s\n\n---\n\n**IMPORTANT:** After completing tasks, UPDATE this plan file at `%s` to track progress.\n\n---\n\n%s' \
    "$PLAN_BASENAME" "$PLAN_FILE" "$PLAN_MODIFIED" "$PROGRESS" "$CURRENT_TASK" "$PLAN_FILE" "$PLAN_CONTENT")

# Prepend action directive for auto-load scenarios (flag or /clear detection).
# For trigger-word loads, the user's message IS the instruction — no directive needed.
if [[ "$LOAD_REASON" == "flag" ]]; then
    ACTION_DIRECTIVE="**ACTION REQUIRED - POST-CLEAR RESUME:**"
    ACTION_DIRECTIVE+="\n\n1. Reconstruct todos from plan checkboxes:"
    ACTION_DIRECTIVE+="\n   - For each \`- [ ]\` task: TaskCreate(subject=task_text, description=\"From plan\", activeForm=\"Working on ...\")"
    ACTION_DIRECTIVE+="\n   - Set first task: TaskUpdate(taskId, status=\"in_progress\")"
    ACTION_DIRECTIVE+="\n2. Load skills: @smith-plan, @smith-plan-claude, @smith-ctx-claude"
    ACTION_DIRECTIVE+="\n3. If Serena MCP available: list_memories() then read_memory() for session state"
    ACTION_DIRECTIVE+="\n4. Resume current task: ${CURRENT_TASK}"

    # Proactive phase resume: Ralph state file in CWD but no resume files
    if check_ralph_recently_active "${HOOK_CWD:-.}"; then
        ACTION_DIRECTIVE+="\n\n**RALPH LOOP PHASE RESUME:**"
        ACTION_DIRECTIVE+="\nPrevious session used ralph-loop (state file found in CWD)."
        ACTION_DIRECTIVE+="\n5. read_memory() for ralph_* state (phase progress, iteration context)"
        ACTION_DIRECTIVE+="\n6. If phase work remains: auto-invoke Skill(skill: \"ralph-loop:ralph-loop\")"
        ACTION_DIRECTIVE+="\n   Pass the original prompt and remaining iterations from memory"
        ACTION_DIRECTIVE+="\n7. Do NOT ask user for permission - auto-invoke if ralph state found in memory"
    fi

    ACTION_DIRECTIVE+="\n\nIf user's message contains a different request, address that first."
    FULL_CONTENT=$(printf '%b\n\n%s' "$ACTION_DIRECTIVE" "$FULL_CONTENT")
fi

# Append context warning if present
if [[ -n "$CONTEXT_MSG" ]]; then
    FULL_CONTENT=$(printf '%s\n\n---\n\n%s' "$FULL_CONTENT" "$CONTEXT_MSG")
fi

# Output JSON using jq for proper escaping (macOS-compatible)
json_user_prompt_output "$FULL_CONTENT"

# Save injection state for post-/clear detection
save_injection_state

exit 0
