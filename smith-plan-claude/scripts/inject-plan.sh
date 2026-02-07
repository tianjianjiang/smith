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
#   - CWD-based state file: transcript_path, size, staleness (60-min max age)
#   - New session (no state file): NO auto-load (user must explicitly request)
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

# Convert to lowercase for matching
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Determine action type
ACTION=""
PLAN_FILE=""
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
        # Expired flag (>1 hour old) or missing plan file, clean up
        rm -f "$FLAG_FILE"
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

# --- Context threshold detection ---
THRESHOLD_KB=${PLAN_CONTEXT_THRESHOLD_KB:-500}

if [[ -n "$TRANSCRIPT_PATH" ]] && [[ -f "$TRANSCRIPT_PATH" ]] && [[ -z "$ACTION" ]]; then
    TRANSCRIPT_SIZE=$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)
    TRANSCRIPT_SIZE=$(echo "$TRANSCRIPT_SIZE" | tr -d '[:space:]')
    THRESHOLD_BYTES=$((THRESHOLD_KB * 1024))

    if [[ $TRANSCRIPT_SIZE -gt $THRESHOLD_BYTES ]]; then
        # Prefer the plan recorded in the state file (session-specific)
        ACTIVE_PLAN=""
        if [[ -f "$STATE_FILE" ]]; then
            prev_plan=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
            if [[ -n "$prev_plan" ]] && [[ -f "$prev_plan" ]]; then
                ACTIVE_PLAN="$prev_plan"
            fi
        fi
        if [[ -n "$ACTIVE_PLAN" ]]; then
            PENDING=$(grep -c '^[[:space:]]*- \[ \]' "$ACTIVE_PLAN" 2>/dev/null || echo 0)
            PENDING=$(echo "$PENDING" | tr -d '[:space:]')
            if [[ $PENDING -gt 0 ]] && [[ ! -f "$FLAG_FILE" ]]; then
                TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S%z)
                printf '%s\n%s\n%s\n%s\n' "$ACTIVE_PLAN" "$CURRENT_SESSION" "$TIMESTAMP" "${HOOK_CWD:-${PWD:-}}" > "$FLAG_FILE"

                SIZE_KB=$((TRANSCRIPT_SIZE / 1024))
                CONTEXT_MSG=$(printf 'CONTEXT CRITICAL: Transcript %dKB (threshold: %dKB). Plan has %d pending tasks.\n\n**YOU MUST:**\n1. Update plan file with current progress\n2. Write Serena memory with session state\n3. Tell user to run /clear\n\nPlan will auto-reload on next prompt after /clear.' \
                    "$SIZE_KB" "$THRESHOLD_KB" "$PENDING")
            fi
        fi
    fi
fi

