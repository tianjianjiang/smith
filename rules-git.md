# Git Workflow Standards

---
name: Git Workflow Standards
description: Standards for branching, commits, and PRs
triggers:
  - git operations
  - branching
  - merging
prerequisites: rules-core.md
---


This document defines **local Git operations** and workflow standards.

## Scope

- **This document**: Local git commands, branching, commits, merges, history, conflict resolution
- **GitHub workflows**: See [GitHub Standards]($HOME/.smith/rules-github.md) for PRs, code reviews, gh CLI, protected branches

## Branch Strategy

**Branch Structure:**
- `main` - Production-ready code
- `develop` - Integration branch for features
- `feature/*` - Feature branches from develop
- `hotfix/*` - Emergency fixes from main

**Prohibited:**
- **NEVER** commit directly to main branch
- **NEVER** force push to main or develop branches
- **NEVER** use `--no-verify` flag (always run hooks)

**Requirements:**
- **MUST** create feature branches from develop
- **MUST** use merge commits for feature branches (preserves history)
- **MUST** keep branches up-to-date with base branch

### Branch Naming

**Pattern**: `type/descriptive-name`

**Types** (short or long form):
- `feature/` or `feat/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation changes
- `refactor/` - Code refactoring
- `test/` - Test additions
- `chore/` - Maintenance tasks

**Examples**:
<example>
feature/user_authentication
feat/login_system
fix/login_validation
fix/null_pointer
docs/api_endpoints
refactor/database_schema
</example>

**Note**: Conventional commits use short forms (feat, fix), but branches can use either short or long forms. See [Naming Standards](rules-naming.md) for detailed conventions.

**Prohibited:**
- **NEVER** use conventional commit format in branch names (e.g., `feat(scope): description`)
- **NEVER** use uppercase letters

### Stacked Pull Requests

**Use for large features:**
- Break large features into dependent branches: `feat/part_1` -> `feat/part_2`
- **Naming**: `feature/my_feat_part1`, `feature/my_feat_part2`
- **Workflow**:
  1. Create `part_1` from `develop`
  2. Create `part_2` from `part_1`
  3. Submit PR for `part_1` (target: `develop`)
  4. Submit PR for `part_2` (target: `part_1` initially, or `develop` but mark as dependent)
- **Tools**: Use `git rebase --onto` to update dependent branches when base changes

### Signed Commits

**Requirements:**
- **MUST** sign all commits using GPG/SSH (`git commit -S`)
- **MUST** verify signature setup in GitHub settings

**Why**: Verifies identity and prevents impersonation.


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

## Atomic Commits

**Definition**: A commit should contain a **single logical change** that leaves the codebase in a working state.

**Requirements:**
- **Single Responsibility**: One commit = one fix, one feature, or one refactor. **NEVER** mix them.
- **Passing Tests**: Every commit **MUST** pass tests. Do not commit broken code.
- **Revertible**: You should be able to revert the commit without side effects on unrelated features.

**Workflow**:
1. `git add -p` (patch mode) to stage specific chunks.
2. `git stash` unrelated changes.
3. Commit the focused change.
4. Unstash and repeat.

## File Operations

**Renaming files:**
**Requirements:**
- **MUST** use `git mv` for renames (preserves Git history)
- **NEVER** delete + recreate (loses history)

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

**Prohibited:**
- **NEVER** skip pre-commit hooks with `--no-verify`
- **NEVER** commit files without running quality checks
- **NEVER** commit with failing tests

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

**Requirements:**
- **MUST** use merge commits (`--no-ff`) for feature branches
- **MUST** resolve conflicts locally before pushing
- **MUST** ensure all tests pass after merge

**When to squash:**
- Tiny fixes (typos, formatting)
- WIP commits that should be single logical change
- **NEVER** squash feature branches with multiple logical changes

**When to rebase:**
- Updating feature branch with latest develop
- Cleaning up local commits before push
- **NEVER** rebase shared branches (main, develop)

### Linear History

**Goal**: Maintain a clean, linear history on `develop` and `main` where possible, but preserve feature context.

- **Local Development**: Rebase frequently on `develop` to keep feature branch linear relative to base.
  ```bash
  git fetch origin
  git rebase origin/develop
  ```
- **Squashing**: Squash "WIP" or "fix typo" commits before merging to keep history clean.
- **Merge**: Use `--no-ff` for feature merges to preserve the "feature bubble" in history, but ensure the feature branch itself is clean (atomic commits).

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

**Prohibited:**
- **NEVER** use `git push --force` on main or develop
- **NEVER** push without pulling latest changes first

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

- **GitHub Workflows**: `$HOME/.smith/rules-github.md` - PR creation, reviews
- **Development Workflow**: `$HOME/.smith/rules-development.md` - Daily practices
- **Naming Conventions**: `$HOME/.smith/rules-naming.md` - Branch naming
- **Personal Rules**: `$HOME/.smith/rules-core.md` - Core standards
