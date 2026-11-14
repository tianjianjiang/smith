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
#   CTX_AUTO_RESET_DISPATCH - "0" turns the automatic continuation of
#     background sessions off (default: on)
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source context functions (canonical location)
source "${SCRIPT_DIR}/lib-context.sh"

# Source lib-plan.sh for plan/Ralph/Orchestrator functions (optional; co-located here, not in smith-mode-plan-claude)
PLAN_LIB="${SMITH_PLAN_LIB:-${SCRIPT_DIR}/lib-plan.sh}"
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

auto_reset_dispatch_enabled() {
    [[ -n "${CLAUDE_JOB_DIR:-}" && "${CTX_AUTO_RESET_DISPATCH:-}" != "0" && -n "${CHECKPOINT_READ_ONE_BACKEND:-}" ]]
}

eligible_restore_flags() {
    local pending_reload="$1" own_key="$2" physical_key="$3" attempt_marker="$4"
    local flag key label
    for flag in "${CTX_FLAGS_DIR}"/.pending-memory-restore-*; do
        [[ -f "$flag" && "$flag" -nt "$pending_reload" ]] || continue
        [[ -f "$attempt_marker" ]] && grep -qxF -- "$flag" "$attempt_marker" && continue
        key=$(sed -n '5p' "$flag" 2>/dev/null)
        [[ -n "$key" && ( "$key" == "$own_key" || "$key" == "$physical_key" ) ]] || continue
        label=$(sed -n '4p' "$flag" 2>/dev/null)
        [[ -n "$label" ]] || continue
        printf '%s\n' "$flag"
    done
}

newest_file_of() {
    local file newest=""
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        [[ -z "$newest" || "$file" -nt "$newest" ]] && newest="$file"
    done <<<"$1"
    printf '%s' "$newest"
}

json_system_message() {
    jq -n --arg m "$1" '{systemMessage: $m}'
}

first_output_line() {
    local line
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -n "$line" ]] && { printf '%s' "${line:0:200}"; return; }
    done <<<"$1"
}

dispatch_successor_session() {
    local hook_cwd="${HOOK_CWD:-${PWD:-}}"
    local own_key physical_cwd physical_key pending_reload attempt_marker
    local eligible_flags flag label name prompt mode output reason
    local launch_options=()
    own_key=$(session_key "" "$hook_cwd") || return 0
    physical_cwd=$(cd -- "$hook_cwd" 2>/dev/null && pwd -P) || physical_cwd="$hook_cwd"
    physical_key=$(session_key "" "$physical_cwd") || physical_key=""
    pending_reload="${CTX_FLAGS_DIR}/.pending-reload-${own_key}"
    attempt_marker="${CTX_FLAGS_DIR}/.auto-reset-attempt-${own_key}"
    find "$CTX_FLAGS_DIR" -maxdepth 1 -name '.auto-reset-attempt-*' ! -name ".auto-reset-attempt-${own_key}" -mmin +60 -delete 2>/dev/null || true
    if [[ ! -f "$pending_reload" ]]; then
        rm -f "$attempt_marker"
        return 0
    fi
    eligible_flags=$(eligible_restore_flags "$pending_reload" "$own_key" "$physical_key" "$attempt_marker")
    flag=$(newest_file_of "$eligible_flags")
    if [[ -z "$flag" ]]; then
        [[ -f "$attempt_marker" && ! "$attempt_marker" -ot "$pending_reload" ]] && return 0
        json_system_message "Context reset: no checkpoint was written after the block, so no background session was started. Checkpoint this session, or type /clear."
        return 0
    fi
    printf '%s\n' "$eligible_flags" >> "$attempt_marker"
    label=$(sed -n '4p' "$flag")
    name="continue: ${label}"
    prompt="This session continues an earlier session whose context was full. Restore the checkpoint \"${label}\": ${CHECKPOINT_READ_ONE_BACKEND}. Then report the restored context and continue the work thread."
    mode=$(jq -r '.permission_mode // empty' <<<"$INPUT" 2>/dev/null)
    launch_options=(--bg --name "$name")
    [[ -n "$mode" ]] && launch_options+=(--permission-mode "$mode")
    output=$(cd -- "$hook_cwd" && claude "${launch_options[@]}" -- "$prompt" < /dev/null 2>&1)
    if [[ "$output" =~ backgrounded\ ·\ ([0-9A-Za-z_-]+) ]]; then
        rm -f "$flag"
        json_system_message "Context reset: the work continues in background session ${BASH_REMATCH[1]} named \"${name}\"."
    else
        reason=$(first_output_line "$output")
        json_system_message "Context reset: dispatching a background session for checkpoint \"${label}\" failed${reason:+ (${reason})}; /clear still restores the checkpoint."
    fi
}

