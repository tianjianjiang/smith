---
name: smith-worktree
description: Claude Code worktree tooling — EnterWorktree/ExitWorktree, the bgIsolation guard, worktree.baseRef, branch-naming gotcha, and the squash-merge sync protocol.
---

# Claude Code Worktree Tooling

<metadata>

- **Scope**: `EnterWorktree`, `ExitWorktree`, `worktree.baseRef`, `worktree.bgIsolation` settings, the background-session isolation guard, and the squash-merge sync protocol
- **Load if**: The bg-isolation guard refused an edit, OR `EnterWorktree` failed, OR the agent is planning a multi-file change that warrants isolation, OR the user mentions worktrees / `bgIsolation` / `baseRef`, OR cleaning up after a worktree-based PR merge
- **Prerequisites**: `@smith-git/SKILL.md` (git worktree fundamentals), `@smith-gh-pr/SKILL.md` (PR flow context)
- **Authoritative sources**: https://code.claude.com/docs/en/changelog (worktree.baseRef v2.1.133, bgIsolation v2.1.143; verified 2026-05-21)

</metadata>

## CRITICAL: Worktree Discipline (Primacy Zone)

<forbidden>

- NEVER modify `git worktree` state via raw Bash (`git worktree add`, `git worktree remove`) when `EnterWorktree` / `ExitWorktree` will do. The Claude Code tools track per-session ownership; raw Bash leaves orphans the harness can't clean up.
- NEVER assume `EnterWorktree({name: "foo"})` produces a branch named `foo`. The actual local branch is `worktree-foo`. Rename it (`git branch -m feat/foo`) before pushing if the PR branch must match a convention.
- NEVER disable the bg-isolation guard transiently for "one edit". The guard exists because parallel background jobs share the working copy and clobber each other.
- NEVER set `worktree.bgIsolation: "none"` at the user-global level (`~/.claude/settings.json`) to escape the guard. If the user has indicated this repo prefers in-place edits, scope it to the repo's `.claude/settings.json`.
- NEVER call `gh pr merge --delete-branch` from inside a worktree session expecting the local main checkout to update — `gh` will warn `'main' is already used by worktree at ...` and skip the switch. The merge itself succeeds; sync local main manually (see Sync-After-Squash-Merge below).

</forbidden>

<required>

