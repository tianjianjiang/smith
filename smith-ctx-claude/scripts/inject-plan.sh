#!/bin/bash
#
# inject-plan.sh - UserPromptSubmit hook for plan-sync skill
#
# Ralph Loop Compatible: Reads fresh from disk on EVERY invocation.
# This ensures each iteration gets the latest plan with updated progress.
#
# Session Isolation: Uses PPID:CWD-based flag files so parallel Claude Code
# sessions (even in the same CWD) don't interfere with each other.
# PPID persists across /clear (Claude Code doesn't restart); session_id does not.
#
# Triggers:
#   - "execute-plan", "!load-plan", "!plan"
#   - "execute the plan", "load the plan", "run the plan", "start the plan"
#   - "reload" (exact), "reload plan", "reload the plan"
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

source "$(dirname "$0")/lib-plan.sh"
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

# Session-keyed flag file (survives /clear; PPID:CWD persists, session_id does not)
CWD_KEY=$(session_key "" "${HOOK_CWD:-${PWD:-}}") || {
    echo "Error: session_key failed" >&2; exit 1
}
FLAG_FILE="${PLANS_DIR}/.pending-reload-${CWD_KEY}"

# Session-keyed state file (survives /clear; tracks plan, transcript state)
STATE_FILE="${PLANS_DIR}/.plan-state-${CWD_KEY}"
STATE_BASENAME=".plan-state-${CWD_KEY}"
OWN_SCOPE=$(scope_key "${HOOK_CWD:-${PWD:-}}")

# Save injection state for post-/clear detection.
# Thin wrapper around shared save_state_file() from lib-plan.sh.
save_injection_state() {
    save_state_file "$STATE_FILE" "${CURRENT_SESSION:-unknown}" "${TRANSCRIPT_PATH:-unknown}" "${PLAN_FILE:-}" "$OWN_SCOPE"
}

# Clean up expired flags (>1 hour old) and legacy single-flag format
find "$PLANS_DIR" -name ".pending-reload-*" -mmin +60 -delete 2>/dev/null || true
rm -f "${PLANS_DIR}/.pending-reload" 2>/dev/null || true
# 24h: state files live longer than flags (matches freshness window in on-session-clear.sh)
find "$PLANS_DIR" -name ".plan-state-*" -mmin +1440 -delete 2>/dev/null || true
find "$PLANS_DIR" -name ".pending-reload-*.exit-marker" -mmin +5 -delete 2>/dev/null || true
find "$PLANS_DIR" -name ".model-*" -mmin +1440 -delete 2>/dev/null || true

