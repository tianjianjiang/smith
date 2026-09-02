#!/bin/bash
#
# lib-context.sh - Context management utilities for Claude Code hooks
#
# Provides model-aware context percentage calculation from transcript JSONL.
# This is the canonical location for context-related functions; plan-claude
# sources this for context management.
#
# Source this file at the top of hook scripts:
#   source "$(dirname "$0")/lib-context.sh"

set -o pipefail

# Directory for flag/state files (shared with plan-claude)
CTX_FLAGS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plans"

# Default context window size (fallback for unknown models)
CONTEXT_WINDOW_TOKENS=${CONTEXT_WINDOW_TOKENS:-200000}

# Check for jq dependency (required for JSON parsing)
require_jq() {
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required but not found. Install: brew install jq (macOS) or apt-get install jq (Linux)" >&2
        exit 1
    fi
}

# Compute session key hash for flag and state files that must survive /clear.
# Hashes PPID:CWD for per-session isolation (concurrent sessions in same CWD
# get different keys). PPID = Claude Code's PID, stable across /clear.
# _SMITH_PPID env var overrides $PPID (for testing).
# macOS: md5, Linux: md5sum, POSIX: shasum/cksum.
session_key() {
    local ppid="${1:-${_SMITH_PPID:-$PPID}}"
    local cwd="${2:-${PWD:-$(pwd)}}"
    local input="${ppid}:${cwd}"
    local hash
    hash=$(printf '%s' "$input" | md5 -q 2>/dev/null) || \
    hash=$(printf '%s' "$input" | md5sum 2>/dev/null | cut -d' ' -f1) || \
    hash=$(printf '%s' "$input" | shasum 2>/dev/null | cut -d' ' -f1) || \
    hash=$(printf '%s' "$input" | cksum 2>/dev/null | cut -d' ' -f1) || {
        echo "Error: no hash command found, cannot ensure session isolation" >&2
        return 1
    }
    printf '%s' "${hash:0:16}"
}

# Map model ID to context window size in tokens.
# Handles both SessionStart format (with [1m] suffix) and transcript format (without).
# Flagships (Opus/Fable/Mythos) are 1M and the [1m] suffix is authoritative;
# current-gen Sonnet (4.6-4.9, incl. Sonnet 5+) is 1M standard as of the
# Claude 5 model family (no opt-in needed); Haiku and legacy Sonnet (4.5 and
# older, incl. undated-minor-version IDs like "claude-sonnet-4-20250514")
# remain 200K; unknown IDs fall back to CONTEXT_WINDOW_TOKENS.
model_to_context_window() {
    local model="${1:-}"
    case "$model" in
        *\[1[mM]\])                    echo 1000000 ;;
        *sonnet-5*|*sonnet-4-[6-9]*)   echo 1000000 ;;
        *haiku*|*sonnet*)              echo 200000  ;;
        *claude-opus-*|*claude-fable-*|*claude-mythos-*) echo 1000000 ;;
        *)                             echo "${CONTEXT_WINDOW_TOKENS}" ;;
    esac
}

# Checkpoint labels: ASCII snake_case slugs, never empty.
# Plan labels come from the plan's first H1 (a trailing "Plan" after a dash is
# dropped), then the filename, then the literal plan_checkpoint.
slugify_label() {
    LC_ALL=C tr '[:upper:]' '[:lower:]' <<<"$1" | LC_ALL=C tr -c '[:alnum:]\n' '_' | sed 's/__*/_/g;s/^_//;s/_$//'
}

checkpoint_label_from_plan() {
    local plan_path="$1"
    local title label
    title=$(grep -m1 '^# ' "$plan_path" 2>/dev/null | sed -E 's/^# *//; s/[[:space:]]*(—|–|-)[[:space:]]*[Pp]lan[[:space:]]*$//')
    label=$(slugify_label "$title")
    [[ -z "$label" ]] && label=$(slugify_label "$(basename "$plan_path" .md)")
    [[ -z "$label" ]] && label="plan_checkpoint"
    label="${label:0:60}"
    printf '%s\n' "${label%_}"
}

checkpoint_label_from_cwd() {
    local cwd="$1"
    local slug
    slug=$(slugify_label "$(basename "$cwd")")
    echo "${slug:-session}_checkpoint"
}

# Save model ID to session-keyed file for cross-hook sharing.
save_session_model() {
    local session_key="$1" model="$2"
    [[ -n "$model" ]] && printf '%s\n' "$model" > "${CTX_FLAGS_DIR}/.model-${session_key}"
}

# Read model ID from session-keyed file.
read_session_model() {
    local session_key="$1"
    local f="${CTX_FLAGS_DIR}/.model-${session_key}"
    [[ -f "$f" ]] && cat "$f" 2>/dev/null
}

# Calculate context percentage from transcript JSONL token usage.
# Reads the last assistant message's usage object (same data as statusline).
# Returns integer percentage (0-100+).
#
# Usage: pct=$(get_context_percentage "/path/to/transcript.jsonl" [context_window])
get_context_percentage() {
    local transcript="$1"
    local context_window="${2:-}"

    if [[ ! -f "$transcript" ]]; then
        echo "0"
        return
    fi

  
  
    local last_line
    last_line=$(tail -c 204800 "$transcript" 2>/dev/null \
        | grep '^{' \
        | grep '"assistant"' | tail -1) || last_line=""

    if [[ -z "$last_line" ]]; then
        echo "0"
        return
    fi

    local total
    total=$(echo "$last_line" | jq -r '
        .message.usage
        | ((.input_tokens // 0) + (.cache_read_input_tokens // 0)
           + (.cache_creation_input_tokens // 0) + (.output_tokens // 0))
    ' 2>/dev/null) || total=""

    if [[ -z "$total" ]] || [[ "$total" == "null" ]] || ! [[ "$total" =~ ^[0-9]+$ ]]; then
        echo "0"
        return
    fi

  
    if [[ -z "$context_window" ]]; then
        local model
        model=$(echo "$last_line" | jq -r '.message.model // empty' 2>/dev/null) || model=""
        if [[ -n "$model" ]]; then
            context_window=$(model_to_context_window "$model")
        else
            context_window="$CONTEXT_WINDOW_TOKENS"
        fi
    fi

    if [[ "$context_window" -le 0 ]]; then
        echo "0"
        return
    fi

    echo "$((total * 100 / context_window))"
}

# Resolve context percentage with session-model priority.
# Uses saved session model when available (more reliable than transcript auto-detect
# after /compact which may have empty/truncated transcript).
# Args: $1 = transcript path, $2 = CWD key
resolve_context_percentage() {
    local transcript="$1" cwd_key="$2"
    local session_model
    session_model=$(read_session_model "$cwd_key")
    if [[ -n "$session_model" ]]; then
        get_context_percentage "$transcript" "$(model_to_context_window "$session_model")"
    else
        get_context_percentage "$transcript"
    fi
}

# Helper: output JSON for Stop hook block decisions using jq for proper escaping
json_stop_block() {
    local reason="$1"
    jq -n --arg r "$reason" '{
        decision: "block",
        reason: $r
    }'
}

json_hook_output() {
    local event="$1" content="$2"
    jq -n --arg e "$event" --arg c "$content" '{
        hookSpecificOutput: {
            hookEventName: $e,
            additionalContext: $c
        }
    }'
}
