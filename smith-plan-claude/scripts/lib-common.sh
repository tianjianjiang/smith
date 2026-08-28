#!/bin/bash
#
# lib-common.sh - Shared utilities for plan-claude hook scripts
#
# Source this file at the top of each hook script:
#   source "$(dirname "$0")/lib-common.sh"

# Strict mode: pipe failures propagated (no set -e; hooks must not abort on transient errors)
set -o pipefail

PLANS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plans"
CONTEXT_WINDOW_TOKENS=${CONTEXT_WINDOW_TOKENS:-200000}
RALPH_STATE_FILENAME="ralph-loop.local.md"

# Map model ID to context window size in tokens.
# Handles both SessionStart format (with [1m] suffix) and transcript format (without).
# Flagships (Opus/Fable/Mythos) are 1M and the [1m] suffix is authoritative;
# current-gen Sonnet (4.6-4.9, incl. Sonnet 5+) is 1M standard as of the
# Claude 5 model family (no opt-in needed); Haiku and legacy Sonnet (4.5 and
# older, incl. undated-minor-version IDs like "claude-sonnet-4-20250514")
# remain 200K; unknown IDs fall back to CONTEXT_WINDOW_TOKENS.
# Ordering matters: the [1m] branch precedes the sonnet branches, and the
# current-gen sonnet branch precedes the generic haiku/sonnet catch-all so
# e.g. "claude-sonnet-4-6" and "claude-sonnet-5" resolve to 1M while
# "claude-sonnet-4-5" and "claude-sonnet-4-20250514" still resolve to 200K.
# The minor-version match is deliberately single-digit ([6-9], not a wider
# digit range): a wider range would also match the leading digits of a dated
# base-Sonnet-4 ID's date suffix (e.g. "sonnet-4-20250514" starts with "20"),
# incorrectly promoting a legacy 200K model to 1M.
model_to_context_window() {
    local model="${1:-}"
    case "$model" in
        *\[1[mM]\])                    echo 1000000 ;;  # explicit terminal suffix
        *sonnet-5*|*sonnet-4-[6-9]*)   echo 1000000 ;;  # current-gen Sonnet (4.6-4.9, 5+): 1M standard
        *haiku*|*sonnet*)              echo 200000  ;;  # Haiku, legacy Sonnet (<=4.5): no automatic 1M
        *claude-opus-*|*claude-fable-*|*claude-mythos-*) echo 1000000 ;;  # flagships -> 1M
        *)                             echo "${CONTEXT_WINDOW_TOKENS}" ;;  # safe fallback
    esac
}

# Save model ID to session-keyed file for cross-hook sharing.
save_session_model() {
    local cwd_key="$1" model="$2"
    [[ -n "$model" ]] && printf '%s\n' "$model" > "${PLANS_DIR}/.model-${cwd_key}"
}

# Read model ID from session-keyed file.
read_session_model() {
    local cwd_key="$1"
    local f="${PLANS_DIR}/.model-${cwd_key}"
    [[ -f "$f" ]] && cat "$f" 2>/dev/null
}

# Resolve context percentage with session-model priority.
# Args: $1 = transcript path, $2 = CWD key
resolve_context_percentage() {
    local transcript="$1" cwd_key="$2"
    local session_model
    session_model=$(read_session_model "$cwd_key")
    if [[ -n "$session_model" ]]; then
        get_context_percentage "$transcript" "$(model_to_context_window "$session_model")"
    else
        get_context_percentage "$transcript"
    fi
}

ORCH_STATE_PREFIX=".ralph-orchestrator-"

# Check for jq dependency (required for JSON parsing)
require_jq() {
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required but not found. Install: brew install jq (macOS) or apt-get install jq (Linux)" >&2
        exit 1
    fi
}

