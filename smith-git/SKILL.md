---
name: smith-git
description: Git workflow gotchas and non-obvious practices. Use when performing Git commits, merges, branch management, rebasing, or raw `git worktree` commands. Covers GPG signing, atomic commits, raw worktree patterns, and safety flags. For the Claude Code worktree tools (EnterWorktree/ExitWorktree) see smith-worktree.
---

# Git Workflow Gotchas

**Load if:** Git commits, merges, branch management
**Prerequisites:** @smith-principles/SKILL.md, @smith-standards/SKILL.md

## CRITICAL

- MUST use `git mv` for renames (preserves history)
- MUST GPG sign all commits: `git commit -S -m "..."`
- MUST keep branches linear (prefer rebase over merge) - essential for stacked PRs, see `@smith-stacks/SKILL.md`
- MUST verify current branch (`git branch --show-current`) before `git commit`, `git push`, or `git rebase` — confirm it matches the branch you intend to modify
- MUST create a dedicated branch (+worktree in background sessions, see
  `@smith-worktree/SKILL.md`) BEFORE the first edit of any repo-file-modifying
  task — even when no commit is requested. Never start edits on the default
  branch or on an unrelated dirty branch. Mechanical backstop: the
  `branch-guard` PreToolUse hook (`smith-ctx-claude/scripts/branch-guard.mjs`,
  registered user-globally) blocks Edit/Write/NotebookEdit and Serena write
  tools on non-gitignored files while the repo is on `main`/`master`/`develop`
  (or its `origin/HEAD` default); per-repo opt-out is
  `.claude/branch-guard.disabled`.
- Reserve force-push for personal branches only — never main or shared branches.
- Commit only to feature branches, never directly to main.
- Rebase only personal feature branches, never shared branches.
- Let git hooks run — skip `--no-verify`.
- Keep GPG signing enabled — skip `--no-gpg-sign`.

## Operation Boundaries

- Match action to request: list=list, create=create — treating "list",
  "check", or "show" as permission to create or modify is out of scope
- Create only the branches/tags that were actually requested, nothing beyond it
- State planned operations before multi-step workflows
- For scope/approval rules, see @smith-guidance/SKILL.md
- For PR creation rules, see `@smith-gh-pr/SKILL.md`

## Worktree Safety

- Before write operations (commits, pushes, dev servers, tests): verify `git rev-parse --show-toplevel` matches your intended working directory
- If multiple worktrees exist, use `git worktree list` to identify the correct one
- If in wrong worktree: stop, `cd` to the correct one before proceeding

## Worktree Patterns

**Git worktree basics:**

```shell
git worktree add ../feature-branch feat/feature
```

```shell
git worktree list
```

```shell
git worktree remove ../feature-branch
```

**Parallel branch work:**
- Each worktree = independent working directory
- Share same `.git` — branches, stash, reflog shared
- Useful for: hotfix while mid-feature, parallel reviews

**Claude Code integration:**
- `isolation: "worktree"` in Agent tool — auto-creates
  worktree for subagent, cleaned up when done
- For `EnterWorktree` / `ExitWorktree`, `bgIsolation`,
  `worktree.baseRef`, and the squash-merge sync protocol
  see `@smith-worktree/SKILL.md`
- Worktree lifecycle hooks (create/remove) fire on
  worktree operations for custom automation
- Agent worktrees auto-cleanup; persistent ones need
  manual `git worktree remove`

- ALWAYS verify worktree path before write operations
- NEVER leave orphaned worktrees (check `git worktree list`)
- Clean up persistent worktrees after branch is merged
- NEVER `git checkout «other-branch»` in the PRIMARY working dir to inspect or
  test another branch — it tramples IDE/dev-server/test state in place. Use a
  worktree (`git worktree add` / `EnterWorktree`), which fails loudly if the
  branch is already checked out elsewhere.

## Branch Naming

**Pattern**: `type/descriptive_name` — type MUST match commit type

**Separators** (abbreviated quick-ref; see `@smith-style/SKILL.md` for full rules):
- **Underscore (_)**: Multi-word single concept → `fix/query_processor`
- **Hyphen (-)**: Hierarchy/variant/ticket → `feat/auth-login`, `fix/JIRA-1234-query_processor`

## Commit Standards

**Format**: See `@smith-style/SKILL.md` for conventional commits.

**Atomic commits**: One logical change per commit, passes tests, reversible.

**Attribution**: AI-assisted commits carry an `Assisted-by:` trailer; the agent
never adds `Signed-off-by:` (only humans certify the DCO) — see
`@smith-style/SKILL.md`.

## Non-Obvious Flags

- **`-u`**: Use on first push to set upstream tracking
- **`--force-with-lease`**: Safe force push for personal branches - required for stacked PRs after rebase, see `@smith-stacks/SKILL.md`
- **`--no-ff`**: Preserve merge commit for feature branches (maintains history)
- **`-S`**: GPG sign commits

## Claude Code Plugin Integration

**When commit-commands plugin is available:**

- **`/commit`**: Auto-generates commit message, stages files, creates commit
- **`/clean_gone`**: Cleans up branches deleted from remote (including worktrees)

**Manual commands still needed for:**
- GPG signing (`-S` flag)
- Interactive rebase
- Force push with lease

## Ralph Loop Commit Strategy

**Atomic commits mark iteration boundaries.** Include iteration number; enables `git bisect` for regressions.

See `@smith-ralph/SKILL.md` for full commit patterns.

## Related

- `@smith-stacks/SKILL.md` - Stacked PR workflows (uses linear history, force-with-lease)
- `@smith-gh-pr/SKILL.md` - PR creation, review cycles, merge strategies
- `@smith-gh-cli/SKILL.md` - GitHub CLI commands
- `@smith-style/SKILL.md` - Naming conventions, conventional commits
- `@smith-ctx-claude/SKILL.md` - Claude Code agent features and context management
- `@smith-worktree/SKILL.md` - Claude Code worktree tools, bgIsolation, squash-merge sync

## Before You Finish

**First push to new branch:**
```shell
git push -u origin feat/my_feature
```

**Safe force push (personal branches only):**
```shell
git push --force-with-lease origin feat/my_feature
```

**Feature merge (preserve history):**
```shell
git merge --no-ff feat/my_feature
```

**Interactive rebase (local commits only):**
```shell
git rebase -i HEAD~3
```
