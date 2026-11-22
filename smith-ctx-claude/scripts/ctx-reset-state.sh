#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib-context.sh"

readonly SESSION_ID="${1:-}"
readonly EVENT="${2:-}"

usage() {
    echo "usage: ctx-reset-state.sh «session-id» «event» [name=value ...]" >&2
    echo "events: stop high=0|1 active=0|1 dispatch=on|off worked=0|1; checkpoint-started; checkpoint-written label=… flag=…; dispatched successor=…; dispatch-unrecognized; known; show; show-field «name»" >&2
    echo "a value holds no newline" >&2
    exit 64
}

[[ -n "$SESSION_ID" && -n "$EVENT" && "$SESSION_ID" != */* && "$SESSION_ID" != .* ]] || usage

readonly STATE_FILE="${CTX_FLAGS_DIR}/.ctx-reset-state-${SESSION_ID}"

field() {
    local name="$1" line
    [[ -f "$STATE_FILE" ]] || return 0
    while IFS= read -r line; do
        [[ "$line" == "$name="* ]] && { printf '%s' "${line#*=}"; return 0; }
    done < "$STATE_FILE"
}

current_state() {
    local state
    state=$(field state)
    printf '%s' "${state:-idle}"
}

local_time_iso() {
    local stamp
    stamp=$(date +%Y-%m-%dT%H:%M:%S%z)
    printf '%s:%s' "${stamp:0:${#stamp}-2}" "${stamp: -2}"
}

save() {
    local scratch
    mkdir -p "$CTX_FLAGS_DIR" \
        && scratch=$(mktemp "${STATE_FILE}.XXXXXX") \
        && printf '%s\n' "$@" > "$scratch" \
        && mv -f "$scratch" "$STATE_FILE" \
        || { echo "state write failed: ${STATE_FILE}" >&2; exit 1; }
}

argument() {
    local name="$1" pair
    for pair in "${EVENT_ARGUMENTS[@]:-}"; do
        [[ "$pair" == "$name="* ]] && { printf '%s' "${pair#*=}"; return 0; }
    done
}

answer() {
    printf '%s %s %s\n' "$1" "$2" "$3"
}

unspecified() {
    answer unspecified - "$1"
}

code_when_dispatch_on() {
    if [[ "$1" == on ]]; then printf '%s' "$2"; else printf -- '-'; fi
}

save_continued() {
    save "state=continued" "label=$(field label)" "flag=$(field flag)" "written_at=$(field written_at)" "$@"
}

on_stop_while_idle() {
    local high="$1" active="$2" dispatch="$3"
    if [[ "$active" == 1 ]]; then
        unspecified idle
    elif [[ "$high" == 1 ]]; then
        answer block "$(code_when_dispatch_on "$dispatch" SMITH_CTX_AUTO_RESET_BLOCKED)" idle
    else
        answer allow - idle
    fi
}

on_stop_while_checkpointed() {
    local high="$1" active="$2" dispatch="$3" worked="$4"
    if [[ "$worked" != 0 ]]; then
        save "state=idle"
        if [[ "$high" == 1 ]]; then
            answer block "$(code_when_dispatch_on "$dispatch" SMITH_CTX_AUTO_RESET_BLOCKED)" idle
        else
            on_stop_while_idle "$high" "$active" "$dispatch"
        fi
    elif [[ "$high" != 1 ]]; then
        answer allow - checkpointed
    elif [[ "$dispatch" == on ]]; then
        save_continued
        answer dispatch - continued
    else
        answer allow SMITH_CTX_CHECKPOINT_WRITTEN checkpointed
    fi
}

on_stop() {
    local state="$1" high active dispatch
    high=$(argument high)
    active=$(argument active)
    dispatch=$(argument dispatch)
    case "$state" in
        idle) on_stop_while_idle "$high" "$active" "$dispatch" ;;
        checkpointing) answer allow SMITH_CTX_CHECKPOINT_IN_PROGRESS checkpointing ;;
        checkpointed) on_stop_while_checkpointed "$high" "$active" "$dispatch" "$(argument worked)" ;;
        continued) answer allow SMITH_CTX_ALREADY_CONTINUED continued ;;
        *) unspecified "$state" ;;
    esac
}

on_checkpoint_started() {
    local state="$1"
    case "$state" in
        idle|checkpointed) save "state=checkpointing" ;;
        checkpointing) ;;
        *) unspecified "$state"; return ;;
    esac
    answer record - checkpointing
}

on_checkpoint_written() {
    local state="$1"
    case "$state" in
        idle|checkpointing|checkpointed) ;;
        *) unspecified "$state"; return ;;
    esac
    save "state=checkpointed" "label=$(argument label)" "flag=$(argument flag)" "written_at=$(local_time_iso)"
    answer record - checkpointed
}

record_launch_outcome() {
    save_continued "launch=$1" "successor=$2"
}

on_dispatch_result() {
    local state="$1" recognized="$2"
    [[ "$state" == continued && -z "$(field launch)" ]] || { unspecified "$state"; return; }
    if [[ "$recognized" == yes ]]; then
        record_launch_outcome recognized "$(argument successor)"
        answer block SMITH_CTX_CONTINUED continued
    else
        record_launch_outcome unrecognized ""
        answer allow SMITH_CTX_DISPATCH_FAILED continued
    fi
}

recorded_values_hold_no_newline() {
    local pair
    for pair in "$@"; do
        [[ "$pair" != *$'\n'* ]] || return 1
    done
}

shift 2
recorded_values_hold_no_newline "$@" || usage
EVENT_ARGUMENTS=("$@")
STATE=$(current_state)

case "$EVENT" in
    known) if [[ -f "$STATE_FILE" ]]; then echo yes; else echo no; fi ;;
    show) printf 'state=%s\n' "$STATE" ;;
    show-field) [[ $# -eq 1 ]] || usage; field "$1"; echo ;;
    stop) on_stop "$STATE" ;;
    checkpoint-started) on_checkpoint_started "$STATE" ;;
    checkpoint-written) on_checkpoint_written "$STATE" ;;
    dispatched) on_dispatch_result "$STATE" yes ;;
    dispatch-unrecognized) on_dispatch_result "$STATE" no ;;
    *) usage ;;
esac
