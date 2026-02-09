#!/bin/bash
#
# lib-common.sh - Shared utilities for plan-claude hook scripts
#
# Source this file at the top of each hook script:
#   source "$(dirname "$0")/lib-common.sh"

# Strict mode: pipe failures propagated (no set -e; hooks must not abort on transient errors)
set -o pipefail

PLANS_DIR="${HOME}/.claude/plans"
CONTEXT_WINDOW_TOKENS=${CONTEXT_WINDOW_TOKENS:-200000}
RALPH_STATE_FILENAME="ralph-loop.local.md"
ORCH_STATE_PREFIX=".ralph-orchestrator-"

# Check for jq dependency (required for JSON parsing)
require_jq() {
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required but not found. Install: brew install jq (macOS) or apt-get install jq (Linux)" >&2
        exit 1
    fi
}

# Compute CWD key hash for flag and state files that must survive /clear.
# CWD persists across /clear (same terminal); session_id does not.
# macOS: md5, Linux: md5sum
cwd_key() {
    local cwd="$1"
    if [[ -z "$cwd" ]]; then
        cwd="${PWD:-$(pwd)}"
    fi
    local hash
    hash=$(printf '%s' "$cwd" | md5 -q 2>/dev/null) || \
    hash=$(printf '%s' "$cwd" | md5sum 2>/dev/null | cut -d' ' -f1) || {
        echo "Warning: md5/md5sum not found, using constant fallback hash (CWD isolation disabled)" >&2
        hash="00000000"
    }
    printf '%s' "${hash:0:8}"
}

# Helper: output JSON for UserPromptSubmit hooks using jq for proper escaping
json_user_prompt_output() {
    local content="$1"
    jq -n --arg c "$content" '{
        hookSpecificOutput: {
            hookEventName: "UserPromptSubmit",
            additionalContext: $c
        }
    }'
}

# Helper: output JSON for PostToolUse hooks using jq for proper escaping
json_post_tool_output() {
    local content="$1"
    jq -n --arg c "$content" '{
        hookSpecificOutput: {
            hookEventName: "PostToolUse",
            additionalContext: $c
        }
    }'
}

# Helper: output JSON for SessionStart hooks using jq for proper escaping
json_session_start_output() {
    local content="$1"
    jq -n --arg c "$content" '{
        hookSpecificOutput: {
            hookEventName: "SessionStart",
            additionalContext: $c
        }
    }'
}

