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
_mr_scope=""       # this session's repository main tree, for the same-repo verdict
# Two stale populations that must NOT share a counter: one is left on disk for its
# own session, the other MATCHED this session and was therefore consumed — destroyed
# without restoring anything. Reporting the second as an ordinary old flag would
# recreate the exact invisible outcome this contract exists to remove.
_mr_seen_n=0       # flag files this scan actually opened
_mr_stale_kept_n=0 # non-matching flags past the 24h window, left where they are
_mr_stale_gone_n=0 # matching flags past the 24h window, consumed without restoring
_mr_swept_n=0      # flags removed by the >7-day hygiene sweep
_mr_match_n=0      # fresh flags matching this session
# Flags that matched this session's directory, counted BEFORE a verdict is chosen and
# whatever the verdict turns out to be. The "nothing belongs to this repository"
# sentence was gated on the priority-3 counter alone, so it fired beside rows at
# priority 2 and 4 -- expired, unmeasured, unclaimable -- every one of which had
# matched this directory exactly. Counting at the match itself rather than listing
# the verdicts is deliberate: a verdict added later is covered without being
# remembered, which is the same reason the bearing sum below subtracts rather than
# enumerates.
_mr_mine_n=0
_mr_same_n=0       # fresh flags in the same repository, offerable
_mr_unclaimed_n=0  # matching flags a filesystem error prevented this hook claiming
_mr_unmeasured_n=0 # matching flags whose age could NOT be established: never consumed
_mr_unconsumed_n=0 # flags this hook claimed but could NOT delete: they survive as .mr-claimed.*
_mr_unver_shown_n=0     # `scope unverifiable` rows the display actually printed
_mr_malformed_shown_n=0 # `malformed flag` rows the display actually printed
_mr_unver_n=0      # fresh flags whose recorded path could not be resolved at all
_mr_foreign_n=0    # fresh flags verified as belonging to another repository
_mr_selfunver_n=0  # fresh flags left unclassified: this session's own scope is unresolvable
_mr_outside_n=0    # fresh flags outside this scope where neither side is a repository
_mr_malformed_n=0  # fresh flags that record no path at all (truncated file)
_mr_unreadable_n=0 # flags this hook could not read (permissions)
_mr_unopenable_n=0 # names matching the flag glob that could not be opened at all
_mr_notplain_n=0   # flag names that are a link or share an inode: never read
_mr_lostrace_n=0   # flags a concurrent hook claimed first
_mr_gone_hidden_n=0 # destroyed-pointer rows the display cap could not show
_mr_same_hidden_n=0 # selectable rows the display cap could not show
_mr_match_relisted_n=0 # matched rows past the cap that the ask-which-one list repeats
# A claim file is a flag moved by `mv`, so what it holds is inherited, never verified here
# — and the flag loop does not itself assume a flag is complete: it carries a "malformed
# flag, no recorded path" verdict. Every sentence written about these two counters, at
# either report site, is therefore phrased as inherited-not-verified.
_mr_claimed_gone_n=0 # stranded claim files removed: each destroyed whatever pointer it held
_mr_claimed_kept_n=0 # stranded claim files left: each SHOULD hold a pointer no scan reads
_mr_tmp_n=0          # interrupted flag writes left in place, VERIFIED empty
_mr_tmp_gone_n=0     # interrupted flag writes removed, verified empty: nothing was lost
_mr_tmp_body_kept_n=0 # interrupted flag writes left in place that are NOT empty
_mr_tmp_body_gone_n=0 # interrupted flag writes removed that were NOT empty
_mr_litter_stuck_n=0 # litter this hook tried and FAILED to remove
_mr_litter_unmeasured_n=0 # litter with no established age: never swept, never classified
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
            # No separator left. `${d%/*}` returns a slashless string UNCHANGED, so
            # deriving the parent that way spins forever on a relative PLANS_DIR
            # whose first component is missing — reachable whenever CLAUDE_CONFIG_DIR
            # is relative. A relative path's remaining parent is the working
            # directory, and asking about it terminates.
            parent="."
        fi
        [[ -d "$parent" && -r "$parent" && -x "$parent" ]] && return 0
        [[ -e "$parent" ]] && return 1   # there, but not inspectable: cannot tell
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
        rest=${rest#*$'\037'}    # verdict
        rest=${rest#*$'\037'}    # label
        rest=${rest#*$'\037'}    # timestamp onwards
        t=${rest%%$'\037'*}
        # A non-numeric key would make the integer comparisons below evaluate the
        # field as a variable name. Sort such a row last rather than unpredictably.
        [[ "$p" =~ ^[0-9]+$ ]] || p=9
        [[ "$m" =~ ^[0-9]+$ ]] || m=0
        in_row+=("$row"); in_p+=("$p"); in_m+=("$m"); in_t+=("$t")
    done <<< "$_mr_rows"
    # Insert from the LAST row backwards, which makes the common case linear rather
    # than quadratic. The scan feeds rows in glob order, and a flag is named
    # `<timestamp>-<pid>` (write-reload-flag.sh), so that order is chronological
    # ASCENDING while the key here is mtime DESCENDING — inserting forwards puts
    # every row at the front and walks the whole sorted run each time. Measured on
    # one developer's machine, not reproducible from this repository: 140ms at 100
    # rows forwards, 2.0s at 400; backwards, 20ms and 55ms. The quadratic case still
    # exists — an input in mtime-DESCENDING order — and what keeps it away is NOT the
    # glob: the glob orders by NAME, and the sort key is mtime. It stays away only
    # while a flag's mtime still tracks its name, which holds because the writer names
    # each flag after its own timestamp and nothing rewrites mtimes afterwards. Two
    # things break that premise: a failed `stat` below leaves that row's mtime empty,
    # which line 328 maps to 0 — the SMALLEST key, so the row sorts last within its
    # priority rather than first — and outside this repository, a restore from backup
    # or a `cp -R` without `-p`. Backwards is therefore the better default, not a
    # guarantee. Do not "simplify" it to a forward scan.
    #
    # For scale: the per-flag scan costs about 16ms per flag, so at 300 flags it is
    # ~4.7s against at most ~1.8s for the sort. This loop is not the ceiling.
    k=${#in_row[@]}
    while [[ "$k" -gt 0 ]]; do
        k=$((k - 1))
        p=${in_p[$k]}; m=${in_m[$k]}; t=${in_t[$k]}; row=${in_row[$k]}
        i=${#a_row[@]}
        while [[ "$i" -gt 0 ]]; do
            j=$((i - 1))
            # Shift while the placed row is NOT strictly before the incoming one.
            # Equal keys shift too: going backwards, the incoming row is the EARLIER
            # one in input order, so it must end up ahead of its equals. That is what
            # keeps the sort stable in this direction.
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
    # The recorded path is how a person recognizes which checkpoint this is, so it
    # gets a longer bound than a label — a deep worktree path silently cut to 200
    # characters would read as a real path that simply is not the one on disk.
    _mr_clean "$6" 400;  path="$_MR_CLEAN"
    [[ "$key" =~ ^[0-9A-Za-z._-]+$ ]] || key=""
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
for _mr_f in "${PLANS_DIR}"/.pending-memory-restore-*; do
    if [[ ! -f "$_mr_f" ]]; then
        # The glob matched a name this hook cannot open as a file: a dangling
        # symlink, a directory sharing the flag prefix, an entry in a directory
        # without its search bit — or a flag a PARALLEL session's /clear consumed
        # between the glob expanding and this test, which is not a fault at all and
        # was previously reported as one. It is not the no-match case — the literal
        # glob pattern is filtered a line below — so it must not vanish.
        #
        # The name being gone is what separates the race from the rest. Testing the
        # directory's search bit here as well would be dead weight: without it every
        # entry tests as absent, but the scan never starts, because a `PLANS_DIR`
        # that is unreadable OR unsearchable sets `_mr_dir_unreadable` and this whole
        # loop is gated on that being empty. Stated so it is not re-added as a guard
        # against a case that cannot reach this line.
        if [[ "$_mr_f" != *'*'* ]]; then
            if [[ ! -e "$_mr_f" ]] && [[ ! -L "$_mr_f" ]]; then
                _mr_lostrace_n=$((_mr_lostrace_n + 1))
            else
                _mr_unopenable_n=$((_mr_unopenable_n + 1))
            fi
        fi
        continue
    fi
    # A flag name that is a LINK is not a flag. `-f` follows a symlink, so without
    # this test the loop reads lines 2-4 of whatever it points at, and lines 3 and 4
    # are printed in the row — a planted link to ~/.aws/credentials or an .ssh key
    # therefore reads that file into this session's context, and is re-read at every
    # /clear because a non-matching flag is never consumed. A HARD link reaches the
    # same disclosure while being neither `-L` nor irregular, so the link COUNT is
    # what closes it: write-reload-flag.sh creates each flag with mktemp and mv, so a
    # genuine flag has exactly one. The litter sweep below already refuses links for
    # the adjacent reason; this loop is the one that prints what it read.
    #
    # The `-L` test is a shell builtin and needs no `stat`, so the symlink case is
    # closed unconditionally. The link COUNT is not: an unmeasurable one is allowed
    # through rather than refused, because refusing it would mean a broken `stat`
    # hides every flag — the failure this branch spent several commits removing, and
    # the one tests 118 and 140 pin. The residual is narrow and stated rather than
    # papered over: while `stat` is unusable, a HARD link planted under a flag name
    # is still read. Refused entries are counted and reported, never dropped silently.
    # ORDER MATTERS, and selecting on the output is not enough on its own. GNU `-f`
    # means --file-system and succeeds on a regular file, where `%l` is the maximum
    # length of filenames — typically 255, a number, which satisfies the same guard
    # a real link count does and would refuse every genuine flag on Linux. `%m` is
    # safe to ask second only because GNU answers it with a mount point, which is
    # not numeric; `%l` has no such tell. So the GNU form is asked FIRST, and BSD,
    # which has no `-c` at all and writes nothing to stdout when handed one, falls
    # through to its own `-f %l`. https://man7.org/linux/man-pages/man1/stat.1.html
    _mr_nlink=$(stat -c %h "$_mr_f" 2>/dev/null)
    [[ "$_mr_nlink" =~ ^[0-9]+$ ]] || _mr_nlink=$(stat -f %l "$_mr_f" 2>/dev/null)
    if [[ -L "$_mr_f" ]] || { [[ "$_mr_nlink" =~ ^[0-9]+$ ]] && [[ "$_mr_nlink" -ne 1 ]]; }; then
        _mr_notplain_n=$((_mr_notplain_n + 1))
        continue
    fi
    _mr_seen_n=$((_mr_seen_n + 1))
    # An unreadable flag is NOT a malformed one. Without this check every line
    # reads as empty and the flag is reported as corrupt, with the directive
    # advising the user to delete a perfectly good pointer whose only problem is
    # a permission bit — and bash's redirection error escapes the 2>/dev/null.
    if [[ ! -r "$_mr_f" ]]; then
        _mr_unreadable_n=$((_mr_unreadable_n + 1))
        continue
    fi
    # Read the whole flag with builtins, once. Three `sed` invocations cost about
    # 29ms per flag here, and this hook runs on every /clear over a directory whose
    # entire problem is that flags accumulate. Pre-initialized so a truncated file
    # simply leaves the missing lines empty instead of reusing the previous flag's.
    # `IFS=` on every read, not just `-r`: a bare `read` into one variable strips
    # leading and trailing IFS whitespace, which `sed -n '3p'` did not. A directory
    # whose name ends in a space would stop matching its own hook cwd, and the
    # trimmed path would then fail to `cd`, so the row would assert "recorded path
    # unreachable" about the directory the hook is standing in.
    _mr_l1=""; _mr_l2=""; _mr_l3=""; _mr_l4=""
    { IFS= read -r _mr_l1; IFS= read -r _mr_l2; IFS= read -r _mr_l3; IFS= read -r _mr_l4; } < "$_mr_f" 2>/dev/null
    _mr_fcwd="$_mr_l3"
    _mr_key="${_mr_f##*/.pending-memory-restore-}"

    # ONE source of truth for age. Taking freshness from `find -mmin` and the age
    # shown in the row from `stat` is two shell-outs measuring the same mtime, free
    # to disagree: a failing `find` prints nothing, which reads as "fresh", so a
    # three-year-old flag is offered for restore while its own row reads `1323d ago`.
    # Deriving both from one number makes that contradiction unrepresentable.
    # An mtime that cannot be read establishes no age at all. Such a flag is reported
    # as matched-but-not-restored, is never consumed, and is never swept — keeping it
    # is what `find`'s silence was meant to achieve, without inventing a number.
    # Select the fallback on the OUTPUT, not on the exit status. On GNU coreutils
    # `-f` means --file-system, so `stat -f %m` SUCCEEDS on a file and prints
    # filesystem information, never an mtime — the `||` chain would then never reach
    # the `-c %Y` form and every flag on Linux would be stamped with the current
    # time: always fresh, never stale, never swept. This pattern was harmless while
    # freshness came from `find`; it became load-bearing when age moved here.
    mtime_of "$_mr_f"; _mr_mtime="$_MTIME_OUT"
    # Substituting `now` for a failed `stat` made an unestablished age read as zero,
    # which is "fresh" everywhere below. The empty mtime is deliberate: the display
    # already renders it as "age unknown" rather than inventing "0m ago", and the zero
    # age is what keeps the seven-day sweep off a flag whose age nobody measured.
    # It takes BOTH a usable clock and a usable mtime to have an age, and the same
    # bound the litter sweep uses applies here for the same reason. Clamping a negative
    # difference to zero used to make either failure read as "fresh": with `date` broken
    # `_mr_now` is 0 at :391, every real mtime is then in the future, and a flag from
    # years ago was announced as this session's and consumed. A mtime AHEAD by less than
    # the sampling window is the ordinary race — the clock is read once, before this
    # loop — and a just-written flag is genuinely fresh, so that case keeps an age of
    # zero. Anything further ahead establishes nothing.
    _mr_measured=1
    _mr_age=0
    if [[ ! "$_mr_mtime" =~ ^[0-9]+$ ]]; then
        _mr_measured=0
    elif [[ "$_mr_now" -ge "$_mr_mtime" ]]; then
        _mr_age=$((_mr_now - _mr_mtime))
    elif [[ $((_mr_mtime - _mr_now)) -gt "$_MR_CLOCK_AHEAD_S" ]]; then
        _mr_measured=0
    fi
    # An empty mtime is what makes the display say "age unknown" instead of inventing
    # "0m ago"; the row itself is still listed, guarded on its priority field.
    [[ "$_mr_measured" -eq 0 ]] && _mr_mtime=""

    _mr_is_match=""
    if [[ "$_mr_fcwd" == "$_mr_cwd" ]]; then
        _mr_is_match="yes"
    elif [[ -n "$_mr_cwd_phys" && -n "$_mr_fcwd" ]]; then
        # `--` for the same reason as in scope_key: this is the flag's own line 3,
        # and without it a recorded `-P` resolves to $HOME and matches whatever hook
        # happens to stand there.
        _mr_fphys=$(cd -- "$_mr_fcwd" 2>/dev/null && pwd -P) || _mr_fphys=""
        [[ -n "$_mr_fphys" && "$_mr_fphys" == "$_mr_cwd_phys" ]] && _mr_is_match="yes"
    fi
    [[ -n "$_mr_is_match" ]] && _mr_mine_n=$((_mr_mine_n + 1))
    if [[ -z "$_mr_is_match" ]]; then
        # Not ours to consume. Hygiene: past seven days it goes — but only when
        # THIS hook is the one that removed it. `rm -f` also succeeds on a file a
        # concurrent hook already deleted, and the count is the only audit trace
        # this path leaves behind, so claim it first exactly as the matched branch
        # does and let the loser of the race stay silent. That silence is the one
        # documented exception to the counted-not-passed-over rule at the top of this
        # file, and it is narrow: this flag is not this session's, so nothing the
        # reader could act on was lost. The matched branch counts its own lost race
        # precisely because a restore did not happen there.
        if [[ "$_mr_age" -gt 604800 ]]; then
            _mr_claim="${PLANS_DIR}/.mr-claimed.$$.${_mr_key}"
            if mv "$_mr_f" "$_mr_claim" 2>/dev/null; then
                # Counting the sweep without checking the `rm` asserted a removal that
                # may not have happened: the file then survives as `.mr-claimed.*`,
                # outside the scan glob, while the report says it is gone. The litter
                # sweep further down sees exactly that file and reports it, so the
                # honest move here is to stop claiming this one.
                if rm -f "$_mr_claim" 2>/dev/null; then
                    _mr_swept_n=$((_mr_swept_n + 1))
                else
                    _mr_unconsumed_n=$((_mr_unconsumed_n + 1))
                fi
                continue
            fi
            [[ -e "$_mr_f" ]] || continue
            echo "Warning: cannot sweep expired memory-restore flag: $_mr_f" >&2
            # Fall through: a flag hygiene could not remove is still reported.
        fi
        # An unestablished age is not a fresh one. The outcome is unchanged — such a
        # flag carries `_mr_age=0` and passes this test anyway — but saying so here
        # means a later change to the window cannot silently age these flags out.
        if [[ "$_mr_measured" -eq 0 || "$_mr_age" -le 86400 ]]; then
            if [[ -z "$_mr_fcwd" ]]; then
                # No recorded path at all: a truncated or hand-mangled flag file,
                # NOT a checkpoint whose worktree was removed. Saying "the recorded
                # directory no longer exists" about a flag that records no directory
                # is the same invented-cause mistake this contract exists to stop.
                _mr_malformed_n=$((_mr_malformed_n + 1))
                _mr_append_row 5 "$_mr_mtime" "malformed flag, no recorded path" "$_mr_l4" "$_mr_l2" "$_mr_fcwd" "$_mr_key"
                continue
            fi
            _mr_scope_cached "$_mr_fcwd"; _mr_fscope="$_MR_SCOPE_OUT"
            # WHICH class this is, is decided by scope_compare() in lib-common.sh,
            # so the plan-file path can consume the same answer rather than grow a
            # second one. That path does NOT call it yet: this is the only caller,
            # into two different answers to the same question. HOW it is worded
            # stays here: every sentence below describes a flag, which records a
            # directory. A plan file records none, so it must say something else
            # for the same class.
            scope_compare "$_mr_scope" "$_mr_fscope"
            _mr_prio="$SCOPE_PRIO"
            case "$SCOPE_CLASS" in
                selfunver)
                    # THIS SESSION's own directory could not be resolved, so no flag can
                    # be established as belonging here — including flags that do. The two
                    # unresolvable cases must NOT share one verdict: that makes the
                    # client-scope withholding contingent on our own cwd resolving, and
                    # with an unresolvable cwd — a removed worktree, the motivating
                    # scenario of this whole change — another project's recorded path and
                    # its label reach an unrelated session under a legend asserting its
                    # directory no longer exists. Withhold instead: nothing was
                    # compared, so nothing may be claimed, and a label is free text people
                    # fill with a ticket key or a codename
                    # (`~/.claude/rules/client-scope.md`). The flags are untouched on
                    # disk; the tail line below says where.
                    _mr_verdict="own scope unresolvable, withheld"
                    _mr_selfunver_n=$((_mr_selfunver_n + 1))
                    ;;
                unver)
                    # NOT "a different repository" — not verifiable. The recorded path
                    # is unreachable, which is the normal state of a checkpoint armed
                    # inside a worktree that has since been removed. Calling that
                    # "different repository" states as fact something never checked,
                    # and the old wording then forbade acting on it — worse than the
                    # silence this contract replaced. Reaching here means our OWN scope
                    # resolved, so "no longer exists" is now a checked claim, not a guess.
                    _mr_verdict="scope unverifiable, recorded path unreachable"
                    _mr_unver_n=$((_mr_unver_n + 1))
                    ;;
                same)
                    # Reaching here means both sides are `repo:`, so naming a
                    # repository is a checked claim. Two equal `dir:` answers would
                    # mean one physical directory, and the match above already
                    # resolves both spellings with `pwd -P` — so that pair is
                    # reported as MATCHES and never arrives here. Verified in both
                    # spelling directions.
                    _mr_verdict="same repository, selectable"
                    _mr_same_n=$((_mr_same_n + 1))
                    ;;
                foreign)
                    _mr_verdict="different repository, counted only"
                    _mr_foreign_n=$((_mr_foreign_n + 1))
                    ;;
                outside)
                    # scope_key() answered for both sides, but at least one answer is
                    # `dir:` — a directory CHECKED to be inside no repository. They are
                    # not the same scope, which is all that was established; calling it
                    # "a different repository" would name something neither side has.
                    _mr_verdict="outside this session's scope, counted only"
                    _mr_outside_n=$((_mr_outside_n + 1))
                    ;;
                *)
                    # A class this caller does not know is not a classification. The
                    # shared function is meant to grow a second consumer, and the
                    # `outside` label used to sit on this arm — so a class added for
                    # the other subsystem would have been reported here as a checked
                    # verdict. Withhold instead: priority 6 is the band that prints
                    # nothing, which is the only default that cannot disclose.
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

    # A matching flag whose age was never established must not be treated as fresh.
    # Reaching the claim below would restore an arbitrarily old checkpoint as though it
    # were this session's, then delete it — the one path that destroys the pointer,
    # taken on a number nobody measured. Reported and left where it is, so it is still
    # there once whatever broke `stat` is fixed. Priority 4 already means "matched, not
    # restored, still on disk"; this is another way of arriving at it.
    if [[ "$_mr_measured" -eq 0 ]]; then
        _mr_append_row 4 "$_mr_mtime" "MATCHED but its age could NOT be established, not restored, still on disk" "$_mr_l4" "$_mr_l2" "$_mr_fcwd" "$_mr_key"
        _mr_unmeasured_n=$((_mr_unmeasured_n + 1))
        continue
    fi

    # Atomically CLAIM the flag before consuming: two simultaneous /clear hooks
    # in the same cwd could otherwise both read it before either rm's it,
    # breaking the one-shot contract with duplicate directives. mv on the same
    # filesystem is atomic — exactly one hook wins; the loser skips. The claim
    # name must stay outside the .pending-memory-restore-* scan glob.
    _mr_claim="${PLANS_DIR}/.mr-claimed.$$.${_mr_key}"
    if ! mv "$_mr_f" "$_mr_claim" 2>/dev/null; then
        if [[ -e "$_mr_f" ]]; then
            # Still present = a real filesystem failure (read-only, EACCES, full),
            # not a lost race. A warning on stderr does NOT reach the session:
            # additionalContext is the only channel into the model's context, so
            # stderr alone would be invisible in precisely the case where a
            # matching checkpoint failed to restore. Report it as a row too.
            echo "Warning: cannot claim memory-restore flag: $_mr_f" >&2
            _mr_append_row 4 "$_mr_mtime" "MATCHED but could NOT be claimed (filesystem error), not restored, still on disk" "$_mr_l4" "$_mr_l2" "$_mr_fcwd" "$_mr_key"
            _mr_unclaimed_n=$((_mr_unclaimed_n + 1))
        else
            # Gone = a concurrent hook claimed it first. Not our flag to restore,
            # but the contract is to say what was seen, not to imply nothing was.
            _mr_lostrace_n=$((_mr_lostrace_n + 1))
        fi
        continue
    fi
    if [[ "$_mr_age" -le 86400 ]]; then
        _mr_append_row 1 "$_mr_mtime" "MATCHES this session" "$_mr_l4" "$_mr_l2" "$_mr_fcwd" "$_mr_key"
        _mr_match_n=$((_mr_match_n + 1))
    else
        # Matched but past the window — consumed all the same. It MUST be listed:
        # this is the one path where the pointer is destroyed rather than left
        # alone, and the label is the only handle left for a manual read_memory().
        _mr_append_row 2 "$_mr_mtime" "MATCHED but expired, consumed WITHOUT restoring (its memory is still in the backends)" "$_mr_l4" "$_mr_l2" "$_mr_fcwd" "$_mr_key"
        _mr_stale_gone_n=$((_mr_stale_gone_n + 1))
    fi
    # One-shot: consume matched-cwd flags, fresh or stale. The row above already says
    # the flag was consumed, so a failed `rm` makes that sentence false — the file lives
    # on as `.mr-claimed.*`, which the litter sweep below then reports.
    rm -f "$_mr_claim" 2>/dev/null || _mr_unconsumed_n=$((_mr_unconsumed_n + 1))
