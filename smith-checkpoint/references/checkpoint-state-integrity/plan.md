# Plan: Checkpoint state integrity (from intent.md 2026-09-17)

Locators below refer to `main` at 91d9dd7 (last `smith-checkpoint` change
#269) and are the *before* state.

## Files that change

New:
- `smith-checkpoint/references/checkpoint-state-integrity/intent.md`,
  `spec.md`, `plan.md` (this chain).

Modified:
- `smith-checkpoint/scripts/write-checkpoint.sh` (401 lines):
  - `extract_arg` `:8-17` — quote the loop so a value with spaces survives;
    new key `serena=`.
  - new `resolve_worktree` beside `resolve_primary_checkout` `:59-65` (§S3).
  - new `resolve_bm_project`: read `.basicMemory.primaryProject` from
    `<primary>/.claude/settings.local.json` then `settings.json` with
    `jq -r`; apply §S2 (`BASIC_MEMORY_CONFIG_DIR`/`HOME` set → exit 1;
    `BASIC_MEMORY_MCP_PROJECT` vs `primaryProject` conflict → exit 1; lock
    alone → no `--project`, report the lock).
  - new `resolve_serena_project` (§S5) replacing the bare primary-checkout
    argument at `:212` and `:233`; absolute path; divergence warning.
  - new `relocate_worktree_memories` (§S4), called before `write_to_serena`
    `:377`.
  - `generate_entry` `:129-149`: after `**Session**` `:146` add `**Git**`
    (moved from `git_state_line` `:93-99`; its call in
    `generate_fallback_body` `:111` is dropped) and, in a worktree,
    `**Worktree**`, `**Branch**`, `**Primary**`, `**Resume**` (§S3).
  - `uvx basic-memory tool read-note` `:240` and `write-note` `:288-294`:
    append `--project "$bm_project"` when non-empty (§S0/§S1); folder logic
    `:259-286` (#267) unchanged.
  - `generate_reload_block` `:297-328` and `report_success` `:330-341`:
    absolute Serena path, `project:` and `folder:`, worktree line,
    relocation counts, reload-flag path captured from `write_reload_flag`
    `:50` (the sibling prints `Wrote reload flag: <path>` at
    `write-reload-flag.sh:105`) (§S6).
  - `main` `:355-399`: order becomes jq check → args → §S2 environment
    check → primary/worktree → Basic-Memory project → Serena project →
    relocate → entry → Serena → Basic-Memory → flag → report (§S7).
- `smith-checkpoint/scripts/tests/write-checkpoint.test.sh` (429 lines,
  34 scenarios):
  - top: `export CLAUDE_CONFIG_DIR="$SHIM/claude-home"`, `unset` the three
    `BASIC_MEMORY_*` variables, record the `~/.claude/plans` flag count and
    assert it unchanged before the final `PASS` line `:429` (§S8). The two
    inline `CLAUDE_CONFIG_DIR="$CTX_HOME"` cases `:352-362` keep their value.
  - the shim `:9-94` already records argv; assertions on `--project` added.
  - new helper `make_repo_with_worktree` reusing the `git init` pattern
    `:254-257`.
  - new scenarios T1–T10 (below); the worktree scenario `:258-261` updates
    its Reload-block assertion to the absolute Serena path.
- `smith-checkpoint/SKILL.md` (276 lines):
  - `:5` `argument-hint: "[label] [plan=path] [body=path] [serena=path]"`.
  - Procedure step 5 `:191-211`: Related lists Serena memories by their
    post-relocation names (the script prints them).
  - step 7 `:218-234`: project selection (§S1/§S2), worktree header and
    Resume line, relocation, absolute-location Reload block.
  - Runtime prerequisites `:239-276`: new bullet "Backend selection".
  - Targets and formats `:66-127`: a Serena project is never auto-created.
- Doc drift found in the earlier census (`smith-ctx-claude/SKILL.md:66`,
  `REFERENCE.md:372,413`, `skill-triggers.json:37`) — separate change per
  the recorded decision; not touched here.

## Order of work

0. **Basic-Memory migration runbook** (manual, outside the repository, run
   by the author with no `BASIC_MEMORY_*` variables exported; each step
   reversible until step 7). Measured 2026-09-17: the notes tree is a git
   repository with zero commits, so plain `mv` is used.
   1. Stop every Basic-Memory MCP server and Claude session (they hold
      `memory.db`).
   2. Back up `~/.basic-memory` and the three sibling config directories;
      `tar` the notes tree.
   3. Move files: the notes-root entries (22) into `~/basic-memory/main/`,
      merging the four folders that already exist there (`claude-memory`,
      `context`, `guidance`, `profile`; no file-level collisions); the
      client content nested under `main/` back to its project folder
      (`main/projects/sat` 15 files → `projects/sat/`; `main/projects/elu`
      and `main/elu` → `projects/elu/`); the strays under `projects/`
      (`stoiquent`, `mcbopomofo`, one loose file → `main/projects/`; `paas`
      → `projects/sat/`; `elu-screen-analysis` → `projects/elu/`). Remove
      emptied directories.
   4. `bm project move main ~/basic-memory/main` (config + DB path only;
      `cli/commands/project.py:991`).
   5. `bm project add smith ~/basic-memory/projects/smith`, likewise `sat`
      and `elu` (`bm project add {name} [path]`, verified in 0.22.1).
   6. `bm reindex --full` (`cli/commands/db.py:278-286`); verify per-project
      entity counts with `sqlite3 ~/.basic-memory/memory.db` (expected
      about main 256, smith 94, sat 332, elu 131) and that `main` holds no
      `projects/<other>` rows beyond the strays moved in step 3.
   7. Switch the consumers: in each pinned repository's
      `.claude/settings.local.json` replace the `env` block with
      `"basicMemory": {"primaryProject": "<name>"}` (`smith` here; `sat`
      for the client repository and its six siblings); in the profile
      launcher replace the two exports with
      `export BASIC_MEMORY_MCP_PROJECT=elu` (`SERENA_HOME` stays).
   8. Restart one session per profile; `env | grep BASIC_MEMORY` shows only
      `BASIC_MEMORY_NO_PROMOS` (personal) or `BASIC_MEMORY_MCP_PROJECT=elu`;
      a personal-session `search_notes` returns no `sat`/`elu` hits; one
      `/smith-checkpoint` per project succeeds.
   9. Retiring the three old config directories is a separate delete
      needing its own explicit approval.
1. Branch and worktree before the first edit (`@smith-git`).
2. Commit the three reference artifacts.
3. Tests first (`@smith-tests`): add T1–T10, run, watch them fail.
4. Script: §S2 environment check + `resolve_bm_project` + `--project`
   (T1–T4) → `resolve_worktree` + header (T5) →
   `relocate_worktree_memories` (T6) → `resolve_serena_project` + `serena=`
   (T7–T8) → Reload block (T9) → test isolation (T10).
5. `SKILL.md` edits.
6. `shellcheck` both scripts; full test run; leak-guard hooks on every
   commit (§S9).
7. Manual proof after the runbook: one real checkpoint from the
   implementation worktree.

Test scenarios (shim environment; `$R` = fake repository,
`$W` = `$R/.claude/worktrees/wt`):

| # | Setup | Expect |
|---|---|---|
| T1 | `BASIC_MEMORY_CONFIG_DIR=/x` | exit 1; stderr names variable, value, three sources; no `*_read.argv` |
| T2 | `BASIC_MEMORY_MCP_PROJECT=elu`, `primaryProject smith` | exit 1; conflict message; no argv |
| T3 | `BASIC_MEMORY_MCP_PROJECT=elu`, no `primaryProject` | exit 0; no `--project` in `bm.argv`; Reload block `project: elu (locked by BASIC_MEMORY_MCP_PROJECT)` |
| T4 | local `primaryProject smith`, shared `other` | `bm_read.argv` and `bm.argv` contain `--project smith`; no key at all → no `--project`, `project: (default)` |
| T5 | worktree `$W`, body given | header has `**Git**`, `**Worktree**`, `**Branch**: wt`, `**Primary**`, `**Resume**: EnterWorktree path=$W …`; `serena.argv` project = `$R`; plain repository → `**Git**` only |
| T6 | `$W/.serena/memories/{a,b,c}.md`; primary has identical `b`, different `c` | primary: a, b, c unchanged, `c__from_worktree_wt.md`; worktree memories empty of a/b/c; `project.yml` intact; 3 stderr lines; Reload `moved 1, removed 1, renamed 1`; primary without `.serena/memories/` → warning, nothing moved |
| T7 | `serena=$D` without `project.yml` / with | exit 1 before argv / `serena.argv` contains `$D`, Reload `Serena: $D/.serena/memories/<label>.md` |
| T8 | `$PWD/.serena/project.yml` exists, primary ≠ `$PWD` | divergence warning names both; with `serena=$PWD` no warning |
| T9 | success from `$W` | Reload lines: `- Serena: $R/.serena/memories/<label>.md`, `- Basic-Memory: <permalink> (project: smith, folder: …)`, `- Worktree: $W (branch wt) — resume with EnterWorktree path=$W`, `- Reload flag: <path>` |
| T10 | whole file | `~/.claude/plans` flag count unchanged; all suite flags under `$SHIM/claude-home/plans` |

## Risks

- Relocation moves files on disk before any backend write; a crash
  mid-loop leaves a half-moved set. Per-file `mv` is atomic on one
  filesystem, every file is logged, and the primary is never overwritten.
- `--project` on a name absent from the config fails hard ("not found in
  configuration", `project_service.py:526`): expected after the runbook;
  before it, the tests only ever hit the shim.
- Public repository: every message string, fixture, and doc line must avoid
  client, company, and ticket identifiers (§S9; the leak guard blocks the
  commit otherwise).
- The `extract_arg` quoting fix changes behaviour for values containing
  spaces; the existing 34 scenarios are the regression net.
- The runbook is manual and outside git; its backup step is the rollback.

## Proof

1. `bash smith-checkpoint/scripts/tests/write-checkpoint.test.sh` →
   `PASS: write-checkpoint` with T1–T10 added.
2. `shellcheck smith-checkpoint/scripts/write-checkpoint.sh
   smith-checkpoint/scripts/tests/write-checkpoint.test.sh`.
3. `bash local-guard-secret/test.sh` and a real commit through the
   pre-commit and commit-msg hooks.
4. After the runbook: from the implementation worktree, `/smith-checkpoint`
   → the entry in the primary checkout's `.serena/memories/<label>.md` has
   the Worktree and Resume lines; the real Basic-Memory call used
   `--project smith`; `sqlite3 ~/.basic-memory/memory.db` shows the note
   under project `smith`; an unrelated worktree's `.serena/memories/` is
   untouched.
5. Re-read `intent.md` items 0–4 against §S0–§S9 and T1–T10: each item has
   at least one section and one test.
