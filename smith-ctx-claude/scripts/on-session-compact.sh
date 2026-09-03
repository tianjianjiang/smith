#!/bin/bash
#
# on-session-compact.sh - SessionStart:compact hook, checkpoint-restore reminder
#
# Fires after /compact (manual or automatic -- Claude Code exposes both under
# one "compact" source, per code.claude.com/docs/en/hooks). Unlike
# on-session-clear.sh, this does NOT end the session: the same process
# continues, so this session's own pending checkpoint-restore flag can be
# identified directly from its own session_key, with no cross-session
# "whose checkpoint is this" guessing.
#
# Deliberately narrow, and deliberately non-destructive:
# - Only ever reminds about a flag whose session_key (line 5) matches this
#   session's OWN key exactly. It never offers another session's flag --
#   that UX belongs to on-session-clear.sh alone.
# - Never sweeps expired flags, never deletes or claims the flag it finds,
#   because /compact can fire more than once per session and a later /clear
#   must still see the same flag to consume it.
# - Fires every compaction: if a flag stays unconsumed across several
#   compactions in one long session, the reminder repeats every time. This
#   is accepted, not suppressed -- see smith-plan-claude/references/HOOKS.md
#   "Checkpoint memory-restore flag" for the rationale.
#
# additionalContext injected here is read on Claude's next model request
# (code.claude.com/docs/en/hooks, "Add context for Claude": SessionStart --
# "at the start of the conversation, before the first prompt"). For a manual
# /compact in an idle interactive session that still means waiting on the
# user's next prompt, same as /clear; for automatic mid-task compaction, the
# "next model request" is the task's own continuation, so the reminder can
# become visible without any human input at all.

source "$(dirname "$0")/lib-plan.sh"
require_jq

_oc_is_plain_file() {
    [[ -L "$1" ]] && return 1
    local nlink
    nlink=$(stat -c %h "$1" 2>/dev/null)
    [[ "$nlink" =~ ^[0-9]+$ ]] || nlink=$(stat -f %l "$1" 2>/dev/null)
    [[ "$nlink" =~ ^[0-9]+$ ]] && [[ "$nlink" -ne 1 ]] && return 1
    return 0
}

INPUT=$(cat)
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
CWD_KEY=$(session_key "" "${HOOK_CWD:-${PWD:-}}") || exit 0

_oc_found=""
_oc_label=""
for _oc_f in "${PLANS_DIR}"/.pending-memory-restore-*; do
    [[ -f "$_oc_f" ]] || continue
    _oc_is_plain_file "$_oc_f" || continue
    [[ -r "$_oc_f" ]] || continue

    _oc_l1=""; _oc_l2=""; _oc_l3=""; _oc_l4=""; _oc_l5=""
    { IFS= read -r _oc_l1; IFS= read -r _oc_l2; IFS= read -r _oc_l3; IFS= read -r _oc_l4; IFS= read -r _oc_l5; } < "$_oc_f" 2>/dev/null

    [[ -n "$_oc_l5" && "$_oc_l5" == "$CWD_KEY" ]] || continue
    _oc_found="$_oc_f"
    _oc_label="$_oc_l4"
    break
done

[[ -n "$_oc_found" ]] || exit 0

_oc_msg="A /smith-checkpoint reload flag for THIS session is still pending"
[[ -n "$_oc_label" ]] && _oc_msg="${_oc_msg} (\"${_oc_label}\")"
_oc_msg="${_oc_msg}. It has not been consumed -- restore it now (Serena list_memories()/read_memory(), Basic-Memory recent notes) if you have not already, or leave it for /clear to offer. Flag: ${_oc_found}"

json_session_start_output "$_oc_msg"
