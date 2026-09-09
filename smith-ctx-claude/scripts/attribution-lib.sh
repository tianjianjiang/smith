#!/usr/bin/env bash

ATTRIBUTION_PLANS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plans"

attribution_cwd_root() {
    local cwd="${1:-$PWD}" root
    if root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) && [[ -n "$root" ]]; then
        printf '%s' "$root"
        return 0
    fi
    if root=$(cd -- "$cwd" 2>/dev/null && pwd -P) && [[ -n "$root" ]]; then
        printf '%s' "$root"
        return 0
    fi
    printf '%s' "$cwd"
}

attribution_cwd_key() {
    local root hash
    root=$(attribution_cwd_root "${1:-$PWD}")
    hash=$(printf '%s' "$root" | md5 -q 2>/dev/null) \
        || hash=$(printf '%s' "$root" | md5sum 2>/dev/null | cut -d' ' -f1) \
        || hash=$(printf '%s' "$root" | shasum 2>/dev/null | cut -d' ' -f1) \
        || hash=$(printf '%s' "$root" | cksum 2>/dev/null | cut -d' ' -f1) \
        || return 1
    [[ -n "$hash" ]] || return 1
    printf '%s' "${hash:0:16}"
}

attribution_model_file() {
    local key
    key=$(attribution_cwd_key "${1:-$PWD}") || return 1
    printf '%s' "${ATTRIBUTION_PLANS_DIR}/.assisted-model-${key}"
}

attribution_model_from_transcript() {
    local transcript="$1"
    [[ -n "$transcript" && -r "$transcript" ]] || return 0
    tail -c 204800 "$transcript" 2>/dev/null \
        | jq -rR 'fromjson?
            | select(.type == "assistant" and (.isSidechain != true)
                     and (.message.model | type == "string")
                     and (.message.model | contains("claude-")))
            | .message.model' 2>/dev/null \
        | tail -1
}

attribution_check_body() {
    local body="$1"
    if ! grep -qE 'Assisted-by: Claude:claude-(sonnet|opus|haiku|fable)-[0-9]+(-[0-9]+)?(-[0-9]+)?' <<< "$body"; then
        echo "Error: Missing or invalid assisted-by attribution" >&2
        echo "" >&2
        echo "Required format:" >&2
        ~/.smith/smith-ctx-claude/scripts/attribution.sh >&2
        echo "" >&2
        echo "NEVER hand-type the attribution - always run the script above" >&2
        return 2
    fi
    if grep -qi "on behalf of" <<< "$body"; then
        echo "Error: Found forbidden 'on behalf of' pattern" >&2
        echo "Use assisted-by attribution only (run attribution.sh)" >&2
        return 2
    fi
    return 0
}
