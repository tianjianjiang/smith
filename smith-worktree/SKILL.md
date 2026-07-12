---
name: smith-worktree
description: Claude Code worktree TOOLS — EnterWorktree/ExitWorktree, the bgIsolation guard, worktree.baseRef, the branch-naming gotcha, and the squash-merge sync protocol. Use when invoking EnterWorktree/ExitWorktree, hitting the bgIsolation guard, or cleaning up after a worktree-based PR merge. For raw `git worktree` commands see smith-git.
---

# Claude Code Worktree Tooling

**Scope:** `EnterWorktree`, `ExitWorktree`, `worktree.baseRef`, `worktree.bgIsolation` settings, the background-session isolation guard, and the squash-merge sync protocol
**Load if:** The bg-isolation guard refused an edit, OR `EnterWorktree` failed, OR the agent is planning a multi-file change that warrants isolation, OR the user mentions worktrees / `bgIsolation` / `baseRef`, OR cleaning up after a worktree-based PR merge
**Prerequisites:** `@smith-git/SKILL.md` (git worktree fundamentals), `@smith-gh-pr/SKILL.md` (PR flow context)
**Authoritative sources:** https://code.claude.com/docs/en/changelog (worktree.baseRef v2.1.133, bgIsolation v2.1.143; verified 2026-05-21)

## CRITICAL: Worktree Discipline

