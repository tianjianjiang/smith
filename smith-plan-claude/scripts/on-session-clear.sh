#!/bin/bash
#
# on-session-clear.sh - SessionStart:clear hook for plan injection
#
# Fires after manual /clear. Reads plan from .plan-state-«session-hash»
# and injects plan content with skill/todo instructions.
#
# This is the reliable injection point for post-/clear plan restoration.
# Unlike UserPromptSubmit heuristics, this fires exactly once after /clear.
#
# Known limitation: Does NOT fire when plan mode exits via "clear context
# and auto-accept edits" (upstream bug #20900). The inject-plan.sh
# heuristic detection remains as fallback for that case.
#
# Session Isolation: Uses PPID:CWD-based state files so parallel Claude Code
# sessions (even in the same CWD) don't interfere with each other.
#

source "$(dirname "$0")/lib-common.sh"
require_jq

INPUT=$(cat)

# Extract CWD from hook input
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
CWD_KEY=$(session_key "" "${HOOK_CWD:-${PWD:-}}") || {
    echo "Error: session_key failed" >&2; exit 1
}
STATE_FILE="${PLANS_DIR}/.plan-state-${CWD_KEY}"
FLAG_FILE="${PLANS_DIR}/.pending-reload-${CWD_KEY}"

# Capture model from SessionStart input (only hook event with model field)
_hook_model=$(echo "$INPUT" | jq -r '.model // empty' 2>/dev/null) || _hook_model=""
if [[ -n "$_hook_model" ]]; then
    save_session_model "$CWD_KEY" "$_hook_model"
fi

# Try to find plan from state file
PLAN_FILE=""
if [[ -f "$STATE_FILE" ]]; then
    # 24h freshness: PPID-keyed state is process-scoped, so stale = process restarted.
    # 60 min was too short — UserPromptSubmit stops firing mid-session (known bug),
    # so state may not be refreshed. enforce-clear.sh now refreshes on block.
    # Validate STATE_FRESHNESS_MIN: must be a positive integer, default 1440 (24h)
    _sfm="${STATE_FRESHNESS_MIN:-1440}"
    [[ "$_sfm" =~ ^[0-9]+$ ]] || _sfm=1440
    STATE_FRESH=$(find "$STATE_FILE" -mmin -"${_sfm}" 2>/dev/null)
    if [[ -n "$STATE_FRESH" ]]; then
        PLAN_FILE=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
        if [[ -n "$PLAN_FILE" ]] && [[ ! -f "$PLAN_FILE" ]]; then
            PLAN_FILE=""
        fi
    fi
fi

# Read flag type (line 5) if flag exists. Old flags without line 5 default to
# "plan-pending" for backward compatibility.
FLAG_TYPE=""
if [[ -f "$FLAG_FILE" ]]; then
    FLAG_TYPE=$(sed -n '5p' "$FLAG_FILE" 2>/dev/null)
    FLAG_TYPE=${FLAG_TYPE:-plan-pending}
fi

