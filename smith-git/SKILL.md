---
name: smith-git
description: Git workflow gotchas and non-obvious practices. Use when performing Git commits, merges, branch management, or rebasing. Covers GPG signing, atomic commits, and safety flags.
---

# Git Workflow Gotchas

<metadata>

- **Load if**: Git commits, merges, branch management
- **Prerequisites**: @smith-principles/SKILL.md, @smith-standards/SKILL.md

</metadata>

## CRITICAL (Primacy Zone)

<required>

- MUST use `git mv` for renames (preserves history)
- MUST GPG sign all commits: `git commit -S -m "..."`
- MUST keep branches linear (prefer rebase over merge) - essential for stacked PRs, see `@smith-stacks/SKILL.md`

</required>

<forbidden>

- NEVER force push to main or shared branches
- NEVER commit directly to main branch
- NEVER rebase shared branches (only personal feature branches)

</forbidden>

## Branch Naming

See `@smith-style/SKILL.md` for naming conventions.

## Commit Standards

**Format**: See `@smith-style/SKILL.md` for conventional commits.

**Atomic commits**: One logical change per commit, passes tests, reversible.

## Non-Obvious Flags

- **`-u`**: Use on first push to set upstream tracking
- **`--force-with-lease`**: Safe force push for personal branches - required for stacked PRs after rebase, see `@smith-stacks/SKILL.md`
- **`--no-ff`**: Preserve merge commit for feature branches (maintains history)
- **`-S`**: GPG sign commits

## Claude Code Plugin Integration

<context>

**When commit-commands plugin is available:**

- **`/commit`**: Auto-generates commit message, stages files, creates commit
- **`/clean_gone`**: Cleans up branches deleted from remote (including worktrees)

**Manual commands still needed for:**
- GPG signing (`-S` flag)
- Interactive rebase
- Force push with lease

</context>

## Ralph Loop Commit Strategy

<required>

**Atomic commits mark iteration boundaries.**

**Ralph commit pattern:**
1. Complete iteration (test passes or hypothesis proven)
2. Commit with iteration number: `fix(feature): iteration 3 - resolved null check`
3. Continue to next iteration
4. If regression, use `git bisect` to find breaking iteration

**Benefits:**
- Rollback to any iteration
- Linear history for debugging
- Recovery point if context compacts

</required>

<related>

- `@smith-stacks/SKILL.md` - Stacked PR workflows (uses linear history, force-with-lease)
- `@smith-gh-pr/SKILL.md` - PR creation, review cycles, merge strategies
- `@smith-gh-cli/SKILL.md` - GitHub CLI commands
- `@smith-style/SKILL.md` - Naming conventions, conventional commits

</related>

## ACTION (Recency Zone)

<required>

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

</required>
