#!/bin/bash
#
# lib-plan.sh - Plan, Ralph, and Orchestrator utilities for plan-claude hooks
#
# Context functions (session_key, get_context_percentage, etc.) live in
# smith-ctx-claude/scripts/lib-context.sh — sourced below for shared use.
#
# Source this file at the top of each plan-claude hook script:
#   source "$(dirname "$0")/lib-plan.sh"

# Strict mode: pipe failures propagated (no set -e; hooks must not abort on transient errors)
set -o pipefail

# Source context functions from canonical location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX_LIB="${SMITH_CTX_LIB:-${SCRIPT_DIR}/../../smith-ctx-claude/scripts/lib-context.sh}"
if [[ -f "$CTX_LIB" ]]; then
    source "$CTX_LIB"
else
    echo "Error: lib-context.sh not found at $CTX_LIB" >&2
    exit 1
fi

# Plan-specific constants
PLANS_DIR="$CTX_FLAGS_DIR"
RALPH_STATE_FILENAME="ralph-loop.local.md"
ORCH_STATE_PREFIX=".ralph-orchestrator-"

# Durable scope for a directory: the repository's MAIN working tree.
#
# A checkpoint is armed from wherever the session happens to stand, which for any
# repo-modifying task is `.claude/worktrees/<name>/` — a directory that is removed
# when the task ends. The repository it belongs to outlives it, so the repository
# is what identifies the work; the working directory only identifies a moment.
#
# `--git-common-dir` is what distinguishes a worktree from its main checkout:
# `--show-toplevel` would return the worktree's own root and defeat the purpose.
# It answers with an absolute path from inside a worktree and a relative `.git`
# from a main checkout, so the relative case is resolved against the input.
# An existing directory in no repository falls back to its own physical path, which
# also normalizes symlink spelling (/tmp vs /private/tmp).
#
# A directory that cannot be reached at all returns the EMPTY string, and callers
# must treat that as "not verifiable" rather than as an answer. Returning the raw
# input instead would make an unreachable path compare unequal to everything and so
# masquerade as a confident "belongs somewhere else" — the exact wrong reading for
# the common case of a checkpoint armed inside a worktree that has since been
# removed.
#
# Usage: key=$(scope_key "/some/dir")
# Answers one of three things, and they are distinguishable:
#   "repo:<main working tree>" — resolved to a repository
#   "dir:<physical path>"      — CHECKED to be inside no repository at all
#   ""                         — could not determine; the caller must claim nothing
scope_key() {
    local dir="${1:-}" phys common resolved probe
    [[ -n "$dir" ]] || return 0
    phys=$(cd -- "$dir" 2>/dev/null && pwd -P) || return 0
    [[ -n "$phys" ]] || return 0
    if common=$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR \
        git -C "$phys" rev-parse --git-common-dir 2>/dev/null) && [[ -n "$common" ]]; then
        [[ "$common" != /* ]] && common="${phys}/${common}"
        if resolved=$(cd -- "${common%/.git}" 2>/dev/null && pwd -P) && [[ -n "$resolved" ]]; then
            printf 'repo:%s' "$resolved"
            return 0
        fi
    fi
    probe="$phys"
    while :; do
        [[ -e "$probe/.git" ]] && return 0
        [[ "$probe" == "/" ]] && break
        probe="${probe%/*}"; probe="${probe:-/}"
    done
    printf 'dir:%s' "$phys"
}

# Parse a single field from YAML frontmatter text.
# Usage: value=$(parse_yaml_field "$frontmatter" "field_name")
parse_yaml_field() {
    local frontmatter="$1" field="$2"
    printf '%s\n' "$frontmatter" | grep "^${field}:" | sed "s/^${field}:[[:space:]]*//" \
        | sed 's/^"//; s/"$//' | sed "s/^'//; s/'$//"
}

# Read multiple lines from a file into an array.
# Usage: mapfile -t lines < <(read_file_lines "$file" 1 5)
read_file_lines() {
    local file="$1" start="$2" end="$3"
    sed -n "${start},${end}p" "$file" 2>/dev/null
}

# File mtime in epoch seconds, into _MTIME_OUT; empty when none could be read.
_MTIME_OUT=""
mtime_of() {
    _MTIME_OUT=$(stat -f %m "$1" 2>/dev/null)
    [[ "$_MTIME_OUT" =~ ^[0-9]+$ ]] || _MTIME_OUT=$(stat -c %Y "$1" 2>/dev/null)
    [[ "$_MTIME_OUT" =~ ^[0-9]+$ ]] || _MTIME_OUT=""
}

# Human-readable file mtime into _MTIME_HUMAN; "unknown" when none could be read.
_MTIME_HUMAN=""
mtime_human() {
    _MTIME_HUMAN=$(stat -c %y "$1" 2>/dev/null | cut -d'.' -f1)
    [[ -n "$_MTIME_HUMAN" ]] || _MTIME_HUMAN=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$1" 2>/dev/null)
    [[ -n "$_MTIME_HUMAN" ]] || _MTIME_HUMAN="unknown"
}

# Classify another artifact's recorded scope against THIS session's scope.
#   SCOPE_CLASS — selfunver | unver | same | foreign | outside
#   SCOPE_PRIO  — row priority; lower sorts first
scope_compare() {
    local own="$1" other="$2"
    if [[ -z "$own" ]]; then
        SCOPE_CLASS="selfunver"; SCOPE_PRIO=6
    elif [[ -z "$other" ]]; then
        SCOPE_CLASS="unver"; SCOPE_PRIO=5
    elif [[ "$other" == "$own" ]]; then
        SCOPE_CLASS="same"; SCOPE_PRIO=3
    elif [[ "$other" == repo:* && "$own" == repo:* ]]; then
        SCOPE_CLASS="foreign"; SCOPE_PRIO=6
    else
        SCOPE_CLASS="outside"; SCOPE_PRIO=6
    fi
}

json_user_prompt_output() { json_hook_output "UserPromptSubmit" "$1"; }
json_post_tool_output() { json_hook_output "PostToolUse" "$1"; }
json_session_start_output() { json_hook_output "SessionStart" "$1"; }

save_state_file() {
    local state_file="$1"
    local session_id="${2:-unknown}"
    local transcript_path="${3:-unknown}"
    local plan_path="${4:-}"
    local scope="${5:-}"
    local current_size=0
    if [[ -n "$transcript_path" ]] && [[ -f "$transcript_path" ]]; then
        current_size=$(wc -c < "$transcript_path" 2>/dev/null | tr -d '[:space:]') || current_size=0
    fi
    printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
        "$session_id" \
        "$transcript_path" \
        "$current_size" \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" \
        "$plan_path" \
        "$scope" > "$state_file"
}

classify_plan_scope() {
    local plan="$1" own_state="$2" own_scope="$3"
    [[ -n "$plan" ]] || return 1
    local sf base other_plan other_scope
    for sf in "$PLANS_DIR"/.plan-state-*; do
        [[ -e "$sf" ]] || continue
        base="${sf##*/}"
        [[ -n "$own_state" ]] && [[ "$base" == "$own_state" ]] && continue
        other_plan=$(sed -n '5p' "$sf" 2>/dev/null)
        [[ "$other_plan" == "$plan" ]] || continue
        other_scope=$(sed -n '6p' "$sf" 2>/dev/null)
        scope_compare "$own_scope" "$other_scope"
        [[ "$SCOPE_CLASS" != "same" ]] && return 1
    done
    return 0
}

newest_adoptable_plan() {
    local own_state="$1" own_scope="$2" require_fresh="${3:-0}" f
    NEWEST_ADOPTABLE=""
    NEWEST_WITHHELD=0
    NEWEST_STALE=0
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        if ! classify_plan_scope "$f" "$own_state" "$own_scope"; then
            NEWEST_WITHHELD=$((NEWEST_WITHHELD + 1))
            continue
        fi
        if [[ "$require_fresh" == "1" ]] && [[ -z "$(find "$f" -mmin -1440 2>/dev/null)" ]]; then
            NEWEST_STALE=$((NEWEST_STALE + 1))
            continue
        fi
        NEWEST_ADOPTABLE="$f"
        return 0
    done < <(ls -t "$PLANS_DIR"/*.md 2>/dev/null)
    return 0
}

# --- Ralph Loop helpers ---

# Parse Ralph's state file (.claude/ralph-loop.local.md) YAML frontmatter.