# Compute session key hash for flag and state files that must survive /clear.
# Hashes PPID:CWD for per-session isolation (concurrent sessions in same CWD
# get different keys). PPID = Claude Code's PID, stable across /clear.
# _SMITH_PPID env var overrides $PPID (for testing). macOS: md5, Linux: md5sum, POSIX: shasum/cksum.
session_key() {
    local ppid="${1:-${_SMITH_PPID:-$PPID}}"
    local cwd="${2:-${PWD:-$(pwd)}}"
    local input="${ppid}:${cwd}"
    local hash
    hash=$(printf '%s' "$input" | md5 -q 2>/dev/null) || \
    hash=$(printf '%s' "$input" | md5sum 2>/dev/null | cut -d' ' -f1) || \
    hash=$(printf '%s' "$input" | shasum 2>/dev/null | cut -d' ' -f1) || \
    hash=$(printf '%s' "$input" | cksum 2>/dev/null | cut -d' ' -f1) || {
        echo "Error: no hash command found, cannot ensure session isolation" >&2
        return 1
    }
    printf '%s' "${hash:0:16}"
}

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
#
# git alone cannot separate the last two: `rev-parse` exits 128 both when the path
# is not a repository and when git refuses to look (dubious ownership under
# `safe.directory`), is missing from PATH, or the repository is damaged. Its
# messages are translated, so matching them is not a discriminator either. So when
# git declines to answer, the question is settled with a filesystem fact instead:
# walk up for a `.git` entry. One found means a repository is there and only the
# resolution failed — unverifiable. Reaching the root without one means "inside no
# repository" is a checked result, not a guess, and the directory itself is then a
# legitimate identity. The walk uses builtins, so the failing path costs no forks.
#
# The answer is an IDENTITY, not a display path, and that is the contract: a
# repository's main working tree and every linked worktree must agree, so a flag
# armed in one is selectable from the other. Under `git init --separate-git-dir` the
# answer is the separate git directory rather than the working tree, which still
# satisfies that contract — verified on git 2.54, where `git worktree list
# --porcelain` reports the same directory in its first entry, so switching to it
# would change nothing. `--show-toplevel` is the one that cannot be used: from a
# linked worktree it answers the worktree, giving every worktree of one repository a
# different identity.
scope_key() {
    local dir="${1:-}" phys common resolved probe
    [[ -n "$dir" ]] || return 0
    # `--` is load-bearing, not decoration: this operand is FLAG CONTENT, and `cd`
    # takes its first word as an option. `-P`, `-L` and `-e` are consumed as flags,
    # leaving no operand, so `cd` chdirs to $HOME and a planted flag recording `-P`
    # resolves to the home directory — reported as a match, restored and consumed.
    phys=$(cd -- "$dir" 2>/dev/null && pwd -P) || return 0
    [[ -n "$phys" ]] || return 0
    # `rev-parse` answers from the ENVIRONMENT before it looks at `-C`, so an inherited
    # `GIT_DIR` makes every directory report that repository — including one inside no
    # repository at all. This function exists to tell scopes apart, and the caller uses
    # its answer to decide whether another session's recorded path and label may be
    # printed, so a collapse to one identity does not merely lose precision: it turns
    # the withholding rule inside out and discloses every foreign flag. The variables
    # are exported by `git rebase --exec` and inside git hooks, so a session launched
    # from either inherits them.
    #
    # The trade-off, recorded rather than left implicit: a setup where the repository is
    # reachable ONLY through those variables — a separate git directory with an explicit
    # `GIT_WORK_TREE` — now answers `dir:` instead of `repo:`, so its worktrees stop
    # sharing one identity. That is a real narrowing, and it is the one worth taking:
    # `dir:` still says something true, since the walk below checked the filesystem and
    # found no repository, whereas honouring the variables makes EVERY directory share a
    # single identity and discloses every foreign flag.
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
        # `.git` is a directory in a main working tree and a file in a linked
        # worktree; either proves a repository is present.
        [[ -e "$probe/.git" ]] && return 0
        [[ "$probe" == "/" ]] && break
        probe="${probe%/*}"; probe="${probe:-/}"
    done
    printf 'dir:%s' "$phys"
}

