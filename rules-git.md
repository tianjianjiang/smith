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

### Branch Naming Conventions

<formatting>

**Pattern**: `type/descriptive_name` (e.g., `feature/user_authentication`, `fix/JIRA-1234-query_processor`)

**Separator Rules** (see [Dash on Wikipedia](https://en.wikipedia.org/wiki/Dash)):

| Separator | Use Case | Example |
|-----------|----------|---------|
| Underscore (_) | Multi-word phrases/concepts | `user_authentication`, `semantic_search` |
| Hyphen (-) | Parts/subsets of a whole | `auth-login`, `auth-password` (login/password are parts of auth) |
| Hyphen (-) | Co-existing/differentiation | `api-rest`, `api-graphql` |
| Hyphen (-) | ISO dates | `2025-01-15` |
| Hyphen (-) | Ticket IDs | `JIRA-1234`, `GH-567` |

</formatting>

<examples>

- `docs/enhance_agents_md` (multi-word concept)
- `feature/user_authentication` (multi-word concept)
- `feature/auth-login` (login is subset of auth module)
- `feature/api-rest` (rest is a variant/type of api)
- `fix/JIRA-1234-query_processor` (ticket ID + concept)
- `feature/GH-123-semantic_search-2025-01-15` (ticket + concept + date)

</examples>

<forbidden>

- `docs/enhance-agents-md` (hyphen for multi-word phrase - should be underscore)
- `feature/add-semantic-search` (hyphens joining words in a phrase)
- `fix/query-processor-null-check` (excessive hyphens for simple phrase)

</forbidden>

## Commit Standards

<formatting>

**Conventional Commits Format**: `type: description` or `type(scope): description`

Scope is optional. Example structure:
```text
feat(auth): add OAuth2 login

Implement OAuth2 authentication flow with token refresh.
Supports Google and GitHub providers.

Closes #123
```

</formatting>

<required>

**Subject line limits** ([50/72 Rule](https://dev.to/noelworden/improving-your-commit-message-with-the-50-72-rule-3g79)):
- **Target**: 50 characters (ideal for `git log --oneline`)
- **Hard limit**: 72 characters (80-char terminal - 4-char git indent - 4-char margin)

**Body line limit**: 72 characters per line

**Atomicity indicator**: Exceeding 50 chars suggests combining multiple changes. Split into separate commits.

</required>

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, no logic change)
- `refactor`: Code refactoring
- `test`: Test additions or changes
- `chore`: Build process, tooling changes

<examples>

```sh
git commit -m "feat(rag): add semantic search filtering

Implement metadata-based filtering for semantic search queries.
Supports multiple filter conditions with AND/OR logic.

Closes #123"
```

</examples>

## File Operations

**Renaming files:**

<required>

- MUST use `git mv` for renames (preserves Git history)
- NEVER delete + recreate (loses history)

</required>

<examples>

```sh
git mv old_name.py new_name.py
git commit -m "refactor: rename old_name to new_name"
```

</examples>

**Large file handling:**
- Use `.gitignore` for build artifacts, debug outputs, `.venv`
- Never commit secrets, API keys, or `.env` files
- Use Git LFS for large binary files if needed

## Commit Workflow

<examples>

**Before committing:**
```sh
poetry run ruff check --fix
poetry run ruff format
poetry run pytest
```

</examples>

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

### GPG Signing

<required>

All commits MUST be GPG signed.

```sh
git commit -S -m "type: description"
```

GPG should be pre-configured for automatic signing.

</required>

### Linear History

<required>

Maintain linear commit history for clarity and bisectability.

- Use rebase to update feature branches: `git rebase main`
- Squash WIP commits before merging
- Each commit should be a complete, working unit
- Avoid merge commits in feature branches

</required>

### Atomic Commits

<required>

Each commit MUST be:
- **Logically atomic**: One coherent change per commit
- **Semantically complete**: Passes tests, compiles, works independently
- **Reversible**: Can be reverted without breaking other changes

</required>

<examples>

```text
# Good: Three separate commits for three logical changes
git commit -m "feat(auth): add OAuth2 login flow"
git commit -m "fix(auth): resolve token refresh race condition"
git commit -m "docs(auth): update authentication guide"
```

</examples>

<forbidden>

```text
# Bad: Single commit with unrelated changes
git commit -m "feat(auth): add OAuth2 login, fix token bug, update docs"
```

</forbidden>

### Atomic Workflow

<required>

Workflow for new work:

1. Create branch with correct naming
2. Make changes in atomic commits with GPG signing
3. Push branch to remote
4. Create PR (recommended)

```sh
git checkout -b "type/descriptive_name"
git add .
git commit -S -m "type: description"
git push -u origin "type/descriptive_name"
gh pr create --title "type: description" --body "..."
```

</required>

## Merge Strategy

**Feature branches:**
```sh
git checkout develop
git pull origin develop
git merge --no-ff feature/my_feature
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
```sh
git fetch origin
git pull origin develop
```

**Push branches:**
```sh
git push origin feature/my_feature
git push -u origin feature/my_feature  # First push with tracking
```

<forbidden>

- NEVER use `git push --force` on main or develop
- NEVER push without pulling latest changes first

</forbidden>

**Force push (only for personal feature branches):**
```sh
git push --force-with-lease origin feature/my_feature
```

### Post-Merge Local Sync

<required>

After merging a PR (yours or someone else's), sync local repository:

```sh
git fetch origin              # Update remote tracking refs
git checkout main && git pull # Sync local main
```

**Why both commands:**
- `git fetch`: Updates `origin/main` reference without modifying working directory
- `git pull`: Fast-forwards local `main` to match remote

</required>

<forbidden>

- Working on stale local main (always pull after merges)
- Forgetting to fetch (remote refs become outdated)

</forbidden>

## Stash Management

<examples>

```sh
git stash push -m "WIP: feature implementation"
git stash list
git stash pop
git stash apply stash@{0}
```

</examples>

## History Management

<examples>

**View history:**
```sh
git log --oneline --graph --decorate
git log --author="name" --since="2 weeks ago"
git diff main...feature/branch  # Changes since branching
```

**Interactive rebase (local only):**
```sh
git rebase -i HEAD~3  # Last 3 commits
```

**Amend last commit (before push):**
```sh
git commit --amend --no-edit
git commit --amend  # Edit message
```

</examples>

## Conflict Resolution

**When conflicts occur:**
1. Pull latest changes: `git pull origin develop`
2. Resolve conflicts in IDE or editor
3. Stage resolved files: `git add <file>`
4. Continue: `git rebase --continue` or `git merge --continue`
5. Test thoroughly before pushing

**Abort if needed:**
```sh
git rebase --abort
git merge --abort
```

## Related Standards

- **PR Workflows**: `$HOME/.smith/rules-pr.md` - Pull request workflows, agent guidelines
- **GitHub Workflows**: `$HOME/.smith/rules-github.md` - GitHub CLI operations
- **Development Workflow**: `$HOME/.smith/rules-development.md` - Daily practices
- **Naming Conventions**: `$HOME/.smith/rules-naming.md` - Branch naming
- **Personal Rules**: `$HOME/.smith/rules-core.md` - Core standards
