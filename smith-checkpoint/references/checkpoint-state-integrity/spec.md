# Checkpoint state integrity — Spec (the contract)

> The *why* lives in `intent.md`; the procedure in `smith-checkpoint/SKILL.md`.
> Sections §S0-§S2 describe the Basic-Memory layout the script assumes; the
> migration that produces it is a manual runbook (`plan.md`, "Order of work"
> step 0), not code in this repository.

## §S0 one-config-many-projects

**EARS (Easy Approach to Requirements Syntax)**: The system shall select a
Basic-Memory *project* by name inside one config directory
(`~/.basic-memory/config.json`) and shall never
choose, set, or compare a config directory.

**GWT (Given-When-Then)**:
- Given one `config.json` listing projects `main`, `smith`, `sat`, `elu`
  with pairwise-disjoint `path` values
- When `write-checkpoint.sh` runs in any repository
- Then every `uvx basic-memory` call it makes carries at most a `--project
  <name>` argument, and the script contains no reference to
  `BASIC_MEMORY_CONFIG_DIR` or `BASIC_MEMORY_HOME` other than the check in
  §S2

## §S1 project-from-settings

**EARS**: When the primary checkout (parent of `git rev-parse
--git-common-dir`; `$PWD` outside git) contains
`.claude/settings.local.json` or `.claude/settings.json` with a non-empty
`.basicMemory.primaryProject`, the system shall pass `--project <value>` to
every Basic-Memory read and write unless `BASIC_MEMORY_MCP_PROJECT` is set
(§S2); the local file wins over the shared file; when neither sets it, the
system shall pass no `--project` argument.
If a settings file exists but cannot be parsed, or its `primaryProject` is
not a string, the system shall exit 1 naming the file before any backend
call.

**GWT**:
- Given a worktree of a repository whose primary checkout has
  `settings.local.json` with `primaryProject: "smith"` and `settings.json`
  with `primaryProject: "other"`
