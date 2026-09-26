# Hooks Reference — smith-serena

Detailed behavior for the hooks whose scripts live under
`smith-serena/scripts/`. See the repo root `README.md` "Hooks" section for
the cross-skill summary table and registration overview.

## Overview

| Hook | Event (matcher) | Blocks / Advisory |
|---|---|---|
| `uv-tool-health-check.sh` | SessionStart (all sources) | Self-heals a broken `uv tool`-managed venv, reports what it did |
| `link-worktree-memories.sh` | SessionStart (all sources) | Links a worktree's Serena memories folder to the primary checkout's, reports what it did |

## uv-tool-health-check

**uv-tool-health-check** (`smith-serena/scripts/uv-tool-health-check.sh`) —
SessionStart hook (matcher `""`, all sources) that detects and self-heals a
broken `uv tool`-managed virtual environment.

**Root cause it works around**: `uv tool install` links a persistent venv to
a specific Python interpreter at install time. If that interpreter is later
upgraded or removed — a MacPorts point-upgrade, a pruned uv-managed Python
build, etc. — the venv's `bin/python3` symlink breaks and every entrypoint
fails with "bad interpreter". Verified 2026-08-27: `serena-hooks` failed
exactly this way on every `Read` call until a manual
`uv tool install serena-agent --reinstall`. This is an acknowledged,
closed-as-not-planned upstream limitation, not something `uv` will fix:
[astral-sh/uv#8514](https://github.com/astral-sh/uv/issues/8514) ("Tools
break (understandably) after upgrading system Python" — a user's proposed
`uv tool reinstall-all` was rejected as a duplicate),
[astral-sh/uv#7634](https://github.com/astral-sh/uv/issues/7634) ("uv tool
shouldn't use Python from homebrew version directories" — the same failure
class as this repo's MacPorts `Python.framework/Versions/3.12` path),
[astral-sh/uv#7651](https://github.com/astral-sh/uv/issues/7651),
[astral-sh/uv#8028](https://github.com/astral-sh/uv/issues/8028).

**Detection**: runs `uv tool list`, whose stderr prints a
`Broken symlink at \`.../tools/<name>/bin/python3\`` warning per broken tool
(exit code stays 0 either way — the warning is the only signal). Matches
that path against a small, deliberately narrow allowlist,
`MONITORED_TOOLS` (currently just `serena-agent`) — the tools this repo
actually depends on functioning, not every `uv tool` on the machine.
Broadening that list is a reviewed change, not something this hook should
decide unilaterally.

**Action**: for each monitored tool found broken, runs
`uv tool install <name> --reinstall` — the exact recovery command `uv`
itself prints in the warning's hint. Reports what happened via
`additionalContext`/`systemMessage`: which tools were healed, and — never
silently — which ones FAILED to reinstall (with the manual recovery command
to run by hand). Silent (no output) when nothing is broken, when `uv` isn't
installed, or when only a non-monitored tool is broken.

**Known limitation, accepted**: only guards the tools named in
`MONITORED_TOOLS`. A broken `ruff`/`headroom-ai`/etc. tool venv is not this
hook's concern (surfaces only via `uv tool list`'s own stderr warning, same
as before this hook existed).

Test suite: `smith-serena/scripts/tests/uv-tool-health-check.test.sh` (5
cases, using a fake `uv` on `PATH` to deterministically simulate healthy,
broken-and-healed, broken-and-failed, non-monitored-tool-broken, and
`uv`-not-installed states), run via `smith-serena/scripts/tests/run-all.sh`.

## link-worktree-memories

**link-worktree-memories** (`smith-serena/scripts/link-worktree-memories.sh`)
— SessionStart hook (matcher `""`, all sources) that lets Serena memory tools
in a linked git worktree reach the primary checkout's memories.

**Problem it fixes**: Serena started with `--project-from-cwd` resolves the
nearest `.serena/project.yml` or `.git`, so a session started inside a worktree
activates the worktree as its own project, with its own empty
`.serena/memories/`. A checkpoint that `/smith-checkpoint` wrote to
`<primary>/.serena/memories` is then invisible to MCP `read_memory`
(`FileNotFoundError`), and `write_memory` strands new memories in the worktree.
There is no `activate_project` in that mode.

**Mechanism**: replaces a missing or empty `<worktree>/.serena/memories` with a
symlink to `<primary>/.serena/memories`. A worktree is detected by its
`--git-dir` differing from its `--git-common-dir`; the primary is the first
entry of `git worktree list --porcelain`, so worktrees outside the repository
tree are covered too. The chain is kept: when the primary's `memories` is itself a
symlink to a folder outside the repository, the worktree points at the
primary's path, not at the resolved target. Serena 1.7.0 supports memories
reached through a directory symlink: listing uses `os.walk(followlinks=True)`
and its containment check is lexical (`serena/memories/memory_manager.py`).

**Leaves alone**: the primary checkout, non-git directories, a primary without
`.serena/memories`, a worktree folder that already resolves to the primary's
(silent), an existing correct link (silent), a symlink to anywhere else, a
regular file at that path, and a non-empty worktree folder. Those last three,
and any failed `rmdir` or `ln`, print a warning to both the model
(`additionalContext`) and the user (`systemMessage`); worktree-local memories
must first move to the primary (`/smith-checkpoint` relocates them).

**Why a SessionStart hook**: probed with Claude Code 2.1.282 on 2026-09-26:
- `.worktreeinclude` copies regular files but skips directory symlinks, so it
  cannot carry the link.
- A `WorktreeCreate` hook would replace Claude Code's worktree creation
  entirely.
- A mid-session `EnterWorktree` keeps the Serena MCP server on its launch
  project, so only a session that STARTS inside a worktree needs the fix, and
  that is what SessionStart covers, whoever created the worktree.

**Removal**: `git worktree remove` deletes the link, never the primary's files
(covered by the test).

**Tests**: `smith-serena/scripts/tests/link-worktree-memories.test.sh`, run by
`tests/run-all.sh`.
