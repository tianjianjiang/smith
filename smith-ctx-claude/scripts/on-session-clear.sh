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

source "$(dirname "$0")/lib-plan.sh"
require_jq

INPUT=$(cat)

# Extract CWD from hook input
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
CWD_KEY=$(session_key "" "${HOOK_CWD:-${PWD:-}}") || {
    echo "Error: session_key failed" >&2; exit 1
}
STATE_FILE="${PLANS_DIR}/.plan-state-${CWD_KEY}"
STATE_BASENAME=".plan-state-${CWD_KEY}"
OWN_SCOPE=$(scope_key "${HOOK_CWD:-${PWD:-}}")
FLAG_FILE="${PLANS_DIR}/.pending-reload-${CWD_KEY}"

# Capture model from SessionStart input (only hook event with model field)
_hook_model=$(echo "$INPUT" | jq -r '.model // empty' 2>/dev/null) || _hook_model=""
if [[ -n "$_hook_model" ]]; then
    save_session_model "$CWD_KEY" "$_hook_model"
fi

# Try to find plan from state file
PLAN_FILE=""
if [[ -f "$STATE_FILE" ]]; then
  
  
  
  
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
#
# REPORTING CONTRACT: whenever the scan produced a row, this hook says what it saw.
# Emitting nothing when nothing matched is how a matching defect survives
# indefinitely: the common outcome is also the invisible one. Two states carry no
# rows and are reported one line at a time instead: only stale, swept or unreadable
# flags; an unusable PLANS_DIR; and an EMPTY hook cwd, where the scan is skipped
# entirely (see the guard below) because "" would match a truncated flag. That last
# one used to be silent and is not any more, so no state carrying no rows is silent.
# Rows are ordered by verdict priority and only then by time, capped at five with
# everything withheld counted, each row carrying label, recorded path, age, verdict,
# and — only where the agent may act on it — the flag key. The verdicts, in priority
# order, with the exact strings the code emits:
#   1 "MATCHES this session"
#   2 "MATCHED but expired, consumed WITHOUT restoring (its memory is still in the
#     backends)" — ABOVE the selectable rows on purpose: this run destroyed its
#     flag, so the label printed here is the only remaining handle, while a row
#     that keeps its flag is offered again at the next /clear
#   3 "same repository, selectable"
#   4 "MATCHED but could NOT be claimed (filesystem error), not restored, still on
#     disk"
#   5 "scope unverifiable, recorded path unreachable" / "malformed flag, no recorded
#     path"
#   6 "different repository, counted only" / "outside this session's scope, counted
#     only" / "own scope unresolvable, withheld" — the WITHHELD band: counted, never
#     printed, because a recorded path and a free-text label are identifying
#     material this session established no claim to (~/.claude/rules/client-scope.md)
# Verdicts 1, 2 and 4 come from the exact cwd match; 3, 5 (unverifiable) and 6
# come from scope_key(); 5 (malformed) comes from neither — it is decided before
# scope_key() is consulted, because the flag records no path to resolve.
# Consumption is unchanged and still keyed on the exact match: matched flags are
# consumed one-shot whether fresh or stale (24h window, hardcoded), and a matched
# flag consumed while stale is LISTED, because that path destroys the only pointer
# to a checkpoint whose memory still exists. Non-matching flags are left for their
# own session's /clear, except a >7-day hygiene sweep. Flags this hook could not
# read are counted rather than passed over, and so is a claim lost to a concurrent
# hook on a flag that MATCHED this session: losing that race means a restore this
# session would have performed did not happen. The hygiene sweep is the deliberate
# exception — the flag there is not this session's, so the loser of that race has
# nothing the reader could act on, and the winner reports the removal.
# The flag is only a pointer — checkpoint state lives in the memory backends.
_mr_cwd="${HOOK_CWD:-${PWD:-}}"
_mr_cwd=${_mr_cwd//$'\n'/ }
MR_DIRECTIVE=""
# Distinct from MR_DIRECTIVE being non-empty: the hook now speaks up to REPORT as
# well as to restore, and a report with nothing restorable must not flip the
# session signal to "resume" — that would claim work is waiting when none is.
MR_ACTIONABLE=""
# One line per listable flag, seven fields separated by 0x1F (NOT a tab — see
# _mr_append_row): priority, mtime, verdict, label, timestamp, path, key.
_mr_rows=""
_mr_scope=""
# Two stale populations that must NOT share a counter: one is left on disk for its
# own session, the other MATCHED this session and was therefore consumed — destroyed
# without restoring anything. Reporting the second as an ordinary old flag would
# recreate the exact invisible outcome this contract exists to remove.
_mr_seen_n=0
_mr_stale_kept_n=0
_mr_stale_gone_n=0
_mr_swept_n=0
_mr_match_n=0
# Flags that matched this session's directory, counted BEFORE a verdict is chosen and
# whatever the verdict turns out to be. The "nothing belongs to this repository"
# sentence was gated on the priority-3 counter alone, so it fired beside rows at
# priority 2 and 4 -- expired, unmeasured, unclaimable -- every one of which had
# matched this directory exactly. Counting at the match itself rather than listing
# the verdicts is deliberate: a verdict added later is covered without being
# remembered, which is the same reason the bearing sum below subtracts rather than
# enumerates.
_mr_mine_n=0
_mr_same_n=0
_mr_fsession_n=0
_mr_unclaimed_n=0
_mr_unmeasured_n=0
_mr_unconsumed_n=0
_mr_unver_shown_n=0
_mr_malformed_shown_n=0
_mr_unver_n=0
_mr_foreign_n=0
_mr_selfunver_n=0
_mr_outside_n=0
_mr_malformed_n=0
_mr_unreadable_n=0
_mr_unopenable_n=0
_mr_notplain_n=0
_mr_lostrace_n=0
_mr_gone_hidden_n=0
_mr_same_hidden_n=0
_mr_match_relisted_n=0
# A claim file is a flag moved by `mv`, so what it holds is inherited, never verified here
# — and the flag loop does not itself assume a flag is complete: it carries a "malformed
# flag, no recorded path" verdict. Every sentence written about these two counters, at
# either report site, is therefore phrased as inherited-not-verified.
_mr_claimed_gone_n=0
_mr_claimed_kept_n=0
_mr_tmp_n=0
_mr_tmp_gone_n=0
_mr_tmp_body_kept_n=0
_mr_tmp_body_gone_n=0
_mr_litter_stuck_n=0
_mr_litter_unmeasured_n=0
_mr_dir_unreadable=""
# An unusable PLANS_DIR is indistinguishable from an empty one downstream: every
# counter stays zero and the session reports "fresh-start" at every /clear while
# checkpoints pile up unread — the pre-fix failure mode, one level up.
#
# BOTH bits matter, and they fail differently. Without read permission the glob
# cannot expand and yields its own literal pattern. Without the search bit the glob
# DOES expand — the names are visible — but `[[ -f ]]` needs to stat each entry and
# every flag is dropped one by one, which is the quieter and therefore worse of the
# two. Mode 600 on a directory reaches the second state, and an over-broad
# `chmod -R`, a restrictive umask or a copied ~/.claude all reach mode 600.
#
# `-d` being FALSE is not by itself an answer either. With the parent unsearchable
# — one over-broad `chmod` higher up, the same causes as above — `-d` is false for a
# directory that is there and full of flags, and the run then reports nothing at
# all: the pre-fix failure mode, reached one level further up than the case this
# guard was first written for. So absence only counts when it was CHECKED: some
# ancestor had to be inspectable for "it is not there" to be a fact rather than the
# shape of a denial.
_mr_absence_is_checked() {
    local d="$1" parent
    while :; do
        if [[ "$d" == */* ]]; then
            parent="${d%/*}"
            [[ -n "$parent" ]] || parent="/"
        else
          
          
          
          
          
            parent="."
        fi
        [[ -d "$parent" && -r "$parent" && -x "$parent" ]] && return 0
        [[ -e "$parent" ]] && return 1
        [[ "$parent" == "/" || "$parent" == "." ]] && return 1
        d="$parent"
    done
}
if [[ -d "$PLANS_DIR" ]]; then
    { [[ ! -r "$PLANS_DIR" ]] || [[ ! -x "$PLANS_DIR" ]]; } && _mr_dir_unreadable="yes"
elif ! _mr_absence_is_checked "$PLANS_DIR"; then
    _mr_dir_unreadable="yes"
fi
# Flag contents are found, not trusted: write-reload-flag.sh strips newlines from
# what it writes, but nothing stops a hand-created file in PLANS_DIR.
#
# Backslashes are neutralized, not merely control characters, because the assembled
# directive is emitted through `printf '%b'` further down: a literal two-character
# `\n` is printable, survives any control-character filter, and is expanded into a
# REAL newline at output time. That is enough to forge extra lines that look like
# this hook's own directives, so the escape has to die here.
#
# What this guarantees: row-schema integrity (nothing in a field can introduce a
# field or a line) and a bounded length, with truncation marked rather than silent.
# What it does NOT guarantee: immunity from instruction-shaped prose. A label is
# free text that reaches the model, and no character filter makes "ignore the above
# and ..." safe. The defence there is that PLANS_DIR is same-user-writable only —
# do not read this filter as closing the injection surface.
# Pure builtins, and the result comes back in _MR_CLEAN rather than on stdout: this
# runs several times per flag on every /clear, and `printf | tr` cost ~9.7ms per call
# against ~0.55ms for the equivalent parameter expansion — one developer's machine,
# not reproducible from this repository — while
# capturing stdout with $( ) would fork a subshell for each result as well.
# `[[:cntrl:]]` is bash 3.2-compatible (macOS /bin/bash) and covers DEL (0x7F) too.
# Args: $1 = text, $2 = max length (default 200). Result: $_MR_CLEAN
_MR_CLEAN=""
_mr_clean() {
    local text="${1//\\/ }" max="${2:-200}"
    text="${text//[[:cntrl:]]/}"
    if [[ "${#text}" -gt "$max" ]]; then
        _MR_CLEAN="${text:0:$max}…"
    else
        _MR_CLEAN="$text"
    fi
}

# The displayed copy of PLANS_DIR is derived HERE, above the scan block, because the
# two directives that report a SKIPPED scan are the `elif` arms of that very block:
# they run precisely when nothing inside it did. Assigning this within the block left
# both of them naming an empty path — and telling the reader which directory to fix
# is the only reason either sentence exists. The real `$PLANS_DIR` still backs every
# filesystem operation; only the printed form is filtered.
_mr_clean "$PLANS_DIR" 300
_mr_plans_shown="$_MR_CLEAN"

# The first conjunct is the empty-cwd guard: "" == "" would match every truncated or
# corrupt flag, so the whole scan is skipped and every flag left for a healthy hook
# run to consume. The second is the unusable-directory guard set just above.
if [[ -n "$_mr_cwd" && -z "$_mr_dir_unreadable" ]]; then
_mr_scope=$(scope_key "$_mr_cwd")
# scope_key() answers "repo:<path>" or "dir:<path>"; the kind steers the verdicts
# below, the path is what a reader can act on. Strip the kind for display only.
_mr_scope_shown="${_mr_scope#*:}"
[[ -n "$_mr_scope_shown" ]] || _mr_scope_shown="unknown"
# The exact match compares PHYSICAL paths. Comparing the writer's logical $PWD
# against the hook's cwd byte-for-byte meant one directory under two spellings
# (/tmp vs /private/tmp, a symlinked home or project tree) never matched — the
# same class of miss this whole change exists to remove. The raw strings are
# still compared first, so a recorded path that no longer exists still matches
# when it is spelled identically.
_mr_cwd_phys=$(cd -- "$_mr_cwd" 2>/dev/null && pwd -P) || _mr_cwd_phys=""

# Memoize scope_key by recorded path, result in _MR_SCOPE_OUT.
#
# This hook runs on every /clear over a directory whose whole problem is that flags
# accumulate for up to seven days, so per-flag cost is the thing to watch. Measured
# measured on one developer's machine at 100 flags and NOT reproducible from this
# repository: 6.8s with a fork per flag, 2.5s without. A `git rev-parse` is ~12ms of
# that, so the cache earns its place, but the forks were the cost that mattered.
# Flags cluster on a few distinct directories, so a
# linear scan over the paths seen so far turns N git calls into one per directory.
# Two indexed arrays rather than one associative array: macOS ships bash 3.2, which
# has none. The result comes back in a variable because $( ) would fork per lookup
# and undo the saving.
_MR_CACHE_PATHS=()
_MR_CACHE_KEYS=()
_MR_SCOPE_OUT=""
_mr_scope_cached() {
    local want="$1" i=0
    while [[ "$i" -lt "${#_MR_CACHE_PATHS[@]}" ]]; do
        if [[ "${_MR_CACHE_PATHS[$i]}" == "$want" ]]; then
            _MR_SCOPE_OUT="${_MR_CACHE_KEYS[$i]}"
            return 0
        fi
        i=$((i + 1))
    done
    _MR_SCOPE_OUT=$(scope_key "$want")
    _MR_CACHE_PATHS+=("$want")
    _MR_CACHE_KEYS+=("$_MR_SCOPE_OUT")
}


# The scope line is displayed, so it goes through the same filter as a flag's own
# fields and for the same reason: a `\c` in this session's own directory name would
# end the whole directive at that point. Filtered once here rather than at each site
# that prints it.
_mr_clean "$_mr_scope_shown" 300
_mr_scope_shown="$_MR_CLEAN"

# Append one listable row for a flag file.
#
# Rows are delimited by the unit separator (0x1F), NOT by a tab: bash treats tab as
# IFS whitespace, so `IFS=$'\t' read` collapses two adjacent tabs into one and an
# empty field shifts every later field left by one. A label IS optionally empty
# (`write-reload-flag.sh` takes it as an optional argument), so with tabs a
# checkpoint saved without a label silently printed its timestamp in the label
# column and its flag key in the path column. 0x1F cannot appear in any field
# because _mr_clean strips the whole 0x00-0x1F range.
#
# The flag key is emitted verbatim into an `rm` command the agent is told to run,
# so it gets an allowlist rather than a filter: anything outside it is dropped and
# the row simply carries no key (the caller then omits the delete instruction).
#
# The leading priority field is what the cap sorts on before mtime. Sorting by time
# alone let five newer rows nobody may act on push the single actionable row past
# the five-row cap, while the directive still said "offer those rows only" — with
# no such row on screen. Priority ordering alone does NOT close that hole: priority
# 2 outranks priority 3, so expired-matched rows evict selectable ones. The display
# loop reserves a slot for the first selectable row for that reason.
# The caller passes the label and timestamp it already read: the flag's four lines
# are read once, with builtins, in the scan loop. Re-reading them here cost three
# `sed` forks per flag (~29ms on one developer's machine, not reproducible from this
# repository) for bytes already in memory.
# Args: $1 = priority (1 matched, 2 matched-but-expired, 3 same repository,
#       4 matched-but-unclaimable, 5 unverifiable or malformed, 6 other repository),
#       $2 = mtime, $3 = verdict, $4 = label, $5 = timestamp, $6 = path, $7 = key
# Order the rows in place: priority ascending, then mtime descending, then the
# recorded timestamp descending — the same key `sort -t$'\037' -k1,1n -k2,2rn -k5,5r`
# produced. It is done with builtins because `sort` was the last fork in this path
# and its result was captured unchecked: a failing `sort` assigned the empty string
# AFTER the matched flags had been consumed, so the block printed its header with no
# rows and the labels — the only remaining handle on a consumed checkpoint — were
# gone with no count and no message. Insertion sort is enough here: the input is the
# flags in one directory, and both leading fields are integers.
_mr_sort_rows() {
    local -a in_row=() in_p=() in_m=() in_t=() a_row=() a_p=() a_m=() a_t=()
    local row rest p m t i j k after_or_equal
    while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        p=${row%%$'\037'*}
        rest=${row#*$'\037'}; m=${rest%%$'\037'*}
        rest=${rest#*$'\037'}
        rest=${rest#*$'\037'}
        rest=${rest#*$'\037'}
        t=${rest%%$'\037'*}
      
      
        [[ "$p" =~ ^[0-9]+$ ]] || p=9
        [[ "$m" =~ ^[0-9]+$ ]] || m=0
        in_row+=("$row"); in_p+=("$p"); in_m+=("$m"); in_t+=("$t")
    done <<< "$_mr_rows"
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
    k=${#in_row[@]}
    while [[ "$k" -gt 0 ]]; do
        k=$((k - 1))
        p=${in_p[$k]}; m=${in_m[$k]}; t=${in_t[$k]}; row=${in_row[$k]}
        i=${#a_row[@]}
        while [[ "$i" -gt 0 ]]; do
            j=$((i - 1))
          
          
          
          
            after_or_equal=1
            if [[ "${a_p[$j]}" -lt "$p" ]]; then
                after_or_equal=0
            elif [[ "${a_p[$j]}" -eq "$p" ]]; then
                if [[ "${a_m[$j]}" -gt "$m" ]]; then
                    after_or_equal=0
                elif [[ "${a_m[$j]}" -eq "$m" && "${a_t[$j]}" > "$t" ]]; then
                    after_or_equal=0
                fi
            fi
            [[ "$after_or_equal" -eq 1 ]] || break
            a_row[$i]=${a_row[$j]}; a_p[$i]=${a_p[$j]}; a_m[$i]=${a_m[$j]}; a_t[$i]=${a_t[$j]}
            i=$j
        done
        a_row[$i]=$row; a_p[$i]=$p; a_m[$i]=$m; a_t[$i]=$t
    done
    _mr_rows=""
    for row in ${a_row[@]+"${a_row[@]}"}; do
        _mr_rows+="${row}"$'\n'
    done
}

_mr_append_row() {
    local prio="$1" mtime="$2" verdict="$3" key="$7" label ts path
    _mr_clean "$4";      label="$_MR_CLEAN"
    _mr_clean "$5";      ts="$_MR_CLEAN"
  
  
  
    _mr_clean "$6" 400;  path="$_MR_CLEAN"
    [[ "$key" =~ $_MR_KEY_ALLOWED ]] || key=""
    _mr_rows+="${prio}"$'\037'"${mtime}"$'\037'"${verdict}"$'\037'"${label}"$'\037'"${ts}"$'\037'"${path}"$'\037'"${key}"$'\n'
}
_mr_now=$(date +%s)
# The last unchecked capture in this block, and it feeds the mtime fallback below:
# an empty `_mr_now` propagates into `_mr_mtime`, which the display loop then drops
# on its `-n` guard with no count while the header still counts the flag. Zero puts
# every real mtime far enough ahead of the sampled clock that no age is established,
# so those flags are reported at priority 4 and neither restored nor consumed. The
# display loop guards on the priority field, not on the mtime, and renders
# "age unknown".
[[ "$_mr_now" =~ ^[0-9]+$ ]] || _mr_now=0

# How far AHEAD of the sampled clock an mtime may sit and still count as measured.
# `_mr_now` is read once, before a per-flag loop that forks, so a flag written by a
# concurrent write-reload-flag.sh ordinarily lands after that read: it is the
# in-flight race, not a broken clock, and it is genuinely fresh. Three places apply
# the rule -- the flag scan, the litter sweep and the row display -- and they must
# agree, because a flag the scan calls fresh and consumes cannot be a flag the row
# calls ageless. Anything further ahead (a restored backup, a `cp -p` from a machine
# running ahead, an NFS clock, or `_mr_now` forced to 0 by a failed `date`)
# establishes no age at all.
_MR_CLOCK_AHEAD_S=60

_mr_is_plain_file() {
    [[ -L "$1" ]] && return 1
    local nlink
    nlink=$(stat -c %h "$1" 2>/dev/null)
    [[ "$nlink" =~ ^[0-9]+$ ]] || nlink=$(stat -f %l "$1" 2>/dev/null)
    [[ "$nlink" =~ ^[0-9]+$ ]] && [[ "$nlink" -ne 1 ]] && return 1
    return 0
}

_MR_PHYS_KEY=""
[[ -n "$_mr_cwd_phys" ]] && { _MR_PHYS_KEY=$(session_key "" "$_mr_cwd_phys") || _MR_PHYS_KEY=""; }

_MR_KEY_ALLOWED='^[0-9A-Za-z._-]+$'
_MR_OFFERED_FILE="${PLANS_DIR}/.mr-offered-${CWD_KEY}"
_mr_offered_usable=1
if [[ -e "$_MR_OFFERED_FILE" || -L "$_MR_OFFERED_FILE" ]]; then
    if [[ ! -f "$_MR_OFFERED_FILE" ]] || ! _mr_is_plain_file "$_MR_OFFERED_FILE"; then
        _mr_offered_usable=0
    fi
fi
_mr_offered_set=""
[[ "$_mr_offered_usable" -eq 1 && -r "$_MR_OFFERED_FILE" ]] && _mr_offered_set=$(cat "$_MR_OFFERED_FILE" 2>/dev/null)
_mr_offered_new=""
_mr_reoffered_n=0

_mr_was_offered() {
    [[ -n "$1" ]] || return 1
    case $'\n'"${_mr_offered_set}"$'\n' in
        *$'\n'"$1"$'\n'*) return 0 ;;
    esac
    return 1
}
for _mr_f in "${PLANS_DIR}"/.pending-memory-restore-*; do
    if [[ ! -f "$_mr_f" ]]; then
      
      
      
      
      
      
      
      
      
      
      
      
      
        if [[ "$_mr_f" != *'*'* ]]; then
            if [[ ! -e "$_mr_f" ]] && [[ ! -L "$_mr_f" ]]; then
                _mr_lostrace_n=$((_mr_lostrace_n + 1))
            else
                _mr_unopenable_n=$((_mr_unopenable_n + 1))
            fi
        fi
        continue
    fi
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
    if ! _mr_is_plain_file "$_mr_f"; then
        _mr_notplain_n=$((_mr_notplain_n + 1))
        continue
    fi
    _mr_seen_n=$((_mr_seen_n + 1))
  
  
  
  
    if [[ ! -r "$_mr_f" ]]; then
        _mr_unreadable_n=$((_mr_unreadable_n + 1))
        continue
    fi
  
  
  
  
  
  
  
  
  
    _mr_l1=""; _mr_l2=""; _mr_l3=""; _mr_l4=""; _mr_l5=""
    { IFS= read -r _mr_l1; IFS= read -r _mr_l2; IFS= read -r _mr_l3; IFS= read -r _mr_l4; IFS= read -r _mr_l5; } < "$_mr_f" 2>/dev/null
    _mr_fcwd="$_mr_l3"
    _mr_key="${_mr_f##*/.pending-memory-restore-}"
    _mr_okey="$_mr_key"
    [[ "$_mr_okey" =~ $_MR_KEY_ALLOWED ]] || _mr_okey=""

  
  
  
  
  
  
  
  
  
  
  
  
  
  
    mtime_of "$_mr_f"; _mr_mtime="$_MTIME_OUT"
  
  
  
  
  
  
  
  
  
  
  
  
    _mr_measured=1
    _mr_age=0
    if [[ ! "$_mr_mtime" =~ ^[0-9]+$ ]]; then
        _mr_measured=0
    elif [[ "$_mr_now" -ge "$_mr_mtime" ]]; then
        _mr_age=$((_mr_now - _mr_mtime))
    elif [[ $((_mr_mtime - _mr_now)) -gt "$_MR_CLOCK_AHEAD_S" ]]; then
        _mr_measured=0
    fi
  
  
    [[ "$_mr_measured" -eq 0 ]] && _mr_mtime=""

    _mr_is_match=""
    if [[ "$_mr_fcwd" == "$_mr_cwd" ]]; then
        _mr_is_match="yes"
    elif [[ -n "$_mr_cwd_phys" && -n "$_mr_fcwd" ]]; then
      
      
      
        _mr_fphys=$(cd -- "$_mr_fcwd" 2>/dev/null && pwd -P) || _mr_fphys=""
        [[ -n "$_mr_fphys" && "$_mr_fphys" == "$_mr_cwd_phys" ]] && _mr_is_match="yes"
    fi
    _mr_foreign_session=""
    _mr_owner_unchecked=""
    if [[ -n "$_mr_is_match" && -n "$_mr_l5" ]] \
       && [[ "$_mr_l5" != "$CWD_KEY" ]] \
       && { [[ -z "$_MR_PHYS_KEY" ]] || [[ "$_mr_l5" != "$_MR_PHYS_KEY" ]]; }; then
        _mr_foreign_session="yes"
        [[ -z "$_MR_PHYS_KEY" ]] && _mr_owner_unchecked="yes"
        _mr_is_match=""
    fi
    [[ -n "$_mr_is_match" ]] && _mr_mine_n=$((_mr_mine_n + 1))
    if [[ -z "$_mr_is_match" ]]; then
      
      
      
      
      
      
      
      
      
        if [[ "$_mr_age" -gt 604800 ]]; then
            _mr_claim="${PLANS_DIR}/.mr-claimed.$$.${_mr_key}"
            if mv "$_mr_f" "$_mr_claim" 2>/dev/null; then
              
              
              
              
              
                if rm -f "$_mr_claim" 2>/dev/null; then
                    _mr_swept_n=$((_mr_swept_n + 1))
                    [[ -n "$_mr_foreign_session" ]] && _mr_append_row 2 "$_mr_mtime" "REMOVED as older than 7 days WITHOUT restoring: another session's flag recorded in THIS directory (its memory is still in the backends)" "$_mr_l4" "$_mr_l2" "$_mr_fcwd" "$_mr_key"
                else
                    _mr_unconsumed_n=$((_mr_unconsumed_n + 1))
                fi
                continue
            fi
            [[ -e "$_mr_f" ]] || continue
            echo "Warning: cannot sweep expired memory-restore flag: $_mr_f" >&2
          
        fi
      
      
      
        if [[ "$_mr_measured" -eq 0 || "$_mr_age" -le 86400 ]]; then
            if [[ -z "$_mr_fcwd" ]]; then
              
              
              
              
                _mr_malformed_n=$((_mr_malformed_n + 1))
                _mr_append_row 5 "$_mr_mtime" "malformed flag, no recorded path" "$_mr_l4" "$_mr_l2" "$_mr_fcwd" "$_mr_key"
                continue
            fi
            if [[ -n "$_mr_foreign_session" ]]; then
                if _mr_was_offered "$_mr_okey"; then
                    _mr_reoffered_n=$((_mr_reoffered_n + 1))
                    continue
                fi
                _mr_fs_verdict="same repository, selectable, recorded in THIS directory by a DIFFERENT session"
                [[ -n "$_mr_owner_unchecked" ]] && _mr_fs_verdict="same repository, selectable, recorded in THIS directory; ownership could NOT be checked, not restored"
                _mr_append_row 3 "$_mr_mtime" "$_mr_fs_verdict" "$_mr_l4" "$_mr_l2" "$_mr_fcwd" "$_mr_key"
                _mr_same_n=$((_mr_same_n + 1))
                _mr_fsession_n=$((_mr_fsession_n + 1))
                continue
            fi
            _mr_scope_cached "$_mr_fcwd"; _mr_fscope="$_MR_SCOPE_OUT"
          
          
          
          
          
          
          
            scope_compare "$_mr_scope" "$_mr_fscope"
            _mr_prio="$SCOPE_PRIO"
            case "$SCOPE_CLASS" in
                selfunver)
                  
                  
                  
                  
                  
                  
                  
                  
                  
                  
                  
                  
                    _mr_verdict="own scope unresolvable, withheld"
                    _mr_selfunver_n=$((_mr_selfunver_n + 1))
                    ;;
                unver)
                  
                  
                  
                  
                  
                  
                  
                    _mr_verdict="scope unverifiable, recorded path unreachable"
                    _mr_unver_n=$((_mr_unver_n + 1))
                    ;;
                same)
                  
                  
                  
                  
                  
                  
                    if _mr_was_offered "$_mr_okey"; then
                        _mr_reoffered_n=$((_mr_reoffered_n + 1))
                        continue
                    fi
                    _mr_verdict="same repository, selectable"
                    _mr_same_n=$((_mr_same_n + 1))
                    ;;
                foreign)
                    _mr_verdict="different repository, counted only"
                    _mr_foreign_n=$((_mr_foreign_n + 1))
                    ;;
                outside)
                  
                  
                  
                  
                    _mr_verdict="outside this session's scope, counted only"
                    _mr_outside_n=$((_mr_outside_n + 1))
                    ;;
                *)
                  
                  
                  
                  
                  
                  
                    _mr_verdict="own scope unresolvable, withheld"
                    _mr_selfunver_n=$((_mr_selfunver_n + 1))
                    _mr_prio=6
                    ;;
            esac
            _mr_append_row "$_mr_prio" "$_mr_mtime" "$_mr_verdict" "$_mr_l4" "$_mr_l2" "$_mr_fcwd" "$_mr_key"
        else
            _mr_stale_kept_n=$((_mr_stale_kept_n + 1))
        fi
        continue
    fi

  
  
  
  
  
  
    if [[ "$_mr_measured" -eq 0 ]]; then
        _mr_append_row 4 "$_mr_mtime" "MATCHED but its age could NOT be established, not restored, still on disk" "$_mr_l4" "$_mr_l2" "$_mr_fcwd" "$_mr_key"
        _mr_unmeasured_n=$((_mr_unmeasured_n + 1))
        continue
    fi

  
  
  
  
  
    _mr_claim="${PLANS_DIR}/.mr-claimed.$$.${_mr_key}"
    if ! mv "$_mr_f" "$_mr_claim" 2>/dev/null; then
        if [[ -e "$_mr_f" ]]; then
          
          
          
          
          
            echo "Warning: cannot claim memory-restore flag: $_mr_f" >&2
            _mr_append_row 4 "$_mr_mtime" "MATCHED but could NOT be claimed (filesystem error), not restored, still on disk" "$_mr_l4" "$_mr_l2" "$_mr_fcwd" "$_mr_key"
            _mr_unclaimed_n=$((_mr_unclaimed_n + 1))
        else
          
          
            _mr_lostrace_n=$((_mr_lostrace_n + 1))
        fi
        continue
    fi
    if [[ "$_mr_age" -le 86400 ]]; then
        _mr_append_row 1 "$_mr_mtime" "MATCHES this session" "$_mr_l4" "$_mr_l2" "$_mr_fcwd" "$_mr_key"
        _mr_match_n=$((_mr_match_n + 1))
    else
      
      
      
        _mr_append_row 2 "$_mr_mtime" "MATCHED but expired, consumed WITHOUT restoring (its memory is still in the backends)" "$_mr_l4" "$_mr_l2" "$_mr_fcwd" "$_mr_key"
        _mr_stale_gone_n=$((_mr_stale_gone_n + 1))
    fi
  
  
  
    rm -f "$_mr_claim" 2>/dev/null || _mr_unconsumed_n=$((_mr_unconsumed_n + 1))
