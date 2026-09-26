#!/bin/bash
#
# link-worktree-memories.sh - SessionStart hook, shares Serena memories with worktrees
#
# Serena started with --project-from-cwd treats a linked git worktree as its
# own project, so a session started inside a worktree reads and writes an
# empty <worktree>/.serena/memories instead of the primary checkout's. This
# hook replaces a missing or empty worktree memories folder with a symlink to
# <primary>/.serena/memories. Serena supports memories reached through a
# directory symlink (serena/memories/memory_manager.py, Serena 1.7.0).
#
# Claude Code's .worktreeinclude does not copy symlinks (probed with Claude
# Code 2.1.282), and a mid-session EnterWorktree keeps the MCP server on its
# launch project, so a session START inside a worktree is the one case to fix.
# A non-empty worktree folder is left alone with a warning.

_lwm_cwd=""
if [[ ! -t 0 ]] && command -v jq >/dev/null 2>&1; then
    _lwm_cwd=$(jq -r '.cwd // empty' 2>/dev/null)
fi
_lwm_cwd="${_lwm_cwd:-$PWD}"

_lwm_top=$(git -C "$_lwm_cwd" rev-parse --path-format=absolute --show-toplevel 2>/dev/null) || exit 0
_lwm_git_dir=$(git -C "$_lwm_cwd" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
_lwm_common=$(git -C "$_lwm_cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
[[ "$_lwm_git_dir" == "$_lwm_common" ]] && exit 0

_lwm_primary=$(git -C "$_lwm_cwd" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
[[ -n "$_lwm_primary" ]] || exit 0
_lwm_target="$_lwm_primary/.serena/memories"
_lwm_link="$_lwm_top/.serena/memories"
[[ -d "$_lwm_target" ]] || exit 0
[[ -d "$_lwm_link" && "$(cd "$_lwm_link" && pwd -P)" == "$(cd "$_lwm_target" && pwd -P)" ]] && exit 0

if [[ -L "$_lwm_link" ]]; then
    _lwm_current=$(readlink "$_lwm_link")
    [[ "$_lwm_current" == "$_lwm_target" ]] && exit 0
    _lwm_msg="link-worktree-memories: $_lwm_link is a symlink to $_lwm_current, not $_lwm_target; left unchanged."
elif [[ -d "$_lwm_link" && -n "$(ls -A "$_lwm_link")" ]]; then
    _lwm_msg="link-worktree-memories: $_lwm_link holds worktree-local memories, so it was NOT linked to $_lwm_target. Move them to the primary checkout (smith-checkpoint relocates them), then start a new session."
elif [[ -e "$_lwm_link" && ! -d "$_lwm_link" ]]; then
    _lwm_msg="link-worktree-memories: $_lwm_link is a file, not a folder; left unchanged, so this worktree does not share $_lwm_target."
elif [[ -d "$_lwm_link" ]] && ! rmdir "$_lwm_link" 2>/dev/null; then
    _lwm_msg="link-worktree-memories: could not remove the empty $_lwm_link (it may have just received a memory); not linked to $_lwm_target."
elif mkdir -p "$(dirname "$_lwm_link")" 2>/dev/null && ln -sn "$_lwm_target" "$_lwm_link" 2>/dev/null \
    && [[ -L "$_lwm_link" && "$(readlink "$_lwm_link")" == "$_lwm_target" ]]; then
    _lwm_msg="link-worktree-memories: linked $_lwm_link -> $_lwm_target, so Serena memory tools in this worktree use the primary checkout's memories."
else
    _lwm_msg="link-worktree-memories: FAILED to create $_lwm_link -> $_lwm_target; Serena memory tools in this worktree will not see the primary checkout's memories."
fi

command -v jq >/dev/null 2>&1 || { echo "$_lwm_msg" >&2; exit 0; }

jq -n --arg msg "$_lwm_msg" '{
    hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: $msg
    },
    systemMessage: $msg
}'
