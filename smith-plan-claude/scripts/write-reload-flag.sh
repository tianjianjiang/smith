#!/bin/bash
#
# write-reload-flag.sh - Bridge /smith-checkpoint into the post-/clear auto-reload pipeline.
#
# /smith-checkpoint (a neutral, cross-platform skill) writes durable state to the
# memory backends but does NOT know about Claude Code's hook machinery. This script
# is the Claude-Code-specific bridge: it drops a `.pending-memory-restore-<CWD_KEY>`
# flag that the SessionStart:clear hook (on-session-clear.sh) reads to inject a
# memory-restore directive on the next /clear.
#
# Deliberately a SEPARATE file from the plan pipeline's `.pending-reload-<CWD_KEY>`:
# that flag is owned by the plan hooks (enforce-clear.sh writes it on every
# high-context Stop; inject-plan.sh deletes it on the next prompt), so overloading
# it with a non-plan meaning would let those hooks clobber/consume the checkpoint's
# intent. A distinct filename keeps the two lifecycles from colliding — the plan
# hooks never touch this file.
#
# Reuses session_key() from lib-common.sh so the CWD_KEY matches what
# on-session-clear.sh recomputes in the same Claude Code process (PPID:CWD hash,
# PPID stable across /clear; a key from a Bash-tool shell matches the hook's).
#
# Scope: local machine only. The flag lives under ~/.claude/plans and is unreachable
# from a fresh-clone cloud run (/schedule, /code-review ultra, web). Those surfaces
# resume only from committed repo state — see smith-checkpoint/SKILL.md.
#
# Usage: write-reload-flag.sh ["<checkpoint label>"] ["<session_id>"]
#   $1 - optional short checkpoint label (line 4; names the checkpoint in the restore
#        directive). Newlines are stripped so they can't corrupt the line schema.
#   $2 - optional session id (line 1, informational; defaults to "smith-checkpoint").
#
# Exit status: 0 and prints "Wrote reload flag" only after the flag is persisted;
# non-zero with a stderr error if the directory or the write failed (so the caller
# must not claim auto-reload is armed on failure).
#

source "$(dirname "$0")/lib-common.sh"

# Strip newlines so a multi-line arg cannot shift the line schema readers depend on.
LABEL=${1//$'\n'/ }
SESSION_ID=${2:-smith-checkpoint}
SESSION_ID=${SESSION_ID//$'\n'/ }

CWD="${PWD:-$(pwd)}"
# Key on the RAW cwd so it matches on-session-clear.sh (which keys on its raw hook cwd).
CWD_KEY=$(session_key "" "$CWD") || {
    echo "Error: session_key failed (no hash command?)" >&2
    exit 1
}
# Strip newlines only from the value WRITTEN to the flag, sealing the line schema so a
# newline in the path can't shift the readers' sed -n 'Np'.
CWD=${CWD//$'\n'/ }

FLAG_FILE="${PLANS_DIR}/.pending-memory-restore-${CWD_KEY}"

if ! mkdir -p "$PLANS_DIR" 2>/dev/null; then
    echo "Error: cannot create plans directory: $PLANS_DIR" >&2
    exit 1
fi

# Write to a temp file in the same dir, then atomically rename into place. The
# rename is atomic on the same filesystem, so on-session-clear.sh never reads a
# half-written flag. 4-line schema: session id, ISO-8601 timestamp, cwd, label.
TMP=$(mktemp "${FLAG_FILE}.XXXXXX") || {
    echo "Error: cannot create temp file in $PLANS_DIR" >&2
    exit 1
}
if ! printf '%s\n%s\n%s\n%s\n' \
        "$SESSION_ID" \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" \
        "$CWD" \
        "$LABEL" > "$TMP" || ! mv -f "$TMP" "$FLAG_FILE"; then
    echo "Error: cannot write reload flag: $FLAG_FILE" >&2
    rm -f "$TMP" 2>/dev/null
    exit 1
fi

echo "Wrote reload flag: ${FLAG_FILE}"
echo "CWD_KEY: ${CWD_KEY}${LABEL:+  (label: ${LABEL})}"
