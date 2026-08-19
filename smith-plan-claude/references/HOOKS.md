# Hook Configuration for Plan Sync

This document explains how to configure the hooks for plan syncing, context management, and Ralph autonomous loop integration.

## Overview

Three hooks work together to manage plan execution across context boundaries:

| Hook | Event | Script | Purpose |
|------|-------|--------|---------|
| `inject-plan.sh` | UserPromptSubmit | Every prompt | Load plan, detect flags, detect context threshold |
| `enforce-clear.sh` | Stop | Agent stop | Block stop when context high + pending tasks |
| `on-plan-exit.sh` | PostToolUse (ExitPlanMode) | Plan mode exit | Create reload flag for auto-load after `/clear` |

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
    ]
  }
}
```

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

1. **Flag detection**: If `.pending-reload-<CWD_KEY>` exists (CWD-keyed, <1hr old), loads the flagged plan and deletes the flag (one-shot).

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
- One-shot: deleted after plan is loaded
- Expired flags (>1 hour old) are auto-cleaned on each hook invocation
- Legacy single `.pending-reload` file auto-cleaned (backward compatibility)

### Checkpoint memory-restore flag (separate file)

`~/.claude/plans/.pending-memory-restore-<unique id>` — written by `/smith-checkpoint` via
`write-reload-flag.sh`, read by `on-session-clear.sh`. **Deliberately separate** from
`.pending-reload`: the plan hooks (`enforce-clear.sh` writes it on every high-context Stop,
`inject-plan.sh` deletes it on the next prompt) own that file, so a non-plan flag stored there
would be clobbered/consumed before `/clear`. The plan hooks never touch this file.
The injected directive is context-only: the restore executes at the user's first prompt after
`/clear` (any prompt) — no hook event can start a model turn in an interactive session
(`initialUserMessage` is `-p`-only), so nothing visible happens at `/clear` itself.

**Discovered by content, not by key.** The writer runs under the Bash tool, whose ephemeral
shell `$PPID` can never reproduce the hook's `session_key` (PPID:CWD) — the old shared-key
design meant the hook found nothing, ever (verified 2026-07-18: 0 flags consumed across 252
`SessionStart:clear` firings in local history). The filename key is therefore merely unique
(timestamp + PID); `on-session-clear.sh` scans all `.pending-memory-restore-*` files and
matches line 3 (cwd) against its hook-input cwd.

**Reporting contract: the hook says what it saw.** A scan that matched nothing used to emit
nothing at all, so the most common outcome was also the invisible one — which is how a
matching defect can survive indefinitely. The observation that prompted this: on one machine
on 2026-08-15, a scan of the 55 session transcripts under `~/.claude/projects/*smith*` found
the several-candidates directive had never once fired, while the single-match directive had
fired in 17 of them. Those numbers are a snapshot of one developer's local history, not a
property of the system — they are recorded here as the motivation, and cannot be reproduced
from this repository.

Whenever the scan produced at least one row, the hook prints a **candidates block**. A scan
that found only stale-kept, swept, unreadable or lost-race flags produces no rows and takes
the one-line summary below instead. The block lists flags
fresher than 24 hours; any flag that matched but had expired, listed despite its age precisely
because consuming it destroyed the only pointer; and any flag that matched but whose age could
not be established at all, which is neither fresh nor expired and is listed because it was
neither restored nor consumed. Entries the scan refused rather than read — a flag name that is
a link or shares an inode, one it could not open or read, and a claim lost to a concurrent
hook on a matched flag — never become rows at all: they are summary-only counts, which is why
the verdict table below does not give them a priority. Each row carries its
label, recorded path, age, verdict, and — only where the agent may act on it — its flag key:

| priority | verdict | meaning | what the agent may do |
| --- | --- | --- | --- |
| 1 | `MATCHES this session` | the recorded path is this hook's cwd | restored as before, flag already consumed |
| 2 | `MATCHED but expired, consumed WITHOUT restoring` | matched, but past the 24-hour window | nothing to delete; the label is the only handle left for a manual `read_memory()` |
| 3 | `same repository, selectable` | the recorded path resolves to the same repository main working tree (`scope_key()`) | offer it to the user; delete the flag after restoring |
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
that same worktree, the cwd matches exactly, so the flag MATCHES, is auto-restored, and is
consumed. Run from the main checkout, `scope_key()` gives both locations the same repository
identity but the directories differ, so the flag is reported as `same repository, selectable`
and offered — nothing is restored and the flag survives. Once the worktree is removed the path
cannot be resolved at all, and the flag is reported as `scope unverifiable` rather than being
assigned to a repository.

```text
sess_abc123def                    <- line 1: session ID (informational)
2026-01-01T00:00:00+0900          <- line 2: ISO 8601 timestamp
/path/to/working/directory        <- line 3: CWD
my-checkpoint-label               <- line 4: optional label (names the checkpoint in the directive)
```

`on-session-clear.sh` consumes matched-cwd flags one-shot (removed whether fresh or stale),
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
