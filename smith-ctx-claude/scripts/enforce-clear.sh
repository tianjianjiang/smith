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

readonly AUTO_RESET_BLOCKED=SMITH_CTX_AUTO_RESET_BLOCKED

coded() {
    printf '[%s] %s' "$1" "$2"
}

json_system_message() {
    jq -n --arg m "$(coded "$1" "$2")" '{systemMessage: $m}'
}

first_output_line() {
    local line
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -n "$line" ]] && { printf '%s' "${line:0:200}"; return; }
    done <<<"$1"
}

stopped_without_successor() {
    json_system_message "$1" "Context reset: $2. No background session was started; checkpoint this session if it has not been checkpointed, then type /clear."
}

transcript_readable() {
    [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" && -r "$TRANSCRIPT_PATH" ]]
}

stop_hook_records() {
    jq -R -c 'def attachment_errors:
            if .type != "hook_blocking_error" then []
            elif (.blockingError | type) == "object" and (.blockingError.blockingError | type) == "string" then [.blockingError.blockingError]
            else null end;
        fromjson? | select(type == "object")
        | if .type == "system" and .subtype == "stop_hook_summary" and (has("hookLabel") | not) then {id: .toolUseID, errors: .hookErrors}
          elif .type == "attachment" and (.attachment | type) == "object" and .attachment.hookEvent == "Stop" then
            {id: .attachment.toolUseID, errors: (.attachment | attachment_errors)}
          else empty end' "$TRANSCRIPT_PATH"
}

latest_stop_batch_verdict() {
    local records
    records=$(stop_hook_records 2>/dev/null) || { printf 'unknown'; return; }
    jq -r -s --arg code "$(coded "$AUTO_RESET_BLOCKED" "")" '
        if length == 0 then "unknown" else
          last.id as $id
          | (if $id == null then [last] else map(select(.id == $id)) end) as $batch
          | if any($batch[]; .errors | type != "array") then "unknown"
            elif any($batch[] | .errors[]; type == "string" and startswith($code)) then "blocked"
            else "other" end
        end' <<<"$records" 2>/dev/null || printf 'unknown'
}

pending_reload_names_this_session() {
    [[ -n "$SESSION_ID" && "$(sed -n '2p' "$1" 2>/dev/null)" == "$SESSION_ID" ]]
}

block_already_attempted() {
    local attempt_marker="$1" pending_reload="$2"
    [[ -f "$attempt_marker" && ! "$attempt_marker" -ot "$pending_reload" ]]
}

unhandled_block_of_this_session() {
    local pending_reload="$1" attempt_marker="$2"
    pending_reload_names_this_session "$pending_reload" && ! block_already_attempted "$attempt_marker" "$pending_reload"
}

readonly UNHANDLED_BLOCK_CLAUSE="records a block of this session that no attempt has handled"

key_of_this_sessions_block_elsewhere() {
    local own_key="$1" flag
    [[ -n "$SESSION_ID" ]] || return 1
    for flag in "${CTX_FLAGS_DIR}"/.pending-reload-*; do
        [[ -f "$flag" && "$flag" != *.exit-marker && "$flag" != "${CTX_FLAGS_DIR}/.pending-reload-${own_key}" ]] || continue
        pending_reload_names_this_session "$flag" || continue
        printf '%s' "${flag##*/.pending-reload-}"
        return 0
    done
    return 1
}

report_unreadable_transcript() {
    local own_key="$1" pending_reload="$2" attempt_marker="$3"
    if unhandled_block_of_this_session "$pending_reload" "$attempt_marker"; then
        stopped_without_successor SMITH_CTX_TRANSCRIPT_UNREADABLE "the transcript ${TRANSCRIPT_PATH:-(no path given)} cannot be read, and .pending-reload-${own_key} ${UNHANDLED_BLOCK_CLAUSE}"
    fi
}

context_still_critical_or_say_why() {
    local cwd_key="$1" pending_reload="$2" attempt_marker="$3" percentage verdict
    percentage=$(resolve_context_percentage "$TRANSCRIPT_PATH" "$cwd_key")
    [[ "$percentage" =~ ^[0-9]+$ ]] || percentage=0
    [[ $percentage -ge $CRITICAL_PCT ]] && return 0
    verdict=$(latest_stop_batch_verdict)
    if [[ "$verdict" == unknown ]] && unhandled_block_of_this_session "$pending_reload" "$attempt_marker"; then
        stopped_without_successor SMITH_CTX_TRANSCRIPT_FORMAT_UNKNOWN "the transcript ${TRANSCRIPT_PATH} holds no stop hook record in a known format, and .pending-reload-${cwd_key} ${UNHANDLED_BLOCK_CLAUSE}"
        return 1
    fi
    [[ "$verdict" == blocked ]] || return 1
    block_already_attempted "$attempt_marker" "$pending_reload" && return 1
    if [[ $percentage -eq 0 ]]; then
        stopped_without_successor SMITH_CTX_CONTEXT_UNMEASURED "after this hook blocked the stop, the context level could not be measured from the transcript ${TRANSCRIPT_PATH}"
    else
        json_system_message SMITH_CTX_CONTEXT_NO_LONGER_CRITICAL "Context reset: after this hook blocked the stop, context is at ${percentage}%, below the critical ${CRITICAL_PCT}%, so no background session was started and none is needed."
    fi
    return 1
}

report_missing_pending_reload() {
    local own_key="$1" other_key
    transcript_readable || return 0
    case "$(latest_stop_batch_verdict)" in
        unknown)
            stopped_without_successor SMITH_CTX_TRANSCRIPT_FORMAT_UNKNOWN "the transcript ${TRANSCRIPT_PATH} holds no stop hook record in a known format, and whether this hook blocked this session is unknown"
            ;;
        blocked)
            other_key=$(key_of_this_sessions_block_elsewhere "$own_key")
            stopped_without_successor SMITH_CTX_PENDING_RELOAD_MISSING "this session was blocked, but .pending-reload-${own_key} is missing${other_key:+ (the one for this session is filed under the session key ${other_key})}"
            ;;
    esac
}