# Calculate context percentage from transcript JSONL token usage.
# Reads the last assistant message's usage object (same data as statusline).
# Returns integer percentage (0-100+).
#
# Usage: pct=$(get_context_percentage "/path/to/transcript.jsonl")
get_context_percentage() {
    local transcript="$1"
    local context_window="${2:-$CONTEXT_WINDOW_TOKENS}"

    if [[ ! -f "$transcript" ]]; then
        echo "0"
        return
    fi

    # Read last 200KB, filter for complete JSON lines only (grep '^{' skips
    # the truncated first line from tail -c byte-boundary cut).
    # || total="" prevents set -eo pipefail from killing the script on grep/jq failure.
    local total
    total=$(tail -c 204800 "$transcript" 2>/dev/null \
        | grep '^{' \
        | grep '"assistant"' | tail -1 \
        | jq -r '
            # Total context consumption: input + cached + output (context window is shared)
            .message.usage
            | ((.input_tokens // 0) + (.cache_read_input_tokens // 0)
               + (.cache_creation_input_tokens // 0) + (.output_tokens // 0))
        ' 2>/dev/null) || total=""

    if [[ -z "$total" ]] || [[ "$total" == "null" ]] || ! [[ "$total" =~ ^[0-9]+$ ]]; then
        echo "0"
        return
    fi

    if [[ "$context_window" -le 0 ]]; then
        echo "0"
        return
    fi

    echo "$((total * 100 / context_window))"
}

# Helper: output JSON for Stop hook block decisions using jq for proper escaping
json_stop_block() {
    local reason="$1"
    jq -n --arg r "$reason" '{
        decision: "block",
        reason: $r
    }'
}

# --- Ralph Loop helpers ---

# Parse Ralph's state file (.claude/ralph-loop.local.md) YAML frontmatter.
# Sets: RALPH_ITERATION, RALPH_MAX_ITERATIONS, RALPH_COMPLETION_PROMISE, RALPH_PROMPT
# Args: $1 = CWD (optional, defaults to PWD)
# Returns: 0 if Ralph active, 1 otherwise
get_ralph_state() {
    local cwd="${1:-${PWD:-}}"
    local state_file="${cwd}/.claude/${RALPH_STATE_FILENAME}"

    RALPH_ITERATION=""
    RALPH_MAX_ITERATIONS=""
    RALPH_COMPLETION_PROMISE=""
    RALPH_PROMPT=""

    if [[ ! -f "$state_file" ]]; then
        return 1
    fi

    # Extract YAML frontmatter (between --- delimiters)
    local frontmatter
    frontmatter=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$state_file" 2>/dev/null) || return 1

    local active
    active=$(echo "$frontmatter" | grep '^active:' | sed 's/^active:[[:space:]]*//' | tr -d '[:space:]')
    if [[ "$active" != "true" ]]; then
        return 1
    fi

    RALPH_ITERATION=$(echo "$frontmatter" | grep '^iteration:' | sed 's/^iteration:[[:space:]]*//' | tr -d '[:space:]')
    RALPH_MAX_ITERATIONS=$(echo "$frontmatter" | grep '^max_iterations:' | sed 's/^max_iterations:[[:space:]]*//' | tr -d '[:space:]')
    RALPH_COMPLETION_PROMISE=$(echo "$frontmatter" | grep '^completion_promise:' | sed 's/^completion_promise:[[:space:]]*//' | sed 's/^"//; s/"$//' | sed "s/^'//; s/'$//")
    if [[ "$RALPH_COMPLETION_PROMISE" == "null" ]]; then
        RALPH_COMPLETION_PROMISE=""
    fi

    # Extract prompt (everything after second ---)
    RALPH_PROMPT=$(awk '/^---$/{i++; next} i>=2' "$state_file" 2>/dev/null)

    return 0
}

# Save Ralph resume state for post-/clear auto-restart.
# Creates two files: metadata + prompt (split to handle newlines in prompt).
# Args: $1 = CWD key, $2 = max_iterations, $3 = iteration, $4 = promise,
#       $5 = prompt text, $6 = plan path (optional)
save_ralph_resume() {
    local cwd_key="$1"
    local max_iter="$2"
    local iteration="$3"
    local promise="$4"
    local prompt="$5"
    local plan_path="${6:-}"

    local resume_file="${PLANS_DIR}/.ralph-resume-${cwd_key}"
    local prompt_file="${resume_file}.prompt"

    printf '%s\n%s\n%s\n%s\n%s\n' \
        "$max_iter" "$iteration" "$promise" "$plan_path" \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" > "$resume_file"
    printf '%s' "$prompt" > "$prompt_file"
}

# Read Ralph resume files.
# Sets: RALPH_RESUME_MAX_ITER, RALPH_RESUME_ITERATION, RALPH_RESUME_PROMISE,
#       RALPH_RESUME_PLAN_PATH, RALPH_RESUME_TIMESTAMP, RALPH_RESUME_PROMPT
# Args: $1 = CWD key
# Returns: 0 if resume files exist and are valid, 1 otherwise
read_ralph_resume() {
    local cwd_key="$1"
    local resume_file="${PLANS_DIR}/.ralph-resume-${cwd_key}"
    local prompt_file="${resume_file}.prompt"

    RALPH_RESUME_MAX_ITER=""
    RALPH_RESUME_ITERATION=""
    RALPH_RESUME_PROMISE=""
    RALPH_RESUME_PLAN_PATH=""
    RALPH_RESUME_TIMESTAMP=""
    RALPH_RESUME_PROMPT=""

    if [[ ! -f "$resume_file" ]]; then
        return 1
    fi

    # Check freshness (< 60 min)
    local fresh
    fresh=$(find "$resume_file" -mmin -60 2>/dev/null)
    if [[ -z "$fresh" ]]; then
        rm -f "$resume_file" "$prompt_file" 2>/dev/null
        return 1
    fi

    RALPH_RESUME_MAX_ITER=$(sed -n '1p' "$resume_file" 2>/dev/null)
    RALPH_RESUME_ITERATION=$(sed -n '2p' "$resume_file" 2>/dev/null)
    RALPH_RESUME_PROMISE=$(sed -n '3p' "$resume_file" 2>/dev/null)
    RALPH_RESUME_PLAN_PATH=$(sed -n '4p' "$resume_file" 2>/dev/null)
    RALPH_RESUME_TIMESTAMP=$(sed -n '5p' "$resume_file" 2>/dev/null)

    if [[ -f "$prompt_file" ]]; then
        RALPH_RESUME_PROMPT=$(cat "$prompt_file" 2>/dev/null)
    fi

    return 0
}

# Check if Ralph was recently active in the given CWD (regardless of active status).
# Used for proactive phase-boundary resume: Ralph exits normally via promise,
# state file remains with active: false. Resume files don't exist (those are
# only created by the reactive context-threshold path).
# Args: $1 = CWD (optional, defaults to PWD)
# Returns: 0 if ralph state file exists and is fresh (<60 min), 1 otherwise
# Sets: RALPH_RECENT_PROMPT (prompt text from the state file)
check_ralph_recently_active() {
    local cwd="${1:-${PWD:-}}"
    local state_file="${cwd}/.claude/${RALPH_STATE_FILENAME}"

    RALPH_RECENT_PROMPT=""

    if [[ ! -f "$state_file" ]]; then
        return 1
    fi

    local fresh
    fresh=$(find "$state_file" -mmin -60 2>/dev/null)
    if [[ -z "$fresh" ]]; then
        return 1
    fi

    RALPH_RECENT_PROMPT=$(awk '/^---$/{i++; next} i>=2' "$state_file" 2>/dev/null)

    return 0
}

# Force Ralph loop to exit by setting max_iterations = iteration in state file.
# Ralph's stop hook checks iteration >= max_iterations as a legitimate exit path.
# Args: $1 = CWD (optional, defaults to PWD)
# Returns: 0 on success, 1 if state file not found
force_ralph_exit() {
    local cwd="${1:-${PWD:-}}"
    local state_file="${cwd}/.claude/${RALPH_STATE_FILENAME}"

    if [[ ! -f "$state_file" ]]; then
        return 1
    fi

    local iteration
    iteration=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$state_file" 2>/dev/null \
        | grep '^iteration:' | sed 's/^iteration:[[:space:]]*//' | tr -d '[:space:]')

    if [[ -z "$iteration" ]] || ! [[ "$iteration" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    # Set max_iterations = iteration so Ralph's stop hook allows exit
    sed -i '' -e "s/^max_iterations:.*/max_iterations: ${iteration}/" "$state_file" 2>/dev/null
    return $?
}

# --- Ralph Orchestrator helpers ---

# Parse orchestrator state file YAML frontmatter.
# Sets: ORCH_ACTIVE, ORCH_MODE, ORCH_ITERATION, ORCH_MAX_ITERATIONS,
#       ORCH_PLAN_PATH, ORCH_COMPLETION_PROMISE, ORCH_CURRENT_TASK, ORCH_STARTED_AT
# Args: $1 = CWD key
# Returns: 0 if orchestrator active, 1 otherwise
get_orchestrator_state() {
    local cwd_key="$1"
    local state_file="${PLANS_DIR}/${ORCH_STATE_PREFIX}${cwd_key}"

    ORCH_ACTIVE=""
    ORCH_MODE=""
    ORCH_ITERATION=""
    ORCH_MAX_ITERATIONS=""
    ORCH_PLAN_PATH=""
    ORCH_COMPLETION_PROMISE=""
    ORCH_CURRENT_TASK=""
    ORCH_STARTED_AT=""

    if [[ ! -f "$state_file" ]]; then
        return 1
    fi

    local frontmatter
    frontmatter=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$state_file" 2>/dev/null) || return 1

    local active
    active=$(echo "$frontmatter" | grep '^active:' | sed 's/^active:[[:space:]]*//' | tr -d '[:space:]')
    if [[ "$active" != "true" ]]; then
        return 1
    fi

    ORCH_ACTIVE="true"
    ORCH_MODE=$(echo "$frontmatter" | grep '^mode:' | sed 's/^mode:[[:space:]]*//' | tr -d '[:space:]')
    ORCH_ITERATION=$(echo "$frontmatter" | grep '^iteration:' | sed 's/^iteration:[[:space:]]*//' | tr -d '[:space:]')
    ORCH_MAX_ITERATIONS=$(echo "$frontmatter" | grep '^max_iterations:' | sed 's/^max_iterations:[[:space:]]*//' | tr -d '[:space:]')
    ORCH_PLAN_PATH=$(echo "$frontmatter" | grep '^plan_path:' | sed 's/^plan_path:[[:space:]]*//' | sed 's/^"//; s/"$//' | sed "s/^'//; s/'$//")
    ORCH_COMPLETION_PROMISE=$(echo "$frontmatter" | grep '^completion_promise:' | sed 's/^completion_promise:[[:space:]]*//' | sed 's/^"//; s/"$//' | sed "s/^'//; s/'$//")
    ORCH_CURRENT_TASK=$(echo "$frontmatter" | grep '^current_task:' | sed 's/^current_task:[[:space:]]*//' | sed 's/^"//; s/"$//' | sed "s/^'//; s/'$//")
    ORCH_STARTED_AT=$(echo "$frontmatter" | grep '^started_at:' | sed 's/^started_at:[[:space:]]*//' | sed 's/^"//; s/"$//' | sed "s/^'//; s/'$//")

    return 0
}

# Save orchestrator resume state for post-/clear restoration.
# Args: $1 = CWD key, $2 = iteration, $3 = max_iterations, $4 = plan_path,
#       $5 = completion_promise, $6 = current_task
save_orchestrator_resume() {
    local cwd_key="$1"
    local iteration="$2"
    local max_iter="$3"
    local plan_path="$4"
    local promise="$5"
    local current_task="$6"

    local resume_file="${PLANS_DIR}/.ralph-orch-resume-${cwd_key}"

    printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
        "$iteration" "$max_iter" "$plan_path" "$promise" "$current_task" \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" > "$resume_file"
}

# Read orchestrator resume state.
# Sets: ORCH_RESUME_ITERATION, ORCH_RESUME_MAX_ITER, ORCH_RESUME_PLAN_PATH,
#       ORCH_RESUME_PROMISE, ORCH_RESUME_CURRENT_TASK, ORCH_RESUME_TIMESTAMP
# Args: $1 = CWD key
# Returns: 0 if resume file exists and is fresh, 1 otherwise
read_orchestrator_resume() {
    local cwd_key="$1"
    local resume_file="${PLANS_DIR}/.ralph-orch-resume-${cwd_key}"

    ORCH_RESUME_ITERATION=""
    ORCH_RESUME_MAX_ITER=""
    ORCH_RESUME_PLAN_PATH=""
    ORCH_RESUME_PROMISE=""
    ORCH_RESUME_CURRENT_TASK=""
    ORCH_RESUME_TIMESTAMP=""

    if [[ ! -f "$resume_file" ]]; then
        return 1
    fi

    local fresh
    fresh=$(find "$resume_file" -mmin -60 2>/dev/null)
    if [[ -z "$fresh" ]]; then
        rm -f "$resume_file" 2>/dev/null
        return 1
    fi

    ORCH_RESUME_ITERATION=$(sed -n '1p' "$resume_file" 2>/dev/null)
    ORCH_RESUME_MAX_ITER=$(sed -n '2p' "$resume_file" 2>/dev/null)
    ORCH_RESUME_PLAN_PATH=$(sed -n '3p' "$resume_file" 2>/dev/null)
    ORCH_RESUME_PROMISE=$(sed -n '4p' "$resume_file" 2>/dev/null)
    ORCH_RESUME_CURRENT_TASK=$(sed -n '5p' "$resume_file" 2>/dev/null)
    ORCH_RESUME_TIMESTAMP=$(sed -n '6p' "$resume_file" 2>/dev/null)

    return 0
}