# File mtime in epoch seconds, into _MTIME_OUT; empty when none could be read.
#
# Select the fallback on the OUTPUT, not on the exit status. On GNU coreutils `-f`
# means --file-system, so `stat -f %m` SUCCEEDS on a file and prints filesystem
# information, never an mtime — an `||` chain on the exit status would then never
# reach the `-c %Y` form and every file on Linux would carry whatever the first form
# printed. What an empty answer MEANS is the caller's to decide, and the two callers
# decide differently; neither may read it as an age of zero without saying so.
# Sets a variable rather than printing: `$( )` would fork a subshell per file, and
# this runs once per flag on every /clear.
# A NEGATIVE epoch — a timestamp before 1970 — is deliberately rejected rather than
# accepted as an established age. Every flag in this directory is written by
# write-reload-flag.sh through mktemp and mv, so its mtime is always "now"; a
# negative one is a corrupted timestamp, not a checkpoint from 1969. Accepting it
# would make the age enormous and hand the flag to the seven-day sweep, destroying
# the only pointer to a checkpoint on a number nobody should trust. Rejecting it
# reports the age as unestablished and leaves the file alone, which is the direction
# this subsystem takes for every reading it cannot rely on.
# Usage: mtime_of "$file"; m="$_MTIME_OUT"
_MTIME_OUT=""
mtime_of() {
    _MTIME_OUT=$(stat -f %m "$1" 2>/dev/null)
    [[ "$_MTIME_OUT" =~ ^[0-9]+$ ]] || _MTIME_OUT=$(stat -c %Y "$1" 2>/dev/null)
    [[ "$_MTIME_OUT" =~ ^[0-9]+$ ]] || _MTIME_OUT=""
}

# Human-readable file mtime into _MTIME_HUMAN; the literal "unknown" when none could
# be read. Six call sites had their own copy of this two-form probe and four of them
# asked BSD first, chained on the exit status -- which on GNU never reaches the
# fallback, for the reason stated above mtime_of: `-f` means --file-system and
# SUCCEEDS on a regular file. Unlike `%m`, the `-f` answer here cannot be recognised
# as wrong from its shape, so the order carries the correctness: GNU's own `-c` form
# is asked FIRST, and BSD, which has no `-c` at all and writes nothing to stdout when
# handed one, falls through to its `-f`+`-t` form. Seconds are always produced;
# callers wanting minute precision take the first 16 characters.
# Usage: mtime_human "$file"; m="$_MTIME_HUMAN"
_MTIME_HUMAN=""
mtime_human() {
    _MTIME_HUMAN=$(stat -c %y "$1" 2>/dev/null | cut -d'.' -f1)
    [[ -n "$_MTIME_HUMAN" ]] || _MTIME_HUMAN=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$1" 2>/dev/null)
    [[ -n "$_MTIME_HUMAN" ]] || _MTIME_HUMAN="unknown"
}

# Classify another artifact's recorded scope against THIS session's scope.
#
# Both arguments are scope_key() answers, so each may be "repo:<repository
# identity>", "dir:<physical path>", or the empty string. The comparison lives here
# because the two subsystems that will need it — checkpoint restore flags and plan
# files — must not drift into two different answers to the same question. They
# differ only in how the outcome is worded for the reader, which is why this
# returns a CLASS rather than a sentence: a flag records a directory, so its
# unverifiable case reads "recorded path unreachable", while a plan file records
# no directory at all, so the same class there means "no scope was ever
# recorded". One sentence covering both would state, for one of them, something
# that was never checked.
#
# The two unresolvable cases are deliberately NOT merged. Merging them makes the
# client-scope withholding contingent on our OWN directory resolving, so a
# session whose cwd is unresolvable — a removed worktree, the motivating case —
# would receive another project's recorded path under a legend asserting that
# the path no longer exists.
#
# Sets variables rather than printing: callers need two values at once, and
# command substitution costs a subshell per candidate. inject-plan.sh runs on
# EVERY user prompt, so a fork per candidate file is a per-keystroke cost.
#   SCOPE_CLASS — selfunver | unver | same | foreign | outside
#   SCOPE_PRIO  — row priority; lower sorts first
# Usage: scope_compare "$own_scope" "$other_scope"
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
        # Both sides answered, but at least one is `dir:` — a directory CHECKED
        # to be inside no repository. All that is established is that the scopes
        # differ; "a different repository" would name something neither has.
        SCOPE_CLASS="outside"; SCOPE_PRIO=6
    fi
}

