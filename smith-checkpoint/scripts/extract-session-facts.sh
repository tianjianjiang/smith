#!/bin/bash

set -euo pipefail

TRANSCRIPT="${1:-}"

if [[ -z "$TRANSCRIPT" ]] || [[ ! -f "$TRANSCRIPT" ]]; then
    echo "# Session Facts"
    echo ""
    echo "No transcript available."
    exit 0
fi

if ! command -v jq &>/dev/null; then
    echo "Error: jq is required. Install: brew install jq (macOS)" >&2
    exit 1
fi

extract_completed_tasks() {
    jq -r '
        select(.type == "assistant")
        | .message.content[]?
        | select(.type == "tool_use" and .name == "TaskUpdate")
        | select(.input.status == "completed")
        | "- [x] Task #\(.input.taskId): \(.input.subject // "unknown")"
    ' "$TRANSCRIPT" 2>/dev/null || true
}

extract_file_edits() {
    jq -r '
        select(.type == "assistant")
        | .message.content[]?
        | select(.type == "tool_use" and (.name == "Edit" or .name == "Write"))
        | "- \(.input.file_path // "unknown file")"
    ' "$TRANSCRIPT" 2>/dev/null | sort -u || true
}

extract_pr_operations() {
    jq -r '
        select(.type == "assistant")
        | .message.content[]?
        | select(.type == "tool_use" and .name == "Bash")
        | select(.input.command | test("gh pr (create|merge|view)"))
        | .input.command
    ' "$TRANSCRIPT" 2>/dev/null \
        | sed -E 's/^gh pr (create|merge) .*/- PR \1d/' \
        | sort -u || true
}

extract_commits() {
    jq -r '
        select(.type == "assistant")
        | .message.content[]?
        | select(.type == "tool_use" and .name == "Bash")
        | select(.input.command | test("git commit"))
        | .input.command
    ' "$TRANSCRIPT" 2>/dev/null \
        | sed -E 's/^git commit .*/- Commit created/' \
        | sort -u || true
}

extract_git_state() {
    local sha branch
    sha=$(/usr/bin/git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    branch=$(/usr/bin/git branch --show-current 2>/dev/null || echo "unknown")
    echo "- Git: $branch @ $sha"
}

echo "# Session Facts (Extracted from Transcript)"
echo ""

COMPLETED=$(extract_completed_tasks)
if [[ -n "$COMPLETED" ]]; then
    echo "## Completed"
    echo "$COMPLETED"
    echo ""
fi

FILES=$(extract_file_edits)
if [[ -n "$FILES" ]]; then
    echo "## Files Modified"
    echo "$FILES"
    echo ""
fi

PRS=$(extract_pr_operations)
if [[ -n "$PRS" ]]; then
    echo "## PRs"
    echo "$PRS"
    echo ""
fi

COMMITS=$(extract_commits)
if [[ -n "$COMMITS" ]]; then
    echo "## Commits"
    echo "$COMMITS"
    echo ""
fi

echo "## Git State"
extract_git_state
