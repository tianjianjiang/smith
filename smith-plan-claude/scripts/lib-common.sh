#!/bin/bash
#
# lib-common.sh - Shared utilities for plan-claude hook scripts
#
# Source this file at the top of each hook script:
#   source "$(dirname "$0")/lib-common.sh"

# Strict mode: exit on error, pipe failures propagated
set -eo pipefail

PLANS_DIR="${HOME}/.claude/plans"

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

# Helper: output JSON for Stop hook block decisions using jq for proper escaping
json_stop_block() {
    local reason="$1"
    jq -n --arg r "$reason" '{
        decision: "block",
        reason: $r
    }'
}
