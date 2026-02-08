#!/bin/bash
#
# enforce-clear.sh - General-purpose Stop hook for context management
#
# Blocks the agent from stopping when context is high, ensuring work
# is committed and Serena memory persisted before context is lost.
#
# This hook is independent of plan-claude (no plan awareness).
# Both hooks can fire on the same Stop event; messages are complementary.
#
# Session Isolation: Uses CWD-based flag files so parallel Claude Code
# sessions (in different worktrees) don't interfere with each other.
#
# Conditions to block:
#   1. Transcript size > threshold
#   2. No CWD-specific .ctx-clear flag file (one-shot: second attempt passes)
#
# Env vars:
#   CTX_CONTEXT_THRESHOLD_KB - Threshold in KB (default: 500, ~60% of 200K)
#

set -eo pipefail

# Require jq for JSON parsing (hard dependency)
if ! command -v jq &>/dev/null; then
    echo "Error: enforce-clear.sh requires jq. Install: brew install jq (macOS) or apt install jq (Linux)" >&2
    exit 0  # Allow stop rather than permanently blocking
fi

# Shared directory with plan-claude for flag files (both use ~/.claude/plans/)
FLAGS_DIR="${HOME}/.claude/plans"
THRESHOLD_KB=${CTX_CONTEXT_THRESHOLD_KB:-500}
if ! [[ "$THRESHOLD_KB" =~ ^[0-9]+$ ]] || [[ "$THRESHOLD_KB" -le 0 ]]; then
    echo "Error: CTX_CONTEXT_THRESHOLD_KB must be a positive integer, got: '$THRESHOLD_KB'" >&2
    exit 0
fi
THRESHOLD_BYTES=$((THRESHOLD_KB * 1024))

INPUT=$(cat)

# --- Inlined helpers (no lib-common.sh dependency) ---

# Compute CWD key hash (8-char). macOS: md5, Linux: md5sum, POSIX: shasum/cksum
cwd_key() {
    local cwd="$1"
    if [[ -z "$cwd" ]]; then
        cwd="${PWD:-$(pwd)}"
    fi
    local hash
    hash=$(printf '%s' "$cwd" | md5 -q 2>/dev/null) || \
    hash=$(printf '%s' "$cwd" | md5sum 2>/dev/null | cut -d' ' -f1) || \
    hash=$(printf '%s' "$cwd" | shasum 2>/dev/null | cut -d' ' -f1) || \
    hash=$(printf '%s' "$cwd" | cksum 2>/dev/null | cut -d' ' -f1) || {
        echo "Warning: no hash command found (md5/md5sum/shasum/cksum), CWD isolation is disabled" >&2
        hash="00000000"
    }
    printf '%s' "${hash:0:8}"
}

# Output JSON for Stop hook block decisions (jq required, checked at top)
json_stop_block() {
    local reason="$1"
    jq -n --arg r "$reason" '{ decision: "block", reason: $r }'
}

# --- Main logic ---

# Extract CWD from hook input
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")

# CWD-keyed flag file (distinct from plan-claude's .pending-reload-*)
CWD_KEY=$(cwd_key "${HOOK_CWD:-${PWD:-}}")
FLAG_FILE="${FLAGS_DIR}/.ctx-clear-${CWD_KEY}"

# If flag exists, this is the second attempt -> allow stop
if [[ -f "$FLAG_FILE" ]]; then
    rm -f "$FLAG_FILE"
    exit 0
fi

# Check transcript size
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    exit 0
fi

TRANSCRIPT_SIZE=$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)
TRANSCRIPT_SIZE=$(echo "$TRANSCRIPT_SIZE" | tr -d '[:space:]')
if [[ $TRANSCRIPT_SIZE -le $THRESHOLD_BYTES ]]; then
    exit 0
fi

# BLOCK: context is high, clear not yet initiated
SIZE_KB=$((TRANSCRIPT_SIZE / 1024))

# Create one-shot flag: first block creates flag, second stop attempt passes
if ! mkdir -p "$FLAGS_DIR" 2>/dev/null; then
    echo "Error: enforce-clear.sh: Cannot create flags directory: $FLAGS_DIR" >&2
    exit 0  # Allow stop rather than permanently blocking
fi
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S%z)
if ! printf '%s\n%s\n%s\n' "$SESSION_ID" "$TIMESTAMP" "${HOOK_CWD:-${PWD:-}}" > "$FLAG_FILE" 2>/dev/null; then
    echo "Error: enforce-clear.sh: Cannot write flag file: $FLAG_FILE" >&2
    exit 0
fi

json_stop_block "Context at ${SIZE_KB}KB (threshold: ${THRESHOLD_KB}KB). Before stopping: (1) Commit any uncommitted work, (2) Persist state to Serena memory with write_memory(), (3) Recommend /clear to user. After /clear, use read_memory() to resume."
