---
name: git
description: Git workflow standards with branch strategy, commit conventions, and merge patterns. Use when performing Git commits, merges, branch management, rebasing, or conflict resolution. Covers GPG signing, atomic commits, and remote operations.
---

# Git Workflow Standards

<metadata>

- **Load if**: Git commits, merges, branch management
- **Prerequisites**: @principles/SKILL.md, @standards/SKILL.md

</metadata>

## CRITICAL (Primacy Zone)

<forbidden>

- NEVER commit directly to main branch
- NEVER force push to main or develop
- NEVER use `--no-verify` (always run hooks)
- NEVER amend commits already pushed to remote
- NEVER amend commits authored by others
- NEVER rebase shared branches (main, develop)

</forbidden>

<required>

- MUST create feature branches from develop
- MUST use `git mv` for renames (preserves history)
- MUST GPG sign all commits: `git commit -S -m "..."`
- MUST keep branches linear (prefer rebase over merge)

</required>

## Branch Strategy

- **`main`**: Production-ready
- **`develop`**: Integration
- **`feat/*`**: Features from develop
- **`fix/*`**: Bug fixes (including emergency fixes from main)

**Naming**: `type/descriptive_name` (e.g., `feat/user_auth`, `fix/JIRA-1234-query`)

## Commit Standards

**Format**: See `@style/SKILL.md#conventional-commits`

```shell
git commit -S -m "feat(auth): add OAuth2 login

Implement OAuth2 authentication flow.
Closes #123"
```

**Atomic commits**: One logical change per commit, passes tests, reversible.

## Merge Strategy

Feature merge (use --no-ff):
```shell
git checkout develop && git pull
git merge --no-ff feat/my_feature
git push origin develop
```

**Squash**: Only for tiny fixes, WIP cleanup
**Rebase**: Update feature branch from develop (never shared branches)

## Working with Remotes

```shell
git fetch origin
git pull origin develop
git push -u origin feat/my_feature
git push --force-with-lease origin feat/my_feature
```

Use `-u` for first push. Use `--force-with-lease` for personal branches only.

## Post-Merge Sync

```shell
git fetch origin
git checkout main && git pull
```

## Conflict Resolution

1. `git pull origin develop`
2. Resolve conflicts in editor
3. `git add <file>`
4. `git rebase --continue` or `git merge --continue`
5. Test before pushing

**Abort**: `git rebase --abort` or `git merge --abort`

<related>

- `@gh-pr/SKILL.md` - PR workflows
- `@gh-cli/SKILL.md` - GitHub CLI
- `@style/SKILL.md` - Naming conventions

</related>

## ACTION (Recency Zone)

**New feature workflow:**
```shell
git checkout -b "feat/user_auth"
git add .
git commit -S -m "feat: add user authentication"
git push -u origin "feat/user_auth"
gh pr create --title "feat: add user auth" --body "..." --assignee @me
```

**Before commit:**
```shell
poetry run ruff check --fix
poetry run ruff format
poetry run pytest
```

**Stash:**
```shell
git stash push -m "feat: feature #WIP"
git stash pop
```

**History:**
```shell
git log --oneline --graph --decorate
git rebase -i HEAD~3
```

Interactive rebase for local commits only.
