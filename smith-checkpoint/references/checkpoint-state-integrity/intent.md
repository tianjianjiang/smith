# Intent: Never lose or misplace checkpoint state

Author: Mike Tian-Jian Jiang (a.k.a. Chiang, Tien Chien). Status: accepted.

## Problem

A `/smith-checkpoint` run can leave its state somewhere the next session
cannot find, or lose it outright, in five ways (all measured 2026-09-16 on
the author's machine):

0. **The Basic-Memory store is chosen by process environment, not by
   configuration.** Four separate Basic-Memory config directories exist
   (`~/.basic-memory`, `~/.basic-memory-{smith,sat,elu}`), selected through
   `BASIC_MEMORY_CONFIG_DIR`/`BASIC_MEMORY_HOME`. Any process that inherits
   those variables from another shell writes to the wrong store; on
   2026-09-06 a background daemon started from a shell exporting one
   client's store routed a personal session's notes there. The separation
   the four directories were meant to give does not exist either: the
   personal store's `main` project root is `~/basic-memory`, an ancestor of
   the three other project folders, so 551 of its 807 indexed entities are
   other projects' notes. `write-checkpoint.sh` reads none of this; it
   calls `uvx basic-memory` and lands wherever the environment points.
1. **A checkpoint taken inside a git worktree does not tell the resuming
   model which worktree to re-enter.** The entry header carries only
   timestamp, plan, and session; branch and worktree appear only in the
   no-body fallback. 21 real reload flags are pending, 6 with a worktree
   cwd, 0 consumed.
2. **Serena memories written by MCP from a worktree session land in
   `<worktree>/.serena/memories/`** and vanish with the worktree. One smith
   worktree currently holds 3 stranded memories.
3. **The Reload block does not say where the writes went.** It prints a
   label and a project basename, not paths, so a session whose MCP server is
   bound to a different Serena project than the script wrote to cannot tell.
4. **The test suite writes reload flags into the real
   `~/.claude/plans`.** 864 of 885 pending flags are `test_label_*` from
   2026-09-10 test runs; `on-session-clear.sh` scans all of them on every
   `/clear`.

## Proposed outcome

- One Basic-Memory config (`~/.basic-memory/config.json`) holding four
  projects with disjoint paths: `main` -> `~/basic-memory/main` (personal
  notes moved in), `smith`, `sat`, `elu` unchanged under
  `~/basic-memory/projects/<name>`. No `BASIC_MEMORY_CONFIG_DIR` anywhere.
- A repository names its project with `basicMemory.primaryProject` in
  `.claude/settings.local.json` (the key the official Basic-Memory Claude
  Code plugin defines; smith reads it with `jq` and does not depend on the
  plugin). Unset means `default_project` (`main`). A launcher that must
  confine a whole profile to one project exports
  `BASIC_MEMORY_MCP_PROJECT=<name>`, which locks MCP, CLI, and background
  sync alike.
- `write-checkpoint.sh` passes `--project <primaryProject>` when set, writes
  a header that names the worktree, branch, primary checkout, and the exact
  `EnterWorktree` step to resume, relocates any worktree-local Serena
  memories into the primary checkout before writing, prints every backend's
  absolute location in the Reload block, accepts `serena=<abs-dir>` to
  target another Serena project, and its tests run under an isolated
  `CLAUDE_CONFIG_DIR`.

## Affected users and systems

- `smith-checkpoint` (`SKILL.md`, `scripts/write-checkpoint.sh`,
  `scripts/tests/write-checkpoint.test.sh`), used by every session that
  runs `/smith-checkpoint` manually or through `enforce-clear.sh`.
- `smith-ctx-claude/scripts/on-session-clear.sh` (reader of the reload
  flags; behavior unchanged, only fewer flags to scan).
- The author's Basic-Memory data (four config directories, the
  `~/basic-memory` tree, 807 + 184 + 675 + 130 indexed entities), the
  per-repository `.claude/settings.local.json` files, and one profile
  launcher script that currently export the store variables. These live
  outside this repository; the migration is a documented manual runbook
  (`plan.md`, "Order of work" step 0), not code in this change.

## Constraints

- No client, company, or ticket identifiers in any committed file (public
  repository; enforced by the local leak guard).
- The reload flag stays reload-only; the reader is not changed. The
  checkpoint memory carries the worktree switch instruction.
- Worktree Serena memories are moved, never merged: a same-named,
  different-content file in the primary checkout is never overwritten.
- A failure before the first backend write leaves every backend untouched;
  a Serena failure never proceeds to Basic-Memory (existing invariant).
- Fewest external dependencies: the Basic-Memory Claude Code plugin is not
  required; only the `basic-memory` CLI (via `uvx`) and `jq`.
- Deleting the 864 stale test flags, the three retired config directories,
  and the stranded worktree memories after relocation are separate manual
  steps needing their own explicit approval.

## Open questions

None outstanding. Resolved with the author on 2026-09-16 and 2026-09-17:
store selection is a configuration question, not a client-folder question;
the store restructure is a prerequisite inside this intent; project layout
and the `primaryProject` convention as above; the plugin is not a
dependency.