# Helper: output JSON for UserPromptSubmit hooks using jq for proper escaping
json_user_prompt_output() {
    local content="$1"
    jq -n --arg c "$content" '{
        hookSpecificOutput: {
            hookEventName: "UserPromptSubmit",
            additionalContext: $c
        }
    }'
}

# Helper: output JSON for PostToolUse hooks using jq for proper escaping
json_post_tool_output() {
    local content="$1"
    jq -n --arg c "$content" '{
        hookSpecificOutput: {
            hookEventName: "PostToolUse",
            additionalContext: $c
        }
    }'
}

# Helper: output JSON for SessionStart hooks using jq for proper escaping
json_session_start_output() {
    local content="$1"
    jq -n --arg c "$content" '{
        hookSpecificOutput: {
            hookEventName: "SessionStart",
            additionalContext: $c
        }
    }'
}

# Calculate context percentage from transcript JSONL token usage.
# Reads the last assistant message's usage object (same data as statusline).
# Returns integer percentage (0-100+).
#
# Usage: pct=$(get_context_percentage "/path/to/transcript.jsonl")
get_context_percentage() {
    local transcript="$1"
    local context_window="${2:-}"

    if [[ ! -f "$transcript" ]]; then
        echo "0"
        return
    fi

    # Read last 200KB, filter for complete JSON lines only (grep '^{' skips
    # the truncated first line from tail -c byte-boundary cut).
    # || last_line="" guards against callers that run with set -e and prevents
    # non-zero pipeline exit from interrupting execution.
    local last_line
    last_line=$(tail -c 204800 "$transcript" 2>/dev/null \
        | grep '^{' \
        | grep '"assistant"' | tail -1) || last_line=""

    if [[ -z "$last_line" ]]; then
        echo "0"
        return
    fi

    local total
    total=$(echo "$last_line" | jq -r '
        .message.usage
        | ((.input_tokens // 0) + (.cache_read_input_tokens // 0)
           + (.cache_creation_input_tokens // 0) + (.output_tokens // 0))
    ' 2>/dev/null) || total=""

    if [[ -z "$total" ]] || [[ "$total" == "null" ]] || ! [[ "$total" =~ ^[0-9]+$ ]]; then
        echo "0"
        return
    fi

    # Auto-detect context window from model if not explicitly provided
    if [[ -z "$context_window" ]]; then
        local model
        model=$(echo "$last_line" | jq -r '.message.model // empty' 2>/dev/null) || model=""
        if [[ -n "$model" ]]; then
            context_window=$(model_to_context_window "$model")
        else
            context_window="$CONTEXT_WINDOW_TOKENS"
        fi
    fi

    if [[ "$context_window" -le 0 ]]; then
        echo "0"
        return
    fi

    echo "$((total * 100 / context_window))"
}

# Helper: output JSON for Stop hook block decisions using jq for proper escaping
json_stop_block() {
    local reason="$1"
    jq -n --arg r "$reason" '{
        decision: "block",
        reason: $r
    }'
}

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
# Sets: RALPH_ITERATION, RALPH_MAX_ITERATIONS, RALPH_COMPLETION_PROMISE, RALPH_PROMPT
# Args: $1 = CWD (optional, defaults to PWD)
# Returns: 0 if Ralph active, 1 otherwise
get_ralph_state() {
    local cwd="${1:-${PWD:-}}"
    local state_file="${cwd}/.claude/${RALPH_STATE_FILENAME}"

    RALPH_ITERATION=""
    RALPH_MAX_ITERATIONS=""
    RALPH_COMPLETION_PROMISE=""
    RALPH_PROMPT=""

    if [[ ! -f "$state_file" ]]; then
        return 1
    fi

    # Extract YAML frontmatter (between --- delimiters)
    local frontmatter
    frontmatter=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$state_file" 2>/dev/null) || return 1

    local active
    active=$(echo "$frontmatter" | grep '^active:' | sed 's/^active:[[:space:]]*//' | tr -d '[:space:]')
    if [[ "$active" != "true" ]]; then
        return 1
    fi

    RALPH_ITERATION=$(echo "$frontmatter" | grep '^iteration:' | sed 's/^iteration:[[:space:]]*//' | tr -d '[:space:]')
    RALPH_MAX_ITERATIONS=$(echo "$frontmatter" | grep '^max_iterations:' | sed 's/^max_iterations:[[:space:]]*//' | tr -d '[:space:]')
    RALPH_COMPLETION_PROMISE=$(echo "$frontmatter" | grep '^completion_promise:' | sed 's/^completion_promise:[[:space:]]*//' | sed 's/^"//; s/"$//' | sed "s/^'//; s/'$//")
    if [[ "$RALPH_COMPLETION_PROMISE" == "null" ]]; then
        RALPH_COMPLETION_PROMISE=""
    fi

    # Extract prompt (everything after second ---)
    RALPH_PROMPT=$(awk '/^---$/{i++; next} i>=2' "$state_file" 2>/dev/null)

    return 0
}

# Save Ralph resume state for post-/clear auto-restart.
# Creates two files: metadata + prompt (split to handle newlines in prompt).
# Args: $1 = CWD key, $2 = max_iterations, $3 = iteration, $4 = promise,
#       $5 = prompt text, $6 = plan path (optional)
save_ralph_resume() {
    local cwd_key="$1"
    local max_iter="$2"
    local iteration="$3"
    local promise="$4"
    local prompt="$5"
    local plan_path="${6:-}"

    local resume_file="${PLANS_DIR}/.ralph-resume-${cwd_key}"
    local prompt_file="${resume_file}.prompt"

    printf '%s\n%s\n%s\n%s\n%s\n' \
        "$max_iter" "$iteration" "$promise" "$plan_path" \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" > "$resume_file"
    printf '%s' "$prompt" > "$prompt_file"
}

# Read Ralph resume files.
# Sets: RALPH_RESUME_MAX_ITER, RALPH_RESUME_ITERATION, RALPH_RESUME_PROMISE,
#       RALPH_RESUME_PLAN_PATH, RALPH_RESUME_TIMESTAMP, RALPH_RESUME_PROMPT
# Args: $1 = CWD key
# Returns: 0 if resume files exist and are valid, 1 otherwise
read_ralph_resume() {
    local cwd_key="$1"
    local resume_file="${PLANS_DIR}/.ralph-resume-${cwd_key}"
    local prompt_file="${resume_file}.prompt"

    RALPH_RESUME_MAX_ITER=""
    RALPH_RESUME_ITERATION=""
    RALPH_RESUME_PROMISE=""
    RALPH_RESUME_PLAN_PATH=""
    RALPH_RESUME_TIMESTAMP=""
    RALPH_RESUME_PROMPT=""

    if [[ ! -f "$resume_file" ]]; then
        return 1
    fi

    # Check freshness (< 60 min)
    local fresh
    fresh=$(find "$resume_file" -mmin -60 2>/dev/null)
    if [[ -z "$fresh" ]]; then
        rm -f "$resume_file" "$prompt_file" 2>/dev/null
        return 1
    fi

    RALPH_RESUME_MAX_ITER=$(sed -n '1p' "$resume_file" 2>/dev/null)
    RALPH_RESUME_ITERATION=$(sed -n '2p' "$resume_file" 2>/dev/null)
    RALPH_RESUME_PROMISE=$(sed -n '3p' "$resume_file" 2>/dev/null)
    RALPH_RESUME_PLAN_PATH=$(sed -n '4p' "$resume_file" 2>/dev/null)
    RALPH_RESUME_TIMESTAMP=$(sed -n '5p' "$resume_file" 2>/dev/null)

    if [[ -f "$prompt_file" ]]; then
        RALPH_RESUME_PROMPT=$(cat "$prompt_file" 2>/dev/null)
    fi

    return 0
}

# Check if Ralph was recently active in the given CWD (regardless of active status).
# Used for proactive phase-boundary resume: Ralph exits normally via promise,
# state file remains with active: false. Resume files don't exist (those are
# only created by the reactive context-threshold path).
# Args: $1 = CWD (optional, defaults to PWD)
# Returns: 0 if ralph state file exists and is fresh (<60 min), 1 otherwise
# Sets: RALPH_RECENT_PROMPT (prompt text from the state file)
check_ralph_recently_active() {
    local cwd="${1:-${PWD:-}}"
    local state_file="${cwd}/.claude/${RALPH_STATE_FILENAME}"

    RALPH_RECENT_PROMPT=""

    if [[ ! -f "$state_file" ]]; then
        return 1
    fi

    local fresh
    fresh=$(find "$state_file" -mmin -60 2>/dev/null)
    if [[ -z "$fresh" ]]; then
        return 1
    fi

    RALPH_RECENT_PROMPT=$(awk '/^---$/{i++; next} i>=2' "$state_file" 2>/dev/null)

    return 0
}

# Force Ralph loop to exit by setting max_iterations = iteration in state file.
# Ralph's stop hook checks iteration >= max_iterations as a legitimate exit path.
# Args: $1 = CWD (optional, defaults to PWD)
# Returns: 0 on success, 1 if state file not found
force_ralph_exit() {
    local cwd="${1:-${PWD:-}}"
    local state_file="${cwd}/.claude/${RALPH_STATE_FILENAME}"

    if [[ ! -f "$state_file" ]]; then
        return 1
    fi

    local iteration
    iteration=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$state_file" 2>/dev/null \
        | grep '^iteration:' | sed 's/^iteration:[[:space:]]*//' | tr -d '[:space:]')

    if [[ -z "$iteration" ]] || ! [[ "$iteration" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    # Set max_iterations = iteration so Ralph's stop hook allows exit
    # Cross-platform: sed -i '' is macOS-only; use temp file instead
    local tmp
    tmp=$(mktemp "${state_file}.XXXXXX") || return 1
    if sed -e "s/^max_iterations:.*/max_iterations: ${iteration}/" "$state_file" > "$tmp" 2>/dev/null; then
        if ! mv "$tmp" "$state_file"; then
            rm -f "$tmp"
            return 1
        fi
    else
        rm -f "$tmp"
        return 1
    fi
}

# --- Ralph Orchestrator helpers ---

# Parse orchestrator state file YAML frontmatter.
# Sets: ORCH_ACTIVE, ORCH_MODE, ORCH_ITERATION, ORCH_MAX_ITERATIONS,
#       ORCH_PLAN_PATH, ORCH_COMPLETION_PROMISE, ORCH_CURRENT_TASK, ORCH_STARTED_AT
# Args: $1 = CWD key
# Returns: 0 if orchestrator active, 1 otherwise
get_orchestrator_state() {
    local cwd_key="$1"
    local state_file="${PLANS_DIR}/${ORCH_STATE_PREFIX}${cwd_key}"

    ORCH_ACTIVE=""
    ORCH_MODE=""
    ORCH_ITERATION=""
    ORCH_MAX_ITERATIONS=""
    ORCH_PLAN_PATH=""
    ORCH_COMPLETION_PROMISE=""
    ORCH_CURRENT_TASK=""
    ORCH_STARTED_AT=""

    if [[ ! -f "$state_file" ]]; then
        return 1
    fi

    local frontmatter
    frontmatter=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$state_file" 2>/dev/null) || return 1

    local active
    active=$(echo "$frontmatter" | grep '^active:' | sed 's/^active:[[:space:]]*//' | tr -d '[:space:]')
    if [[ "$active" != "true" ]]; then
        return 1
    fi

    ORCH_ACTIVE="true"
    ORCH_MODE=$(echo "$frontmatter" | grep '^mode:' | sed 's/^mode:[[:space:]]*//' | tr -d '[:space:]')
    ORCH_ITERATION=$(echo "$frontmatter" | grep '^iteration:' | sed 's/^iteration:[[:space:]]*//' | tr -d '[:space:]')
    ORCH_MAX_ITERATIONS=$(echo "$frontmatter" | grep '^max_iterations:' | sed 's/^max_iterations:[[:space:]]*//' | tr -d '[:space:]')
    ORCH_PLAN_PATH=$(echo "$frontmatter" | grep '^plan_path:' | sed 's/^plan_path:[[:space:]]*//' | sed 's/^"//; s/"$//' | sed "s/^'//; s/'$//")
    ORCH_COMPLETION_PROMISE=$(echo "$frontmatter" | grep '^completion_promise:' | sed 's/^completion_promise:[[:space:]]*//' | sed 's/^"//; s/"$//' | sed "s/^'//; s/'$//")
    ORCH_CURRENT_TASK=$(echo "$frontmatter" | grep '^current_task:' | sed 's/^current_task:[[:space:]]*//' | sed 's/^"//; s/"$//' | sed "s/^'//; s/'$//")
    ORCH_STARTED_AT=$(echo "$frontmatter" | grep '^started_at:' | sed 's/^started_at:[[:space:]]*//' | sed 's/^"//; s/"$//' | sed "s/^'//; s/'$//")

    return 0
}

# Save orchestrator resume state for post-/clear restoration.
# Args: $1 = CWD key, $2 = iteration, $3 = max_iterations, $4 = plan_path,
#       $5 = completion_promise, $6 = current_task
save_orchestrator_resume() {
    local cwd_key="$1"
    local iteration="$2"
    local max_iter="$3"
    local plan_path="$4"
    local promise="$5"
    local current_task="$6"

    local resume_file="${PLANS_DIR}/.ralph-orch-resume-${cwd_key}"

    printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
        "$iteration" "$max_iter" "$plan_path" "$promise" "$current_task" \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" > "$resume_file"
}

# Read orchestrator resume state.
# Sets: ORCH_RESUME_ITERATION, ORCH_RESUME_MAX_ITER, ORCH_RESUME_PLAN_PATH,
#       ORCH_RESUME_PROMISE, ORCH_RESUME_CURRENT_TASK, ORCH_RESUME_TIMESTAMP
# Args: $1 = CWD key
# Returns: 0 if resume file exists and is fresh, 1 otherwise
read_orchestrator_resume() {
    local cwd_key="$1"
    local resume_file="${PLANS_DIR}/.ralph-orch-resume-${cwd_key}"

    ORCH_RESUME_ITERATION=""
    ORCH_RESUME_MAX_ITER=""
    ORCH_RESUME_PLAN_PATH=""
    ORCH_RESUME_PROMISE=""
    ORCH_RESUME_CURRENT_TASK=""
    ORCH_RESUME_TIMESTAMP=""

    if [[ ! -f "$resume_file" ]]; then
        return 1
    fi

    local fresh
    fresh=$(find "$resume_file" -mmin -60 2>/dev/null)
    if [[ -z "$fresh" ]]; then
        rm -f "$resume_file" 2>/dev/null
        return 1
    fi

    ORCH_RESUME_ITERATION=$(sed -n '1p' "$resume_file" 2>/dev/null)
    ORCH_RESUME_MAX_ITER=$(sed -n '2p' "$resume_file" 2>/dev/null)
    ORCH_RESUME_PLAN_PATH=$(sed -n '3p' "$resume_file" 2>/dev/null)
    ORCH_RESUME_PROMISE=$(sed -n '4p' "$resume_file" 2>/dev/null)
    ORCH_RESUME_CURRENT_TASK=$(sed -n '5p' "$resume_file" 2>/dev/null)
    ORCH_RESUME_TIMESTAMP=$(sed -n '6p' "$resume_file" 2>/dev/null)

    return 0
}
