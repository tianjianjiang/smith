# Hooks Reference — smith-serena

Detailed behavior for the hooks whose scripts live under
`smith-serena/scripts/`. See the repo root `README.md` "Hooks" section for
the cross-skill summary table and registration overview.

## Overview

| Hook | Event (matcher) | Blocks / Advisory |
|---|---|---|
| `uv-tool-health-check.sh` | SessionStart (all sources) | Self-heals a broken `uv tool`-managed venv, reports what it did |
| `link-worktree-memories.sh` | SessionStart (all sources) | Links a worktree's Serena memories folder to the primary checkout's, reports what it did |
| `worktree-path-guard.mjs` | PreToolUse (`mcp__(plugin_serena_)?serena__.*`) | Blocks a Serena call whose path lands in the checkout Serena is rooted in while the session works in another, names the corrected path |

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

## worktree-path-guard

**worktree-path-guard** (`smith-serena/scripts/worktree-path-guard.mjs`) —
PreToolUse hook (matcher `mcp__(plugin_serena_)?serena__.*`) that keeps Serena
calls inside the checkout the session works in when Serena is rooted in
another one, typically after a mid-session `EnterWorktree`.

**Problem it fixes**: Serena started with `--project-from-cwd` fixes its
project root once, at server start, and the `claude-code` context sets
`single_project: true`, which removes `activate_project` (Serena 1.7.0,
`resources/config/contexts/claude-code.yml`). After `EnterWorktree` the session
works in `<primary>/.claude/worktrees/<name>/` while Serena still joins every
`relative_path` onto `<primary>`, so `replace_content` with an unprefixed path
silently edits the primary checkout. Upstream treats this as a Claude Code
limitation (https://github.com/oraios/serena/issues/1496, closed 2026-08-12).

**Principle**: a worktree belongs to the same Serena project as its primary
checkout. No second project is registered and no custom context is used. The
worktree lies inside the project root, so `<prefix>/<file>` reaches it, where
`<prefix>` is the worktree's path relative to the root, for example
`.claude/worktrees/<name>`.

**Serena's root**: the hook payload carries no Serena state.
`CLAUDE_PROJECT_DIR` stays at the launch directory after `EnterWorktree` while
the payload's `cwd` follows Claude into the worktree
(https://code.claude.com/docs/en/hooks, retrieved 2026-09-28), so
`smith-git/scripts/lib/serena-root.mjs` repeats Serena's `find_project_root`
walk from `CLAUDE_PROJECT_DIR`: the nearest ancestor holding
`.serena/project.yml` or `.git`. The hook acts when that root and `cwd` lie in
different checkouts (the primary checkout or a linked worktree) of one
repository, in either direction. Paths are compared after resolving symlinks
and letter case, and a `relative_path` is judged as given, without trimming.

The rows are checked top to bottom; the first that applies decides.

| Call | Result |
|---|---|
| Memory tools and any tool without a string `relative_path`, except the three whole-project tools below when the path is absent or `null` | Passes; memories belong to the primary checkout |
| `cwd` in the checkout Serena is rooted in, `CLAUDE_PROJECT_DIR` unset or in an unrelated repository, not a repository, malformed input | Passes silently (fail open) |
| The session's checkout is unreachable (see Reachability) | Write tools blocked and sent to the built-in `Edit`/`Write`; read tools pass with a note naming the checkout that the result describes |
| Path that resolves outside the checkout Serena is rooted in | Passes; it cannot land in that checkout, so it is outside this hook's concern |
| `relative_path` that resolves inside the checkout Serena is rooted in but outside every linked worktree and the session's checkout | Blocked (exit 2); message gives `relative_path="<prefix>/<path>"`, where `<path>` is relative to the top of Serena's checkout (the same file in the session's checkout) |
| `find_symbol`, `replace_in_files` or `search_for_pattern` with an absent, `null` or blank path (whole project) | Blocked like the row above, with Serena's root as the path: `relative_path="<prefix>"` when that root is the top of its checkout |
| Non-blank `paths_include_glob` or `paths_exclude_glob` that starts neither with `**/` nor with the prefix of the checkout the path names | Blocked; message gives the prefixed glob. Serena anchors a glob at its root, so `*.md` matches root-level files only (Serena 1.7.0 `GlobMatcher` in `serena/util/text_utils.py`, probed 2026-09-28) |
| `rename_symbol` with a path inside the session's checkout or another linked worktree | Passes with a warning to check `git status` in every tree |
| Path inside the session's checkout or another linked worktree | Passes |

**Why it blocks instead of rewriting the input**: the hooks documentation
(retrieved 2026-09-28) states `updatedInput` generically and does not say that
it applies to MCP tools or how it merges when several PreToolUse hooks match
one call; `external-write-guard` and `branch-guard` match the same Serena
calls. A report of a rewrite dropped under several hooks,
https://github.com/anthropics/claude-code/issues/15897, was closed as not
planned on 2026-05-14, and a commenter reported it fixed in Claude Code 2.1.168
(read 2026-09-28); that is not confirmed for MCP tools. A rewrite that is not
applied would be the silent primary edit again, while a block costs one extra
round trip and cannot fail silently.

**Reachability**: the session's checkout is unreachable when it lies outside
Serena's root (a worktree elsewhere on disk, Serena rooted at a subdirectory
project or at another worktree, or a session that returned to the primary
checkout while Serena is rooted in a worktree), when a `.gitignore` file covers
it, or when that query fails. With `ignore_all_files_in_gitignore` (default
`true`, `serena/config/serena_config.py`), Serena 1.7.0 refuses a covered path
in `replace_in_files` (`serena/tools/file_tools.py`, `_collect_files`) and
leaves it out of symbol lookups; `replace_content` and the line-editing tools
carry no ignore check and would still work, and the hook treats every write
tool alike. Serena reads neither `.git/info/exclude` nor `core.excludesFile`,
so the hook asks
`git ls-files --others --ignored --exclude-per-directory=.gitignore`. Probed
with git 2.55.0 on 2026-09-28: `git check-ignore` reports a parent directory's
`info/exclude` rule and hides a `.gitignore` rule beneath it, and ignored files
inside a worktree do not make the worktree itself ignored.

**A repository that gitignores its worktrees**: the Claude Code documentation
advises adding `.claude/worktrees/` to `.gitignore`
(https://code.claude.com/docs/en/worktrees, retrieved 2026-09-28). In such a
repository every worktree is unreachable, so the hook never names a prefixed
path: it blocks Serena write tools and sends them to the built-in
`Edit`/`Write`. Excluding the directory through `.git/info/exclude` instead
keeps the worktrees reachable for Serena.

**Known limits**:
- Not verified: `rename_symbol` applies the language server's workspace edit
  without a path filter (`serena/code_editor.py`), and the language server
  indexes the primary checkout together with its nested worktrees, so a rename
  may edit the same symbol in another tree.
- Not verified: which directory Serena is rooted at after `/mcp` reconnect or
  after resuming a session into a worktree. If Serena is then rooted at the
  worktree, the prefixed path does not exist and Serena raises an error; the
  block message names the built-in `Edit`/`Write` as the way out.
- `ignore_all_files_in_gitignore` and `ignored_paths`, in `.serena/project.yml`
  or in the global `serena_config.yml`, are not read.
- Serena's root is derived, not read: a Serena started with an explicit
  `--project` path instead of `--project-from-cwd` may be rooted elsewhere.
  Not verified: the root and `CLAUDE_PROJECT_DIR` of a session started with
  `claude --worktree`.
- A `relative_path` that is a number, a list or an object passes for every
  tool; one that is `null` passes for every tool except the three
  whole-project tools.
- A path that leaves the checkout Serena is rooted in is not this hook's
  concern and passes. Serena 1.7.0 refuses a path that leaves its root in
  `serena/tools/file_tools.py` (`replace_content`, `replace_in_files`,
  `search_for_pattern`, `create_text_file` and the read and list tools); its
  symbol tools and line-editing tools carry no such check.
- Serena's containment check compares paths as written and does not resolve
  symlinks (`serena/project.py`, `is_path_in_project`), while the hook
  resolves them, so the two can disagree about a path through a symlink.
- POSIX paths only: on Windows the prefix holds backslashes while Serena
  matches globs with forward slashes.

**Tests**: `smith-serena/scripts/tests/worktree-path-guard.test.sh`, run by
`tests/run-all.sh`.