# Independent checkpoint memory-restore flags — SEPARATE files from the plan flag
# above (written by write-reload-flag.sh). The plan hooks never touch them, so they
# survive the enforce-clear/inject-plan writes that own `.pending-reload`.
#
# Discovery is BY CONTENT, not by key: the writer runs under the Bash tool, whose
# ephemeral shell $PPID can never reproduce this hook's session_key, so the flag's
# filename key is merely unique. Scan every `.pending-memory-restore-*` file and
# match line 3 (cwd, newline-stripped by the writer) against this hook's cwd.
# 0 fresh matches → nothing; 1 fresh match → hard restore directive; ≥2 fresh
# (parallel sessions in this cwd checkpointed) → directive listing every candidate
# and instructing Claude to ASK which one to restore. Matched flags are consumed
# one-shot whether fresh or stale (24h window, hardcoded); the flag is only a pointer —
# checkpoint state itself lives in the memory backends. Foreign-cwd flags are left
# for their own session's /clear, except a >7-day hygiene sweep.
_mr_cwd="${HOOK_CWD:-${PWD:-}}"
_mr_cwd=${_mr_cwd//$'\n'/ }
MR_DIRECTIVE=""
_mr_rows=""   # sortable rows: "<mtime>\t<label>\t<timestamp>"
# Guard: with an empty hook cwd ("" == "" would match truncated/corrupt flags),
# skip the whole scan and leave every flag for a healthy hook run to consume.
if [[ -n "$_mr_cwd" ]]; then
for _mr_f in "${PLANS_DIR}"/.pending-memory-restore-*; do
    [[ -f "$_mr_f" ]] || continue
    _mr_fcwd=$(sed -n '3p' "$_mr_f" 2>/dev/null)
    if [[ "$_mr_fcwd" != "$_mr_cwd" ]]; then
        # Another session's flag (or unreadable): not ours to consume. Hygiene:
        # drop only on POSITIVE staleness (>7 days) — `find -mmin +N` prints
        # nothing on a transient find/IO failure, so failure means keep, never
        # delete a flag another session may still need.
        if [[ -n "$(find "$_mr_f" -mmin +10080 -print 2>/dev/null)" ]]; then
            rm -f "$_mr_f" 2>/dev/null
        fi
        continue
    fi
    # Atomically CLAIM the flag before consuming: two simultaneous /clear hooks
    # in the same cwd could otherwise both read it before either rm's it,
    # breaking the one-shot contract with duplicate directives. mv on the same
    # filesystem is atomic — exactly one hook wins; the loser skips. The claim
    # name must stay outside the .pending-memory-restore-* scan glob.
    _mr_claim="${PLANS_DIR}/.mr-claimed.$$.${_mr_f##*/.pending-memory-restore-}"
    if ! mv "$_mr_f" "$_mr_claim" 2>/dev/null; then
        # Gone = lost the race to a concurrent hook (fine). Still present = a
        # real filesystem failure (read-only, EACCES, full) — surface it so the
        # feature can't degrade to silently-off forever.
        [[ -e "$_mr_f" ]] && echo "Warning: cannot claim memory-restore flag: $_mr_f" >&2
        continue
    fi
    # Freshness: positive staleness detection, same rationale as the sweep —
    # a find failure must read as fresh (a spurious directive is recoverable;
    # a silently swallowed fresh checkpoint is the bug this file exists to fix).
    if [[ -z "$(find "$_mr_claim" -mmin +1440 -print 2>/dev/null)" ]]; then
        # mtime fallback is "now", never 0: an unstat-able flag must not be
        # silently demoted to oldest (headless restores "the newest").
        _mr_mtime=$(stat -f %m "$_mr_claim" 2>/dev/null) || \
            _mr_mtime=$(stat -c %Y "$_mr_claim" 2>/dev/null) || _mr_mtime=$(date +%s)
        # Strip tabs from the label so a legacy/foreign flag can't misalign the rows.
        _mr_label_raw=$(sed -n '4p' "$_mr_claim" 2>/dev/null)
        _mr_rows+="${_mr_mtime}"$'\t'"${_mr_label_raw//$'\t'/ }"$'\t'"$(sed -n '2p' "$_mr_claim" 2>/dev/null)"$'\n'
    fi
    rm -f "$_mr_claim" 2>/dev/null   # one-shot: consume matched-cwd flags, fresh or stale
done
# Litter sweep: a hook killed between claim and rm, or a crashed writer, can
# strand .mr-claimed.* / .mr-tmp.* files nothing else scans. Positive-staleness
# only, same failure-means-keep rationale as above.
find "$PLANS_DIR" \( -name '.mr-claimed.*' -o -name '.mr-tmp.*' \) -mmin +10080 -delete 2>/dev/null
fi
if [[ -n "$_mr_rows" ]]; then
    _mr_rows=$(printf '%s' "$_mr_rows" | sort -t$'\t' -k1,1 -rn)
    _mr_count=$(printf '%s\n' "$_mr_rows" | wc -l | tr -d ' ')
    _mr_newest_label=$(printf '%s\n' "$_mr_rows" | head -1 | cut -f2)
    if [[ "$_mr_count" -eq 1 ]]; then
        MR_LABEL="$_mr_newest_label"
        MR_DIRECTIVE="**ACTION REQUIRED - MEMORY RESTORE"
        [[ -n "$MR_LABEL" ]] && MR_DIRECTIVE+=" (checkpoint: ${MR_LABEL})"
        MR_DIRECTIVE+=":**"
        MR_DIRECTIVE+="\n\nA /smith-checkpoint saved durable session state before this /clear. Restore it before responding:"
        MR_DIRECTIVE+="\n1. If Serena MCP available: list_memories() then read_memory() for the checkpoint"
        [[ -n "$MR_LABEL" ]] && MR_DIRECTIVE+=" (\`${MR_LABEL}\`)"
        MR_DIRECTIVE+=" or the most recent session memory"
        MR_DIRECTIVE+="\n2. Read the auto-memory index at \`~/.claude/projects/«project»/memory/MEMORY.md\`, then the referenced checkpoint file"
        MR_DIRECTIVE+="\n3. If Basic-Memory MCP available: search recent notes for the checkpoint"
        MR_DIRECTIVE+="\n4. Report the restored context and continue the work thread"
        MR_DIRECTIVE+="\n\nDo NOT skip this. Do NOT respond with \"Ready for your next task.\""
        MR_DIRECTIVE+="\nIf the user's message contains a different request, address it first but still restore context."
    else
        MR_DIRECTIVE="**ACTION REQUIRED - MEMORY RESTORE (${_mr_count} checkpoints for this directory):**"
        MR_DIRECTIVE+="\n\nMultiple /smith-checkpoint flags were saved for this directory (parallel sessions). Candidates, newest first (label — saved at):"
        while IFS=$'\t' read -r _ _mr_l _mr_t; do
            MR_DIRECTIVE+="\n- ${_mr_l:-(no label)} — ${_mr_t:-unknown time}"
        done <<< "$_mr_rows"
        MR_DIRECTIVE+="\n\nBEFORE doing anything else, use AskUserQuestion to ask which checkpoint to restore."
        MR_DIRECTIVE+="\nIf unable to ask (headless/non-interactive), restore the newest (\`${_mr_newest_label:-(no label)}\`) and say so explicitly."
        MR_DIRECTIVE+="\nThen restore it: Serena list_memories()/read_memory(), the auto-memory index at \`~/.claude/projects/«project»/memory/MEMORY.md\`, and Basic-Memory recent notes."
        MR_DIRECTIVE+="\nDo NOT skip this. Do NOT respond with \"Ready for your next task.\""
    fi
fi

# Only auto-load plan if a flag file exists (explicit reload intent from
# enforce-clear or on-plan-exit). The state file alone is informational —
# it records which plan was active but does NOT mean the user wants to resume.
# Without this gate, every /clear for 24 hours forces plan resume, even when
# the user wants to work on something else.
if [[ -n "$PLAN_FILE" ]] && [[ ! -f "$FLAG_FILE" ]]; then
    PLAN_FILE=""  # No flag = no auto-resume. Fall through to no-plan path.
fi

# Defense-in-depth: if flag type is not plan-pending (i.e., plan-completed or
# no-plan), don't auto-load the plan. The flag TYPE is the source of truth for
# intent — completed/absent plans should not be re-loaded after /clear.
if [[ -n "$PLAN_FILE" ]] && [[ -f "$FLAG_FILE" ]] && [[ "$FLAG_TYPE" != "plan-pending" ]]; then
    PLAN_FILE=""
fi

# Compute state/flag metadata for directive output (replaces "may be STALE" guessing)
STATE_META_STATE=""
if [[ -f "$STATE_FILE" ]]; then
    _state_plan=$(sed -n '5p' "$STATE_FILE" 2>/dev/null)
    _state_mtime=$(stat -f %m "$STATE_FILE" 2>/dev/null) || \
        _state_mtime=$(stat -c %Y "$STATE_FILE" 2>/dev/null) || _state_mtime=""
    _state_age="?"
    if [[ -n "$_state_mtime" ]] && [[ "$_state_mtime" =~ ^[0-9]+$ ]]; then
        _state_age=$(( ($(date +%s) - _state_mtime) / 60 ))
    fi
    if [[ -n "$PLAN_FILE" ]]; then
        _pending=$(grep -c '^[[:space:]]*- \[ \]' "$PLAN_FILE" 2>/dev/null || true)
        _pending=$(echo "$_pending" | tr -d '[:space:]')
        STATE_META_STATE="- State file: found (plan: \`$(basename "${_state_plan:-unknown}")\`, pending: ${_pending} tasks, age: ${_state_age}m)"
    elif [[ -n "$_state_plan" ]] && [[ -f "$_state_plan" ]]; then
        _pending=$(grep -c '^[[:space:]]*- \[ \]' "$_state_plan" 2>/dev/null || true)
        _pending=$(echo "$_pending" | tr -d '[:space:]')
        STATE_META_STATE="- State file: found (plan: \`$(basename "${_state_plan}")\`, pending: ${_pending} tasks — not loaded, age: ${_state_age}m)"
    elif [[ -n "$_state_plan" ]]; then
        STATE_META_STATE="- State file: found (plan: \`$(basename "${_state_plan}")\` — file missing, age: ${_state_age}m)"
    else
        STATE_META_STATE="- State file: found (no plan recorded, age: ${_state_age}m)"
    fi
else
    STATE_META_STATE="- State file: not found"
fi
STATE_META_FLAG="- Flag file: $([ -f "$FLAG_FILE" ] && echo "found" || echo "not found")"

# --- Ralph resume detection (shared by both plan and no-plan paths) ---
RALPH_RESUME_DIRECTIVE=""
if read_ralph_resume "$CWD_KEY"; then
    # Calculate remaining iterations (min 10 if exhausted)
    RALPH_REMAINING=10
    if [[ -n "$RALPH_RESUME_MAX_ITER" ]] && [[ "$RALPH_RESUME_MAX_ITER" =~ ^[0-9]+$ ]] && \
       [[ -n "$RALPH_RESUME_ITERATION" ]] && [[ "$RALPH_RESUME_ITERATION" =~ ^[0-9]+$ ]]; then
        RALPH_REMAINING=$(( RALPH_RESUME_MAX_ITER - RALPH_RESUME_ITERATION ))
        if [[ $RALPH_REMAINING -lt 10 ]]; then
            RALPH_REMAINING=10
        fi
    fi

    # Build Skill tool args: prompt --completion-promise 'promise' --max-iterations N
    RALPH_SKILL_ARGS="${RALPH_RESUME_PROMPT:-continue}"
    if [[ -n "$RALPH_RESUME_PROMISE" ]]; then
        RALPH_SKILL_ARGS+=" --completion-promise '${RALPH_RESUME_PROMISE}'"
    fi
    RALPH_SKILL_ARGS+=" --max-iterations ${RALPH_REMAINING}"

    RALPH_RESUME_DIRECTIVE="\n\n**RALPH LOOP AUTO-RESUME:**"
    RALPH_RESUME_DIRECTIVE+="\n1. If Serena MCP available: read_memory() for ralph_*_state"
    RALPH_RESUME_DIRECTIVE+="\n2. Restore iteration context from memory"
    RALPH_RESUME_DIRECTIVE+="\n3. Auto-start Ralph loop NOW using Skill tool:"
    RALPH_RESUME_DIRECTIVE+="\n   Skill(skill: \"ralph-loop:ralph-loop\", args: \"${RALPH_SKILL_ARGS}\")"
    RALPH_RESUME_DIRECTIVE+="\n4. Do NOT ask user for permission - auto-invoke immediately after memory restore"

    # Clean up resume files (consumed)
    rm -f "${PLANS_DIR}/.ralph-resume-${CWD_KEY}" "${PLANS_DIR}/.ralph-resume-${CWD_KEY}.prompt" 2>/dev/null
fi

# Proactive phase resume: Ralph state file exists but no resume files.
# This covers the phase-boundary exit path where the agent exited Ralph
# normally (via promise) and no context threshold was hit.
if [[ -z "$RALPH_RESUME_DIRECTIVE" ]]; then
    if check_ralph_recently_active "${HOOK_CWD:-${PWD:-.}}"; then
        RALPH_RESUME_DIRECTIVE="\n\n**RALPH LOOP PHASE RESUME:**"
        RALPH_RESUME_DIRECTIVE+="\nPrevious session used ralph-loop (state file found in CWD)."
        RALPH_RESUME_DIRECTIVE+="\n1. read_memory() for ralph_* state (phase progress, iteration context)"
        RALPH_RESUME_DIRECTIVE+="\n2. If phase work remains: auto-invoke Skill(skill: \"ralph-loop:ralph-loop\")"
        RALPH_RESUME_DIRECTIVE+="\n   Pass the original prompt and remaining iterations from memory"
        RALPH_RESUME_DIRECTIVE+="\n3. Do NOT ask user for permission - auto-invoke if ralph state found in memory"
    fi
fi

# --- Orchestrator resume detection (Pattern B) ---
ORCH_RESUME_DIRECTIVE=""
if read_orchestrator_resume "$CWD_KEY"; then
    ORCH_RESUME_DIRECTIVE="\n\n**RALPH ORCHESTRATOR AUTO-RESUME (Pattern B):**"
    ORCH_RESUME_DIRECTIVE+="\nPrevious session was running orchestration mode."
    ORCH_RESUME_DIRECTIVE+="\n1. If Serena MCP available: read_memory() for orchestrator state"
    ORCH_RESUME_DIRECTIVE+="\n2. Read plan file: \`${ORCH_RESUME_PLAN_PATH:-unknown}\`"
    ORCH_RESUME_DIRECTIVE+=$(printf '\n3. Resume from iteration %s, task: %s' "${ORCH_RESUME_ITERATION:-?}" "${ORCH_RESUME_CURRENT_TASK:-unknown}")
    ORCH_RESUME_DIRECTIVE+="\n4. Continue orchestration: parse remaining \`- [ ]\` tasks, spawn workers via Task tool"
    ORCH_RESUME_DIRECTIVE+="\n5. Do NOT ask user for permission - auto-resume orchestration"

    # Clean up resume file (consumed)
    rm -f "${PLANS_DIR}/.ralph-orch-resume-${CWD_KEY}" 2>/dev/null
fi

# No plan found — output state data for SKILL.md to interpret
if [[ -z "$PLAN_FILE" ]]; then
    # List only the 5 most recent plans (not 100+)
    AVAILABLE_PLANS=""
    PLAN_COUNT=0
    if [[ -d "$PLANS_DIR" ]]; then
        while IFS= read -r f; do
            AVAILABLE_PLANS+="\n  - \`$(basename "$f")\` (\`$f\`)"
            PLAN_COUNT=$((PLAN_COUNT + 1))
            [[ $PLAN_COUNT -ge 5 ]] && break
        done < <(ls -t "$PLANS_DIR"/*.md 2>/dev/null)
    fi

    # Determine signal: flag or Ralph/orchestrator resume means reload intent
    if [[ -n "$FLAG_TYPE" ]] || [[ -n "$RALPH_RESUME_DIRECTIVE" ]] || [[ -n "$ORCH_RESUME_DIRECTIVE" ]] || [[ -n "$MR_DIRECTIVE" ]]; then
        SIGNAL="resume"
    else
        SIGNAL="fresh-start"
    fi

    STATE_OUTPUT="**State check (session-keyed):**"
    STATE_OUTPUT+="\n${STATE_META_STATE}"
    STATE_OUTPUT+="\n${STATE_META_FLAG}"
    STATE_OUTPUT+="\n- Flag type: ${FLAG_TYPE:-none}"
    STATE_OUTPUT+="\n- Signal: ${SIGNAL}"
    if [[ -n "$AVAILABLE_PLANS" ]]; then
        STATE_OUTPUT+="\n\nRecent plans (for reference if user asks):"
        STATE_OUTPUT+="${AVAILABLE_PLANS}"
    fi
    if [[ -n "$RALPH_RESUME_DIRECTIVE" ]]; then
        STATE_OUTPUT+="$RALPH_RESUME_DIRECTIVE"
    fi
    if [[ -n "$ORCH_RESUME_DIRECTIVE" ]]; then
        STATE_OUTPUT+="$ORCH_RESUME_DIRECTIVE"
    fi

    # Prepend the checkpoint memory-restore directive (if its flag was consumed above)
    # so the action leads.
    [[ -n "$MR_DIRECTIVE" ]] && STATE_OUTPUT="${MR_DIRECTIVE}\n\n${STATE_OUTPUT}"

    rm -f "$FLAG_FILE" 2>/dev/null
    json_session_start_output "$(printf '%b' "$STATE_OUTPUT")"
    exit 0
fi

# Read plan content fresh from disk
if ! PLAN_CONTENT=$(cat "$PLAN_FILE" 2>/dev/null); then
    # Plan file unreadable — output state data with plan path hint
    STATE_OUTPUT="**State check (session-keyed):**"
    STATE_OUTPUT+="\n${STATE_META_STATE}"
    STATE_OUTPUT+="\n${STATE_META_FLAG}"
    STATE_OUTPUT+="\n- Flag type: ${FLAG_TYPE:-plan-pending}"
    STATE_OUTPUT+="\n- Signal: resume"
    STATE_OUTPUT+="\n- Plan file: \`${PLAN_FILE}\` (unreadable)"
    STATE_OUTPUT+="\n- Plans directory: \`${PLANS_DIR}\`"
    if [[ -n "$RALPH_RESUME_DIRECTIVE" ]]; then
        STATE_OUTPUT+="$RALPH_RESUME_DIRECTIVE"
    fi
    if [[ -n "$ORCH_RESUME_DIRECTIVE" ]]; then
        STATE_OUTPUT+="$ORCH_RESUME_DIRECTIVE"
    fi
    [[ -n "$MR_DIRECTIVE" ]] && STATE_OUTPUT="${MR_DIRECTIVE}\n\n${STATE_OUTPUT}"
    rm -f "$FLAG_FILE" 2>/dev/null
    json_session_start_output "$(printf '%b' "$STATE_OUTPUT")"
    exit 0
fi
PLAN_BASENAME=$(basename "$PLAN_FILE")

# Get modification time (macOS first, then Linux fallback)
PLAN_MODIFIED=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$PLAN_FILE" 2>/dev/null) || \
    PLAN_MODIFIED=$(stat -c %y "$PLAN_FILE" 2>/dev/null | cut -d'.' -f1) || \
    PLAN_MODIFIED="unknown"

# Calculate progress
TOTAL=$(echo "$PLAN_CONTENT" | grep -c '^[[:space:]]*- \[.\]' || true)
COMPLETED=$(echo "$PLAN_CONTENT" | grep -c '^[[:space:]]*- \[x\]' || true)

if [[ $TOTAL -gt 0 ]]; then
    PERCENT=$((COMPLETED * 100 / TOTAL))
    PROGRESS="${COMPLETED}/${TOTAL} tasks (${PERCENT}%)"
else
    PROGRESS="No trackable tasks found"
fi

CURRENT_TASK=$(echo "$PLAN_CONTENT" | grep -m1 '^[[:space:]]*- \[ \]' | sed 's/^[[:space:]]*- \[ \] //') || CURRENT_TASK=""
CURRENT_TASK=${CURRENT_TASK:-None}
PENDING=$((TOTAL - COMPLETED))

# Build injection content — state data + plan content (Ralph/orchestrator directives appended below if active)
STATE_OUTPUT="**State check (session-keyed):**"
STATE_OUTPUT+="\n${STATE_META_STATE}"
STATE_OUTPUT+="\n${STATE_META_FLAG}"
STATE_OUTPUT+="\n- Flag type: ${FLAG_TYPE:-plan-pending}"
STATE_OUTPUT+="\n- Signal: resume"

FULL_CONTENT=$(printf '%b\n\n---\n\n## Plan: `%s`\n\n**File:** `%s`\n**Modified:** %s\n**Progress:** %s\n**Current task:** %s\n\n**IMPORTANT:** After completing tasks, UPDATE this plan file at `%s` to track progress.\n\n---\n\n%s' \
    "$STATE_OUTPUT" "$PLAN_BASENAME" "$PLAN_FILE" "$PLAN_MODIFIED" "$PROGRESS" "$CURRENT_TASK" "$PLAN_FILE" "$PLAN_CONTENT")

# Add ACTION REQUIRED directive for plan-pending (mirrors inject-plan.sh lines 473-494)
if [[ "$FLAG_TYPE" == "plan-pending" ]] && [[ $PENDING -gt 0 ]]; then
    ACTION_DIRECTIVE="**ACTION REQUIRED - POST-CLEAR RESUME:**"
    ACTION_DIRECTIVE+="\n\n1. Reconstruct todos from plan checkboxes:"
    ACTION_DIRECTIVE+="\n   - For each \`- [ ]\` task: TaskCreate(subject=task_text, description=\"From plan\", activeForm=\"Working on ...\")"
    ACTION_DIRECTIVE+="\n   - Set first task: TaskUpdate(taskId, status=\"in_progress\")"
    ACTION_DIRECTIVE+="\n2. Load skills: @smith-plan, @smith-plan-claude, @smith-ctx-claude"
    ACTION_DIRECTIVE+="\n3. If Serena MCP available: list_memories() then read_memory() for session state"
    ACTION_DIRECTIVE+="\n4. Resume current task: ${CURRENT_TASK}"
    ACTION_DIRECTIVE+="\n\nIf user's message contains a different request, address that first."
    FULL_CONTENT=$(printf '%b\n\n%s' "$ACTION_DIRECTIVE" "$FULL_CONTENT")
fi

# Append Ralph resume directive if present
if [[ -n "$RALPH_RESUME_DIRECTIVE" ]]; then
    FULL_CONTENT+=$(printf '%b' "$RALPH_RESUME_DIRECTIVE")
fi

# Append orchestrator resume directive if present
if [[ -n "$ORCH_RESUME_DIRECTIVE" ]]; then
    FULL_CONTENT+=$(printf '%b' "$ORCH_RESUME_DIRECTIVE")
fi

# Prepend the checkpoint memory-restore directive (if its flag was consumed above) so
# it leads even when a plan also reloaded.
[[ -n "$MR_DIRECTIVE" ]] && FULL_CONTENT=$(printf '%b\n\n%s' "$MR_DIRECTIVE" "$FULL_CONTENT")

# Clean up the pending-reload flag if it exists (SessionStart:clear handles it now)
rm -f "$FLAG_FILE" 2>/dev/null

json_session_start_output "$FULL_CONTENT"

exit 0
