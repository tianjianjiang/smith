# Hook Configuration for Plan Sync

This document explains how to configure the hooks for plan syncing, context management, and Ralph autonomous loop integration.

## Overview

These hooks work together to manage plan execution across context boundaries:

| Hook | Event | Fires | Purpose |
|------|-------|-------|---------|
| `inject-plan.sh` | UserPromptSubmit | Every prompt | Load plan, detect flags, detect context threshold |
| `enforce-clear.sh` | Stop | Agent stop | Block stop when context high + pending tasks |
| `on-plan-exit.sh` | PostToolUse (ExitPlanMode) | Plan mode exit | Create reload flag for auto-load after `/clear` |
| `on-session-clear.sh` | SessionStart (`clear`) | After `/clear` | Scan checkpoint flags, restore this session's, report the rest |
| `mark-session-restart.sh` | SessionStart (`clear`, `compact`) | After `/clear` or `/compact` | Record that a restart actually happened, and which one |

## Installation

### 1. Copy the Skill

```bash
# Symlink (recommended)
ln -sf ~/.smith/smith-plan-claude ~/.claude/skills/smith-plan-claude

# Make scripts executable
chmod +x ~/.smith/smith-plan-claude/scripts/*.sh
```

### 2. Configure the Hooks

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/skills/smith-plan-claude/scripts/inject-plan.sh",
            "timeout": 5000
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/skills/smith-plan-claude/scripts/enforce-clear.sh",
            "timeout": 5000
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "ExitPlanMode",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/skills/smith-plan-claude/scripts/on-plan-exit.sh",
            "timeout": 5000
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "clear",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/skills/smith-plan-claude/scripts/on-session-clear.sh",
            "timeout": 5000
          },
          {
            "type": "command",
            "command": "~/.claude/skills/smith-plan-claude/scripts/mark-session-restart.sh",
            "timeout": 5000
          }
        ]
      },
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/skills/smith-plan-claude/scripts/mark-session-restart.sh",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

Register `mark-session-restart.sh` under BOTH matchers. Under `compact` alone the
gate is never armed, so nothing changes; under `clear` alone a `/compact` still
produces the false "POST-CLEAR RESUME" this hook exists to remove.

### 3. Ensure Plans Directory Exists

Paths in this document assume the default profile (`CLAUDE_CONFIG_DIR`
unset), i.e. `~/.claude/plans` resolves to `${CLAUDE_CONFIG_DIR}/plans`
under an explicit profile override. Examples that already read `$PLANS_DIR`
(sourced from `lib-common.sh`) are already profile-aware as written.

```bash
mkdir -p "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plans"
```

## Hook Details

### inject-plan.sh (UserPromptSubmit)

Fires on every prompt. Three main paths:

1. **Flag detection**: If `.pending-reload-<CWD_KEY>` exists (CWD-keyed, <1hr old), loads the flagged plan and deletes the flag (one-shot). Once `mark-session-restart.sh` has armed its sentinel, this path additionally requires a session-restart marker: without one the flag is left untouched, because nothing was actually cleared or compacted. See "Session-restart marker" below.

2. **Context threshold**: If `transcript_path` file size exceeds `PLAN_CONTEXT_THRESHOLD_KB` (default: 500KB) and an active plan has pending tasks, creates the flag and outputs a CONTEXT CRITICAL warning.

3. **Trigger words**: Matches `execute plan`, `!load-plan`, `!plan`, `!plan-status`, etc.

**Input JSON fields used:**
- `prompt` - User's prompt text
- `session_id` - Current session identifier
- `transcript_path` - Path to JSONL transcript file

### enforce-clear.sh (Stop)

Fires when agent attempts to stop. Blocks stop if ALL conditions met:
1. No `.pending-reload-<CWD_KEY>` flag (clear not yet initiated)
2. Transcript size > threshold
3. Active plan has pending `- [ ]` tasks

When blocking, the hook **auto-creates the `.pending-reload` flag** before returning the block. This breaks the infinite loop: on the first stop attempt, the agent is blocked and gets one turn to save state. On the second stop attempt, the flag exists and the stop is allowed.

**Input JSON fields used:**
- `transcript_path` - Path to JSONL transcript file
- `session_id` - Current session identifier (for flag file)

### on-plan-exit.sh (PostToolUse: ExitPlanMode)

Fires after ExitPlanMode tool is used. Locates the active plan by first checking `.plan-state-<CWD_KEY>` (line 5: plan path) and only falling back to the most recently modified `*.md` in the plans directory when state is missing. Creates/updates `.pending-reload-<CWD_KEY>` flag with the resolved plan, enabling auto-reload after `/clear`. Output is minimal (non-actionable) to prevent Claude from following numbered "next steps" instead of exiting. Also creates an `.exit-marker` file that signals `enforce-clear.sh` to allow the stop, preventing the Stop hook from blocking the turn after ExitPlanMode. The marker is validated for session match and consumed on read to prevent permanent bypass.

