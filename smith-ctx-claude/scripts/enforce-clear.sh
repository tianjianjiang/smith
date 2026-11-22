#!/bin/bash
#
# enforce-clear.sh - Unified Stop hook for context management
#
# Canonical location: smith-ctx-claude (context management foundation).
# Handles both plan and non-plan contexts (single hook design).
#
# Measures the context from the transcript's token usage and sends each
# stop it does not settle first to the per-session state kept by
# ctx-reset-state.sh; the state answers allow, block, dispatch or unspecified.
# On unspecified the older path runs: it blocks at the critical threshold and,
# in a background session the state holds no record of, may dispatch from
# the PPID:CWD-keyed flag files.
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
        move_file_to_temp "$marker"
    done < <(find "$CTX_FLAGS_DIR" -maxdepth 1 -name '.auto-reset-attempt-*' -mmin +60 2>/dev/null)
}

dispatch_successor_session() {
    local hook_cwd="${HOOK_CWD:-${PWD:-}}"
    local own_key physical_cwd physical_key pending_reload attempt_marker
    local eligible_flags flag label
    own_key=$(session_key "" "$hook_cwd") || return 0
    physical_cwd=$(cd -- "$hook_cwd" 2>/dev/null && pwd -P) || physical_cwd="$hook_cwd"
    physical_key=$(session_key "" "$physical_cwd") || physical_key=""
    pending_reload="${CTX_FLAGS_DIR}/.pending-reload-${own_key}"
    attempt_marker="${CTX_FLAGS_DIR}/.auto-reset-attempt-${own_key}"
    remove_abandoned_attempt_markers "$own_key"
    if [[ ! -f "$pending_reload" ]]; then
        move_file_to_temp "$attempt_marker"
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
    if launch_successor "$label" "$(sed -n '2p' "$flag")"; then
        move_file_to_temp "$flag"
        json_system_message SMITH_CTX_CONTINUED "Context reset: the work continues in background session ${SUCCESSOR_ID} named \"${SUCCESSOR_NAME}\"."
    else
        json_system_message SMITH_CTX_DISPATCH_FAILED "$(dispatch_failed_text "$label")"
    fi
}

launch_successor() {
    local label="$1" checkpoint_time="$2" prompt mode
    SUCCESSOR_NAME="${checkpoint_time:+${checkpoint_time:0:16} }${label}"
    SUCCESSOR_ID=""
    prompt="This session continues an earlier session whose context was full. Restore the checkpoint \"${label}\": ${CHECKPOINT_READ_ONE_BACKEND}. Then report the restored context and continue the work thread."
    mode=$(jq -r '.permission_mode // empty' <<<"$INPUT" 2>/dev/null)
    local launch_options=(--bg --name "$SUCCESSOR_NAME")
    [[ -n "$mode" ]] && launch_options+=(--permission-mode "$mode")
    LAUNCH_OUTPUT=$(cd -- "${HOOK_CWD:-${PWD:-}}" && claude "${launch_options[@]}" -- "$prompt" < /dev/null 2>&1)
    [[ "$LAUNCH_OUTPUT" =~ backgrounded\ ·\ ([0-9A-Za-z_-]+) ]] || return 1
    SUCCESSOR_ID="${BASH_REMATCH[1]}"
}

dispatch_failed_text() {
    local reason
    reason=$(first_output_line "$LAUNCH_OUTPUT")
    if [[ "${2:-flagged}" == unflagged ]]; then
        printf 'Context reset: dispatching a background session for checkpoint "%s" failed%s; no restore flag was written for it, so restore it by its label in a new session.' "$1" "${reason:+ (${reason})}"
    else
        printf 'Context reset: dispatching a background session for checkpoint "%s" failed%s; /clear still restores the checkpoint.' "$1" "${reason:+ (${reason})}"
    fi
}

readonly STATE_SCRIPT="${SCRIPT_DIR}/ctx-reset-state.sh"
readonly STATE_UNSPECIFIED="unspecified - unknown"
readonly PENDING_RESTORE_PREFIX=".pending-memory-restore-"
readonly CONSUMED_RESTORE_PREFIX=".consumed-memory-restore-"

set_consumed_restore_flag_aside() {
    local flag="$1" name="${1##*/}"
    [[ -f "$flag" && "$name" == "${PENDING_RESTORE_PREFIX}"* ]] || return 0
    mv -f -- "$flag" "${flag%/*}/${CONSUMED_RESTORE_PREFIX}${name#"${PENDING_RESTORE_PREFIX}"}" 2>/dev/null \
        || echo "Context reset: could not set the restore flag aside: ${flag}" >&2
}