done

find "$PLANS_DIR" -name '.mr-offered-*' -mtime +7 -delete 2>/dev/null || true
# Litter sweep: a hook killed between claim and rm, or a crashed writer, can strand
# .mr-claimed.* / .mr-tmp.* files. A claim file is the ORIGINAL flag, moved rather
# than rewritten, so it still holds a label and a recorded path — but it sits outside
# the .pending-memory-restore-* scan glob, so no later run mentions it, and deleting
# it silently destroys a checkpoint pointer with no trace anywhere. Both outcomes are
# counted and reported. Positive-staleness only: an age nobody established never
# reaches the seven-day test, the same rule the flag scan above now applies.
for _mr_litter in "${PLANS_DIR}"/.mr-claimed.* "${PLANS_DIR}"/.mr-tmp.*; do
  
  
    [[ -e "$_mr_litter" || -L "$_mr_litter" ]] || continue
  
  
  
  
  
  
  
    if [[ -L "$_mr_litter" || ! -f "$_mr_litter" ]]; then
        _mr_litter_unmeasured_n=$((_mr_litter_unmeasured_n + 1))
        continue
    fi
  
  
    _mr_is_claim=0
    [[ "${_mr_litter##*/}" == .mr-claimed.* ]] && _mr_is_claim=1
  
  
  
  
  
  
  
  
  
    mtime_of "$_mr_litter"; _mr_lm="$_MTIME_OUT"
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
    _mr_lmeasured=0
    _mr_lage=0
    if [[ "$_mr_lm" =~ ^[0-9]+$ ]]; then
        if [[ "$_mr_now" -ge "$_mr_lm" ]]; then
            _mr_lmeasured=1
            _mr_lage=$((_mr_now - _mr_lm))
        elif [[ $((_mr_lm - _mr_now)) -le "$_MR_CLOCK_AHEAD_S" ]]; then
            _mr_lmeasured=1
        fi
    fi
  
  
  
  
  
  
  
  
    if [[ "$_mr_lmeasured" -eq 0 ]]; then
        _mr_litter_unmeasured_n=$((_mr_litter_unmeasured_n + 1))
        continue
    fi
  
  
  
  
  
  
  
  
    _mr_has_body=0
    [[ "$_mr_is_claim" -eq 0 && -s "$_mr_litter" ]] && _mr_has_body=1
    if [[ "$_mr_lage" -gt 604800 ]]; then
      
      
      
        if rm -f "$_mr_litter" 2>/dev/null; then
            if [[ "$_mr_is_claim" -eq 1 ]]; then
                _mr_claimed_gone_n=$((_mr_claimed_gone_n + 1))
            elif [[ "$_mr_has_body" -eq 1 ]]; then
                _mr_tmp_body_gone_n=$((_mr_tmp_body_gone_n + 1))
            else
                _mr_tmp_gone_n=$((_mr_tmp_gone_n + 1))
            fi
        else
            _mr_litter_stuck_n=$((_mr_litter_stuck_n + 1))
        fi
        continue
    fi
  
  
  
  
  
  
    [[ "$_mr_lage" -lt 60 ]] && continue
    if [[ "$_mr_is_claim" -eq 1 ]]; then
        _mr_claimed_kept_n=$((_mr_claimed_kept_n + 1))
    elif [[ "$_mr_has_body" -eq 1 ]]; then
        _mr_tmp_body_kept_n=$((_mr_tmp_body_kept_n + 1))
    else
        _mr_tmp_n=$((_mr_tmp_n + 1))
    fi