- For multi-file edits in a background session, the bg-isolation guard will refuse the first `Edit` and tell the agent to `EnterWorktree`. Comply on the first refusal — do not try alternative edit paths.
- After a squash-merge of a worktree branch, the local copy of that feature branch is an **orphan** (its commit is not in main's history under the same SHA). `git branch -d` will refuse it with "not fully merged"; use `git branch -D` (force) once the squash commit is confirmed on main.
- **Branch naming:** `EnterWorktree` auto-names the branch
  `worktree-<name>` which violates `@smith-style/SKILL.md`. MUST
  rename before pushing: `git branch -m <type>/<scope>_<description>`
  Alternative: create branch first, then `EnterWorktree({path: ...})`

</required>

## EnterWorktree Semantics

<context>

`EnterWorktree({name: "<n>"})` creates `.claude/worktrees/<n>/` on local branch `worktree-<n>`, branched from the ref specified by `worktree.baseRef`. The session's CWD switches into the worktree.

- Naming: the `name` param accepts `/`-separated segments; each segment may contain letters, digits, dots, underscores, dashes only. The branch name is always `worktree-<name>` regardless.
- Base ref (`worktree.baseRef` setting in `~/.claude/settings.json` or repo `.claude/settings.json`):
  - `fresh` (default since v2.1.133) — branches from `origin/<default-branch>`. Ignores local unpushed commits on main.
  - `head` — branches from local `HEAD`. Use when iterating on top of work that isn't on origin yet.
`ExitWorktree({action: "keep"|"remove", discard_changes: bool})`:

- `keep` — leaves the dir + branch on disk; session CWD restores to the original. Use when the work isn't finished or shouldn't be discarded.
- `remove` — deletes both. Refuses if uncommitted files or commits exist on the branch unless `discard_changes: true`.
- Operates **only** on worktrees this session created via `EnterWorktree`. A worktree created manually with `git worktree add` is unaffected; use `EnterWorktree({path: ...})` to switch into it instead.

</context>

## The bg-isolation Guard

<context>

Background sessions in repos without `worktree.bgIsolation: "none"` block the first `Edit`/`Write` against tracked files until the session is inside a worktree. The refusal message names `EnterWorktree` as the fix.

Two correct responses:

- **`EnterWorktree`** — default. Branch off, work in isolation, push from the worktree, merge, exit + remove.
- **Repo-scoped opt-out**: write `{ "worktree": { "bgIsolation": "none" } }` to the repo's `.claude/settings.json`. Appropriate when the user has indicated they want in-place edits in this repo (e.g. *"keep changes in the local working copy so I can evaluate"*).

</context>

## Editing Inside a Worktree (MCP write blind spot)

<context>

The bg-isolation guard catches only built-in `Edit`/`Write` — NOT MCP file operations. Serena MCP writes (`replace_content`, `replace_symbol_body`, `insert_*`) target the MAIN repo checkout, not the worktree, because `activate_project` binds at session start and does not follow `EnterWorktree`. So Serena edits land silently in the wrong tree.

- After `EnterWorktree`, use built-in `Edit`/`Write` with worktree ABSOLUTE paths for all writes; use Serena for reads / symbol lookup only.

</context>

## `worktree.baseRef` — `fresh` vs `head`

<context>

- `fresh` (default) — start from `origin/<default-branch>`. Safe when iterating against an up-to-date main. **Loses** local-only commits that haven't been pushed to origin.
- `head` — start from local `HEAD`. **Keeps** unpushed commits. Use when the user has staged or committed work locally on main that should carry forward into the worktree.

If `worktree.baseRef` is set in a repo's `.claude/settings.json`, that repo wins over the user-level setting.

</context>

## Sync-After-Squash-Merge Protocol

<context>

When a PR from a worktree branch is squash-merged to main, the local artifacts are inconsistent:

- `origin/main` has a new commit with the squashed content.
- The local `feat/<name>` branch still points at the original (un-squashed) commit; it shows `[origin/feat/<name>: gone]` after `git fetch --prune`.
- `git branch -d feat/<name>` will refuse: *"the branch is not fully merged"*. This is a squash-merge orphan; the content **is** in main, just under a different SHA.

Protocol:

1. `ExitWorktree({action: "remove", discard_changes: true})` — the worktree's branch is now redundant since its content is on origin/main.
2. From the main working copy: `git fetch --prune origin && git pull --ff-only`. This catches origin's new commit and removes the stale remote-tracking ref.
3. `git branch -D feat/<name>` to remove the orphan local branch.

If the user pre-mirrored worktree changes back to the main working copy (the "evaluate-in-place" pattern), the working copy has uncommitted edits that are now stale (they're an older version of what's in the merge commit). Clean up:

```shell
git checkout -- <tracked-files-from-the-PR>
rm -rf <new-untracked-dirs-from-the-PR>
git pull --ff-only
```

</context>

## Operational Worktree Gotchas

<context>

- Worktree `.env` and `node_modules` are often SYMLINKS to the main repo. A blanket `git add -A` / `git add .` then stages the symlink itself. Stage explicit paths only; never blanket-add inside a worktree.
- `gh pr create` run from a non-primary worktree resets the shell CWD back to the first worktree after it returns. Use `git -C <worktree>` for follow-on git ops rather than trusting CWD persistence.

</context>

<related>

- `@smith-git/SKILL.md` - Git fundamentals; raw `git worktree` for cases outside the Claude Code tools
- `@smith-gh-pr/SKILL.md` - PR flow that worktree-based work feeds into
- `@smith-ctx-claude/SKILL.md` - Claude Code session model, including background sessions

</related>

## ACTION (Recency Zone)

<required>

**On bg-isolation guard refusal:**
1. `EnterWorktree({name: "<short-slug>"})` — any short name works
2. Rename branch per primacy-zone rule above:
   `git branch -m <type>/<scope>_<description>`
3. Mirror prior uncommitted changes from the main copy via `cp`
   only when the user has asked for "evaluate-in-place"

**After squash-merge:**
- `ExitWorktree` (remove + discard) → `git pull --ff-only` on main → `git branch -D feat/<name>` to clear the orphan

</required>