# Official best practice: if already continuing from a stop hook, allow stop
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
    auto_reset_dispatch_enabled && dispatch_successor_session
    exit 0
fi
CWD_KEY=$(session_key "" "${HOOK_CWD:-${PWD:-}}") || {
    echo "Error: session_key failed" >&2
    exit 1
}
PLAN_STATE_KEY=$(plan_state_key "${HOOK_CWD:-${PWD:-}}") || {
    echo "Error: plan_state_key failed" >&2
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

STATE_FILE="${FLAGS_DIR}/.plan-state-${PLAN_STATE_KEY}"

ACTIVE_PLAN=""
PENDING=0
if [[ -f "$STATE_FILE" ]]; then
    prev_plan=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
    if [[ -n "$prev_plan" ]] && [[ -f "$prev_plan" ]]; then
        ACTIVE_PLAN="$prev_plan"
    fi
fi

if [[ -n "$ACTIVE_PLAN" ]]; then
    PENDING=$(grep -c '^[[:space:]]*- \[ \]' "$ACTIVE_PLAN" 2>/dev/null) || PENDING=0
fi

# Create pending-reload flag
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S%z)
if [[ -n "$ACTIVE_PLAN" ]] && [[ $PENDING -gt 0 ]]; then
    FLAG_TYPE="plan-pending"
elif [[ -n "$ACTIVE_PLAN" ]]; then
    FLAG_TYPE="plan-completed"
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

EXTRACT_FACTS_SCRIPT="${SCRIPT_DIR}/../../smith-checkpoint/scripts/extract-session-facts.sh"
EXTRACTED_FACTS=""
FACTS_SUMMARY=""
if [[ -f "$EXTRACT_FACTS_SCRIPT" ]] && [[ -x "$EXTRACT_FACTS_SCRIPT" ]]; then
    EXTRACTED_FACTS=$("$EXTRACT_FACTS_SCRIPT" "$TRANSCRIPT_PATH" 2>/dev/null || echo "")

    FACTS_FILE="${CLAUDE_JOB_DIR:-/tmp}/session-facts-${CWD_KEY}.md"
    printf '%s\n' "$EXTRACTED_FACTS" > "$FACTS_FILE"

    FILE_COUNT=$(echo "$EXTRACTED_FACTS" | sed -n '/## Files Modified/,/^$/p' | grep -c '^- ') || FILE_COUNT=0
    PR_COUNT=$(echo "$EXTRACTED_FACTS" | sed -n '/## PRs/,/^$/p' | grep -c '^- ') || PR_COUNT=0
    COMMIT_INFO=$(echo "$EXTRACTED_FACTS" | sed -n '/## Commits/,/^$/p' | grep '^- [0-9]' | head -1 || true)
    GIT_STATE=$(echo "$EXTRACTED_FACTS" | sed -n '/## Git State/,/^$/p' | grep '^- Git:' | head -1 || true)

    FACTS_SUMMARY="Session: "
    [[ $FILE_COUNT -gt 0 ]] && FACTS_SUMMARY+="${FILE_COUNT} files modified, "
    [[ $PR_COUNT -gt 0 ]] && FACTS_SUMMARY+="${PR_COUNT} PR operations, "
    [[ -n "$COMMIT_INFO" ]] && FACTS_SUMMARY+="${COMMIT_INFO#- }, "
    FACTS_SUMMARY+="${GIT_STATE#- }"
    FACTS_SUMMARY="${FACTS_SUMMARY%, }"
fi

case "$FLAG_TYPE" in
    plan-pending)
        STATUS="Context at ${CONTEXT_PCT}% (${PENDING} pending)"
        ;;
    plan-completed)
        STATUS="Context at ${CONTEXT_PCT}% (plan completed)"
        ;;
    *)
        STATUS="Context at ${CONTEXT_PCT}%"
        ;;
esac

if auto_reset_dispatch_enabled; then
    REASON="${STATUS}. Checkpoint this session; a fresh background session then continues from the checkpoint."
else
    REASON="${STATUS}. Checkpoint this session, then /clear."
fi

AGENT_CONTEXT=""
[[ -n "$FACTS_SUMMARY" ]] && AGENT_CONTEXT="${FACTS_SUMMARY}

"

json_stop_block "$REASON" "$AGENT_CONTEXT"