done
fi
# The fallback sentence is assembled BEFORE the branch that prints it, so the test is
# "is there anything to say" rather than a list of counter names repeated in two
# places. That list had grown to thirteen, and every counter added to this file had to
# be written into both — miss the condition and a scan that found something reports
# nothing at all, which is the silence this whole path exists to remove.
_mr_fallback_note=""
    [[ "$_mr_stale_kept_n" -gt 0 ]] && _mr_fallback_note+="; ${_mr_stale_kept_n} older than 24h, left in place"
    [[ "$_mr_reoffered_n" -gt 0 ]] && _mr_fallback_note+="; ${_mr_reoffered_n} already offered to this session at an earlier /clear and NOT relisted, still in \`${_mr_plans_shown}\`"
    [[ "$_mr_offered_usable" -eq 0 ]] && _mr_fallback_note+="; the already-offered record \`.mr-offered-*\` in \`${_mr_plans_shown}\` is a link or shares an inode, so it was NOT read or written and candidates will repeat until you remove it"
    [[ "$_mr_swept_n" -gt 0 ]] && _mr_fallback_note+="; ${_mr_swept_n} removed as older than 7 days"
    [[ "$_mr_unreadable_n" -gt 0 ]] && _mr_fallback_note+="; ${_mr_unreadable_n} could NOT be read (permissions)"
    [[ "$_mr_unopenable_n" -gt 0 ]] && _mr_fallback_note+="; ${_mr_unopenable_n} matched the flag name but could NOT be opened"
    [[ "$_mr_notplain_n" -gt 0 ]] && _mr_fallback_note+="; ${_mr_notplain_n} carried the flag name but are a link or share an inode and were NOT read"
    [[ "$_mr_claimed_gone_n" -gt 0 ]] && _mr_fallback_note+="; ${_mr_claimed_gone_n} stranded claim file(s) removed, whatever pointer they held is gone"
    [[ "$_mr_claimed_kept_n" -gt 0 ]] && _mr_fallback_note+="; ${_mr_claimed_kept_n} stranded claim file(s) in \`${_mr_plans_shown}\` should still hold a checkpoint pointer no scan reads — look at \`.mr-claimed.*\` there if a checkpoint seems missing"
    [[ "$_mr_tmp_n" -gt 0 ]] && _mr_fallback_note+="; ${_mr_tmp_n} interrupted flag write(s) (\`.mr-tmp.*\`) left in \`${_mr_plans_shown}\` — verified empty, so they hold no checkpoint and can be deleted"
    [[ "$_mr_tmp_gone_n" -gt 0 ]] && _mr_fallback_note+="; ${_mr_tmp_gone_n} interrupted flag write(s) removed as older than 7 days were verified empty, so nothing was lost with them"
    [[ "$_mr_tmp_body_kept_n" -gt 0 ]] && _mr_fallback_note+="; ${_mr_tmp_body_kept_n} interrupted flag write(s) in \`${_mr_plans_shown}\` are NOT empty, so they may hold a checkpoint body no scan reads — look at \`.mr-tmp.*\` there before deleting anything"
    [[ "$_mr_tmp_body_gone_n" -gt 0 ]] && _mr_fallback_note+="; ${_mr_tmp_body_gone_n} interrupted flag write(s) (\`.mr-tmp.*\`) removed as older than 7 days were NOT empty, so whatever they held is gone"
    [[ "$_mr_litter_stuck_n" -gt 0 ]] && _mr_fallback_note+="; ${_mr_litter_stuck_n} litter file(s) could NOT be removed from \`${_mr_plans_shown}\` — check its permissions"
    [[ "$_mr_litter_unmeasured_n" -gt 0 ]] && _mr_fallback_note+="; ${_mr_litter_unmeasured_n} litter file(s) in \`${_mr_plans_shown}\` have an age this hook could NOT establish, so none of them was swept or classified — inspect them by hand"
    [[ "$_mr_lostrace_n" -gt 0 ]] && _mr_fallback_note+="; ${_mr_lostrace_n} claimed concurrently by another session"
    [[ "$_mr_unconsumed_n" -gt 0 ]] && _mr_fallback_note+="; ${_mr_unconsumed_n} flag(s) this hook claimed but could NOT delete, so they survive as \`.mr-claimed.*\` in \`${_mr_plans_shown}\` and are listed among the litter above"