**ExitPlanMode rejection context.** ExitPlanMode rejection has three scenarios: (1) user gives revision feedback (normal -- agent revises and retries), (2) silent redirect back to plan mode without feedback (known issue -- agent should ask user to exit manually), (3) "auto-accept and clear" kills session before PostToolUse fires ([#20397](https://github.com/anthropics/claude-code/issues/20397)). For scenarios 2-3, on-plan-exit.sh never fires, making it **defense-in-depth** only. The **primary reliability mechanism** is the preemptive flag created by inject-plan.sh during plan mode, which ensures plan auto-reload regardless of ExitPlanMode outcome.

**Input JSON fields used:**
- `session_id` - Current session identifier
- `cwd` - Working directory (used to derive `CWD_KEY` via `session_key()` for `.plan-state-<CWD_KEY>` lookup)

## Flag File Format

`~/.claude/plans/.pending-reload-<CWD_KEY>` (`CWD_KEY` = first 16 chars of `md5(PPID:CWD)`, computed by `session_key()` in `lib-common.sh`; PPID is Claude Code's PID, stable across `/clear`):

```
/Users/user/.claude/plans/my-plan.md    <- line 1: absolute plan path
sess_abc123def                           <- line 2: session ID
$(date +%Y-%m-%dT%H:%M:%S%z)            <- line 3: ISO 8601 timestamp
/path/to/working/directory              <- line 4: CWD (for debugging)
plan-pending                             <- line 5: FLAG_TYPE (see below)
```

**FLAG_TYPE (line 5)** — old flags without line 5 default to `plan-pending`:
- `plan-pending` — active plan with pending `- [ ]` tasks → on-session-clear.sh reloads the plan.
- `plan-completed` — plan exists, no pending tasks → not reloaded (defense-in-depth).
- `no-plan` — no active plan → soft state signal only.

**Properties:**
- **CWD-keyed**: Each parallel session (worktree) gets its own flag file
- Persists through `/clear` (which only clears conversation, not disk files)
- One-shot: deleted after plan is loaded — but only once a restart is established. With the session-restart sentinel armed and no marker present, the flag is neither loaded nor deleted; it waits for the `/clear` or `/compact` that has not happened yet. The 60-minute sweep in `inject-plan.sh` does NOT bound that wait on the `/clear` route: `/clear` fires SessionStart, so `on-session-clear.sh` runs before any prompt is submitted, and it checks the flag's existence and type only — never its age. The plan it loads comes from the state file under its own 24-hour window. The sweep bites only when an ORDINARY prompt lands after the flag passes 60 minutes and before the next `/clear`, and even then the hook reports `Flag file: not found` rather than staying silent
- Expired flags (>1 hour old) are auto-cleaned on each hook invocation
- Legacy single `.pending-reload` file auto-cleaned (backward compatibility)

### Session-restart marker

`~/.claude/plans/.session-restart-<CWD_KEY>` — written by `mark-session-restart.sh`
(SessionStart, matchers `clear` and `compact`), read and consumed by `inject-plan.sh`.

The pending-reload flag above records an INTENT, never an event: `enforce-clear.sh` writes
it every time it blocks a high-context Stop, which says "you should reload after clearing"
and says nothing about whether a `/clear` followed. `inject-plan.sh` nevertheless consumed
it on the next prompt and announced **POST-CLEAR RESUME**, so a session that was blocked and
then simply kept working — or that was `/compact`ed instead of cleared — was told a `/clear`
had happened, and handed the whole recent-plans listing along with the claim. Observed
directly on 2026-08-27: a Stop block, then `/compact`, then a POST-CLEAR RESUME directive on
the very next prompt.

The marker supplies the missing fact. `inject-plan.sh` consumes it whether or not a flag is
waiting, so one restart produces one announcement rather than one per prompt, and it names
the route that actually discarded the conversation: **POST-CLEAR RESUME** or **POST-COMPACT
RESUME**. A marker recording any other source is treated as absent rather than announced
under a guessed label.

Only `clear` and `compact` are marked. `startup` and `resume` discard nothing a reload could
recover, and marking them would recreate the false announcement this exists to remove. The
source is checked inside the script as well as in the matcher, so a later matcher change
cannot silently widen the contract.

```text
compact                           <- line 1: SessionStart source (clear | compact)
2026-01-01T00:00:00+0900          <- line 2: ISO 8601 timestamp
/path/to/working/directory        <- line 3: CWD
```

Only line 1 is read. Lines 2 and 3 are a deliberate record for a human debugging a marker found
on disk — which session wrote it and when — and are kept for that reason, not because anything
consumes them.

**Rollout sentinel.** Requiring a marker unconditionally would silence auto-reload completely
for anyone who updated the scripts without updating `settings.json` — a total feature loss
announced by nothing. `mark-session-restart.sh` therefore touches
`~/.claude/plans/.sr-hook-installed`; `inject-plan.sh` requires a marker only once that
sentinel exists, and keeps the old ungated behaviour until then.

The sentinel is armed **only by a `clear`**, never by a `compact`, so that a partial
registration fails in the safe direction. Registered for `compact` alone, the gate would
otherwise arm without anything ever marking a `/clear`, and auto-reload after `/clear` would
stop working with no diagnostic; arming on `clear` only means that installation simply keeps
today's ungated behaviour instead. Register both matchers and the first `/clear` arms it.

It is armed only by a `clear`, but once it exists ANY marked restart refreshes it, `compact`
included. Refreshing on `clear` alone would let a machine that went 14 days without a single
`/clear` anywhere — a compact-led workflow, or a long break — age the sentinel out, disarm the
gate, and silently restore the false "POST-CLEAR RESUME" this hook removes. Arming stays
clear-only, so a `compact`-only registration still never creates the file and that installation
still stays ungated, exactly as stated above.

It is also rewritten on EVERY marked restart, not only the first, and `inject-plan.sh` requires it to
be newer than 14 days (testing `find`'s OUTPUT, never its exit status, for the reason recorded
against `stat` elsewhere in this document). Without that the sentinel would be a one-way latch:
remove the `clear` matcher later, or let the hook start failing after it has already armed, and
auto-reload is dead permanently with no diagnostic anywhere. An installation that is still
marking `/clear` keeps the gate indefinitely; one that has stopped falls back to the ungated
behaviour after 14 days rather than failing closed forever.

The sentinel is also named OUTSIDE the `.session-restart-*` glob, because `inject-plan.sh`
sweeps that glob hourly and a self-matching sentinel would un-install the gate an hour after
installation.

**Plan mode does not consume the marker.** A prompt with `permission_mode: plan` never takes
the reload path, so consuming the marker there would discard the restart and the next
non-plan prompt would find nothing — a regression against the pre-marker behaviour, where the
flag simply waited. The marker is read and consumed only outside plan mode.

When the gate is active and nothing restarted, the pending-reload flag is left ON DISK: the
intent it records is still waiting for the `/clear` that has not happened. Consuming it there
is what made a blocked-then-continued session lose its reload.

That wait is bounded, and the bound is older than this gate: `inject-plan.sh` deletes any
`.pending-reload-*` older than 60 minutes on every prompt, before the gate is consulted. The
window was sized when the flag was consumed on the very next prompt; with the gate it becomes
load-bearing. Blocked at high context, then working on for more than an hour, then `/clear`,
and there is no plan to auto-resume.

### Checkpoint memory-restore flag (separate file)

`~/.claude/plans/.pending-memory-restore-<unique id>` — written by `/smith-checkpoint` via
`write-reload-flag.sh`, read by `on-session-clear.sh`. **Deliberately separate** from
`.pending-reload`: the plan hooks (`enforce-clear.sh` writes it on every high-context Stop,
`inject-plan.sh` deletes it on the next prompt) own that file, so a non-plan flag stored there
would be clobbered/consumed before `/clear`. The plan hooks never touch this file.
The injected directive is context-only: the restore executes at the user's first prompt after
`/clear` (any prompt) — no hook event can start a model turn in an interactive session
(`initialUserMessage` is `-p`-only), so nothing visible happens at `/clear` itself.

**Discovered by content, not by filename.** The writer runs under the Bash tool, whose
ephemeral shell `$PPID` can never reproduce the hook's `session_key` (PPID:CWD) — the old
shared-key design meant the hook found nothing, ever (verified 2026-07-18: 0 flags consumed
across 252 `SessionStart:clear` firings in local history). The filename key is therefore
merely unique (timestamp + PID); `on-session-clear.sh` scans all `.pending-memory-restore-*`
files and matches line 3 (cwd) against its hook-input cwd.

**Line 5 says WHOSE checkpoint it is.** A cwd match establishes the directory, never the
session, and directories are reused constantly — a repository root, or a worktree path
recreated under the same name. Every later session standing there therefore matched, restored
another session's checkpoint as its own, and then consumed the flag, so the session that wrote
it could never get it back. Line 5 carries `session_key(PPID:RESOLVED CWD)` computed by the writer from
the `CLAUDE_PID` environment variable, which holds the Claude Code process id that script-local
`$PPID` cannot see. That id is stable across `/clear` because the process does not restart —
`session_id` is NOT, since `/clear` issues a fresh session id and a fresh transcript file, which
is why the id is recorded on line 1 for reading only and never compared.

The WRITER hashes the RESOLVED path (`pwd -P`), so one directory produces one key
whatever spelling reached it. Had the writer hashed the raw string, a `/tmp` versus
`/private/tmp` or trailing-slash difference would read as a different session — the
2026-08-15 cwd-mismatch defect, one layer up.

The READER computes TWO keys and accepts either: `CWD_KEY` from its raw hook cwd, and
`_MR_PHYS_KEY` from the resolved one. That acceptance set is not the writer's choice
restated, and it is not redundant: every flag already on disk was written by a build
that hashed the raw path, and those flags live for up to seven days, so dropping the
raw acceptance as a tidy-up would orphan all of them. Both keys hash the READER's own
PPID, so neither can be satisfied by a different session.

Narrowing the check to literal cwd matches is NOT an alternative to either: it lets a
resolved-path match skip the check entirely, so another session's checkpoint is
restored AND consumed — the very defect line 5 exists to close. Line 3 stays
unresolved, so the row still shows the directory the user recognises.

| line 5 | outcome |
| --- | --- |
| equal to either of the hook's two keys | this session's own: restored and consumed, as before |
| present and different, resolved key available | another session's: listed as selectable with its label, **not** restored, **not** consumed, so its own session can still claim it |
| present and different, resolved key unavailable | ownership was never checked — the hook cannot `cd` into its own recorded cwd, so only the raw key could be compared. Listed as selectable, **not** restored, and no claim is made about who owns it |
| empty | written before line 5 existed, or by a build that exports no `CLAUDE_PID`: the cwd-only rule it was written under still applies |

The writer refuses to guess: `session_key()`'s own default is `$PPID`, so passing nothing would
hash the Bash-tool shell and mint a confident-looking key no hook can ever match — strictly
worse than an empty line, because the reader would then stop falling back to line 3. A missing
or non-numeric `CLAUDE_PID`, and a machine with no usable hash command, all leave line 5 empty.
`_SMITH_PPID` overrides `CLAUDE_PID` in the writer for the same reason `session_key()` lets it
override `$PPID`: both sides of a key comparison must honour the same test override, or the
end-to-end test compares a real process against a substituted one and reads the mismatch as the
feature working.

Known limitation, not yet addressed: a checkpoint armed from a **background job** keys to that
job's own Claude Code process, so the interactive session's `/clear` sees it as another
session's flag — offered by label rather than auto-restored. Verified rather than assumed: a
background job runs as its own `claude bg-spare` process with its own pid, and the plan
pipeline's `.plan-state-*` file for such a job is keyed by that pid, not the interactive
session's.

Two consequences are deliberate, and are stated here because each reads like an oversight:

- **In the 24-hour to 7-day band, another session's flag is kept and NOT named.** It is
  reported only in the "older than 24h, left in place" count. Before line 5 existed, a
  cwd-matching flag past 24 hours was consumed and therefore had to print its label — that is
  the "the label is the only handle left" rule. Here nothing is destroyed, so the rule does
  not apply; the flag is still on disk under a name the owning session can act on.
- **The marker's 60-minute sweep never applies to the marker being read.** `inject-plan.sh`
  reads and consumes this session's marker BEFORE sweeping, so a `/clear` followed by a long
  gap still announces the restart. The sweep exists to clear OTHER sessions' abandoned
  markers, not to bound this one.

**A selectable flag is offered once per session, not once per `/clear`.** Such a flag is
never consumed — it is not this session's to destroy — so it was relisted at EVERY `/clear`
in the directory for the full 24-hour window, and the directive's "delete it after restoring"
was the only thing that ever ended the loop. Nobody deletes it, so the same rows kept
arriving; that repetition, not the restore, is what made the injection read as noise.

`on-session-clear.sh` records the flag keys it has already offered in
`~/.claude/plans/.mr-offered-<CWD_KEY>` and skips relisting them. Nothing is destroyed: the
flag stays on disk for whoever owns it, and a different session in the same directory still
gets its own first offer. Suppressed flags are reported as a count in the summary line rather
than dropped in silence. The record is appended, never rewritten, so two concurrent hooks in
one directory cannot lose each other's lines, and it is written after the rows exist — a hook
killed mid-scan records nothing and merely repeats an offer, which is far preferable to
recording an offer that was never printed. Keys are filtered through the same filename
allowlist the rows use (`^[0-9A-Za-z._-]+$`); a flag whose name fails it cannot be recorded,
so it is offered every time rather than suppressed on a key nobody can match. The record is
swept after seven days, the point at which the flag scan gives up on the flags it names.

A key is recorded where the row is actually PRINTED, never where it is classified. The display
caps the block at five rows, so a selectable row can be found by the scan and then pushed out of
the block; recording it at scan time marked it offered when the user never saw it, and the
suppression is permanent, so that checkpoint became unreachable. Recording at render time also
makes the crash behaviour the safe one: a hook killed before it prints has recorded nothing and
merely repeats the offer next time.

**Reporting contract: the hook says what it saw.** A scan that matched nothing used to emit
nothing at all, so the most common outcome was also the invisible one — which is how a
matching defect can survive indefinitely. The observation that prompted this: on one machine
on 2026-08-15, a scan of the 55 session transcripts under `~/.claude/projects/*smith*` found
the several-candidates directive had never once fired, while the single-match directive had
fired in 17 of them. Those numbers are a snapshot of one developer's local history, not a
property of the system — they are recorded here as the motivation, and cannot be reproduced
from this repository.

Whenever the scan produced at least one row, the hook prints a **candidates block**. A scan
that found only stale-kept, swept, unreadable, lost-race or already-offered flags produces no
rows and takes the one-line summary below instead. The block lists flags
fresher than 24 hours; any flag that matched but had expired, listed despite its age precisely
because consuming it destroyed the only pointer; and any flag that matched but whose age could
not be established at all, which is neither fresh nor expired and is listed because it was
neither restored nor consumed. Entries the scan refused rather than read — a flag name that is
a link or shares an inode, one it could not open or read, and a claim lost to a concurrent
hook on a matched flag — never become rows at all: they are summary-only counts, which is why
the verdict table below does not give them a priority. Two further outcomes are summary-only
for the same reason and likewise carry no priority: a selectable flag this session was already
offered at an earlier `/clear`, and an `.mr-offered-*` record that is a link or shares an inode
and so was neither read nor written. Each row carries its
label, recorded path, age, verdict, and — only where the agent may act on it — its flag key:

| priority | verdict | meaning | what the agent may do |
| --- | --- | --- | --- |
| 1 | `MATCHES this session` | the recorded path is this hook's cwd, and line 5 either agrees it is this session or is absent | restored as before, flag already consumed |
| 2 | `MATCHED but expired, consumed WITHOUT restoring` | matched, but past the 24-hour window | nothing to delete; the label is the only handle left for a manual `read_memory()` |
| 3 | `same repository, selectable` | the recorded path resolves to the same repository main working tree (`scope_key()`) | offer it to the user; delete the flag after restoring |
| 3 | `same repository, selectable, recorded in THIS directory by a DIFFERENT session` | the recorded path IS this hook's cwd, but line 5 names another session | offer it to the user; delete the flag after restoring. Never auto-restored — that is the defect line 5 exists to close |
| 3 | `same repository, selectable, recorded in THIS directory; ownership could NOT be checked, not restored` | the recorded path IS this hook's cwd, but the resolved key could not be computed, so ownership was never established | offer it to the user; delete the flag after restoring. Assert nothing about who owns it — the comparison that would have settled it did not run |
| 2 | `REMOVED as older than 7 days WITHOUT restoring: another session's flag recorded in THIS directory` | the same kind of flag, past the seven-day sweep | nothing to delete; the label is the only handle left for a manual `read_memory()`. Listed for the same reason the expired-match row is: this path destroys the pointer |
| 4 | `MATCHED but could NOT be claimed` | matched, but a filesystem error blocked the claim | nothing restored, flag still on disk; the plans directory needs attention |
| 4 | `MATCHED but its age could NOT be established` | matched, but `stat` or the clock gave no usable number, so the 24-hour window could not be applied | nothing restored, nothing consumed, flag still on disk; report the age as unknown and assert no freshness |
| 5 | `scope unverifiable, recorded path unreachable` | this session's own scope resolved, but the recorded directory could not be reached | assert nothing about it; show the path and let the user judge |
| 5 | `malformed flag, no recorded path` | the file records no path at all — truncated or hand-mangled | nothing to restore; the user may want to delete it |
| 6 | `different repository, counted only` | both sides resolved to a repository, and they differ | **counted, never printed** — the path and label belong to that project (`~/.claude/rules/client-scope.md`) |
| 6 | `outside this session's scope, counted only` | both sides resolved, but at least one is a directory inside no repository | **counted, never printed** — only the difference of scope was established, never that it belongs to another project |
| 6 | `own scope unresolvable, withheld` | this session's OWN directory could not be resolved, so no flag could be checked against it | **counted, never printed** — the flags are untouched in `PLANS_DIR`; read them there |

Verdicts 1, 2 and 4 come from the exact match; 3, 5 (`scope unverifiable`) and 6 come from
`scope_key()`. `malformed flag` comes from neither: a flag that records no path is
classified before `scope_key()` is consulted, because there is nothing to resolve.

`scope_key()` answers `repo:<repository identity>`, `dir:<physical path>` for a directory
CHECKED to be inside no repository, or the empty string for "could not determine". The
identity is the main working tree whenever the git directory is named `.git`, and the git
directory's own path otherwise — `git init --separate-git-dir` produces the second form.
Either way it is stable across a repository's worktrees, which is all the caller needs; it
is an identity to compare, not a path to hand to anyone.

Telling those three answers apart takes a filesystem fact, because git's own signals cannot
do it. `git rev-parse` exits 128 BOTH when a path is not a repository and when git started
but refused to resolve one (`safe.directory` dubious ownership, a damaged repository), and its
messages are translated, so neither the status nor the text separates them. A missing `git`
executable is a different failure again: the shell reports command-not-found and exits 127,
before git has an opinion about anything. So when git declines, a walk up for a `.git` entry
settles it — one found means a repository IS present and only the resolution failed, which is
reported as unresolved rather than claimed.
The match compares the recorded path and the hook's cwd both as raw strings and as physical
paths, so one directory under two spellings (`/tmp` versus `/private/tmp`, a symlinked home or
project tree) still matches.

Nothing in a flag file is trusted, and the scan refuses two shapes of planted content before
it can act on them. A flag NAME that is a symlink, or that shares an inode with another file,
is never read: `-f` follows a symlink, so the loop would print lines 3 and 4 of whatever it
pointed at into the session, and re-read them at every `/clear` because a non-matching flag is
never consumed. Those entries are counted and reported as carrying the flag name but being a
link or sharing an inode. Separately, a recorded PATH that begins with a dash is not resolved:
`cd` would take `-P`, `-L` or `-e` as its own option and, with no operand left, chdir to
`$HOME`, so a planted flag recording `-P` used to match whatever hook stood there and be
consumed. Every `cd` on externally-derived content passes `--`, and `scope_key()` answers the
empty string for such a path rather than naming a directory that was never resolved.

Ordering, row selection and the reserved slot are computed with shell builtins. `sort` and
`awk` were the forks in this path and each was captured unchecked, so a failure emptied the
row set or the matched-row list AFTER the matching flags had been consumed — the header
printed with no rows under it, and the labels, which are all that is left of a consumed
checkpoint, went with them.

Rows are ordered by that priority and only then by time. The destroyed-pointer verdict
outranks the selectable one deliberately: a selectable row keeps its flag and is offered again
at the next `/clear`, while a consumed row's label is the only thing left of it. That ordering
alone does NOT protect the actionable row, because it is the lower-priority one — five expired
matches used to fill the cap while the notes still told the agent to offer "those rows only".
So one of the five slots is **reserved** for the first `same repository, selectable` row
whenever priority ordering would otherwise push every one of them past the cap, and any
further selectable rows are counted. Everything withheld is counted:
rows past the cap, flags older than 24 hours left in place, flags removed by the sweep, flags
in the priority-6 withheld band, flags this hook could not read, and a claim lost to a
concurrent hook on a flag that MATCHED (the hygiene sweep's loser stays silent, since that
flag was never this session's). Destroyed pointers and selectable rows the cap could not show
are SUBSETS of the rows-past-cap count, not populations beside it, so they are reported inside
its clause — `3 more not shown, 2 of them destroyed pointers` — because printed as siblings
they invited a reader to add them and one hidden row read as two. A matched row past
the cap is the one exception, and it is not withheld at all: the ask-which-one branch lists
every matched flag in full, so it is reported as "listed in full below" rather than counted as
unseen — otherwise one message said a row was held back and then printed it. An unreadable
`PLANS_DIR` gets its own line, and the two permission bits fail differently: without the read
bit the glob cannot expand and yields its own literal pattern, while without the search bit
the names ARE visible and each entry is instead dropped one by one when it cannot be stat'd.
That second one is the quieter failure, and it is the state a directory reaches under
`chmod 600`: readable, so the names list, but not searchable, so nothing in it can be stat'd.

Outcomes: one match → the restore directive, preceded by the block; several matches → the
ask-which-one directive; **no match but at least one fresh flag → a `CHECKPOINT CANDIDATES`
block stating that nothing was restored and offering only the same-repository rows**; no fresh
flags but some stale ones → a single summary line; no flags at all → silence. `Signal` flips to
`resume` for exactly two outcomes: a fresh match that was claimed, and a `same repository,
selectable` candidate. An expired match does not, because it was consumed without restoring; an
unclaimable one does not, because until the permissions are fixed nothing can be restored here;
and a match whose age could not be established does not, because no freshness was ever
measured. A report with nothing restorable must not claim work is waiting.

**Consumption is unchanged and still keyed on the exact match.** Only matching flags are
claimed and consumed, one-shot, and only when their age was ESTABLISHED — fresh or stale. A
match whose age could not be measured is left on disk untouched, because consuming it would
destroy the pointer on a number nobody has; an unclaimable one is left because the claim itself
failed. A `same repository, selectable` flag is NOT
consumed by the hook, so the directive tells the agent to `rm` it after restoring — naming
`$PLANS_DIR`, never a hardcoded `~/.claude/plans`, because under a non-default
`CLAUDE_CONFIG_DIR` a hardcoded path makes that `rm -f` a silent no-op. Until it is deleted
the flag is re-offered at every `/clear` for the next 24 hours; after that it is only counted,
and it survives on disk until the seven-day sweep.

Age is derived once, from the file's mtime, and everything else follows from it — freshness,
the displayed age, and the sweep. An earlier design took freshness from `find -mmin`'s silence
while the displayed age came from `stat`: two measurements of the same mtime that could
disagree, and a failing `find` printed nothing, which read as "fresh". Deriving it needs
two readings — the file's mtime and the clock to subtract it from — and a failure of either
leaves the age unestablished rather than substituting a value. Such a flag is reported at
priority 4 as matched but not restored, is neither claimed nor consumed, and is still on
disk once whatever broke the reading is fixed; an earlier design substituted the current
time, which read as an age of zero and therefore as "fresh", so a flag from years back was
announced as matching, restored, and then deleted. The litter sweep described below reports
an unestablished age the same way. Non-matching flags are
otherwise left for their own session's `/clear`; the seven-day sweep claims a flag with `mv`
before removing it, so a hook that lost the race does not also count the removal.

**Stranded litter.** The same sweep covers stranded `.mr-claimed.*` and `.mr-tmp.*` files,
and reports each by what was actually established about it rather than by what its name
suggests. A `.mr-claimed.*` is the original flag, moved rather than rewritten, so it still
holds whatever the flag held — which the flag loop does not itself assume is complete,
since it has its own verdict for a flag that records no path at all. So a surviving claim file
is reported as one that SHOULD still hold a pointer, and a removed one as having taken
whatever it held with it; neither sentence asserts a pointer the sweep never read. A
`.mr-tmp.*` is only sometimes empty: `write-reload-flag.sh` writes the whole body into the
temp file and renames it afterwards, so a writer killed in that window leaves a complete
flag. The sweep therefore tests the file instead of assuming, and distinguishes verified
empty from merely not empty; not empty is never a promise that the bytes form a usable
pointer. Removal and survival are counted separately in every category, because "left in
place, delete it yourself" and "already deleted" are different instructions.

Anything under those two names that is not a plain regular file — a symlink, a directory,
a socket — is reported as having no established age and is never swept. Nothing this hook
writes is anything but a regular file, so these arrived from outside, and they cannot be
measured on their own terms: the emptiness and existence tests follow a symlink while
`stat` does not, so a link to a live file used to read as old and non-empty, be deleted
(taking only the link), and then be reported as a destroyed body while its target sat
untouched. A dangling link or a directory was left with no mention at all.

Two ages are kept separate, and neither is treated as zero. The flag scan above applies the
same rule: a reading it cannot establish is reported as an unknown age rather than replaced
by one, so such a flag is neither restored nor swept. Within the litter sweep, two
situations reach the unexamined outcome, and the report claims only what is true of both: no
age was established. A failed `stat` establishes nothing at all, not even emptiness, since the
emptiness test asks the same thing of the filesystem. A clock too far off leaves the file
perfectly readable and only the age unknown — which is why the wording says the age could not
be established rather than that the file could not be read. Neither is swept, because sweeping
needs an age, and neither is classified, so both are re-reported at every `/clear` until
someone looks.

A mtime AHEAD of the hook's clock is bounded, not blanket. `_mr_now` is sampled once,
before a per-flag scan that forks several times, so a concurrent `write-reload-flag.sh`
ordinarily lands after that sample: within the same window the in-flight guard uses,
because it is the same phenomenon, the file is treated as at most zero seconds old, takes
the in-flight exit, and is not reported, since calling it litter would report a live
writer's work in progress as wreckage. Further ahead than that is not a live writer but
a restored backup, a `cp -p` from a machine running ahead, an NFS server's clock, or a failed
`date` leaving the sampled clock at zero, which puts every real mtime out there. Those are
unexamined and reported. Reading them as in-flight instead would skip the whole sweep in
silence.

One limitation to know when the report sends you to look. The in-flight guard reads a
`.mr-claimed.*` file's mtime, which `mv` inherits from the original flag, so it measures when
the FLAG was written and never when the claim was made. A claim another session is consuming
right now therefore looks as old as its flag, and can be reported as stranded. If you go to
`PLANS_DIR` after such a report and find nothing there, that is the expected outcome of this
race and not a lost checkpoint: the other session finished consuming it.

The same race also has a removal half, and that one reads worse. A claim taken by the expiry
sweep comes from a flag already past the seven-day threshold, so the claim is over it the
moment it exists; a concurrent sweep landing in the same window removes the claim and reports
a pointer gone. A pointer reported gone this way was one its owning session was deliberately
expiring, and that session reported it correctly on its own side.

Caveat: the physical half of the match needs both directories to still exist, since it
resolves them with `pwd -P`. A flag whose recorded directory has been removed can therefore
only match on the raw string, i.e. when it was recorded under exactly the spelling the hook
receives. A checkpoint armed inside `.claude/worktrees/<name>/` behaves differently
depending on where the hook is standing, and the two outcomes are easy to conflate. Run from
that same worktree, the cwd matches exactly, so the flag MATCHES — provided line 5 agrees that
it is the same session — is auto-restored, and is consumed. Run from the main checkout,
`scope_key()` gives both locations the same repository
identity but the directories differ, so the flag is reported as `same repository, selectable`
and offered — nothing is restored and the flag survives. Once the worktree is removed the path
cannot be resolved at all, and the flag is reported as `scope unverifiable` rather than being
assigned to a repository.

```text
sess_abc123def                    <- line 1: session ID (informational)
2026-01-01T00:00:00+0900          <- line 2: ISO 8601 timestamp
/path/to/working/directory        <- line 3: CWD
my-checkpoint-label               <- line 4: optional label (names the checkpoint in the directive)
0123456789abcdef                  <- line 5: session key, or empty (see "Line 5 says WHOSE checkpoint it is")
```

`write-reload-flag.sh` prints a second line after "Wrote reload flag", either
`Discovery: by session key (line 5) …` or `Discovery: by cwd match only, no session key …`. It
reports only whether the writer recorded a session key: the verdict is decided later, by whatever
session's `/clear` scans it, so the line predicts no outcome in the verdict table above. Do not
word a checkpoint's Reload block from it.

`on-session-clear.sh` consumes flags it matched as this session's one-shot (removed whether
fresh or stale; a flag line 5 attributes to a different session is offered, never consumed),
applies a 24h freshness window, and prepends the restore directive to its output (regardless
of plan state). The write is atomic (temp file + `mv`, temp name outside the scan glob) and
`write-reload-flag.sh` exits non-zero without printing success if the directory or write fails.
Exit 0 proves only that the flag was written — only a live `/clear` showing the directive
proves the read side.

## Ralph Loop Integration

### How It Works with Ralph

```
Iteration 1:
  1. Ralph sends prompt
  2. UserPromptSubmit fires
  3. Hook reads ~/.claude/plans/my-plan.md (v1)
  4. Plan v1 injected into context
  5. Claude works on Task 1
  6. Claude updates plan file -> now v2 on disk
  7. Iteration ends

Iteration 2:
  1. Ralph sends next prompt
  2. UserPromptSubmit fires
  3. Hook reads ~/.claude/plans/my-plan.md (v2) <- UPDATED
  4. Plan v2 injected (shows Task 1 complete)
  5. Claude sees progress, works on Task 2
  6. Claude updates plan file -> now v3 on disk
  7. Iteration ends

... continues until all tasks complete ...
```

### Ralph Exit Detection

The skill outputs specific signals for Ralph to detect:

**Completion Signal:**
```
PLAN COMPLETE: All tasks finished successfully.
```

**Blocker Signal:**
```
BLOCKER: [description of issue]
```

## Trigger Phrases

| Pattern | Example |
|---------|---------|
| `execute-plan` | "Let's use execute-plan" |
| `!load-plan` | "!load-plan" or "!load-plan my-project" |
| `!plan` | "!plan" or "!plan feature-auth" |
| `!plan-status` | "!plan-status" |
| `execute the plan` | "Execute the plan now" |
| `load the plan` | "Load the plan" |
| `run the plan` | "Run the plan" |
| `start the plan` | "Start the plan" |
| `continue the plan` | "Continue the plan" |
| `resume the plan` | "Resume the plan" |

## Plan File Format

For best progress tracking, use checkbox format:

```markdown
# My Project Plan

## Objective
Build a REST API for user management

## Tasks

- [x] Task 1: Set up project structure
- [x] Task 2: Create database models
- [ ] Task 3: Implement CRUD endpoints <- CURRENT
- [ ] Task 4: Add authentication
- [ ] Task 5: Write tests
- [ ] Task 6: Documentation

## Progress Log

### Iteration 1 (2024-01-15 10:30)
- Completed: Task 1
- Notes: Using Express.js with TypeScript

### Iteration 2 (2024-01-15 10:45)
- Completed: Task 2
- Files: src/models/user.ts, src/db/schema.sql
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PLAN_CONTEXT_THRESHOLD_KB` | `500` | Transcript size threshold in KB for context warnings |

## Manual Testing

### Test flag consumption (auto-reload)

```bash
source ~/.smith/smith-plan-claude/scripts/lib-common.sh
CWD_KEY=$(session_key)   # first 16 chars of md5(PPID:CWD); matches the hook in this same shell

echo '{"prompt":"go","session_id":"test1","cwd":"'$PWD'"}' | \
  ~/.smith/smith-plan-claude/scripts/inject-plan.sh
ls "$PLANS_DIR/.pending-reload-${CWD_KEY}" 2>&1  # Should show "No such file"
```

### Test context threshold detection

```bash
dd if=/dev/zero bs=1024 count=900 of=/tmp/test-transcript.jsonl 2>/dev/null
echo '{"prompt":"hello","session_id":"test2","transcript_path":"/tmp/test-transcript.jsonl","cwd":"'$PWD'"}' | \
  ~/.smith/smith-plan-claude/scripts/inject-plan.sh
```

### Test Stop hook blocking

```bash
source ~/.smith/smith-plan-claude/scripts/lib-common.sh
CWD_KEY=$(session_key)   # first 16 chars of md5(PPID:CWD); matches the hook in this same shell
rm -f "$PLANS_DIR/.pending-reload-${CWD_KEY}"
echo '{"transcript_path":"/tmp/test-transcript.jsonl","cwd":"'$PWD'"}' | \
  ~/.smith/smith-plan-claude/scripts/enforce-clear.sh
```

### Test Stop hook allow (flag exists)

```bash
source ~/.smith/smith-plan-claude/scripts/lib-common.sh
CWD_KEY=$(session_key)   # first 16 chars of md5(PPID:CWD); matches the hook in this same shell
printf '/tmp/plan.md\ntest\n'"$(date +%Y-%m-%d)"'\n/tmp\n' > "$PLANS_DIR/.pending-reload-${CWD_KEY}"
echo '{"transcript_path":"/tmp/test-transcript.jsonl","cwd":"'$PWD'"}' | \
  ~/.smith/smith-plan-claude/scripts/enforce-clear.sh
```

### Test stale flag cleanup

```bash
source ~/.smith/smith-plan-claude/scripts/lib-common.sh
CWD_KEY=$(session_key)   # first 16 chars of md5(PPID:CWD); matches the hook in this same shell
printf '/path/plan.md\nold_session\n'"$(date +%Y-%m-%dT%H:%M:%S%z)"'\n/old/path\n' > "$PLANS_DIR/.pending-reload-${CWD_KEY}"
# Set file mtime to 2 hours ago to trigger cleanup
touch -t $(date -v-2H +%Y%m%d%H%M 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M) "$PLANS_DIR/.pending-reload-${CWD_KEY}"
echo '{"prompt":"go","session_id":"different_session","cwd":"'$PWD'"}' | \
  ~/.smith/smith-plan-claude/scripts/inject-plan.sh
ls "$PLANS_DIR/.pending-reload-${CWD_KEY}" 2>&1  # Should show "No such file"
```

## Troubleshooting

### Hook Not Firing

1. Check settings.json syntax:
   ```bash
   cat ~/.claude/settings.json | jq .
   ```

2. Verify scripts are executable:
   ```bash
   ls -la ~/.smith/smith-plan-claude/scripts/*.sh
   ```

3. Test hook manually:
   ```bash
   echo '{"prompt":"execute the plan"}' | ~/.smith/smith-plan-claude/scripts/inject-plan.sh
   ```

### Plan Not Updating Between Iterations

1. Verify Claude is writing to the correct file path
2. Check the plan file manually between iterations:
   ```bash
   cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plans/my-plan.md"
   ```

### Stale Flag File

Expired flag files (>1 hour old) are auto-cleaned. To manually clear all flags:
```bash
rm -f "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plans"/.pending-reload-*
```

### jq Not Found

Install jq:
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq
```

## Dependencies

- **bash** 4.0+
- **jq** for JSON parsing
- **Claude Code** with hooks support
- **Ralph** (optional, for autonomous loop)

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Context high, no active plan | Stop hook allows stop, no flag created |
| Context high, all tasks done | Stop hook allows stop (PENDING=0) |
| Expired flag (>1 hour) | Auto-cleaned on next hook invocation |
| User ignores /clear | Flag persists; plan loads on any prompt in same CWD |
| Multiple threshold warnings | Flag overwritten each time (idempotent) |
| Auto-load after /clear | Directive prepended: "Resume working on current task" |
| Stop hook blocks | Flag auto-created, loop breaks after one iteration |
| Fresh session with pending plan | Directive prepended: "This plan was auto-loaded in a fresh session" |
| Trigger-word load | No directive added (user's message is the instruction) |
