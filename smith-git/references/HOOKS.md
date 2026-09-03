# Hooks Reference — smith-git

Detailed behavior for the guard hooks whose scripts live under
`smith-git/scripts/hooks/`. See the repo root `README.md` "Hooks" section for
the cross-skill summary table, the full `settings.json` registration block,
and the manual verification checklist (registration and verification steps
for these hooks are numbered there alongside every other hook, since they all
register into the same profile-level `settings.json`).
`smith-ctx-claude/references/HOOKS.md` and `smith-standards/references/HOOKS.md`
cover hooks owned by those skills, including shared helpers
(`smith-git/scripts/lib/git-command-tokenizer.mjs`,
`smith-git/scripts/lib/transcript-turns.mjs`) that several ctx-claude hooks
import from this skill.

## Overview

| Hook | Event (matcher) | Blocks / Advisory |
|---|---|---|
| `branch-guard.mjs` | PreToolUse (`Edit\|Write\|NotebookEdit\|serena writes`) | Blocks file edits while a repo is on its default branch |
| `worktree-dirty-guard.mjs` | PreToolUse (`EnterWorktree`) | Blocks entering a worktree while the checkout has uncommitted changes |
| `branch-name-guard.mjs` | PreToolUse (`Bash`, `EnterWorktree`) | Blocks a non-Conventional-Branch-Names branch create/rename |
| `post-merge-pull-reminder.mjs` | PostToolUse (`Bash`) | Advisory: reminds to fast-forward-only pull the default branch after `gh pr merge` |

## branch-guard

**branch-guard** (`smith-git/scripts/hooks/branch-guard.mjs`) — PreToolUse
guard that blocks file edits while a repo is on its default branch
(`main`/`master`/`develop`): branch/worktree first. Per-repo opt-out: create
`.claude/branch-guard.disabled` in that repo.

## worktree-dirty-guard

**worktree-dirty-guard** (`smith-git/scripts/hooks/worktree-dirty-guard.mjs`)
— PreToolUse guard that blocks `EnterWorktree` while the checkout has
uncommitted changes (they would not carry into the new worktree).

## branch-name-guard

**branch-name-guard** (`smith-git/scripts/hooks/branch-name-guard.mjs`)
— PreToolUse guard (matcher `Bash`) that blocks `git checkout -b`/`-B`/
`--orphan`, `git switch -c`/`-C`/`--create`/`--orphan`, `git branch <name>`/
`-m`/`-M`/`--move`/`-c`/`-C`/`--copy`, `git stash branch`, and
`git worktree add -b`/`-B` (short
flags, jammed short flags like `-bname`, and `--long=value` forms all
recognized) when the target name doesn't match the Conventional Branch
pattern `type/description` (`@smith-style/SKILL.md` Branch Names) —
lowercase type from the Conventional Commits set, kebab-case description
(hyphen-separated segments that may contain dots, e.g.
`chore/deps-node18.20-bump`), no underscores/uppercase/consecutive-hyphens
— or contains `post-review`/`after-review`. The pattern and
forbidden-substring list are
pre-compiled `const`s in the script itself, so no external config can
silently disable the check. Blocks with an auto-corrected suggestion
(lowercase, `_`→`-`, collapsed hyphens) rather than a bare rejection.
Skips names containing an unresolved shell substitution (`$VAR`, `` `cmd` ``)
rather than validating the literal syntax. **Known limitation** (shared
with `branch-rename-open-pr`/`gh-stack-guard` in `smith-ctx-claude`, which
parse Bash command text the same way): it only sees the command as typed,
so a name resolved through a git/shell alias, or a branch created through
a non-Bash path (`EnterWorktree`, an IDE git panel, an external terminal) is
not checked. Closing that gap would need a git-native hook (e.g. `pre-push`)
validating the resolved ref instead of Bash-command text — tracked as a
follow-up, not attempted here. `git branch`'s create/rename/copy/listing/upstream
flags are classified by a single per-token scan (`branchTokenCategory`)
that stops at the first recognized flag character, so a value-taking
flag's attached value (e.g. `-umain`) is never rescanned as if its
characters were further bundled flags. `checkout`/`switch`'s flag lists
only recognize `-b`/`-B`/`-c`/`-C`/`--create`/`--orphan` as create
signals — plain `git checkout <name>`/`git switch <name>` DWIM-creating a
local branch from a single matching remote-tracking branch, and
`--track`/`-t` against a remote ref, are not recognized as creates at
all, so no validation happens on those paths; tracked as a follow-up,
not attempted here.