done
# Litter sweep: a hook killed between claim and rm, or a crashed writer, can strand
# .mr-claimed.* / .mr-tmp.* files. A claim file is the ORIGINAL flag, moved rather
# than rewritten, so it still holds a label and a recorded path — but it sits outside
# the .pending-memory-restore-* scan glob, so no later run mentions it, and deleting
# it silently destroys a checkpoint pointer with no trace anywhere. Both outcomes are
# counted and reported. Positive-staleness only: an age nobody established never
# reaches the seven-day test, the same rule the flag scan above now applies.
for _mr_litter in "${PLANS_DIR}"/.mr-claimed.* "${PLANS_DIR}"/.mr-tmp.*; do
    # An unexpanded glob is the only thing that may leave silently; everything else
    # that carries one of these names gets an answer.
    [[ -e "$_mr_litter" || -L "$_mr_litter" ]] || continue
    # Nothing this hook writes is a symlink or a directory, so anything here that is
    # not a plain regular file arrived from outside and cannot be measured on its own
    # terms. `-f` and `-s` follow a link while `stat` does not, so a link to a live
    # file reads as old-and-non-empty, gets deleted — taking only the LINK — and is
    # then reported as a destroyed body that is in fact untouched. A dangling link, a
    # directory or a socket used to leave through the old `-f` guard counted by
    # nothing at all.
    if [[ -L "$_mr_litter" || ! -f "$_mr_litter" ]]; then
        _mr_litter_unmeasured_n=$((_mr_litter_unmeasured_n + 1))
        continue
    fi
    # Match on the BASENAME: a whole-path test also fires on any ancestor directory
    # named `.mr-claimed.*`, filing a temp file under a glob it never matches.
    _mr_is_claim=0
    [[ "${_mr_litter##*/}" == .mr-claimed.* ]] && _mr_is_claim=1
    # KNOWN LIMITATION, left in place deliberately. A `.mr-claimed.*` is produced by
    # `mv`, which carries the ORIGINAL flag's mtime across, so this asks when the FLAG
    # was written and never when the claim was made: the in-flight guard below cannot
    # protect a live claim, and a claim taken from an already-expired flag is over the
    # sweep threshold the moment it exists. `ctime` is the correct reading and rename
    # does update it, but no test can arrange an old ctime — `touch` cannot set it —
    # so the change could only be verified by shimming `stat` in every fixture that
    # plants a claim file, which would test the shim rather than the filesystem. The
    # consequence is documented for the reader in references/HOOKS.md instead.
    mtime_of "$_mr_litter"; _mr_lm="$_MTIME_OUT"
    # In THIS loop, an age nobody could establish is not an age of zero. Collapsing
    # the failure to `now` handed the file to the in-flight guard below, which dropped
    # it from the report entirely. No sentinel mtime is substituted here, because
    # substituting one is that same move. The `.pending-memory-restore-*` loop above
    # applies the same rule: it too refuses to invent an age, and a matching flag
    # whose age was never established is reported rather than restored and deleted.
    #
    # A mtime slightly AHEAD of the sample is a different case. `_mr_now` is read once,
    # before a per-flag scan that forks several times, so a concurrent
    # `write-reload-flag.sh` ordinarily lands after that read: the file is at most zero
    # seconds old and belongs to the in-flight case, not this one. The tolerance is the
    # same window the in-flight guard uses, because it is the same phenomenon.
    #
    # Further ahead than that window is neither. A restored backup, a `cp -p` from a
    # machine running ahead, an NFS server's clock — and `_mr_now` forced to 0 above
    # when `date` failed, which puts EVERY real mtime out here. None of them
    # establishes an age, and reading them as in-flight would skip the whole sweep in
    # silence, so they fall through as unmeasured.
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
    # Two populations reach this branch and only one fact is true of both: no age was
    # established. A failed `stat` establishes nothing at all — not even emptiness,
    # since `-s` asks the same syscall — while a clock too far off leaves the file
    # perfectly readable. So the report claims the age and nothing more; saying "could
    # not be examined" would send the reader to inspect files that were never
    # unreadable. Neither population is swept, because sweeping needs an age, and
    # neither is classified, because one honest answer has to cover both. The count
    # stays disjoint from every other count on the line.
    if [[ "$_mr_lmeasured" -eq 0 ]]; then
        _mr_litter_unmeasured_n=$((_mr_litter_unmeasured_n + 1))
        continue
    fi
    # A .mr-tmp.* is NOT a claim file, but whether it holds a checkpoint has to be
    # LOOKED AT rather than assumed. `write-reload-flag.sh` writes the whole body into
    # the temp file and only then renames it (its printf redirects into the temp file,
    # and the `mv` follows), so a writer killed in that window leaves a complete flag
    # behind. Only an EMPTY one is the "holds nothing" case this branch may claim —
    # and `-s` establishes size alone, so a non-empty one is reported as possibly
    # holding a body, never as certainly holding a usable one: a `printf` killed after
    # its first line leaves bytes but no recorded path.
    _mr_has_body=0
    [[ "$_mr_is_claim" -eq 0 && -s "$_mr_litter" ]] && _mr_has_body=1
    if [[ "$_mr_lage" -gt 604800 ]]; then
        # THREE outcomes, not two. `rm` fails on a read-only or non-writable plans
        # directory, and counting only the two successes let the file vanish from the
        # report entirely — the same silence this whole loop was rewritten to remove.
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
    # Younger than a minute is a file in flight, not litter: a concurrent hook's claim
    # lives for microseconds, and a writer's temp file for barely longer. Calling
    # either one stranded reports another session's work in progress as wreckage.
    # This is the same sixty seconds the future-mtime tolerance above uses, and
    # deliberately so: both exist for one phenomenon, a writer racing a clock sampled
    # once. Change one and the other has to move with it.
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
    # Priority first, then newest — NOT time alone. The cap truncates the tail, so
    # ordering by time let rows nobody may act on evict the one row the directive
    # then told the agent to offer.
    _mr_sort_rows
    # The candidates block: what the scan saw, whatever it matched. Capped at
    # five rows so a busy plans directory cannot flood the session context;
    # anything beyond the cap is counted, never silently dropped.
    # Whether every matched flag is relisted in full below. TWO places must agree on
    # this: the display cap must not count a matched row as withheld when the list
    # below is about to print it, and that list only exists on this branch. Deciding
    # it once is the difference between a coupling and a coincidence.
    _mr_relists_every_match=0
    [[ "$_mr_match_n" -ge 2 ]] && _mr_relists_every_match=1
    _mr_block="Checkpoint candidates seen at this /clear (scope: ${_mr_scope_shown}):"
    _mr_shown=0
    _mr_over=0
    _mr_same_shown_n=0
    _mr_same_keyed_shown_n=0
    # One of the five slots is RESERVED for the first `same repository, selectable`
    # row when priority ordering would otherwise push every one of them past the
    # cap. Priority 2 (`MATCHED but expired`) deliberately outranks priority 3, so
    # without it five expired rows evict the only actionable row while the notes below
    # still tell the agent to run an AskUserQuestion over "those rows" and to delete a
    # flag whose key was never printed. The reservation spends the fifth slot of a
    # lower-value verdict; it does not reorder anything.
    # Counted with builtins for the same reason the ordering is: an unchecked
    # capture from a helper that failed would silently switch the reservation off
    # and restore the very defect it exists to close.
    _mr_same_pos=""
    _mr_pos_n=0
    while IFS=$'\037' read -r _mr_pp _ _mr_pv _; do
        [[ -n "$_mr_pp" ]] || continue
        [[ "$_mr_pp" == "6" ]] && continue
        _mr_pos_n=$((_mr_pos_n + 1))
        if [[ "$_mr_pv" == "same repository, selectable" ]]; then
            _mr_same_pos=$_mr_pos_n
            break
        fi
    done <<< "$_mr_rows"
    _mr_reserve=0
    [[ "$_mr_same_pos" =~ ^[0-9]+$ ]] && [[ "$_mr_same_pos" -gt 5 ]] && _mr_reserve=1
    _mr_cap=$((5 - _mr_reserve))
    while IFS=$'\037' read -r _mr_prio_r _mr_m _mr_v _mr_l _mr_t _mr_p _mr_k; do
        # Guard on the PRIORITY, not the mtime. The row set ends in a newline, so the
        # here-string yields one empty trailing line, and skipping it is all this guard
        # is for. Keying it on the mtime also dropped every row whose age could not be
        # established — the display renders those as "age unknown" perfectly well, so
        # the row simply vanished while the counts above still included it. The sibling
        # scan a few lines up already guards on the priority field.
        [[ -n "$_mr_prio_r" ]] || continue
        # A flag belonging to another repository is COUNTED, never printed. Its
        # recorded path and its label are that project's material — a label is free
        # text people fill with a ticket key or a codename — and nothing in this
        # block permits acting on it, so printing it into an unrelated session buys
        # nothing and carries another project's identifiers for 24 hours.
        # `~/.claude/rules/client-scope.md`: other clients' work is "not in any report".
        # Priority 6 is the withheld band: another repository, a scope outside this
        # one, and rows this session could not classify at all. Keying on the
        # priority the row already carries keeps the privacy rule in one place
        # instead of in a list of verdict strings that must be kept in step.
        if [[ "$_mr_prio_r" == "6" ]]; then
            continue
        fi
        # The verdict the display acts on, matched ONCE: it decides the reserved
        # slot, the hidden-row count, whether the flag key is printed, and the offer
        # count. Four spellings of one contract string are four chances for one to
        # drift out of step with the scan that writes it.
        _mr_is_same=0
        [[ "$_mr_v" == "same repository, selectable" ]] && _mr_is_same=1
        # The reserved slot, taken once, by the first selectable row only.
        _mr_take_reserved=0
        [[ "$_mr_reserve" -eq 1 && "$_mr_same_shown_n" -eq 0 && "$_mr_is_same" -eq 1 ]] && _mr_take_reserved=1
        if [[ "$_mr_take_reserved" -eq 0 && "$_mr_shown" -ge "$_mr_cap" ]]; then
            # A matched row past the cap is NOT withheld: the ask-which-one branch
            # below lists every matched flag in full, so counting it as "not shown"
            # made one message say a row was kept back and then print it. Only that
            # branch relists, and it runs on two or more matches.
            if [[ "$_mr_v" == "MATCHES this session" && "$_mr_relists_every_match" -eq 1 ]]; then
                _mr_match_relisted_n=$((_mr_match_relisted_n + 1))
                continue
            fi
            _mr_over=$((_mr_over + 1))
            # A destroyed pointer that the cap hid must be counted separately: the
            # directive tells the reader its label is listed above, and for these
            # rows the flag is already gone, so an unqualified claim would be false.
            [[ "$_mr_v" == "MATCHED but expired"* ]] && _mr_gone_hidden_n=$((_mr_gone_hidden_n + 1))
            # Same reason, other direction: the notes tell the agent to offer the
            # selectable rows, so any it cannot see must be counted, not implied.
            [[ "$_mr_is_same" -eq 1 ]] && _mr_same_hidden_n=$((_mr_same_hidden_n + 1))
            continue
        fi
        # Own name, not the scan loop's _mr_age: that one holds seconds, this one
        # holds the rendered phrase.
        _mr_age_text="age unknown"
        # The second arm is the in-flight race the scan already accepted: it gave that
        # flag an age of zero and went on to restore and consume it, so refusing to
        # render one here made the row contradict the action taken on it.
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
        # The key exists so the agent can delete a flag the hook did NOT consume.
        # Two verdicts qualify. A matched row's flag is already gone by this point,
        # and a foreign row is never offered — printing the key on either would name
        # something the agent must not act on. A MALFORMED row belongs to neither
        # exclusion: nothing consumed it, and with no recorded path it cannot be
        # attributed to any repository, so naming it discloses nothing while making
        # the note that asks the user to delete it possible to act on at all. Without
        # the key that row reads `(no label) — recorded (unknown path)` and identifies
        # no file.
        [[ -n "$_mr_k" ]] && { [[ "$_mr_is_same" -eq 1 ]] || [[ "$_mr_v" == "malformed flag"* ]]; } \
            && _mr_block+=" — flag ${_mr_k}"
        [[ "$_mr_v" == "scope unverifiable"* ]] && _mr_unver_shown_n=$((_mr_unver_shown_n + 1))
        [[ "$_mr_v" == "malformed flag"* ]] && _mr_malformed_shown_n=$((_mr_malformed_shown_n + 1))
        if [[ "$_mr_is_same" -eq 1 ]]; then
            _mr_same_shown_n=$((_mr_same_shown_n + 1))
            [[ -n "$_mr_k" ]] && _mr_same_keyed_shown_n=$((_mr_same_keyed_shown_n + 1))
        fi
        _mr_shown=$((_mr_shown + 1))
    done <<< "$_mr_rows"
    _mr_tail=""
    # The hidden-kind counters are SUBSETS of the overflow -- all three are
    # incremented in the same `continue` branch -- so they are reported inside its
    # clause rather than beside it. Printed as siblings they read as separate
    # populations and a reader totals them: one hidden row was announced as
    # "1 more not shown; 1 destroyed pointers NOT shown above".
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
    # _mr_stale_gone_n is deliberately absent here: those rows are LISTED above,
    # label and all, because that path destroys the pointer. A count as well would
    # report the same flag twice.
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

    # An unclaimable flag is deliberately NOT actionable: its own directive says
    # nothing can be restored here until the permissions are fixed, which is the
    # definition of nothing restorable. Including it would contradict the rule
    # stated where MR_ACTIONABLE is declared.
    [[ "$_mr_match_n" -gt 0 || "$_mr_same_n" -gt 0 ]] && MR_ACTIONABLE="yes"
    # A selectable row is only actually deletable if its key survived the allowlist,
    # AND the delete instruction can only name a row the reader was shown — counting
    # keys the cap hid is how the instruction came to reference an invisible flag.
    # The reserved slot above guarantees at least one shown row whenever any exists.
    _mr_same_keyed_n=$_mr_same_keyed_shown_n
    # Field-exact, not substring: a checkpoint LABEL is user-supplied text and could
    # itself read "MATCHES this session", which a grep over the whole row would
    # mistake for a verdict. The third field is taken by position with parameter
    # expansion — no fork, so there is no failure here to swallow.
    _mr_match_rows=""
    while IFS= read -r _mr_row; do
        [[ -n "$_mr_row" ]] || continue
        _mr_rest=${_mr_row#*$'\037'}
        _mr_rest=${_mr_rest#*$'\037'}
        [[ "${_mr_rest%%$'\037'*}" == "MATCHES this session" ]] && _mr_match_rows+="${_mr_row}"$'\n'
    done <<< "$_mr_rows"
    # Rows are already sorted newest-first within a priority, so the first matched
    # row is the newest one. Read it with the same field-split as every other row
    # reader rather than a second `cut -d$'\037'` spelling of the same schema.
    IFS=$'\037' read -r _ _ _ _mr_newest_label _ <<< "$_mr_match_rows"
    # Per-verdict guidance is built ONCE and appended to whichever directive the
    # match count selects. Confining it to the zero-match branch silences every
    # explanation on a single match: selectable rows print a bare `— flag <key>` with
    # nothing saying what a key is for, and destroyed pointers are never announced.
    # The rows are emitted in all three branches, so their legends have to be too.
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
        # Two or more matched flags means the directive above already orders ONE
        # AskUserQuestion over the matched list. Repeating the order here produced a
        # second question over a DISJOINT set, and its "those rows only" pointed at
        # rows the first list excludes — only one question can sensibly be asked.
        # The condition is the same variable that selects that directive, not a
        # second reading of the match count, so the two cannot drift apart.
        if [[ "$_mr_relists_every_match" -eq 1 ]]; then
            _mr_notes+="\n\nRows marked \`same repository, selectable\` belong to this repository and were NOT consumed. They are NOT in the numbered list above: add them to the SAME AskUserQuestion as further options, clearly separated from the matched ones, rather than asking a second question."
        else
            _mr_notes+="\n\nRows marked \`same repository, selectable\` belong to this repository and were NOT consumed. Use AskUserQuestion to ask whether to restore one of them (offer those rows only, plus a \"none\" option)."
        fi
        [[ "$_mr_same_hidden_n" -gt 0 ]] && _mr_notes+="\n${_mr_same_hidden_n} further selectable row(s) could NOT be shown above (row cap). Offer only the ones listed; say the rest exist rather than implying the list is complete."
        if [[ "$_mr_same_keyed_n" -eq 0 ]]; then
            _mr_notes+="\nNone of those rows carries a usable flag key, so do not attempt to delete one; report that and continue."
        else
            # PLANS_DIR, never a hardcoded ~/.claude/plans: it is
            # "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plans" (lib-common.sh), and under a
            # non-default config directory a hardcoded path makes the agent's `rm -f`
            # a silent no-op — after which this same flag is re-offered at every
            # /clear until the seven-day sweep.
            _mr_notes+="\nIf one is chosen: restore it (Serena list_memories()/read_memory(), the auto-memory index at \`~/.claude/projects/«project»/memory/MEMORY.md\`, Basic-Memory recent notes), then delete its flag with \`rm -f ${_mr_plans_shown}/.pending-memory-restore-«flag»\` — the hook did not consume it, so it will be offered again at every /clear for the next 24 hours until you do."
        fi
    fi
    # Explain a verdict only when a row actually carries it: a legend for a
    # category that is not on screen is noise, and it also reads as if such a
    # row were present.
    [[ "$_mr_selfunver_n" -gt 0 ]] && _mr_notes+="\nThis session's own directory could not be resolved to a repository, so no flag could be checked against it and none is shown: withholding is not a claim that they belong elsewhere. They are untouched in \`${_mr_plans_shown}\`; read them there if you need one."
    [[ "$_mr_outside_n" -gt 0 ]] && _mr_notes+="\nFlags \`recorded outside this scope\` were resolved, and at least one side is a directory inside no repository, so the only established fact is that the scopes differ — not that they belong to another project. Their paths and labels are withheld on the same rule; they are untouched in \`${_mr_plans_shown}\`."
    [[ "$_mr_foreign_n" -gt 0 ]] && _mr_notes+="\nThe count of flags \`recorded in another repository\` is deliberately all you get: their paths and labels belong to those projects and are withheld from this session. Do not go looking for them."
    [[ "$_mr_malformed_shown_n" -gt 0 ]] && _mr_notes+="\nRows marked \`malformed flag, no recorded path\` are corrupt or truncated flag files, not checkpoints. Nothing can be restored from them; mention them so the user can delete them."
    [[ "$_mr_unver_shown_n" -gt 0 ]] && _mr_notes+="\nRows marked \`scope unverifiable, recorded path unreachable\` were NOT checked — the recorded path could not be resolved. A worktree that has since been removed is the usual reason, but a directory that still exists and cannot be entered, or a repository git declined to resolve, reaches this row too, so the cause is not established. Do not assert which repository they belong to. Show the recorded path and let the user decide."

    if [[ "$_mr_match_n" -eq 0 ]]; then
        # The outcome this contract exists for. Nothing is restored and nothing is
        # consumed; the same-repository rows are handed to the user to choose from.
        MR_DIRECTIVE="${_mr_block}\n\n**CHECKPOINT CANDIDATES - nothing was restored:**"
        # This sentence makes two claims — that no flag recorded this session's
        # scope, and that nothing was consumed — so it may be printed only when
        # NOTHING in the scan bears against either.
        #
        # Adding a state to this scan does NOT mean editing this sum. Every entry
        # the scan opened is counted once in `_mr_seen_n`, and only the states
        # BELOW are declared not to bear: flags left for their own session, flags
        # that matched, and flags whose scope resolved to somewhere this session
        # could name. A state added later therefore bears until someone declares
        # otherwise, so forgetting withholds the sentence instead of printing one
        # the scan contradicts. That is the direction it has to fail in: this
        # condition was previously a hand-maintained list of counter names, and
        # four states were missing from it — a flag that could not be read, a name
        # that could not be opened, a non-matching flag the seven-day sweep
        # DELETED, and a truncated flag recording no path. Each was reproduced
        # against the running hook, printing the sentence while falsifying it.
        #
        # `_mr_unopenable_n` and `_mr_lostrace_n` are added rather than subtracted
        # because those names never reached the `-f` guard, so they are not in
        # `_mr_seen_n` at all. A flag another session consumed is a case this scan
        # never READ: it cannot say whether that flag recorded this directory, and
        # two sessions in one directory both match, so it bears and the sentence is
        # withheld. Being sure the report is silent costs less than a sentence the
        # scan cannot support.
        _mr_bearing_n=$(( _mr_seen_n + _mr_unopenable_n + _mr_lostrace_n + _mr_notplain_n \
                        - _mr_stale_kept_n - _mr_match_n \
                        - _mr_same_n - _mr_foreign_n - _mr_outside_n ))
        if [[ "$_mr_bearing_n" -eq 0 ]]; then
            MR_DIRECTIVE+="\n\nNo checkpoint flag recorded this session's working directory, so NOTHING was restored and no flag was consumed."
        fi
        [[ "$_mr_same_n" -eq 0 && "$_mr_mine_n" -eq 0 ]] && MR_DIRECTIVE+="\nNo row was verified as belonging to this repository, so there is nothing to offer automatically. Say so in one line and continue with the user's request."
        MR_DIRECTIVE+="$_mr_notes"
    elif [[ "$_mr_relists_every_match" -eq 0 ]]; then   # exactly one match
        MR_LABEL="$_mr_newest_label"
        MR_DIRECTIVE="${_mr_block}\n\n**ACTION REQUIRED - MEMORY RESTORE"
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
        MR_DIRECTIVE+="$_mr_notes"
    else
        MR_DIRECTIVE="${_mr_block}\n\n**ACTION REQUIRED - MEMORY RESTORE (${_mr_match_n} checkpoints for this directory):**"
        MR_DIRECTIVE+="\n\nMultiple /smith-checkpoint flags were saved for this directory (parallel sessions). Candidates, newest first (label — saved at):"
        while IFS=$'\037' read -r _mr_pr _ _ _mr_l _mr_t _ _; do
            # Guard on the PRIORITY field, which this script writes and which is
            # never empty — not on the label and timestamp, which come from the flag
            # file. A matched flag with both of those blank is still a consumed
            # checkpoint, and skipping it left the header counting a candidate that
            # the list below never offered, with its pointer already destroyed.
            [[ -n "$_mr_pr" ]] || continue
            MR_DIRECTIVE+="\n- ${_mr_l:-(no label)} — ${_mr_t:-unknown time}"
        done <<< "$_mr_match_rows"
        MR_DIRECTIVE+="\n\nBEFORE doing anything else, use AskUserQuestion to ask which checkpoint to restore."
        MR_DIRECTIVE+="\nIf unable to ask (headless/non-interactive), restore the newest (\`${_mr_newest_label:-(no label)}\`) and say so explicitly."
        MR_DIRECTIVE+="\nThen restore it: Serena list_memories()/read_memory(), the auto-memory index at \`~/.claude/projects/«project»/memory/MEMORY.md\`, and Basic-Memory recent notes."
        MR_DIRECTIVE+="\nDo NOT skip this. Do NOT respond with \"Ready for your next task.\""
        MR_DIRECTIVE+="$_mr_notes"
    fi
elif [[ -z "$_mr_cwd" ]]; then
    # The scan was skipped, not empty. Skipping is correct — "" would match every
    # truncated flag — but saying nothing about it is the failure this whole contract
    # exists to remove, and the two are indistinguishable in the output. Reachable:
    # bash leaves PWD empty when it is unset in the environment AND getcwd() fails,
    # which is what a REMOVED working directory does, and a removed worktree is the
    # motivating scenario of this change.
    MR_DIRECTIVE="Checkpoint flags at this /clear: this session's working directory could not be determined, so NO flag was scanned, none was consumed and nothing was restored. Every checkpoint pointer is still in \`${_mr_plans_shown}\`. This is not the same as having no checkpoints."
elif [[ -n "$_mr_dir_unreadable" ]]; then
    MR_DIRECTIVE="Checkpoint flags at this /clear: \`${_mr_plans_shown}\` could NOT be inspected — it, or a directory above it, denied access — so no flag was scanned and nothing was restored. This is not the same as having no checkpoints. Check the permissions on that path before relying on /clear restore here."
elif [[ -n "$_mr_fallback_note" ]]; then
    # Nothing fresh to list, but the scan was not empty. One line, not silence:
    # a scan whose result is discarded is exactly what let the matching defect
    # survive unnoticed. With no flags at all this stays quiet, as before.
    MR_DIRECTIVE="Checkpoint flags at this /clear (scope: ${_mr_scope_shown}): nothing fresh enough to restore${_mr_fallback_note}. Nothing was restored."
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
    # Through mtime_of, which selects on the output: chaining the two stat forms on
    # the EXIT STATUS never reaches the fallback on GNU, where `-f %m` succeeds and
    # prints a mount point, and the age here would read as unknown on every Linux.
    mtime_of "$STATE_FILE"
    _state_mtime="$_MTIME_OUT"
    _state_age="?"
    # The clock is validated like the flag scan's, and for the same reason: an empty
    # capture leaves bash evaluating `(( ( - <mtime>) / 60 ))`, which renders an age
    # of minus twenty-nine million minutes -- a number, so it reads as a measurement
    # rather than as the failed reading it is. It takes BOTH readings to have an age;
    # without one the initialised `?` is the honest answer.
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
    if [[ -n "$FLAG_TYPE" ]] || [[ -n "$RALPH_RESUME_DIRECTIVE" ]] || [[ -n "$ORCH_RESUME_DIRECTIVE" ]] || [[ -n "$MR_ACTIONABLE" ]]; then
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

    # Prepend the checkpoint memory-restore directive so the action leads. It is set
    # whether or not anything was consumed: the zero-match, unusable-directory and
    # stale-only paths all produce one, which is the whole point of this change.
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

# Append Ralph resume directive if present
if [[ -n "$RALPH_RESUME_DIRECTIVE" ]]; then
    FULL_CONTENT+=$(printf '%b' "$RALPH_RESUME_DIRECTIVE")
fi

# Append orchestrator resume directive if present
if [[ -n "$ORCH_RESUME_DIRECTIVE" ]]; then
    FULL_CONTENT+=$(printf '%b' "$ORCH_RESUME_DIRECTIVE")
fi

# Prepend the checkpoint memory-restore directive so it leads even when a plan also
# reloaded. Set whether or not anything was consumed — a report is a directive too.
[[ -n "$MR_DIRECTIVE" ]] && FULL_CONTENT=$(printf '%b\n\n%s' "$MR_DIRECTIVE" "$FULL_CONTENT")

# Clean up the pending-reload flag if it exists (SessionStart:clear handles it now)
rm -f "$FLAG_FILE" 2>/dev/null

json_session_start_output "$FULL_CONTENT"

exit 0