# --- CWD state detection + auto-load (lowest priority) ---
# Only auto-loads when CWD-keyed state file exists and is <60 min old.
# New sessions (no state file) do NOT auto-load — user must explicitly request.
#
# Detects post-/clear using signals:
#   1. Transcript path changed -> /clear created new transcript
#   2. Transcript shrank by >50% -> /clear truncated file
#   3. Transcript < 10KB -> small transcript
#   4. State file stale (> PLAN_REFRESH_STALE_MIN) -> /clear without transcript change
if [[ -z "$ACTION" ]]; then
    NEW_CONTEXT_REASON=""

    CURRENT_TRANSCRIPT_SIZE=0
    if [[ -n "$TRANSCRIPT_PATH" ]] && [[ -f "$TRANSCRIPT_PATH" ]]; then
        CURRENT_TRANSCRIPT_SIZE=$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null | tr -d '[:space:]')
    fi

    if [[ -f "$STATE_FILE" ]]; then
        # Skip auto-load from stale state (>60 min = likely new session in same CWD)
        STATE_FRESH=$(find "$STATE_FILE" -mmin -60 2>/dev/null)
        if [[ -z "$STATE_FRESH" ]]; then
            : # State too old, skip auto-load
        else
        # State file exists and fresh -> check for /clear signals.
        prev_session_id=$(sed -n '1p' "$STATE_FILE" 2>/dev/null)
        prev_path=$(sed -n '2p' "$STATE_FILE" 2>/dev/null)
        prev_size=$(sed -n '3p' "$STATE_FILE" 2>/dev/null)

        if [[ -n "$TRANSCRIPT_PATH" ]] && [[ -n "$prev_path" ]] && \
           [[ "$prev_path" != "$TRANSCRIPT_PATH" ]]; then
            # Signal 1: Transcript path changed
            NEW_CONTEXT_REASON="refresh"
        elif [[ -n "$prev_size" ]] && [[ "$prev_size" =~ ^[0-9]+$ ]] && \
             [[ "$prev_size" -gt 0 ]] && \
             [[ $CURRENT_TRANSCRIPT_SIZE -lt $((prev_size / 2)) ]]; then
            # Signal 2: Transcript shrank by >50%
            NEW_CONTEXT_REASON="refresh"
        elif [[ $CURRENT_TRANSCRIPT_SIZE -lt 10240 ]]; then
            # Signal 3: Small transcript (post-/clear detection).
            # Only trigger if same session (post-/clear) — different session_id = new session, skip.
            if [[ -n "$prev_session_id" ]] && [[ "$prev_session_id" != "$CURRENT_SESSION" ]]; then
                : # Different session in same CWD — skip auto-load
            else
                NEW_CONTEXT_REASON="refresh"
            fi
        else
            # Signal 4: State file stale -> /clear likely happened
            STALE_MIN=${PLAN_REFRESH_STALE_MIN:-3}
            state_fresh=$(find "$STATE_FILE" -mmin -"$STALE_MIN" 2>/dev/null)
            if [[ -z "$state_fresh" ]]; then
                NEW_CONTEXT_REASON="refresh"
            fi
        fi
        fi  # STATE_FRESH age guard
    fi
    # No state file (or stale >60 min) -> no auto-load (intentional)

    if [[ -n "$NEW_CONTEXT_REASON" ]]; then
        # Get plan from session state (no most-recent fallback for auto-load)
        ACTIVE_PLAN=""
        prev_plan=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
        if [[ -n "$prev_plan" ]] && [[ -f "$prev_plan" ]]; then
            ACTIVE_PLAN="$prev_plan"
        fi
        if [[ -n "$ACTIVE_PLAN" ]]; then
            PENDING=$(grep -c '^[[:space:]]*- \[ \]' "$ACTIVE_PLAN" 2>/dev/null || echo 0)
            PENDING=$(echo "$PENDING" | tr -d '[:space:]')
            if [[ $PENDING -gt 0 ]]; then
                ACTION="load"
                PLAN_FILE="$ACTIVE_PLAN"
                LOAD_REASON="$NEW_CONTEXT_REASON"
            fi
        fi
    fi
fi

# If context warning was generated but no trigger matched, output warning only
if [[ -z "$ACTION" ]] && [[ -n "$CONTEXT_MSG" ]]; then
    json_user_prompt_output "$CONTEXT_MSG"
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
        ls -t "$PLANS_DIR"/*.md 2>/dev/null | head -1
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
    task=$(echo "$content" | grep -m1 '^[[:space:]]*- \[ \]' | sed 's/^[[:space:]]*- \[ \] //')
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
        current_size=$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null | tr -d '[:space:]')
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
PLAN_CONTENT=$(cat "$PLAN_FILE")
PLAN_BASENAME=$(basename "$PLAN_FILE")

# Get modification time (macOS first, then Linux fallback)
PLAN_MODIFIED=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$PLAN_FILE" 2>/dev/null || stat -c %y "$PLAN_FILE" 2>/dev/null | cut -d'.' -f1 || echo "unknown")

# Calculate progress
PROGRESS=$(calculate_progress "$PLAN_CONTENT")
CURRENT_TASK=$(get_current_task "$PLAN_CONTENT")

# Build full context with header and plan content
FULL_CONTENT=$(printf '## Plan: `%s`\n\n**File:** `%s`\n**Modified:** %s\n**Progress:** %s\n**Current task:** %s\n\n---\n\n**IMPORTANT:** After completing tasks, UPDATE this plan file at `%s` to track progress.\n\n---\n\n%s' \
    "$PLAN_BASENAME" "$PLAN_FILE" "$PLAN_MODIFIED" "$PROGRESS" "$CURRENT_TASK" "$PLAN_FILE" "$PLAN_CONTENT")

# Prepend action directive for auto-load scenarios (flag or /clear detection).
# For trigger-word loads, the user's message IS the instruction — no directive needed.
if [[ "$LOAD_REASON" == "flag" ]] || [[ "$LOAD_REASON" == "refresh" ]]; then
    ACTION_DIRECTIVE="**ACTION REQUIRED:** This plan was auto-loaded after context clear."
    ACTION_DIRECTIVE+=" Resume working on the current task listed below."
    ACTION_DIRECTIVE+=" If the user's message contains a different request, address that first."
    FULL_CONTENT=$(printf '%s\n\n%s' "$ACTION_DIRECTIVE" "$FULL_CONTENT")
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
