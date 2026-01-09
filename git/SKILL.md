---
name: git
description: Git workflow gotchas and non-obvious practices. Use when performing Git commits, merges, branch management, or rebasing. Covers GPG signing, atomic commits, and safety flags.
---

# Git Workflow Standards

<metadata>

- **Load if**: Git commits, merges, branch management
- **Prerequisites**: @principles/SKILL.md, @standards/SKILL.md

</metadata>

## CRITICAL (Primacy Zone)

<required>

- MUST use `git mv` for renames (preserves history)
- MUST GPG sign all commits: `git commit -S -m "..."`
- MUST keep branches linear (prefer rebase over merge) - essential for stacked PRs, see `@stacks/SKILL.md`

</required>

## Branch Naming

See `@style/SKILL.md` for naming conventions.

## Commit Standards

**Format**: See `@style/SKILL.md` for conventional commits.

**Atomic commits**: One logical change per commit, passes tests, reversible.

## Non-Obvious Flags

- **`-u`**: Use on first push to set upstream tracking
- **`--force-with-lease`**: Safe force push for personal branches - required for stacked PRs after rebase, see `@stacks/SKILL.md`
- **`--no-ff`**: Preserve merge commit for feature branches (maintains history)
- **`-S`**: GPG sign commits

<related>

- `@stacks/SKILL.md` - Stacked PR workflows (uses linear history, force-with-lease)
- `@gh-pr/SKILL.md` - PR creation, review cycles, merge strategies
- `@gh-cli/SKILL.md` - GitHub CLI commands
- `@style/SKILL.md` - Naming conventions, conventional commits

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