# --- Plan mode state saving ---
# During plan mode (permission_mode: "plan"), save state on every prompt.
# This ensures the state file has the plan path BEFORE the user exits plan mode.
# Critical because PostToolUse:ExitPlanMode doesn't fire with "clear context
# and auto-accept edits" (upstream bug #20397).
if [[ "$PERMISSION_MODE" == "plan" ]]; then
    CURRENT_PLAN=""
    CURRENT_PLAN_SOURCE=""
    NEWEST_WITHHELD=0
    NEWEST_STALE=0
  
    if [[ -f "$STATE_FILE" ]]; then
        prev_plan=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
        if [[ -n "$prev_plan" ]] && [[ -f "$prev_plan" ]]; then
            CURRENT_PLAN="$prev_plan"
            CURRENT_PLAN_SOURCE="state"
        fi
    fi
    if [[ -z "$CURRENT_PLAN" ]] && [[ ! -f "$STATE_FILE" ]]; then
        newest_adoptable_plan "$STATE_BASENAME" "$OWN_SCOPE" 1
        CURRENT_PLAN="$NEWEST_ADOPTABLE"
        [[ -n "$CURRENT_PLAN" ]] && CURRENT_PLAN_SOURCE="guess"
    fi
    if [[ -n "$CURRENT_PLAN" ]] && [[ -f "$CURRENT_PLAN" ]]; then
        PLAN_FILE="$CURRENT_PLAN"
        save_injection_state

      
      
      
        if [[ "$CURRENT_PLAN_SOURCE" != "guess" ]]; then
            PENDING=$(grep -c '^[[:space:]]*- \[ \]' "$CURRENT_PLAN" 2>/dev/null || true)
            PENDING=${PENDING:-0}
            FLAG_TYPE=$([[ "$PENDING" -gt 0 ]] && echo "plan-pending" || echo "plan-completed")
            TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S%z)
          
            PLAN_PATH_FOR_FLAG=$([[ "$FLAG_TYPE" == "plan-pending" ]] && echo "$CURRENT_PLAN" || echo "")
            printf '%s\n%s\n%s\n%s\n%s\n' "$PLAN_PATH_FOR_FLAG" "$CURRENT_SESSION" "$TIMESTAMP" "${HOOK_CWD:-${PWD:-}}" "$FLAG_TYPE" > "$FLAG_FILE"
        fi
    elif [[ "$NEWEST_WITHHELD" -gt 0 ]] || [[ "$NEWEST_STALE" -gt 0 ]]; then
        REFUSE_MSG=$(printf 'PLAN ADOPTION REFUSED: none of the %d plan file(s) in `%s` was auto-adopted here — %d claimed by another or unverifiable scope, %d older than the 24h auto-adopt window. To load one deliberately, name it: `!load-plan «name»`.' "$((NEWEST_WITHHELD + NEWEST_STALE))" "$PLANS_DIR" "$NEWEST_WITHHELD" "$NEWEST_STALE")
    fi
fi

# Convert to lowercase for matching
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Determine action type
ACTION=""
PLAN_FILE=""
LOAD_REASON=""

RESTART_SOURCE=""
RESTART_LABEL="CLEAR"
RESTART_MARKER="${PLANS_DIR}/.session-restart-${CWD_KEY}"
if [[ "$PERMISSION_MODE" != "plan" ]] && [[ -f "$RESTART_MARKER" ]]; then
    RESTART_SOURCE=$(sed -n '1p' "$RESTART_MARKER" 2>/dev/null)
    rm -f "$RESTART_MARKER" 2>/dev/null || true
fi
case "$RESTART_SOURCE" in
    clear) RESTART_LABEL="CLEAR" ;;
    compact) RESTART_LABEL="COMPACT" ;;
    *) RESTART_SOURCE="" ;;
esac
RESTART_GATED=0
[[ -n "$(find "$PLANS_DIR" -maxdepth 1 -name '.sr-hook-installed' -mtime -14 2>/dev/null)" ]] && RESTART_GATED=1

find "$PLANS_DIR" -name ".session-restart-*" -mmin +60 -delete 2>/dev/null || true
find "$PLANS_DIR" -name ".sr-tmp.*" -mmin +60 -delete 2>/dev/null || true

