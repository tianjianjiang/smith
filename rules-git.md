# Git Workflow Standards

This document defines **local Git operations** and workflow standards.

## Scope

- **This document**: Local git commands, branching, commits, merges, history, conflict resolution
- **PR workflows**: See [PR Workflows]($HOME/.smith/rules-pr.md) for pull request workflows, code reviews, agent guidelines
- **GitHub operations**: See [GitHub Standards]($HOME/.smith/rules-github.md) for GitHub CLI commands

## Branch Strategy

**Branch Structure:**
- `main` - Production-ready code
- `develop` - Integration branch for features
- `feature/*` - Feature branches from develop
- `hotfix/*` - Emergency fixes from main

<forbidden>
- NEVER commit directly to main branch
- NEVER force push to main or develop branches
- NEVER use `--no-verify` flag (always run hooks)
</forbidden>

<required>
- MUST create feature branches from develop
- MUST use merge commits for feature branches (preserves history)
- MUST keep branches up-to-date with base branch
</required>

## Commit Standards

**Conventional Commits Format:**
```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, no logic change)
- `refactor`: Code refactoring
- `test`: Test additions or changes
- `chore`: Build process, tooling changes

**Example:**
```bash
git commit -m "feat(rag): add semantic search filtering

Implement metadata-based filtering for semantic search queries.
Supports multiple filter conditions with AND/OR logic.

Closes #123"
```

## File Operations

**Renaming files:**
<required>
- MUST use `git mv` for renames (preserves Git history)
- NEVER delete + recreate (loses history)
</required>

```bash
git mv old_name.py new_name.py
git commit -m "refactor: rename old_name to new_name"
```

**Large file handling:**
- Use `.gitignore` for build artifacts, debug outputs, `.venv`
- Never commit secrets, API keys, or `.env` files
- Use Git LFS for large binary files if needed

## Commit Workflow

**Before committing:**
```bash
poetry run ruff check --fix
poetry run ruff format
poetry run pytest
```

<forbidden>
- NEVER skip pre-commit hooks with `--no-verify`
- NEVER commit files without running quality checks
- NEVER commit with failing tests
</forbidden>

**Commit message guidelines:**
- Write meaningful descriptions (why, not what)
- Reference issues with `#123` or `Closes #123`
- Keep subject line under 72 characters
- Use imperative mood ("add feature" not "added feature")

## Merge Strategy

**Feature branches:**
```bash
git checkout develop
git pull origin develop
git merge --no-ff feature/my-feature
git push origin develop
```

<required>
- MUST use merge commits (`--no-ff`) for feature branches
- MUST resolve conflicts locally before pushing
- MUST ensure all tests pass after merge
</required>

**When to squash:**
- Tiny fixes (typos, formatting)
- WIP commits that should be single logical change
- **NEVER** squash feature branches with multiple logical changes

**When to rebase:**
- Updating feature branch with latest develop
- Cleaning up local commits before push
- **NEVER** rebase shared branches (main, develop)

## Working with Remotes

**Fetch and pull:**
```bash
git fetch origin
git pull origin develop
```

**Push branches:**
```bash
git push origin feature/my-feature
git push -u origin feature/my-feature  # First push with tracking
```

<forbidden>
- NEVER use `git push --force` on main or develop
- NEVER push without pulling latest changes first
</forbidden>

**Force push (only for personal feature branches):**
```bash
git push --force-with-lease origin feature/my-feature
```

## Stash Management

**Save work in progress:**
```bash
git stash push -m "WIP: feature implementation"
git stash list
git stash pop
git stash apply stash@{0}
```

## History Management

**View history:**
```bash
git log --oneline --graph --decorate
git log --author="name" --since="2 weeks ago"
git diff main...feature/branch  # Changes since branching
```

**Interactive rebase (local only):**
```bash
git rebase -i HEAD~3  # Last 3 commits
```

**Amend last commit (before push):**
```bash
git commit --amend --no-edit
git commit --amend  # Edit message
```

## Conflict Resolution

**When conflicts occur:**
1. Pull latest changes: `git pull origin develop`
2. Resolve conflicts in IDE or editor
3. Stage resolved files: `git add <file>`
4. Continue: `git rebase --continue` or `git merge --continue`
5. Test thoroughly before pushing

**Abort if needed:**
```bash
git rebase --abort
git merge --abort
```

## Related Standards

- **PR Workflows**: `$HOME/.smith/rules-pr.md` - Pull request workflows, agent guidelines
- **GitHub Workflows**: `$HOME/.smith/rules-github.md` - GitHub CLI operations
- **Development Workflow**: `$HOME/.smith/rules-development.md` - Daily practices
- **Naming Conventions**: `$HOME/.smith/rules-naming.md` - Branch naming
- **Personal Rules**: `$HOME/.smith/rules-core.md` - Core standards
