#!/bin/bash
#
# write-reload-flag.sh - Bridge /smith-checkpoint into the post-/clear auto-reload pipeline.
#
# /smith-checkpoint (a neutral, cross-platform skill) writes durable state to the
# memory backends but does NOT know about Claude Code's hook machinery. This script
# is the Claude-Code-specific bridge: it drops a `.pending-memory-restore-<unique id>`
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
# Discovery is BY CONTENT, not by filename: the flag's key is merely unique
# (timestamp + PID). on-session-clear.sh scans all `.pending-memory-restore-*`
# files and matches line 3 (cwd) against its own hook-input cwd. This is
# deliberate — a writer executed by the Bash tool sees an ephemeral shell as
# $PPID, so it can NEVER recompute the hook's session_key (PPID:CWD); the old
# key-parity design meant the hook found nothing, ever (verified 2026-07-18
# against the full local session history: 0 flags consumed across 252
# SessionStart:clear firings).
#
# Scope: local machine only. The flag lives under ~/.claude/plans and is unreachable
# from a fresh-clone cloud run (/schedule, /code-review ultra, web). Those surfaces
# resume only from committed repo state — see smith-checkpoint/SKILL.md.
#
# Usage: write-reload-flag.sh ["<checkpoint label>"] ["<session_id>"]
#   $1 - optional short checkpoint label (line 4; names the checkpoint in the restore
#        directive). Newlines and tabs are stripped so they can't corrupt the line
#        schema or the reader's tab-delimited candidate rows.
#   $2 - optional session id (line 1, informational; defaults to "smith-checkpoint").
#
# Exit status: 0 and prints "Wrote reload flag" only after the flag is persisted;
# non-zero with a stderr error if the directory or the write failed. Exit 0 proves
# only that the flag was WRITTEN — never claim auto-reload is armed from it; only
# a live /clear that shows the restore directive proves the read side.
#

source "$(dirname "$0")/lib-common.sh"

# Strip newlines so a multi-line arg cannot shift the line schema readers depend on,
# and tabs so a label cannot misalign the reader's tab-delimited candidate rows.
LABEL=${1//$'\n'/ }
LABEL=${LABEL//$'\t'/ }
SESSION_ID=${2:-smith-checkpoint}
SESSION_ID=${SESSION_ID//$'\n'/ }

CWD="${PWD:-$(pwd)}"
# Reject a cwd containing a newline outright: replacing it would alias distinct
# paths AND a raw newline would shift the readers' sed -n 'Np' line schema.
if [[ "$CWD" == *$'\n'* ]]; then
    echo "Error: CWD containing a newline is unsupported: cannot write reload flag" >&2
    exit 1
fi

# Unique key: readable timestamp + this script's PID. Uniqueness is all that is
# required — the reader never recomputes this (see header).
FLAG_KEY="$(date +%Y%m%dT%H%M%S)-$$"
FLAG_FILE="${PLANS_DIR}/.pending-memory-restore-${FLAG_KEY}"

if ! mkdir -p "$PLANS_DIR" 2>/dev/null; then
    echo "Error: cannot create plans directory: $PLANS_DIR" >&2
    exit 1
fi

# Write to a temp file in the same dir, then atomically rename into place, so
# on-session-clear.sh never reads a half-written flag. The temp name must NOT
# match the `.pending-memory-restore-*` scan glob, or a crashed run's leftover
# could be picked up as a candidate. 4-line schema: session id, ISO-8601
# timestamp, cwd, label.
TMP=$(mktemp "${PLANS_DIR}/.mr-tmp.XXXXXX") || {
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
echo "Discovery: by cwd match (line 3 = ${CWD})${LABEL:+  (label: ${LABEL})}"