# --- Auto-reload: check for CWD-specific pending-reload flag ---
# Each parallel session (worktree) has its own flag file keyed by CWD hash.
# CWD persists across /clear, so the new session finds the flag.
if [[ -f "$FLAG_FILE" ]] && [[ "$PERMISSION_MODE" != "plan" ]] \
   && { [[ -n "$RESTART_SOURCE" ]] || [[ "$RESTART_GATED" -eq 0 ]]; }; then
    FLAGGED_PLAN=$(sed -n '1p' "$FLAG_FILE")

  
    FLAG_FRESH=$(find "$FLAG_FILE" -mmin -60 2>/dev/null)

    if [[ -n "$FLAG_FRESH" ]] && [[ -n "$FLAGGED_PLAN" ]] && [[ -f "$FLAGGED_PLAN" ]]; then
        rm -f "$FLAG_FILE"
        ACTION="load"
        PLAN_FILE="$FLAGGED_PLAN"
        LOAD_REASON="flag"
    else
      
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
  
    elif [[ "$PROMPT_LOWER" == *"execute-plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"!load-plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"!plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"load the plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"execute the plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"run the plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"start the plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"continue with the plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"continue the plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"resume the plan"* ]] || \
         [[ "$PROMPT_LOWER" == "reload" ]] || \
         [[ "$PROMPT_LOWER" == *"reload plan"* ]] || \
         [[ "$PROMPT_LOWER" == *"reload the plan"* ]]; then
        ACTION="load"
        LOAD_REASON="trigger"
    fi
fi

# --- Context threshold detection (percentage-based) ---
WARNING_PCT=${PLAN_CONTEXT_WARNING_PCT:-50}
CRITICAL_PCT=${PLAN_CONTEXT_CRITICAL_PCT:-60}

if [[ -n "$TRANSCRIPT_PATH" ]] && [[ -f "$TRANSCRIPT_PATH" ]] && [[ -z "$ACTION" ]]; then
    CONTEXT_PCT=$(resolve_context_percentage "$TRANSCRIPT_PATH" "$CWD_KEY")

    if [[ $CONTEXT_PCT -ge $WARNING_PCT ]]; then
      
        ACTIVE_PLAN=""
        if [[ -f "$STATE_FILE" ]]; then
            prev_plan=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
            if [[ -n "$prev_plan" ]] && [[ -f "$prev_plan" ]]; then
                ACTIVE_PLAN="$prev_plan"
            fi
        fi

        PENDING=0
        if [[ -n "$ACTIVE_PLAN" ]]; then
            PENDING=$(grep -c '^[[:space:]]*- \[ \]' "$ACTIVE_PLAN" 2>/dev/null || true)
            PENDING=${PENDING:-0}
        fi

      
        if [[ ! -f "$FLAG_FILE" ]]; then
          
            if [[ -n "$ACTIVE_PLAN" ]] && [[ $PENDING -gt 0 ]]; then
                TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S%z)
                printf '%s\n%s\n%s\n%s\n%s\n' "$ACTIVE_PLAN" "$CURRENT_SESSION" "$TIMESTAMP" "${HOOK_CWD:-${PWD:-}}" "plan-pending" > "$FLAG_FILE"
            fi
        elif [[ -f "$FLAG_FILE" ]] && [[ -n "$ACTIVE_PLAN" ]] && [[ $PENDING -eq 0 ]]; then
          
          
            TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S%z)
            printf '%s\n%s\n%s\n%s\n%s\n' "" "$CURRENT_SESSION" "$TIMESTAMP" "${HOOK_CWD:-${PWD:-}}" "plan-completed" > "$FLAG_FILE"
        fi
    fi
fi

