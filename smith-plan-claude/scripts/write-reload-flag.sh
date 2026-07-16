#!/bin/bash
#
# write-reload-flag.sh - Bridge /smith-checkpoint into the post-/clear auto-reload pipeline.
#
# /smith-checkpoint (a neutral, cross-platform skill) writes durable state to the
# memory backends but does NOT know about Claude Code's hook machinery. This script
# is the Claude-Code-specific bridge: it drops the same `.pending-reload-<CWD_KEY>`
# flag that enforce-clear.sh / on-plan-exit.sh write, tagged with FLAG_TYPE
# `memory-restore`, so the existing SessionStart:clear hook (on-session-clear.sh)
# auto-injects a memory-restore directive on the next /clear.
#
# Reuses session_key() from lib-common.sh so the CWD_KEY matches what
# on-session-clear.sh recomputes in the same Claude Code process (PPID:CWD hash,
# PPID stable across /clear). Empirically verified: a key computed from a Bash-tool
# shell matches the hook-written flag for the same session+cwd.
#
# Scope: local machine only. The flag lives under ~/.claude/plans and is unreachable
# from a fresh-clone cloud run (/schedule, /code-review ultra, web). Those surfaces
# can only resume from committed repo state — see smith-checkpoint/SKILL.md.
#
# Usage: write-reload-flag.sh ["<checkpoint label>"] ["<session_id>"]
#   $1 - optional short checkpoint label (recorded on line 6; names the checkpoint
#        in the restore directive). Falls back to a generic directive if omitted.
#   $2 - optional session id (line 2, informational; defaults to "smith-checkpoint").
#
# Prints the flag path and CWD_KEY so the caller can report/verify.
#

source "$(dirname "$0")/lib-common.sh"

LABEL="${1:-}"
SESSION_ID="${2:-smith-checkpoint}"

CWD="${PWD:-$(pwd)}"
CWD_KEY=$(session_key "" "$CWD") || {
    echo "Error: session_key failed (no hash command?)" >&2
    exit 1
}

FLAG_FILE="${PLANS_DIR}/.pending-reload-${CWD_KEY}"
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S%z)

mkdir -p "$PLANS_DIR" 2>/dev/null || true

# Don't clobber an active plan's reload intent. A plan-pending flag already drives
# both plan reload AND list_memories()/read_memory() on the next /clear
# (on-session-clear.sh plan-pending path), so the checkpoint's memory is restored
# anyway. Overwriting it with memory-restore would silently drop the plan reload.
if [[ -f "$FLAG_FILE" ]]; then
    EXISTING_TYPE=$(sed -n '5p' "$FLAG_FILE" 2>/dev/null)
    EXISTING_TYPE=${EXISTING_TYPE:-plan-pending}
    if [[ "$EXISTING_TYPE" == "plan-pending" ]]; then
        echo "Kept existing plan-pending reload flag (already restores memory on /clear): ${FLAG_FILE}"
        exit 0
    fi
fi

# 5-line schema shared with enforce-clear.sh / on-plan-exit.sh:
#   1 plan path (empty — a checkpoint is not a plan)
#   2 session id (informational)
#   3 timestamp
#   4 cwd
#   5 FLAG_TYPE = memory-restore
# Optional line 6 = checkpoint label (backward compatible; old readers stop at line 5).
{
    printf '%s\n' ""
    printf '%s\n' "$SESSION_ID"
    printf '%s\n' "$TIMESTAMP"
    printf '%s\n' "$CWD"
    printf '%s\n' "memory-restore"
    [[ -n "$LABEL" ]] && printf '%s\n' "$LABEL"
} > "$FLAG_FILE"

echo "Wrote reload flag: ${FLAG_FILE}"
echo "CWD_KEY: ${CWD_KEY}  (FLAG_TYPE: memory-restore${LABEL:+, label: ${LABEL}})"