remove_abandoned_attempt_markers() {
    local own_key="$1" marker marker_key
    while IFS= read -r marker; do
        [[ -n "$marker" ]] || continue
        marker_key="${marker##*/.auto-reset-attempt-}"
        [[ "$marker_key" == "$own_key" || -f "${CTX_FLAGS_DIR}/.pending-reload-${marker_key}" ]] && continue
        rm -f "$marker"
    done < <(find "$CTX_FLAGS_DIR" -maxdepth 1 -name '.auto-reset-attempt-*' -mmin +60 2>/dev/null)
}

dispatch_successor_session() {
    local hook_cwd="${HOOK_CWD:-${PWD:-}}"
    local own_key physical_cwd physical_key pending_reload attempt_marker
    local eligible_flags flag label checkpoint_time name prompt mode output reason
    local launch_options=()
    own_key=$(session_key "" "$hook_cwd") || return 0
    physical_cwd=$(cd -- "$hook_cwd" 2>/dev/null && pwd -P) || physical_cwd="$hook_cwd"
    physical_key=$(session_key "" "$physical_cwd") || physical_key=""
    pending_reload="${CTX_FLAGS_DIR}/.pending-reload-${own_key}"
    attempt_marker="${CTX_FLAGS_DIR}/.auto-reset-attempt-${own_key}"
    remove_abandoned_attempt_markers "$own_key"
    if [[ ! -f "$pending_reload" ]]; then
        rm -f "$attempt_marker"
        report_missing_pending_reload "$own_key"
        return 0
    fi
    if ! transcript_readable; then
        report_unreadable_transcript "$own_key" "$pending_reload" "$attempt_marker"
        return 0
    fi
    context_still_critical_or_say_why "$own_key" "$pending_reload" "$attempt_marker" || return 0
    eligible_flags=$(eligible_restore_flags "$pending_reload" "$own_key" "$physical_key" "$attempt_marker")
    flag=$(newest_file_of "$eligible_flags")
    if [[ -z "$flag" ]]; then
        block_already_attempted "$attempt_marker" "$pending_reload" && return 0
        json_system_message SMITH_CTX_NO_CHECKPOINT "Context reset: no checkpoint was written after the block, so no background session was started. Checkpoint this session, or type /clear."
        return 0
    fi
    printf '%s\n' "$eligible_flags" >> "$attempt_marker"
    label=$(sed -n '4p' "$flag")
    checkpoint_time=$(sed -n '2p' "$flag")
    name="${checkpoint_time:0:16} ${label}"
    prompt="This session continues an earlier session whose context was full. Restore the checkpoint \"${label}\": ${CHECKPOINT_READ_ONE_BACKEND}. Then report the restored context and continue the work thread."
    mode=$(jq -r '.permission_mode // empty' <<<"$INPUT" 2>/dev/null)
    launch_options=(--bg --name "$name")
    [[ -n "$mode" ]] && launch_options+=(--permission-mode "$mode")
    output=$(cd -- "$hook_cwd" && claude "${launch_options[@]}" -- "$prompt" < /dev/null 2>&1)
    if [[ "$output" =~ backgrounded\ ·\ ([0-9A-Za-z_-]+) ]]; then
        rm -f "$flag"
        json_system_message SMITH_CTX_CONTINUED "Context reset: the work continues in background session ${BASH_REMATCH[1]} named \"${name}\"."
    else
        reason=$(first_output_line "$output")
        json_system_message SMITH_CTX_DISPATCH_FAILED "Context reset: dispatching a background session for checkpoint \"${label}\" failed${reason:+ (${reason})}; /clear still restores the checkpoint."
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
    REASON=$(coded "$AUTO_RESET_BLOCKED" "${STATUS}. Checkpoint this session; a fresh background session then continues from the checkpoint.")
else
    REASON="${STATUS}. Checkpoint this session, then /clear."
fi

AGENT_CONTEXT=""
[[ -n "$FACTS_SUMMARY" ]] && AGENT_CONTEXT="${FACTS_SUMMARY}

"

json_stop_block "$REASON" "$AGENT_CONTEXT"
