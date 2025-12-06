# Pull Request Workflows

<metadata>

- **Scope**: Platform-neutral pull request and workflow concepts
- **Load if**: Creating PRs, reviewing code, merging changes, working with any Git platform
- **Prerequisites**: [Git Standards](./rules-git.md)

</metadata>

This document defines **platform-neutral PR workflows** and best practices applicable to any Git platform (GitHub, GitLab, Bitbucket, Azure DevOps, etc.).

## Scope

- **This document**: PR concepts, code review workflows, merge strategies, agent guidelines
- **Platform-specific operations**: See platform-specific files (e.g., rules-github.md for GitHub CLI)
- **Local git operations**: See [Git Standards]($HOME/.smith/rules-git.md) for commits, branches, merges

## Pull Request Creation

### Prerequisites

<required>

- MUST run all quality checks before creating PR
- MUST ensure branch is up-to-date with base branch
- MUST have meaningful commit messages
- MUST link to related issues

</required>

**Pre-PR checklist:**
```sh
# Run formatters and linters
poetry run ruff format . && poetry run ruff check --fix .

# Run all tests
poetry run pytest

# Update from base branch
git fetch origin
git rebase origin/main  # or merge, depending on project

# Push your changes
git push -u origin feature/my-feature
```

### PR Title Format

<formatting>

**Format**: `type: description` or `type(scope): description`

Scope is optional. Choose type based on PRIMARY change:

- `feat`: New user-facing functionality
- `fix`: Bug fix for existing functionality
- `docs`: Documentation ONLY (no code changes)
- `refactor`: Code restructure without behavior change
- `style`: Formatting ONLY (whitespace, semicolons)
- `test`: Test changes ONLY
- `chore`: Build/tooling (CI, dependencies, scripts)
- `perf`: Performance improvement

</formatting>

<examples>

- `feat(rag): add semantic search filtering`
- `fix(api): resolve CORS issues`
- `docs: update deployment guide`
- `refactor(auth): extract validation logic`
- `test: add integration tests for search`

</examples>

<forbidden>

- Using `docs` when also changing code → use `feat` or `fix`
- Using `refactor` for bug fixes → use `fix`
- Using `chore` for new features → use `feat`

</forbidden>

### PR Body Template