dispatch_from_state() {
    local label flag
    label=$(state_field label)
    flag=$(state_field flag)
    if launch_successor "$label" "$(sed -n '2p' "$flag" 2>/dev/null)"; then
        "$STATE_SCRIPT" "$SESSION_ID" dispatched "successor=${SUCCESSOR_ID}" > /dev/null 2>&1
        set_consumed_restore_flag_aside "$flag"
        json_stop_block "$(coded SMITH_CTX_CONTINUED "Context reset: the work continues in background session ${SUCCESSOR_ID} named \"${SUCCESSOR_NAME}\". End this turn without further work.")"
    else
        "$STATE_SCRIPT" "$SESSION_ID" dispatch-unrecognized > /dev/null 2>&1
        json_system_message SMITH_CTX_DISPATCH_FAILED "$(dispatch_failed_text "$label" "$([[ -f "$flag" ]] || echo unflagged)")"
    fi
    exit 0
}

exit_on_state_dispatch() {
    [[ "$STATE_ACTION" == dispatch ]] && dispatch_from_state
    return 0
}

readonly TOOL_CALL_AFTER_THE_WRITE='
    def instant: (.[0:19] + "Z" | fromdateiso8601);
    ($written_at | instant - (if .[19:20] == "-" then -1 else 1 end) * ((.[20:22] | tonumber) * 3600 + (.[23:25] | tonumber) * 60)) as $write
    | reduce (inputs | fromjson? | select(.type == "assistant")) as $entry ({write_call_seen: false, worked: false};
        ($entry.timestamp | if type == "string" then instant else null end) as $called
        | reduce ($entry.message.content[]? | select(.type == "tool_use")) as $call (.;
            if $called != null and $called < $write and (($call.input.command? // "") | tostring | contains("write-checkpoint.sh"))
            then {write_call_seen: true, worked: false}
            elif .write_call_seen or $called == null or $called >= $write
            then .worked = true
            else . end))
    | .worked'

worked_since_the_checkpoint() {
    local written_at tool_call_follows
    [[ "$("$STATE_SCRIPT" "$SESSION_ID" show 2>/dev/null)" == "state=checkpointed" ]] || { echo 0; return; }
    written_at=$(state_field written_at)
    if tool_call_follows=$(jq -nR --arg written_at "$written_at" "$TOOL_CALL_AFTER_THE_WRITE" "$TRANSCRIPT_PATH" 2>/dev/null) && [[ "$tool_call_follows" == false ]]; then
        echo 0
    else
        echo 1
    fi
}

stop_answer_of_state() {
    local percentage="$1" active="$2" high=0 dispatch=off answer
    [[ -n "$SESSION_ID" && -x "$STATE_SCRIPT" ]] || { echo "$STATE_UNSPECIFIED"; return; }
    [[ "$percentage" =~ ^[0-9]+$ && $percentage -ge $CRITICAL_PCT ]] && high=1
    auto_reset_dispatch_enabled && dispatch=on
    answer=$("$STATE_SCRIPT" "$SESSION_ID" stop "high=${high}" "active=${active}" "dispatch=${dispatch}" "worked=$(worked_since_the_checkpoint)" 2>/dev/null) || answer="$STATE_UNSPECIFIED"
    echo "$answer"
}

continuation_stop_percentage() {
    local cwd_key
    transcript_readable || return 0
    cwd_key=$(session_key "" "${HOOK_CWD:-${PWD:-}}") || return 0
    resolve_context_percentage "$TRANSCRIPT_PATH" "$cwd_key"
}

state_field() {
    "$STATE_SCRIPT" "$SESSION_ID" show-field "$1" 2>/dev/null
}

state_records_this_session() {
    [[ -n "$SESSION_ID" && -x "$STATE_SCRIPT" && "$("$STATE_SCRIPT" "$SESSION_ID" known 2>/dev/null)" == yes ]]
}

already_continued_text() {
    local successor
    successor=$(state_field successor)
    if [[ -n "$successor" ]]; then
        printf 'Context reset: the work already continues in background session %s; this stop is allowed.' "$successor"
    else
        printf 'Context reset: a background session was already tried for this checkpoint and is not tried again; this stop is allowed.'
    fi
}

checkpoint_written_text() {
    local label
    label=$(state_field label)
    if [[ -n "$(state_field flag)" ]]; then
        printf 'Context reset: checkpoint "%s" is written; type /clear to continue from it.' "$label"
    else
        printf 'Context reset: checkpoint "%s" is written, but no restore flag was written for it; restore it by its label in a new session.' "$label"
    fi
}

allowed_stop_text() {
    case "$1" in
        SMITH_CTX_CHECKPOINT_IN_PROGRESS) printf 'Context reset: a checkpoint is in progress; this stop is allowed.' ;;
        SMITH_CTX_CHECKPOINT_WRITTEN) checkpoint_written_text ;;
        SMITH_CTX_ALREADY_CONTINUED) already_continued_text ;;
        *) return 1 ;;
    esac
}