- When the script runs from the worktree
- Then `bm_read.argv` and `bm.argv` (the `uvx` shim's recordings) both
  contain `--project smith`
- Given a repository with neither key
- When the script runs
- Then no `--project` argument is passed and the Reload block reports
  `project: (default)`

## §S2 environment-lock-and-retired-variables

**EARS**: If `BASIC_MEMORY_CONFIG_DIR` or `BASIC_MEMORY_HOME` is set, the
system shall exit 1 before any backend call, naming the variable, its
value, and the three possible sources (a repository `settings.local.json`
not yet migrated, a profile launcher not yet migrated, a stale shell
export). If `BASIC_MEMORY_MCP_PROJECT` is set and the repository's
`primaryProject` is set to a different name, the system shall exit 1
naming the conflict. Where `BASIC_MEMORY_MCP_PROJECT` is set and
`primaryProject` is unset, the system shall pass no `--project` and shall
report the locked name.

Rationale (verified 2026-09-17, basic-memory 0.22.1): the resolver honours
the environment lock before any explicit `--project`
(`project_resolver.py:61-67`), so passing one would make every report lie
about the destination; a retired config-directory variable pointing at a
deleted directory makes `config.py:744-748` silently create a fresh store,
and one pointing at a surviving old directory makes `--project <name>`
fail with "not found in configuration" (`project_service.py:526`).

**GWT**:
- Given `BASIC_MEMORY_CONFIG_DIR=/x` in the environment
- When the script runs
- Then exit 1, stderr names `BASIC_MEMORY_CONFIG_DIR=/x` and the three
  sources, and no `serena_read.argv` or `bm_read.argv` exists
- Given `BASIC_MEMORY_MCP_PROJECT=elu` and a repository whose
  `primaryProject` is `smith`
- When the script runs
- Then exit 1, stderr says the environment lock `elu` conflicts with
  `primaryProject smith` (wrong profile for this repository), no backend argv
- Given `BASIC_MEMORY_MCP_PROJECT=elu` and a repository with no
  `primaryProject`
- When the script runs
- Then no `--project` is passed and the Reload block reports
  `project: elu (locked by BASIC_MEMORY_MCP_PROJECT)`

## §S3 worktree-header-and-resume

**EARS**: When the checkpoint runs inside a linked git worktree
(`git rev-parse --git-dir` differs from `--git-common-dir`), the entry
header shall contain `**Worktree**`, `**Branch**`, `**Primary**` lines with
absolute paths and a `**Resume**` line reading `EnterWorktree
path=<worktree-abs> before any file edit`; in a plain checkout the header
shall contain `**Git**: <branch> @ <short-sha>, <n> uncommitted file(s)`
and no worktree lines; outside git, neither.

**GWT**:
- Given `.claude/worktrees/wt` on branch `wt` of a repository at `$R`
- When a checkpoint with a body is written from `$R/.claude/worktrees/wt`
- Then the Serena memory content contains `**Worktree**: \`$R/.claude/worktrees/wt\``,
  `**Branch**: wt`, `**Primary**: \`$R\``, and `**Resume**: EnterWorktree path=$R/.claude/worktrees/wt before any file edit`,
  and the Serena CLI call names `$R` as the project (existing #220 invariant)
- Given a plain checkout
- When a checkpoint is written
- Then the header has `**Git**` and none of the four worktree lines

## §S4 relocate-worktree-serena-memories

**EARS**: While the checkpoint runs inside a linked worktree whose
`.serena/memories/` contains `*.md` files and the primary checkout has
`.serena/project.yml`, the system shall, before any backend write (creating
`.serena/memories/` in the primary checkout if absent),
move each file to the primary checkout (`mv` when absent there; `rm` the
worktree copy when byte-identical; `mv` as
`<name>__from_worktree_<worktree-basename>.md` when different, choosing the
first unused `_2`, `_3`, … suffix when that name is taken), printing
one stderr line per file and a count line in the Reload block; it shall
never overwrite any file in the primary checkout, shall exit 1 when a
comparison itself fails, never touch `project.yml`, `cache/`, or
non-`.md` files, and shall skip everything with a warning when the primary
checkout has no `.serena/project.yml`. While the worktree's
`.serena/memories/` resolves to the same physical directory as the primary
checkout's (a symlinked `memories/` or a symlinked `.serena/`), the system
shall move, remove and rename nothing and print no relocation line.

The remaining rules apply only while the worktree's `.serena/memories/`
contains `*.md` files and the primary checkout has `.serena/project.yml`;
without either, the earlier rules return first. If the primary checkout's
`.serena/memories` is a symbolic link whose target does not exist, exists
without being a directory, or cannot be created, the system shall exit 1
before any backend write, naming the path and stating that the worktree
memories were left in place and no backend was written. The first two of
these are checked before the worktree's own directory is examined, so they
stop the run whatever that directory resolves to. While the worktree's
`.serena/memories/` resolves to any directory other than
`<worktree>/.serena/memories` itself and other than the primary checkout's
(a link leading outside the worktree, or to another directory inside it),
the system shall move, remove and rename nothing, print one warning naming
the resolved directory, and still write the checkpoint. If that directory
cannot be resolved to a physical path the system shall do the same, with a
warning that says so instead of naming a directory.

**GWT**:
- Given worktree memories `a.md`, `b.md`, `c.md`; primary has `b.md`
  identical and `c.md` different
- When the script runs
- Then primary holds `a.md`, `b.md` (unchanged bytes), `c.md` (unchanged
  bytes), `c__from_worktree_wt.md`; the worktree memories directory holds
  none of `a/b/c`; its `project.yml` is intact; stderr has three per-file
  lines; the Reload block has `Relocated worktree memories: moved 1,
  removed 1, renamed 1`
- Given the primary checkout has no `.serena/project.yml`
- When the script runs
- Then no file moves and stderr has `Warning: primary checkout <abs> is not
  a Serena project; <n> worktree memories left in place`
- Given the primary checkout has `.serena/project.yml` but no
  `.serena/memories/` directory
- When the script runs
- Then the directory is created and the worktree memories are moved into it
- Given the primary holds `keep.md` and `other.md`, and the worktree's
  `.serena/memories` (or its whole `.serena`) is a symlink to the primary's
- When the script runs from the worktree
- Then both files keep their bytes, the symlink stays, stderr has no
  per-file relocation line, and the Reload block has no `Relocated worktree
  memories` line
- Given the worktree's `.serena/memories` (or its whole `.serena`) is a
  symlink to a directory that holds `ext.md` and is neither the worktree's
  own `.serena/memories` nor the primary's: one outside the worktree, one in
  a sibling worktree whose name starts with this worktree's name, or one
  elsewhere inside this worktree
- When the script runs from the worktree
- Then `ext.md` stays where it is, the primary gains no `ext.md`, stderr has
  `resolves to <resolved-abs>, which is not the memories directory of
  worktree <worktree-abs>; 1 memories left in place, not relocated`, and
  both backends are written
- Given the primary's `.serena/memories` is a symlink to a missing directory
  and the worktree holds `s.md`, in its own directory or in one linked from
  outside the worktree
- When the script runs from the worktree
- Then it exits 1, stderr names the missing target and ends with `no backend
  was written.`, `s.md` stays where it was, the symlink stays, and no
  backend is called
- Given the primary's `.serena/memories` is a symlink to a missing directory
  and the worktree's `.serena/memories` holds no `*.md` file
- When the script runs from the worktree
- Then it exits 0 and both backends are written
- Given the primary's `.serena/memories` is a regular file, or its `.serena`
  directory is not writable, and the worktree holds `s.md`
- When the script runs from the worktree
- Then it exits 1, stderr has `exists and is not a directory` or `could not
  create` with the path, ends with `no backend was written.`, `s.md` stays
  in the worktree, and no backend is called

## §S5 serena-project-resolution

**EARS**: The system shall pass the Serena project to the CLI as an
absolute path: `serena=<abs-dir>` when given and it contains
`.serena/project.yml`, else the primary checkout, else no project argument
(outside git the Serena CLI's own default applies). If `serena=` names a
directory without `.serena/project.yml` the system shall exit 1 before any
backend call. When `serena=` is not given and `$PWD` is itself a Serena
project different from the chosen one, the system shall print a divergence
warning naming both paths.

**GWT**:
- Given `serena=$D` where `$D/.serena/project.yml` is missing
- When the script runs
- Then exit 1, stderr `Error: serena=$D is not a Serena project`, and no
  `serena_read.argv` or `bm_read.argv` exists
- Given `$PWD/.serena/project.yml` exists and the primary checkout is a
  different directory
- When the script runs without `serena=`
- Then stderr contains `Warning: cwd <PWD> is itself a Serena project; this
  checkpoint is written to <primary> ... pass serena=<PWD>`

## §S6 reload-block-absolute-locations

**EARS**: The system shall end stdout with a Reload block listing the
Serena memory file's absolute path, the Basic-Memory permalink with
project and folder, the plan path when set, the worktree line when in a
worktree, the relocation counts when any, and the reload flag path when
written; `report_success` on stderr shall name the same Serena path and
project.

**GWT**:
- Given a successful run from a worktree with `primaryProject smith`
- When the script finishes
- Then stdout contains lines `- Serena: <primary>/.serena/memories/<label>.md`,
  `- Basic-Memory: <permalink> (project: smith, folder: <folder>)`,
  `- Worktree: <abs> (branch <b>) — resume with EnterWorktree path=<abs>`,
  `- Reload flag: <path>`

## §S7 write-order-invariant

**EARS**: The system shall perform argument validation, project
resolution, and worktree-memory relocation before the first backend
call; a failure before that call shall leave both backends untouched, and
a Serena write failure shall never proceed to Basic-Memory.

**GWT**:
- Given any exit-1 condition in §S2, §S4, §S5
- When the script exits
- Then no `serena_read.argv`, `serena.argv`, `bm_read.argv`, or `bm.argv`
  exists (existing `write-checkpoint.test.sh:141-143` invariant retained)

## §S8 test-isolation

**EARS**: The test suite shall export `CLAUDE_CONFIG_DIR` to a temporary
directory before the first test and shall assert at its end that no
`.pending-memory-restore-*` file under `$HOME/.claude/plans` records a
working directory of this suite run, and that at least one of the suite's
own flags does record one.

**GWT**:
- Given any number of flag files in `$HOME/.claude/plans`, changing or not
  during the run
- When the whole suite runs
- Then none of them names the suite's temporary directory, the temporary
  `CLAUDE_CONFIG_DIR` holds at least one flag, and at least one flag there
  names it

## §S9 no-client-identifiers

**EARS**: The system (script, tests, SKILL.md, references) shall contain
no client, company, ticket, or client-folder identifier as defined by the
local leak guard's denylist (Basic-Memory project names are not in it); the local leak
guard (`local-guard-secret`) is the check.

**GWT**:
- Given the staged diff of this change
- When the pre-commit and commit-msg hooks run
- Then both pass