```markdown
## Summary
- Bullet point 1: Main change
- Bullet point 2: Additional change
- Bullet point 3: Impact or benefit

## Test Plan
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing completed
- [ ] Documentation updated

## Related Issues
Closes #123
Fixes #456

Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### PR Requirements

<required>

- MUST have descriptive title following conventional commits format
- MUST include summary (1-3 bullet points)
- MUST include test plan with checklist
- MUST link to related issues
- MUST have all CI checks passing
- MUST have minimum 1 approval (if enforced by project)

</required>

<forbidden>

- NEVER create PR with failing tests
- NEVER merge PR with unresolved conflicts
- NEVER skip CI checks
- NEVER merge without required approvals

</forbidden>

### Stacked PRs

<required>

For large features, use stacked PRs to maintain atomic, reviewable changes.

**When to stack**:
- Feature requires 500+ lines of changes
- Multiple logical components that can be reviewed independently
- Need to unblock dependent work before full feature is ready

**How to stack**:
1. Create base PR with foundation (e.g., `feature/auth-base`)
2. Create child PR branching from base (e.g., `feature/auth-login` from `feature/auth-base`)
3. Each PR should be independently reviewable and mergeable
4. Merge bottom-up: base first, then children

</required>

<examples>

**Stack structure**:
```
main
 └── feature/auth-base (PR #1: models, migrations)
      └── feature/auth-login (PR #2: login endpoint)
           └── feature/auth-oauth (PR #3: OAuth integration)
```

**PR description for stacked PRs**:
```markdown
## Stack
- **Depends on**: #123 (feature/auth-base) ← This PR requires #123 to be merged first
- **Blocks**: #125 (feature/auth-oauth) ← PR #125 depends on this PR
```

**Field meanings**:
- `Depends on`: PRs that must merge before this one (upstream dependencies)
- `Blocks`: PRs waiting for this one to merge (downstream dependents)

</examples>

### Stacked PR Merge Workflow

<required>

**Sequential merge order** (bottom-up):
1. Wait for parent PR approval
2. Merge parent PR into `main`
3. Rebase child PR onto updated `main`
4. Get child PR approved
5. Repeat for each level in stack

</required>

<forbidden>

- NEVER merge child PR before parent (merges into parent branch, not main)
- NEVER merge main directly into child branch (corrupts history)
- NEVER use squash merge for non-final PRs in a stack

</forbidden>

<examples>

**Correct merge sequence**:
```text
1. Merge PR #1 (feature/auth-base) → main
2. Rebase PR #2 (feature/auth-login) onto main
3. Merge PR #2 → main
4. Rebase PR #3 (feature/auth-oauth) onto main
5. Merge PR #3 → main (can squash this one)
```

</examples>

### Rebasing After Parent Merges

<required>

When a parent PR merges, child PRs must be rebased:

1. Fetch latest changes
2. Checkout child branch
3. Rebase onto updated main
4. Force push (safe for your PR branch)

```sh
git fetch origin
git checkout feature/auth-login
git rebase --onto origin/main feature/auth-base
git push --force-with-lease
```

**Why `--onto`**: Only transplants commits unique to child branch (commits between parent and child), avoiding duplicate commits.

</required>

<examples>

**Before rebase** (after parent merged):
```text
main ──●──●──●──M (parent merged as M)
                 \
feature/auth-login ──A──B──C (still based on old parent)
```

**After `git rebase --onto origin/main feature/auth-base`**:
```text
main ──●──●──●──M
                 \
                  └──A'──B'──C' (feature/auth-login rebased)
```

</examples>

### Squash Merge Restrictions

<forbidden>

**NEVER squash merge parent PRs in a stack.**

Squash merge creates a single commit, destroying commit ancestry. Child branches still contain parent's original commits, causing:
- Duplicate commits in child PR
- Merge conflicts when rebasing
- Git unable to recognize commits already in main

</forbidden>

<required>

**Merge strategy by position**:

| PR Position | Allowed Merge Strategy |
|-------------|----------------------|
| Parent (base) | Merge commit only |
| Middle | Merge commit only |
| Final (leaf) | Any (squash OK) |

</required>

<examples>

**Workaround if squash merge was used**:

Option 1 - Rebase with `--fork-point`:
```sh
git fetch origin
git checkout feature/auth-login
git rebase --onto origin/main --fork-point origin/feature/auth-base
git push --force-with-lease
```

Option 2 - Interactive rebase to drop parent's commits:
```sh
git checkout main && git pull
git checkout feature/auth-login
git rebase -i main
```
In the interactive editor, mark all commits from the parent branch as `drop`.

</examples>

### Keeping Stack Updated

<required>

When pulling changes from main into a stack, cascade updates through the stack sequentially:

```sh
git checkout feature/auth-base
git merge main
git push

git checkout feature/auth-login
git merge feature/auth-base
git push
```

</required>

<forbidden>

Merging main directly into a child branch corrupts history:

```sh
git checkout feature/auth-login
git merge main
```

</forbidden>

### Stacked PR References

- [How to handle stacked PRs on GitHub](https://www.nutrient.io/blog/how-to-handle-stacked-pull-requests-on-github/)
- [Stacked pull requests with squash merge](https://echobind.com/post/stacked-pull-requests-with-squash-merge/)
- [How to merge stacked PRs in GitHub](https://graphite.com/guides/how-to-merge-stack-pull-requests-github)

## Working on Existing PRs

### CRITICAL: Always Use Actual Branch Name

<forbidden>

**NEVER create arbitrary local branch names when working on PRs:**

- ❌ Create local branches with assumed names like `pr-123`
- ❌ Assume branch name follows a pattern
- ❌ Make changes without verifying current branch

</forbidden>

<required>

**ALWAYS get and use the actual PR branch name:**

```sh
# 1. Get actual branch name from your platform
# (Use your platform's CLI or UI to find the branch name)

# 2. Fetch and checkout from origin
git fetch origin
git checkout -b "<actual-branch-name>" "origin/<actual-branch-name>"

# 3. VERIFY you're on the correct branch
git branch --show-current  # MUST match the PR's actual branch name

# 4. Before making ANY changes, verify again
git status  # Should show "On branch <actual-branch-name>"
```

</required>

### Why This Matters

**Problem**: Creating local branches with assumed names that don't match the PR's actual branch name.

**Impact**:
- Your changes won't push to the PR
- You're working on a disconnected branch
- Risk of losing work or creating merge conflicts

**Solution**: Always verify the PR's actual branch name from your platform, then checkout from origin.

### Recovery if You Made This Mistake

If you already made changes to the wrong branch:

```sh
# 1. Get the actual branch name from your platform

# 2. Checkout the correct branch
git checkout "<actual-branch-name>"

# 3. Cherry-pick your commits from the wrong branch
git cherry-pick <commit-sha-from-wrong-branch>

# 4. Delete the wrong branch
git branch -D <wrong-branch-name>
```

## Code Review Process

### Requesting Review

**Best practices:**
- Request reviews from relevant team members
- Provide context in PR description
- Link to design docs or RFCs if applicable
- Highlight areas needing special attention
- Ensure all CI checks are passing before requesting review

### Responding to Reviews

**Address all comments:**
1. Read all review comments carefully
2. Respond to each comment thread
3. Make requested changes
4. Test your changes thoroughly
5. Mark conversations as resolved
6. Re-request review after changes

**Workflow:**
```sh
# Make changes based on review feedback
git add .
git commit -m "refactor: address review comments"

# Push changes
git push

# Respond to review comments in your platform's UI
# Re-request review through your platform
```

### Giving Reviews

**Review checklist:**
- [ ] Code follows project standards
- [ ] Tests are adequate and passing
- [ ] Documentation is updated
- [ ] No security vulnerabilities
- [ ] Performance considerations addressed
- [ ] Error handling is appropriate
- [ ] Changes are focused and don't include unrelated modifications

**Review types:**
- **Approve**: Code is ready to merge
- **Request changes**: Issues must be addressed before merging
- **Comment**: Suggestions or questions, but not blocking

## Merging Pull Requests

### Pre-Merge Checklist

<required>

- MUST have all CI checks passing
- MUST have required approvals
- MUST be up-to-date with base branch
- MUST have no merge conflicts
- MUST have related issues linked

</required>

### Merge Strategies

**Merge commit:**
- Creates a merge commit preserving all individual commits
- **Use for**: Feature branches with multiple logical commits
- Maintains complete history of branch development

**Squash and merge:**
- Combines all commits into a single commit
- **Use for**: Small fixes, documentation updates, single logical change
- Clean main branch history, but loses individual commit history

**Rebase and merge:**
- Replays commits on top of base branch
- **Use for**: When linear history is required and commits are clean
- No merge commits, but rewrites history

**When to use each:**
- **Merge commit**: Feature branches with meaningful commit history
- **Squash**: Tiny fixes, doc updates, experimental branches with messy commits
- **Rebase**: Projects requiring linear history with clean commits

### Post-Merge Cleanup

```sh
# Switch to main branch
git checkout main

# Pull latest changes
git pull origin main

# Delete local feature branch
git branch -d feature/my-feature

# Delete remote feature branch (if not auto-deleted)
git push origin --delete feature/my-feature
```

## Agent-Created Pull Requests

**Context**: AI agents (Claude Code, GitHub Copilot) creating PRs

<required>

- Agent MUST analyze full commit history from base branch divergence
- Agent MUST review ALL changed files (not just latest commit)
- Agent MUST write summary based on actual cumulative changes
- Agent MUST run all checks before PR creation
- Agent MUST verify branch tracks correct remote

</required>

**Workflow**:
```sh
# 1. Understand full scope of changes
git diff base...HEAD  # See all cumulative changes
git log base..HEAD    # Review all commits that will be included

# 2. Analyze cumulative impact (not just latest commit)
# Read all modified files
# Understand how commits work together

# 3. Draft summary covering ALL changes
# NOT just latest commit - entire PR scope
# 1-3 bullets covering cumulative impact

# 4. Create test plan
# Based on all changes, not just latest

# 5. Run pre-PR checks
poetry run ruff format . && poetry run ruff check --fix .
poetry run pytest

# 6. Create PR with structured body
# Use platform CLI or API
```

### Common Agent Mistakes

<forbidden>

- **NEVER** analyze only the latest commit for PR summary
- **NEVER** skip full diff review (base...HEAD)
- **NEVER** create PR without running checks
- **NEVER** assume file contents without reading
- **NEVER** write generic summaries ("updated files")

</forbidden>

**Example - Bad vs Good**:
```markdown
❌ Bad (only looked at latest commit):
Summary:
- Fixed typo in README

(But PR actually includes 5 commits adding entire auth system!)

✓ Good (analyzed full diff):
Summary:
- Implement OAuth2 authentication with token refresh
- Add rate limiting to prevent abuse (10 req/min)
- Update API documentation with auth examples

(Accurately reflects all 5 commits in the PR)
```

### PR Analysis Checklist

<required>

Before creating PR, agent MUST:

1. Run `git diff base...HEAD` to see cumulative changes
2. Run `git log base..HEAD` to see all commits
3. Read all modified files (not assume contents)
4. Identify cumulative impact across all commits
5. Verify tests pass for all changes
6. Draft summary reflecting full PR scope

</required>

**See**: `$HOME/.smith/rules-ai_agents.md` - Complete agent interaction standards

## Agent Workflow Guidelines

### Pre-Commit Hook Coordination

<scenario>

**When hooks modify files during commit:**

1. Pre-commit hook runs automatically
2. Hook modifies files (formatting, linting fixes)
3. Commit fails with "files were modified by hook"

</scenario>

<required>

**Workflow for hook modifications:**

```sh
# 1. Make your changes
git add .
git commit -m "feat: add feature"

# 2. If pre-commit modifies files, commit fails
# Files are now staged with hook's modifications

# 3. VERIFY what changed
git diff --cached

# 4. VERIFY commit safety before amending
git log -1 --format='%an %ae'  # Check author is you
git status  # Check not pushed yet

# 5. IF SAFE: Amend to include hook changes
git commit --amend --no-edit

# 6. IF UNSAFE: Create new commit instead
git commit -m "style: apply pre-commit hook fixes"
```

</required>

<forbidden>

- **NEVER** amend without checking commit authorship
- **NEVER** amend commits already pushed to remote
- **NEVER** amend commits from other authors

</forbidden>

**Decision tree:**
- ✅ Amend IF: You authored last commit AND commit not pushed yet
- ❌ New commit IF: Last commit from someone else OR already pushed

### CI Check Coordination

<required>

**Monitor CI status before and after changes:**

```sh
# 1. Check current CI status in your platform's UI

# 2. After making changes and pushing
git push

# 3. Monitor CI checks in your platform's UI
# Wait for all checks to complete

# 4. If checks fail, investigate
# View logs in your platform's UI

# 5. Fix issues and push again
git add .
git commit -m "fix: resolve CI check failures"
git push
```

</required>

<forbidden>

- **NEVER** request review while CI checks are failing
- **NEVER** ignore CI check failures
- **NEVER** merge with failing checks

</forbidden>

**Best practices:**
- Wait for all checks to pass before requesting review
- If checks fail, fix immediately before other work
- Monitor checks continuously to catch failures early

### Amend Operations Safety

<forbidden>

**NEVER amend in these scenarios:**

- ❌ Commit authored by someone else
- ❌ Commit already pushed to remote (unless you force push intentionally)
- ❌ Working on protected branches (main, develop)
- ❌ Commit is part of a PR under active review by others

</forbidden>

<required>

**Verification checklist before amending:**

```sh
# 1. Check commit authorship
AUTHOR=$(git log -1 --format='%ae')
if [ "$AUTHOR" != "your-email@example.com" ]; then
  echo "Not your commit - create new commit instead"
  exit 1
fi

# 2. Check if commit is pushed
if git log @{upstream}.. | grep -q $(git rev-parse HEAD); then
  echo "Commit not pushed yet - safe to amend"
else
  echo "Commit already pushed - avoid amending"
fi

# 3. Check branch protection
BRANCH=$(git branch --show-current)
if [[ "$BRANCH" == "main" || "$BRANCH" == "develop" ]]; then
  echo "Protected branch - DO NOT AMEND"
  exit 1
fi
```

</required>

**Safe amend scenarios:**
- ✅ Pre-commit hook modified files (see Pre-Commit Hook Coordination)
- ✅ Fixing typo in commit message you just made
- ✅ Adding forgotten file to your last commit (before push)

**When to create new commit instead:**
- 📝 Addressing review feedback (keep review history)
- 📝 Fixing bugs found after push
- 📝 Any change to commits from other authors

### Review Response Workflow

<required>

**Systematic approach to address review comments:**

```sh
# 1. Fetch latest review comments from your platform

# 2. For each comment thread:
#    - Understand the concern
#    - Make necessary code changes
#    - Test the changes
#    - Commit with descriptive message

git add .
git commit -m "refactor: extract validation logic per review"

# 3. Push all changes together
git push

# 4. Respond to review comments in your platform's UI
# Explain what you changed and why

# 5. Re-request review through your platform
```

</required>

**Best practices:**
- Group related fixes into single commit when logical
- Write clear commit messages referencing review feedback
- Respond to each comment thread explaining your changes
- Re-request review only after all comments addressed

### Troubleshooting Common Issues

#### Issue 1: Changes Not Appearing in PR

**Symptoms**: You made changes and committed but PR doesn't show them

**Diagnosis:**
```sh
# Check which branch you're on
git branch --show-current

# Check if branch tracks remote correctly
git branch -vv

# Verify the PR's actual branch name in your platform
```

**Solution:**
```sh
# If on wrong branch, see "Recovery if You Made This Mistake" above

# If branch doesn't track remote
git branch --set-upstream-to=origin/<branch-name>
git push
```

#### Issue 2: Merge Conflicts After Base Branch Update

**Symptoms**: PR shows merge conflicts with base branch

**Diagnosis:**
```sh
# Check if base branch updated
git fetch origin
git log HEAD..origin/main  # Check what changed in main
```

**Solution:**
```sh
# Update local main
git fetch origin main:main

# Rebase your branch
git rebase main

# Resolve conflicts if any
git status  # See conflicting files
# Edit files to resolve conflicts
git add .
git rebase --continue

# Force push (safe because it's your PR branch)
git push --force-with-lease
```

#### Issue 3: CI Checks Fail After Pre-Commit Hook

**Symptoms**: Pre-commit passes locally but CI fails

**Solution:**
```sh
# CI may have different tool versions
# Check CI config to match versions locally

# Run checks exactly as CI does
poetry run ruff check . --config=<same-as-ci>
poetry run pytest --cov=<same-as-ci>
```

### Recovery Procedures

#### Scenario 1: Wrong Branch Checkout

**Problem**: Made changes to wrong branch

**Solution**: See "Recovery if You Made This Mistake" section above

#### Scenario 2: Accidentally Pushed to Wrong Remote

**Problem**: Pushed PR branch to wrong repository

**Solution:**
```sh
# 1. Check remotes
git remote -v

# 2. Remove wrong remote
git remote remove wrong-remote

# 3. Add correct remote if needed
git remote add origin <correct-repo-url>

# 4. Push to correct remote
git push -u origin <branch-name>
```

#### Scenario 3: Need to Undo Last Commit but Keep Changes

**Problem**: Made commit but want to redo it differently

**Solution:**
```sh
# Undo commit but keep changes staged
git reset --soft HEAD~1

# Or: Undo commit and unstage changes
git reset HEAD~1

# Make new commit with changes
git add .
git commit -m "better commit message"
```

#### Scenario 4: Syncing with Updated Base Branch

**Problem**: Base branch (main/develop) has new commits

**Solution:**
```sh
# Fetch latest
git fetch origin

# Option 1: Rebase (clean history)
git rebase origin/main
git push --force-with-lease

# Option 2: Merge (preserve history)
git merge origin/main
git push
```

## Best Practices

### PR Size

- Keep PRs focused and small (< 400 lines changed ideal)
- Split large features into multiple PRs
- Use draft PRs for work in progress
- One logical change per PR

### Communication

- Use PR comments for technical discussions
- Use issue comments for requirements and planning
- Tag relevant team members with @mentions
- Be respectful and constructive in reviews
- Explain your reasoning in review responses

### Documentation

- Update README if public API changes
- Update CHANGELOG for notable changes
- Add inline code comments for complex logic
- Include examples in PR description for new features

### CI Integration

- Ensure all tests run in CI
- Set up automatic deployment previews when possible
- Configure status checks as required
- Monitor CI failures and fix promptly

## Related Standards

- **Git Operations**: `$HOME/.smith/rules-git.md` - Commits, branches, merges
- **Development Workflow**: `$HOME/.smith/rules-development.md` - Daily practices, quality gates
- **Testing**: `$HOME/.smith/rules-testing.md` - Test requirements
- **Platform-Specific**: See your platform's rules file (e.g., rules-github.md for GitHub CLI)