# Serena-only fallback: flag existed but plan file was missing/expired
if [[ "$ACTION" == "serena_only" ]]; then
  
    AVAILABLE_PLANS=""
    if [[ -d "$PLANS_DIR" ]]; then
        while IFS= read -r f; do
            classify_plan_scope "$f" "$STATE_BASENAME" "$OWN_SCOPE" || continue
            AVAILABLE_PLANS+="\n  - \`$(basename "$f")\` (\`$f\`)"
        done < <(ls -t "$PLANS_DIR"/*.md 2>/dev/null)
    fi

    SERENA_DIRECTIVE="**ACTION REQUIRED - POST-${RESTART_LABEL} RESUME:**"
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

# Exit if no matching action.
# Before exiting, refresh the state file if a plan is active (keeps it fresh
# for post-/clear detection even without explicit trigger words).
if [[ -z "$ACTION" ]]; then
    if [[ -n "${REFUSE_MSG:-}" ]]; then
        json_user_prompt_output "$REFUSE_MSG"
        exit 0
    fi
    if [[ -f "$STATE_FILE" ]]; then
        STATE_FRESH=$(find "$STATE_FILE" -mmin -60 2>/dev/null)
        if [[ -n "$STATE_FRESH" ]]; then
            prev_plan=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
            if [[ -n "$prev_plan" ]] && [[ -f "$prev_plan" ]]; then
              
                pending=$(grep -c '^[[:space:]]*- \[ \]' "$prev_plan" 2>/dev/null || true)
                pending=${pending:-0}
                if [[ "$pending" -gt 0 ]]; then
                    PLAN_FILE="$prev_plan"
                    save_injection_state
                fi
            fi
        fi
    fi
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
        newest_adoptable_plan "$STATE_BASENAME" "$OWN_SCOPE"
        printf '%s' "$NEWEST_ADOPTABLE"
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
        classify_plan_scope "$file" "$STATE_BASENAME" "$OWN_SCOPE" || continue
        local name
        name=$(basename "$file" .md)
        local modified
        mtime_human "$file"
        modified="${_MTIME_HUMAN:0:16}"
        result+=$(printf '  - %s (modified: %s)\n' "$name" "$modified")
    done < <(ls -t "$PLANS_DIR"/*.md 2>/dev/null)
    printf '%s' "$result"
}

# Handle status action
if [[ "$ACTION" == "status" ]]; then
    if [[ -z "$PLAN_FILE" ]]; then
      
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
        MSG=$(printf '**Plan Not Found**\n\nNo plan matching `%s` found.\n\n**Available plans:**\n%s\n\nCreate a plan using plan mode (Shift+Tab) or manually create a file in `%s/`' \
            "$PLAN_NAME" "$AVAILABLE" "$PLANS_DIR")
    else
        MSG=$(printf '**Plan Not Found**\n\n**Available plans:**\n%s\n\nCreate a plan using plan mode (Shift+Tab) or manually create a file in `%s/`' \
            "$AVAILABLE" "$PLANS_DIR")
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

mtime_human "$PLAN_FILE"
PLAN_MODIFIED="$_MTIME_HUMAN"

# Calculate progress
PROGRESS=$(calculate_progress "$PLAN_CONTENT")
CURRENT_TASK=$(get_current_task "$PLAN_CONTENT")

# Build full context with header and plan content
FULL_CONTENT=$(printf '## Plan: `%s`\n\n**File:** `%s`\n**Modified:** %s\n**Progress:** %s\n**Current task:** %s\n\n---\n\n**IMPORTANT:** After completing tasks, UPDATE this plan file at `%s` to track progress.\n\n---\n\n%s' \
    "$PLAN_BASENAME" "$PLAN_FILE" "$PLAN_MODIFIED" "$PROGRESS" "$CURRENT_TASK" "$PLAN_FILE" "$PLAN_CONTENT")

# Prepend action directive for auto-load scenarios (flag or /clear detection).
# For trigger-word loads, the user's message IS the instruction — no directive needed.
if [[ "$LOAD_REASON" == "flag" ]]; then
    ACTION_DIRECTIVE="**ACTION REQUIRED - POST-${RESTART_LABEL} RESUME:**"
    ACTION_DIRECTIVE+="\n\n1. Reconstruct todos from plan checkboxes:"
    ACTION_DIRECTIVE+="\n   - For each \`- [ ]\` task: TaskCreate(subject=task_text, description=\"From plan\", activeForm=\"Working on ...\")"
    ACTION_DIRECTIVE+="\n   - Set first task: TaskUpdate(taskId, status=\"in_progress\")"
    ACTION_DIRECTIVE+="\n2. Load skills: @smith-plan, @smith-plan-claude, @smith-ctx-claude"
    ACTION_DIRECTIVE+="\n3. If Serena MCP available: list_memories() then read_memory() for session state"
    ACTION_DIRECTIVE+="\n4. Resume current task: ${CURRENT_TASK}"
    ACTION_DIRECTIVE+="\n\nIf user's message contains a different request, address that first."
    FULL_CONTENT=$(printf '%b\n\n%s' "$ACTION_DIRECTIVE" "$FULL_CONTENT")
fi

# Output JSON using jq for proper escaping (macOS-compatible)
json_user_prompt_output "$FULL_CONTENT"

# Save injection state for post-/clear detection
save_injection_state

exit 0