if [[ -n "$_mr_rows" ]]; then
  
  
  
    _mr_sort_rows
  
  
  
  
  
  
  
    _mr_relists_every_match=0
    [[ "$_mr_match_n" -ge 2 ]] && _mr_relists_every_match=1
    _mr_block="Checkpoint candidates seen at this /clear (scope: ${_mr_scope_shown}):"
    _mr_shown=0
    _mr_over=0
    _mr_same_shown_n=0
    _mr_same_keyed_shown_n=0
  
  
  
  
  
  
  
  
  
  
    _mr_same_pos=""
    _mr_pos_n=0
    while IFS=$'\037' read -r _mr_pp _ _mr_pv _; do
        [[ -n "$_mr_pp" ]] || continue
        [[ "$_mr_pp" == "6" ]] && continue
        _mr_pos_n=$((_mr_pos_n + 1))
        if [[ "$_mr_pv" == "same repository, selectable"* ]]; then
            _mr_same_pos=$_mr_pos_n
            break
        fi
    done <<< "$_mr_rows"
    _mr_reserve=0
    [[ "$_mr_same_pos" =~ ^[0-9]+$ ]] && [[ "$_mr_same_pos" -gt 5 ]] && _mr_reserve=1
    _mr_cap=$((5 - _mr_reserve))
    while IFS=$'\037' read -r _mr_prio_r _mr_m _mr_v _mr_l _mr_t _mr_p _mr_k; do
      
      
      
      
      
      
        [[ -n "$_mr_prio_r" ]] || continue
      
      
      
      
      
      
      
      
      
      
        if [[ "$_mr_prio_r" == "6" ]]; then
            continue
        fi
      
      
      
      
        _mr_is_same=0
        [[ "$_mr_v" == "same repository, selectable"* ]] && _mr_is_same=1
      
        _mr_take_reserved=0
        [[ "$_mr_reserve" -eq 1 && "$_mr_same_shown_n" -eq 0 && "$_mr_is_same" -eq 1 ]] && _mr_take_reserved=1
        if [[ "$_mr_take_reserved" -eq 0 && "$_mr_shown" -ge "$_mr_cap" ]]; then
          
          
          
          
            if [[ "$_mr_v" == "MATCHES this session" && "$_mr_relists_every_match" -eq 1 ]]; then
                _mr_match_relisted_n=$((_mr_match_relisted_n + 1))
                continue
            fi
            _mr_over=$((_mr_over + 1))
          
          
          
            { [[ "$_mr_v" == "MATCHED but expired"* ]] || [[ "$_mr_v" == "REMOVED as older than 7 days"* ]]; } \
                && _mr_gone_hidden_n=$((_mr_gone_hidden_n + 1))
          
          
            [[ "$_mr_is_same" -eq 1 ]] && _mr_same_hidden_n=$((_mr_same_hidden_n + 1))
            continue
        fi
      
      
        _mr_age_text="age unknown"
      
      
      
        if [[ "$_mr_m" =~ ^[0-9]+$ ]] && [[ "$_mr_now" =~ ^[0-9]+$ ]]; then
            if [[ "$_mr_now" -ge "$_mr_m" ]]; then
                _mr_secs=$((_mr_now - _mr_m))
            elif [[ $((_mr_m - _mr_now)) -le "$_MR_CLOCK_AHEAD_S" ]]; then
                _mr_secs=0
            else
                _mr_secs=-1
            fi
        else
            _mr_secs=-1
        fi
        if [[ "$_mr_secs" -ge 0 ]]; then
            if [[ "$_mr_secs" -lt 3600 ]]; then _mr_age_text="$((_mr_secs / 60))m ago"
            elif [[ "$_mr_secs" -lt 86400 ]]; then _mr_age_text="$((_mr_secs / 3600))h ago"
            else _mr_age_text="$((_mr_secs / 86400))d ago"; fi
        fi
        _mr_block+="\n- ${_mr_l:-(no label)} — recorded ${_mr_p:-(unknown path)} — ${_mr_age_text} — ${_mr_v}"
      
      
      
      
      
      
      
      
      
        [[ -n "$_mr_k" ]] && { [[ "$_mr_is_same" -eq 1 ]] || [[ "$_mr_v" == "malformed flag"* ]]; } \
            && _mr_block+=" — flag ${_mr_k}"
        [[ "$_mr_v" == "scope unverifiable"* ]] && _mr_unver_shown_n=$((_mr_unver_shown_n + 1))
        [[ "$_mr_v" == "malformed flag"* ]] && _mr_malformed_shown_n=$((_mr_malformed_shown_n + 1))
        if [[ "$_mr_is_same" -eq 1 ]]; then
            _mr_same_shown_n=$((_mr_same_shown_n + 1))
            [[ -n "$_mr_k" ]] && _mr_same_keyed_shown_n=$((_mr_same_keyed_shown_n + 1))
            [[ -n "$_mr_k" ]] && _mr_offered_new+="${_mr_k}"$'\n'
        fi
        _mr_shown=$((_mr_shown + 1))
    done <<< "$_mr_rows"
    if [[ -n "$_mr_offered_new" && "$_mr_offered_usable" -eq 1 ]]; then
        printf '%s' "$_mr_offered_new" >> "$_MR_OFFERED_FILE" 2>/dev/null || true
    fi
    _mr_tail=""
  
  
  
  
  
    if [[ "$_mr_over" -gt 0 ]]; then
        _mr_over_text=" ${_mr_over} more not shown"
        [[ "$_mr_gone_hidden_n" -gt 0 ]] && _mr_over_text+=", ${_mr_gone_hidden_n} of them destroyed pointers"
        [[ "$_mr_same_hidden_n" -gt 0 ]] && _mr_over_text+=", ${_mr_same_hidden_n} of them selectable"
        _mr_tail+="${_mr_over_text};"
    fi
    [[ "$_mr_match_relisted_n" -gt 0 ]] && _mr_tail+=" ${_mr_match_relisted_n} further matched flag(s) listed in full below;"
    [[ "$_mr_foreign_n" -gt 0 ]] && _mr_tail+=" ${_mr_foreign_n} recorded in another repository (path and label withheld);"
    [[ "$_mr_selfunver_n" -gt 0 ]] && _mr_tail+=" ${_mr_selfunver_n} left unclassified because this session's own directory could not be resolved (path and label withheld);"
    [[ "$_mr_outside_n" -gt 0 ]] && _mr_tail+=" ${_mr_outside_n} recorded outside this scope, in a directory inside no repository (path and label withheld);"
    [[ "$_mr_stale_kept_n" -gt 0 ]] && _mr_tail+=" ${_mr_stale_kept_n} older than 24h, left in place;"
    [[ "$_mr_reoffered_n" -gt 0 ]] && _mr_tail+=" ${_mr_reoffered_n} already offered to this session at an earlier /clear and NOT relisted;"
    [[ "$_mr_offered_usable" -eq 0 ]] && _mr_tail+=" the already-offered record \`.mr-offered-*\` is a link or shares an inode, so it was NOT read or written and candidates will repeat until you remove it;"
  
  
  
    [[ "$_mr_swept_n" -gt 0 ]] && _mr_tail+=" ${_mr_swept_n} removed as older than 7 days;"
    [[ "$_mr_unreadable_n" -gt 0 ]] && _mr_tail+=" ${_mr_unreadable_n} could NOT be read (permissions);"
    [[ "$_mr_unopenable_n" -gt 0 ]] && _mr_tail+=" ${_mr_unopenable_n} matched the flag name but could NOT be opened;"
    [[ "$_mr_notplain_n" -gt 0 ]] && _mr_tail+=" ${_mr_notplain_n} carried the flag name but are a link or share an inode and were NOT read;"
    [[ "$_mr_lostrace_n" -gt 0 ]] && _mr_tail+=" ${_mr_lostrace_n} claimed concurrently by another session;"
    [[ "$_mr_claimed_gone_n" -gt 0 ]] && _mr_tail+=" ${_mr_claimed_gone_n} stranded claim file(s) removed, whatever pointer they held is gone;"
    [[ "$_mr_claimed_kept_n" -gt 0 ]] && _mr_tail+=" ${_mr_claimed_kept_n} stranded claim file(s) should still hold a checkpoint pointer no scan reads;"
    [[ "$_mr_tmp_n" -gt 0 ]] && _mr_tail+=" ${_mr_tmp_n} interrupted flag write(s) left in place, verified empty;"
    [[ "$_mr_tmp_gone_n" -gt 0 ]] && _mr_tail+=" ${_mr_tmp_gone_n} interrupted flag write(s) removed, verified empty, nothing lost;"
    [[ "$_mr_tmp_body_kept_n" -gt 0 ]] && _mr_tail+=" ${_mr_tmp_body_kept_n} interrupted flag write(s) left in place are NOT empty;"
    [[ "$_mr_tmp_body_gone_n" -gt 0 ]] && _mr_tail+=" ${_mr_tmp_body_gone_n} interrupted flag write(s) removed were NOT empty;"
    [[ "$_mr_litter_stuck_n" -gt 0 ]] && _mr_tail+=" ${_mr_litter_stuck_n} litter file(s) could NOT be removed;"
    [[ "$_mr_litter_unmeasured_n" -gt 0 ]] && _mr_tail+=" ${_mr_litter_unmeasured_n} litter file(s) whose age could NOT be established;"
    [[ -n "$_mr_tail" ]] && _mr_block+="\n-${_mr_tail%;}"

  
  
  
  
    [[ "$_mr_match_n" -gt 0 || "$_mr_same_n" -gt 0 || "$_mr_reoffered_n" -gt 0 ]] && MR_ACTIONABLE="yes"
  
  
  
  
    _mr_same_keyed_n=$_mr_same_keyed_shown_n
  
  
  
  
    _mr_match_rows=""
    while IFS= read -r _mr_row; do
        [[ -n "$_mr_row" ]] || continue
        _mr_rest=${_mr_row#*$'\037'}
        _mr_rest=${_mr_rest#*$'\037'}
        [[ "${_mr_rest%%$'\037'*}" == "MATCHES this session" ]] && _mr_match_rows+="${_mr_row}"$'\n'
    done <<< "$_mr_rows"
  
  
  
    IFS=$'\037' read -r _ _ _ _mr_newest_label _ <<< "$_mr_match_rows"
  
  
  
  
  
    _mr_notes=""
    if [[ "$_mr_stale_gone_n" -gt 0 ]]; then
        _mr_notes+="\n\n${_mr_stale_gone_n} flag(s) DID match this session but were past the 24-hour window, so they were consumed WITHOUT restoring. Their checkpoint memory is still in the backends — restore one by hand if the work thread is still live."
        if [[ "$_mr_gone_hidden_n" -gt 0 ]]; then
            _mr_notes+=" ${_mr_gone_hidden_n} of them could not be shown above (row cap), so those labels are GONE — say so rather than implying the list is complete."
        else
            _mr_notes+=" Their labels are in the list above."
        fi
    fi
    [[ "$_mr_unmeasured_n" -gt 0 ]] && _mr_notes+="\n\n${_mr_unmeasured_n} flag(s) matched this session but their age could NOT be established, so nothing was restored and they are still on disk. \`stat\` gave no usable answer for them; an old checkpoint restored as a current one would be worse than none, so the decision is left to you."
    [[ "$_mr_unconsumed_n" -gt 0 ]] && _mr_notes+="\n\n${_mr_unconsumed_n} flag(s) were claimed by this hook but it could NOT delete the claim, so they survive as \`.mr-claimed.*\` in \`${_mr_plans_shown}\` even where a row above says the flag was consumed or swept. Check the permissions on that directory."
    [[ "$_mr_unclaimed_n" -gt 0 ]] && _mr_notes+="\n\n${_mr_unclaimed_n} flag(s) matched this session but could NOT be claimed because of a filesystem error, so nothing was restored and they are still on disk. Check the permissions on \`${_mr_plans_shown}\` — until that is fixed, no checkpoint can be restored here."
    if [[ "$_mr_same_n" -gt 0 ]]; then
      
      
      
      
      
      
        if [[ "$_mr_relists_every_match" -eq 1 ]]; then
            _mr_notes+="\n\nRows marked \`same repository, selectable\` belong to this repository and were NOT consumed. They are NOT in the numbered list above: add them to the SAME AskUserQuestion as further options, clearly separated from the matched ones, rather than asking a second question."
        else
            _mr_notes+="\n\nRows marked \`same repository, selectable\` belong to this repository and were NOT consumed. Use AskUserQuestion to ask whether to restore one of them (offer those rows only, plus a \"none\" option)."
        fi
        [[ "$_mr_same_hidden_n" -gt 0 ]] && _mr_notes+="\n${_mr_same_hidden_n} further selectable row(s) could NOT be shown above (row cap). Offer only the ones listed; say the rest exist rather than implying the list is complete."
        if [[ "$_mr_same_keyed_n" -eq 0 ]]; then
            _mr_notes+="\nNone of those rows carries a usable flag key, so do not attempt to delete one; report that and continue."
        else
          
          
          
          
          
            _mr_notes+="\nIf one is chosen: restore it (Serena list_memories()/read_memory(), Basic-Memory recent notes), then delete its flag with \`rm -f ${_mr_plans_shown}/.pending-memory-restore-«flag»\` — the hook did not consume it, so it is still there — but THIS session will not list it again, so act on it now or note the flag name. A later session in this directory gets its own first offer."
        fi
    fi
  
  
  
    [[ "$_mr_selfunver_n" -gt 0 ]] && _mr_notes+="\nThis session's own directory could not be resolved to a repository, so no flag could be checked against it and none is shown: withholding is not a claim that they belong elsewhere. They are untouched in \`${_mr_plans_shown}\`; read them there if you need one."
    [[ "$_mr_outside_n" -gt 0 ]] && _mr_notes+="\nFlags \`recorded outside this scope\` were resolved, and at least one side is a directory inside no repository, so the only established fact is that the scopes differ — not that they belong to another project. Their paths and labels are withheld on the same rule; they are untouched in \`${_mr_plans_shown}\`."
    [[ "$_mr_foreign_n" -gt 0 ]] && _mr_notes+="\nThe count of flags \`recorded in another repository\` is deliberately all you get: their paths and labels belong to those projects and are withheld from this session. Do not go looking for them."
    [[ "$_mr_malformed_shown_n" -gt 0 ]] && _mr_notes+="\nRows marked \`malformed flag, no recorded path\` are corrupt or truncated flag files, not checkpoints. Nothing can be restored from them; mention them so the user can delete them."
    [[ "$_mr_unver_shown_n" -gt 0 ]] && _mr_notes+="\nRows marked \`scope unverifiable, recorded path unreachable\` were NOT checked — the recorded path could not be resolved. A worktree that has since been removed is the usual reason, but a directory that still exists and cannot be entered, or a repository git declined to resolve, reaches this row too, so the cause is not established. Do not assert which repository they belong to. Show the recorded path and let the user decide."

    if [[ "$_mr_match_n" -eq 0 ]]; then
      
      
        MR_DIRECTIVE="${_mr_block}\n\n**CHECKPOINT CANDIDATES - nothing was restored:**"
      
      
      
      
      
      
      
      
      
      
      
      
      
      
      
      
      
      
      
      
      
      
      
      
        _mr_bearing_n=$(( _mr_seen_n + _mr_unopenable_n + _mr_lostrace_n + _mr_notplain_n \
                        - _mr_stale_kept_n - _mr_match_n \
                        - _mr_same_n - _mr_foreign_n - _mr_outside_n \
                        + _mr_fsession_n ))
        if [[ "$_mr_bearing_n" -eq 0 ]]; then
            MR_DIRECTIVE+="\n\nNo checkpoint flag recorded this session's working directory, so NOTHING was restored and no flag was consumed."
        fi
        [[ "$_mr_same_n" -eq 0 && "$_mr_mine_n" -eq 0 && "$_mr_reoffered_n" -eq 0 ]] && MR_DIRECTIVE+="\nNo row was verified as belonging to this repository, so there is nothing to offer automatically. Say so in one line and continue with the user's request."
        MR_DIRECTIVE+="$_mr_notes"
    elif [[ "$_mr_relists_every_match" -eq 0 ]]; then
        MR_LABEL="$_mr_newest_label"
        MR_DIRECTIVE="${_mr_block}\n\n**ACTION REQUIRED - MEMORY RESTORE"
        [[ -n "$MR_LABEL" ]] && MR_DIRECTIVE+=" (checkpoint: ${MR_LABEL})"
        MR_DIRECTIVE+=":**"
        MR_DIRECTIVE+="\n\nA /smith-checkpoint saved durable session state before this /clear. Restore it before responding:"
        MR_DIRECTIVE+="\n1. If Serena MCP available: list_memories() then read_memory() for the checkpoint"
        [[ -n "$MR_LABEL" ]] && MR_DIRECTIVE+=" (\`${MR_LABEL}\`)"
        MR_DIRECTIVE+=" or the most recent session memory"
        MR_DIRECTIVE+="\n2. If Basic-Memory MCP available: search recent notes for the checkpoint"
        MR_DIRECTIVE+="\n3. Report the restored context and continue the work thread"
        MR_DIRECTIVE+="\n\nDo NOT skip this. Do NOT respond with \"Ready for your next task.\""
        MR_DIRECTIVE+="\nIf the user's message contains a different request, address it first but still restore context."
        MR_DIRECTIVE+="$_mr_notes"
    else
        MR_DIRECTIVE="${_mr_block}\n\n**ACTION REQUIRED - MEMORY RESTORE (${_mr_match_n} checkpoints for this directory):**"
        MR_DIRECTIVE+="\n\nMultiple /smith-checkpoint flags were saved for this directory (parallel sessions). Candidates, newest first (label — saved at):"
        while IFS=$'\037' read -r _mr_pr _ _ _mr_l _mr_t _ _; do
          
          
          
          
          
            [[ -n "$_mr_pr" ]] || continue
            MR_DIRECTIVE+="\n- ${_mr_l:-(no label)} — ${_mr_t:-unknown time}"
        done <<< "$_mr_match_rows"
        MR_DIRECTIVE+="\n\nBEFORE doing anything else, use AskUserQuestion to ask which checkpoint to restore."
        MR_DIRECTIVE+="\nIf unable to ask (headless/non-interactive), restore the newest (\`${_mr_newest_label:-(no label)}\`) and say so explicitly."
        MR_DIRECTIVE+="\nThen restore it: Serena list_memories()/read_memory() and Basic-Memory recent notes."
        MR_DIRECTIVE+="\nDo NOT skip this. Do NOT respond with \"Ready for your next task.\""
        MR_DIRECTIVE+="$_mr_notes"
    fi
elif [[ -z "$_mr_cwd" ]]; then
  
  
  
  
  
  
    MR_DIRECTIVE="Checkpoint flags at this /clear: this session's working directory could not be determined, so NO flag was scanned, none was consumed and nothing was restored. Every checkpoint pointer is still in \`${_mr_plans_shown}\`. This is not the same as having no checkpoints."
elif [[ -n "$_mr_dir_unreadable" ]]; then
    MR_DIRECTIVE="Checkpoint flags at this /clear: \`${_mr_plans_shown}\` could NOT be inspected — it, or a directory above it, denied access — so no flag was scanned and nothing was restored. This is not the same as having no checkpoints. Check the permissions on that path before relying on /clear restore here."
elif [[ -n "$_mr_fallback_note" ]]; then
  
  
  
    MR_DIRECTIVE="Checkpoint flags at this /clear (scope: ${_mr_scope_shown}): nothing offered${_mr_fallback_note}. Nothing was restored."
fi

# Only auto-load plan if a flag file exists (explicit reload intent from
# enforce-clear or on-plan-exit). The state file alone is informational —
# it records which plan was active but does NOT mean the user wants to resume.
# Without this gate, every /clear for 24 hours forces plan resume, even when
# the user wants to work on something else.
if [[ -n "$PLAN_FILE" ]] && [[ ! -f "$FLAG_FILE" ]]; then
    PLAN_FILE=""
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
  
  
  
    mtime_of "$STATE_FILE"
    _state_mtime="$_MTIME_OUT"
    _state_age="?"
  
  
  
  
  
    _state_now=$(date +%s 2>/dev/null)
    if [[ "$_state_mtime" =~ ^[0-9]+$ ]] && [[ "$_state_now" =~ ^[0-9]+$ ]]; then
        _state_age=$(( (_state_now - _state_mtime) / 60 ))
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


# No plan found — output state data for SKILL.md to interpret
if [[ -z "$PLAN_FILE" ]]; then
  
    AVAILABLE_PLANS=""
    PLAN_COUNT=0
    if [[ -d "$PLANS_DIR" ]]; then
        while IFS= read -r f; do
            classify_plan_scope "$f" "$STATE_BASENAME" "$OWN_SCOPE" || continue
            AVAILABLE_PLANS+="\n  - \`$(basename "$f")\` (\`$f\`)"
            PLAN_COUNT=$((PLAN_COUNT + 1))
            [[ $PLAN_COUNT -ge 5 ]] && break
        done < <(ls -t "$PLANS_DIR"/*.md 2>/dev/null)
    fi

  
    if [[ -n "$FLAG_TYPE" ]] || [[ -n "$MR_ACTIONABLE" ]]; then
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

  
  
  
    [[ -n "$MR_DIRECTIVE" ]] && STATE_OUTPUT="${MR_DIRECTIVE}\n\n${STATE_OUTPUT}"

    rm -f "$FLAG_FILE" 2>/dev/null
    json_session_start_output "$(printf '%b' "$STATE_OUTPUT")"
    exit 0
fi

# Read plan content fresh from disk
if ! PLAN_CONTENT=$(cat "$PLAN_FILE" 2>/dev/null); then
  
    STATE_OUTPUT="**State check (session-keyed):**"
    STATE_OUTPUT+="\n${STATE_META_STATE}"
    STATE_OUTPUT+="\n${STATE_META_FLAG}"
    STATE_OUTPUT+="\n- Flag type: ${FLAG_TYPE:-plan-pending}"
    STATE_OUTPUT+="\n- Signal: resume"
    STATE_OUTPUT+="\n- Plan file: \`${PLAN_FILE}\` (unreadable)"
    STATE_OUTPUT+="\n- Plans directory: \`${PLANS_DIR}\`"
    [[ -n "$MR_DIRECTIVE" ]] && STATE_OUTPUT="${MR_DIRECTIVE}\n\n${STATE_OUTPUT}"
    rm -f "$FLAG_FILE" 2>/dev/null
    json_session_start_output "$(printf '%b' "$STATE_OUTPUT")"
    exit 0
fi
PLAN_BASENAME=$(basename "$PLAN_FILE")

mtime_human "$PLAN_FILE"
PLAN_MODIFIED="$_MTIME_HUMAN"

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


# Prepend the checkpoint memory-restore directive so it leads even when a plan also
# reloaded. Set whether or not anything was consumed — a report is a directive too.
[[ -n "$MR_DIRECTIVE" ]] && FULL_CONTENT=$(printf '%b\n\n%s' "$MR_DIRECTIVE" "$FULL_CONTENT")

# Clean up the pending-reload flag if it exists (SessionStart:clear handles it now)
rm -f "$FLAG_FILE" 2>/dev/null

json_session_start_output "$FULL_CONTENT"

exit 0
