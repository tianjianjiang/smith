#!/usr/bin/env bash

ATTRIBUTION_PLANS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plans"
ATTRIBUTION_SESSION_ID_FORMAT='[A-Za-z0-9_-]+'
ATTRIBUTION_MODEL_ID_FORMAT='([A-Za-z0-9_-]+[.:])*claude-[a-z0-9][A-Za-z0-9._@:-]*[A-Za-z0-9]'

attribution_model_file() {
    local session_id="${1:-${CLAUDE_CODE_SESSION_ID:-}}"
    [[ "$session_id" =~ ^${ATTRIBUTION_SESSION_ID_FORMAT}$ ]] || return 1
    printf '%s' "${ATTRIBUTION_PLANS_DIR}/.assisted-model-${session_id}"
}

attribution_model_from_transcript() {
    local transcript="$1"
    [[ -r "$transcript" ]] || return 0
    tail -c 204800 "$transcript" 2>/dev/null \
        | jq -rR 'fromjson?
            | select(.type == "assistant" and (.isSidechain != true)
                     and (.message.model | type == "string")
                     and (.message.model | contains("claude-")))
            | .message.model' 2>/dev/null \
        | tail -1
}

attribution_model_is_well_formed() {
    [[ "$1" =~ ^${ATTRIBUTION_MODEL_ID_FORMAT}$ ]]
}

attribution_session_model() {
    local model_file model
    model_file=$(attribution_model_file "${1:-}") || return 1
    [[ -f "$model_file" ]] || return 1
    model=$(<"$model_file")
    model="${model//[$'\n\r\t ']/}"
    attribution_model_is_well_formed "$model" || return 1
    printf '%s' "$model"
}
