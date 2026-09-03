#!/bin/bash

set -euo pipefail

TRANSCRIPT="${1:-}"
MAX_FILES=30

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

assistant_tool_input_first_line() {
    local tool="$1" field="$2"
    jq -r --arg tool "$tool" --arg field "$field" '
        select(.type == "assistant")
        | .message.content[]?
        | select(.type == "tool_use" and .name == $tool)
        | .input[$field]? // empty
        | tostring
        | split("\n")[0]
    ' "$TRANSCRIPT" 2>/dev/null || true
}

extract_completed_tasks() {
    jq -r '
        select(.type == "assistant")
        | .message.content[]?
        | select(.type == "tool_use" and .name == "TaskUpdate")
        | select(.input.status == "completed")
        | "- [x] Task #\(.input.taskId): \((.input.subject // "unknown") | tostring | split("\n")[0])"
    ' "$TRANSCRIPT" 2>/dev/null | sort -u || true
}

extract_file_edits() {
    {
        assistant_tool_input_first_line Edit file_path
        assistant_tool_input_first_line Write file_path
    } | sort -u
}

bash_command_heads() {
    assistant_tool_input_first_line Bash command
}

extract_pr_operations() {
    bash_command_heads | sed -nE '
        s|.*gh pr merge[^0-9]*([0-9]+).*|- PR #\1 merged|p
        s|.*gh pr merge.*|- PR merged|p
        s|.*gh pr create.*|- PR created|p
    ' | sort -u
}

extract_commits() {
    local count
    count=$(bash_command_heads | grep -cE '(^|[;&|[:space:]])git commit([[:space:]]|$)' || true)
    count=${count//[^0-9]/}
    if [[ -n "$count" ]] && (( count > 0 )); then
        echo "- ${count} commit command(s) run"
    fi
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
    FILE_COUNT=$(printf '%s\n' "$FILES" | wc -l | tr -d '[:space:]')
    echo "## Files Modified"
    printf '%s\n' "$FILES" | head -n "$MAX_FILES" | sed 's|^|- |'
    if (( FILE_COUNT > MAX_FILES )); then
        echo "- ... and $((FILE_COUNT - MAX_FILES)) more"
    fi
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