## post-merge-pull-reminder

**post-merge-pull-reminder** (`smith-git/scripts/hooks/post-merge-pull-reminder.mjs`,
using shared helpers from `smith-git/scripts/lib/git-command-tokenizer.mjs`)
— PostToolUse guard (matcher `Bash`) that emits an **advisory** after a
`gh pr merge` runs, reminding the session to fast-forward-only pull the
repository's default branch in the primary checkout — the decide-and-do rule
restated in `@smith-gh-pr` and `@smith-worktree` and skipped often enough to
warrant a mechanical prompt. It fires on the
command text alone and does NOT gate on success: Claude Code's Bash
`tool_response` carries no numeric exit code (census of 3467 real
`toolUseResult` objects under `~/.claude/projects/*smith*`, fetched
2026-08-28: keys are `stdout`/`stderr`/`interrupted`/`isImage`/
`noOutputExpected`, `exitCode` in 0 of them; the docs' PostToolUse Output
object likewise names no exit code), and a non-zero-exit Bash command still
reaches PostToolUse rather than `PostToolUseFailure`, so a failed
`gh pr merge` (conflict, unmergeable) would trigger it too. `stderr` is
populated on success as well, so there is no reliable structured failure
signal to gate on — hence the reminder is worded "if it merged" and stays
advisory: a spurious reminder after a failed merge costs only one line, and
the fast-forward-only pull it suggests is a safe no-op. Does NOT fire for `gh
pr merge --auto`/`--disable-auto`, which only enable or disable auto-merge
rather than merging now (per `gh pr merge --help`: "--auto Automatically merge
only after necessary requirements are met"), so a "pull now" reminder there
would be premature; the deferred-flag check matches both the bare form and the
attached `--auto=true`/`--disable-auto=true` boolean form (a `--flag=value`
token is matched on its name, so `--subject=--auto` — a commit subject that is
literally `--auto` — is correctly treated as a real merge, not a deferral).
`gh pr merge --help`/`-h` is likewise not a merge and stays silent. Accepted
advisory limitations: `--auto=false` (technically an immediate merge) is
treated as a deferral and stays silent — a fail-open miss of a form
essentially never typed; a cross-repo `gh -R owner/other pr merge` still names
"the primary checkout", which then belongs to a different repository; a
space-separated flag value that is literally a deferral/help flag (`gh pr merge
--subject --auto`, `-t -h`) is read as the flag and stays silent, unlike the
attached `--subject=--auto` form which is handled correctly — the tokenizer
does not track which flags consume a value, and a commit subject of literally
`--auto` never occurs; a stacked-PR child merge (`gh pr merge <child>`) merges
into its parent branch, yet the reminder still names the default branch; and a
command wrapped in an unrecognized launcher (`timeout`, `xargs`) leaves the gh
invocation unparsed, so the reminder is skipped. All are advisory fail-open
misses or generic-wording edges, not blocking failures. The reminder text also
names the two adjacent behaviours worth expecting: from
a worktree, `gh pr merge --delete-branch` can print `fatal: '<default-branch>'
is already used by worktree ...` even though the merge itself succeeded, and a
squash merge can leave an orphan local branch to delete. Advisory only, never
blocks (a PostToolUse hook cannot block a command that already ran).

## Test runners

`smith-ctx-claude` hooks under `smith-ctx-claude/scripts/tests/run-all.sh`
also exercise these hooks' shared libs where imported; there is no separate
`smith-git`-specific runner yet.