- Use `EnterWorktree` / `ExitWorktree` instead of raw Bash `git worktree add`/`git worktree remove` — the Claude Code tools track per-session ownership; raw Bash leaves orphans the harness can't clean up.
- Keep the bg-isolation guard enabled rather than disabling it transiently for "one edit" — the guard exists because parallel background jobs share the working copy and clobber each other.
- Scope `worktree.bgIsolation: "none"` to the repo's `.claude/settings.json` (not the user-global level `~/.claude/settings.json`) when the user has indicated this repo prefers in-place edits.
- After `gh pr merge --delete-branch` from inside a worktree session, sync local main manually (see Sync-After-Squash-Merge below) — `gh` will warn `'main' is already used by worktree at ...` and skip the switch, even though the merge itself succeeds.
- For multi-file edits in a background session, the bg-isolation guard will refuse the first `Edit` and tell the agent to `EnterWorktree`. Comply on the first refusal — do not try alternative edit paths.
- After a squash-merge of a worktree branch, the local copy of that feature branch is an **orphan** (its commit is not in main's history under the same SHA). `git branch -d` will refuse it with "not fully merged"; use `git branch -D` (force) once the squash commit is confirmed on main.
- **Branch naming:** `EnterWorktree` auto-names the branch
  `worktree-«name»` which violates `@smith-style/SKILL.md`. MUST
  rename before pushing: `git branch -m «type»/«scope»_«description»`
  Alternative: create branch first, then `EnterWorktree({path: ...})`

## EnterWorktree Semantics

`EnterWorktree({name: "«n»"})` creates `.claude/worktrees/«n»/` on local branch `worktree-«n»`, branched from the ref specified by `worktree.baseRef`. The session's CWD switches into the worktree.

A new worktree starts with a CLEAN tree: uncommitted changes in the current
checkout never carry over — they stay behind, stranded from the task. The
`worktree-dirty-guard` PreToolUse hook
(`smith-ctx-claude/scripts/worktree-dirty-guard.mjs`, registered
user-globally) blocks `EnterWorktree` while `git status --porcelain` is
non-empty; resolve deliberately (commit, stash-and-apply inside the worktree,
or branch in place) before retrying.

- Naming: the `name` param accepts `/`-separated segments; each segment may contain letters, digits, dots, underscores, dashes only. The branch name is always `worktree-«name»` regardless.
- Base ref (`worktree.baseRef` setting in `~/.claude/settings.json` or repo `.claude/settings.json`):
  - `fresh` (default since v2.1.133) — branches from `origin/«default-branch»`. Ignores local unpushed commits on main.
  - `head` — branches from local `HEAD`. Use when iterating on top of work that isn't on origin yet.
`ExitWorktree({action: "keep"|"remove", discard_changes: bool})`:

- `keep` — leaves the dir + branch on disk; session CWD restores to the original. Use when the work isn't finished or shouldn't be discarded.
- `remove` — deletes both. Refuses if uncommitted files or commits exist on the branch unless `discard_changes: true`.
- Operates **only** on worktrees this session created via `EnterWorktree`. A worktree created manually with `git worktree add` is unaffected; use `EnterWorktree({path: ...})` to switch into it instead.

## The bg-isolation Guard

Background sessions in repos without `worktree.bgIsolation: "none"` block the first `Edit`/`Write` against tracked files until the session is inside a worktree. The refusal message names `EnterWorktree` as the fix.

Two correct responses:

- **`EnterWorktree`** — default. Branch off, work in isolation, push from the worktree, merge, exit + remove.
- **Repo-scoped opt-out**: write `{ "worktree": { "bgIsolation": "none" } }` to the repo's `.claude/settings.json`. Appropriate when the user has indicated they want in-place edits in this repo (e.g. *"keep changes in the local working copy so I can evaluate"*).

## Editing Inside a Worktree (MCP write blind spot)

The bg-isolation guard catches only built-in `Edit`/`Write` — NOT MCP file operations. Serena MCP writes (`replace_content`, `replace_symbol_body`, `insert_*`) target the MAIN repo checkout, not the worktree, because `activate_project` binds at session start and does not follow `EnterWorktree`. So Serena edits land silently in the wrong tree.

- After `EnterWorktree`, use built-in `Edit`/`Write` with worktree ABSOLUTE paths for all writes; use Serena for reads / symbol lookup only.

## `worktree.baseRef` — `fresh` vs `head`

- `fresh` (default) — start from `origin/«default-branch»`. Safe when iterating against an up-to-date main. **Loses** local-only commits that haven't been pushed to origin — and uncommitted changes are stranded either way (see EnterWorktree Semantics; the dirty-guard hook catches this).
- `head` — start from local `HEAD`. **Keeps** unpushed commits. Use when the user has staged or committed work locally on main that should carry forward into the worktree.

If `worktree.baseRef` is set in a repo's `.claude/settings.json`, that repo wins over the user-level setting.

## Sync-After-Squash-Merge Protocol

When a PR from a worktree branch is squash-merged to the default branch (`main`, `develop`, etc. — never assume `main`), the local artifacts are inconsistent:

- `origin/<default-branch>` has a new commit with the squashed content.
- The local `feat/«name»` branch still points at the original (un-squashed) commit; it shows `[origin/feat/«name»: gone]` after `git fetch --prune`.
- `git branch -d feat/«name»` will refuse: *"the branch is not fully merged"*. This is a squash-merge orphan; the content **is** in main, just under a different SHA.

Protocol:

1. `ExitWorktree({action: "remove", discard_changes: true})` — removes the worktree AND its branch (the content is now on the default branch).
2. From the primary working copy: `git fetch --prune origin && git pull --ff-only`. This catches the new commit and removes the stale remote-tracking ref.
3. Only if a branch survived step 1 (you exited with `keep`, renamed it, or created it outside the tool): `git branch -D «branch»` to clear the squash-merge orphan (`git branch -d` refuses it as "not fully merged").

If the user pre-mirrored worktree changes back to the main working copy (the "evaluate-in-place" pattern), the working copy has uncommitted edits that are now stale (they're an older version of what's in the merge commit). Clean up:

```shell
git checkout -- «tracked-files-from-the-PR»
rm -rf «new-untracked-dirs-from-the-PR»
git pull --ff-only
```

## Operational Worktree Gotchas

- Worktree `.env` and `node_modules` are often SYMLINKS to the main repo. A blanket `git add -A` / `git add .` then stages the symlink itself. Stage explicit paths only; never blanket-add inside a worktree.
- `gh pr create` run from a non-primary worktree resets the shell CWD back to the first worktree after it returns. Use `git -C «worktree»` for follow-on git ops rather than trusting CWD persistence.

## Related

- `@smith-git/SKILL.md` - Git fundamentals; raw `git worktree` for cases outside the Claude Code tools
- `@smith-gh-pr/SKILL.md` - PR flow that worktree-based work feeds into
- `@smith-ctx-claude/SKILL.md` - Claude Code session model, including background sessions

## Before You Finish

**Before any EnterWorktree:**
- `git status --porcelain` — if non-empty, STOP: commit, stash-and-apply
  inside the worktree, or branch in place instead. Uncommitted changes never
  carry into a new worktree (the `worktree-dirty-guard` hook blocks this).

**On bg-isolation guard refusal:**
1. `EnterWorktree({name: "«short-slug»"})` — any short name works
2. Rename branch per the CRITICAL-section rule above:
   `git branch -m «type»/«scope»_«description»`
3. Mirror prior uncommitted changes from the main copy via `cp`
   only when the user has asked for "evaluate-in-place"

**After squash-merge:**
- `ExitWorktree` (remove + discard — deletes the branch too) → `git pull --ff-only` on the default branch. Only if a branch survived (`keep`/renamed/manual): `git branch -D «branch»` to clear the squash-merge orphan.