CHECKPOINT_OUT_OF_DATE=false

ask_the_state_about_this_stop() {
    local percentage="$1" active="$2" state_before answer="$STATE_UNSPECIFIED"
    state_before=$("$STATE_SCRIPT" "$SESSION_ID" show 2>/dev/null)
    [[ "$active" == 1 && -z "$percentage" ]] || answer=$(stop_answer_of_state "$percentage" "$active")
    read -r STATE_ACTION STATE_CODE STATE_NEXT <<<"$answer"
    [[ "$state_before" == "state=checkpointed" && "$STATE_ACTION" == block ]] && CHECKPOINT_OUT_OF_DATE=true
    return 0
}

exit_when_a_checkpoint_waits_unmeasured() {
    local percentage="$1" written
    [[ "$STATE_ACTION" == allow && "$STATE_CODE" == - && "$STATE_NEXT" == checkpointed ]] || return 0
    [[ "$percentage" =~ ^[1-9][0-9]*$ ]] && return 0
    written=$(checkpoint_written_text)
    json_system_message SMITH_CTX_CONTEXT_UNMEASURED "Context reset: the context level could not be measured from the transcript ${TRANSCRIPT_PATH}, so no background session was started; ${written#Context reset: }"
    exit 0
}

exit_when_state_allows() {
    local text
    [[ "$STATE_ACTION" == allow && "$STATE_CODE" != - ]] || return 0
    text=$(allowed_stop_text "$STATE_CODE") || return 0
    json_system_message "$STATE_CODE" "$text"
    exit 0
}

if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
    CONTINUATION_PCT=$(continuation_stop_percentage)
    ask_the_state_about_this_stop "$CONTINUATION_PCT" 1
    exit_on_state_dispatch
    exit_when_a_checkpoint_waits_unmeasured "$CONTINUATION_PCT"
    exit_when_state_allows
    if [[ "$STATE_ACTION" != block ]]; then
        [[ "$STATE_ACTION" == allow && "$STATE_CODE" == - ]] && exit 0
        state_records_this_session && exit 0
        auto_reset_dispatch_enabled && dispatch_successor_session
        exit 0
    fi
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
    move_file_to_temp "$EXIT_MARKER"
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
ask_the_state_about_this_stop "$CONTEXT_PCT" 0
exit_on_state_dispatch
exit_when_a_checkpoint_waits_unmeasured "$CONTEXT_PCT"
exit_when_state_allows

case "$STATE_ACTION" in
    allow) exit 0 ;;
    block) ;;
    *) [[ $CONTEXT_PCT -lt $CRITICAL_PCT ]] && exit 0 ;;
esac

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
FACTS_SUMMARY=""
if [[ -f "$EXTRACT_FACTS_SCRIPT" ]] && [[ -x "$EXTRACT_FACTS_SCRIPT" ]]; then
    EXTRACTED_FACTS=$("$EXTRACT_FACTS_SCRIPT" "$TRANSCRIPT_PATH" 2>/dev/null || echo "")

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

block_reason_is_coded() {
    if [[ "$STATE_ACTION" == block ]]; then
        [[ "$STATE_CODE" == "$AUTO_RESET_BLOCKED" ]]
    else
        auto_reset_dispatch_enabled
    fi
}

if block_reason_is_coded; then
    REASON=$(coded "$AUTO_RESET_BLOCKED" "${STATUS}. Checkpoint this session; a fresh background session then continues from the checkpoint.")
else
    REASON="${STATUS}. Checkpoint this session, then /clear."
fi

if [[ "$CHECKPOINT_OUT_OF_DATE" == true ]]; then
    REASON+=" A tool call followed the earlier checkpoint, so that checkpoint is not handed on; after the new checkpoint, stop without another tool call."
fi

AGENT_CONTEXT=""
[[ -n "$FACTS_SUMMARY" ]] && AGENT_CONTEXT="${FACTS_SUMMARY}

"

json_stop_block "$REASON" "$AGENT_CONTEXT"
