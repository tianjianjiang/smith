# Pull Request Workflows

<metadata>

- **Scope**: Platform-neutral pull request concepts and best practices
- **Load if**: Creating PRs, reviewing code, merging changes, working with any Git platform
- **Prerequisites**: rules-core.md, rules-git.md

</metadata>

<context>

## Scope

- **This document**: Platform-neutral PR concepts, code review workflows, merge strategies
- **GitHub PR operations**: rules-github-pr.md
- **Agent automation**: rules-github-agent-*.md
- **Local git operations**: rules-git.md

</context>

## Pull Request Creation

### Prerequisites

<constraints>

<required>

- MUST run all quality checks before creating PR
- MUST ensure branch is up-to-date with base branch
- MUST have meaningful commit messages
- MUST link to related issues

</required>

**Pre-PR checklist:**
```sh
poetry run ruff format . && poetry run ruff check --fix .
poetry run pytest
git fetch origin
git rebase origin/main
git push -u origin feature/my_feature
```

</constraints>

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

<required>

**Length limits** (PR title becomes merge commit subject):
- **Target**: 50 characters (forces conciseness)
- **Hard limit**: 72 characters (GitLab enforces, GitHub truncates)

**Atomicity indicator**: If title exceeds 50 chars, consider if PR combines multiple changes. Split into stacked PRs if needed.

</required>

<examples>

- `feat(rag): add semantic search filtering`
- `fix(api): resolve CORS issues`
- `docs: update deployment guide`
- `refactor(auth): extract validation logic`
- `test: add integration tests for search`

</examples>

<forbidden>

- PR title over 72 characters
- Multiple unrelated changes in title (e.g., "add X and fix Y and update Z")
- Using "and" to join unrelated changes (indicator of non-atomic PR)
- Using `docs` when also changing code → use `feat` or `fix`
- Using `refactor` for bug fixes → use `fix`
- Using `chore` for new features → use `feat`

</forbidden>

### PR Body Template

<examples>

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

</examples>

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

<context>

For large features, use stacked PRs to maintain atomic, reviewable changes.

**When to stack**:
- Feature requires 500+ lines of changes
- Multiple logical components that can be reviewed independently
- Need to unblock dependent work before full feature is ready

</context>

<required>

**How to stack**:
1. Create base PR with foundation (e.g., `feature/auth-base`)
2. Create child PR branching from base (e.g., `feature/auth-login` from `feature/auth-base`)
3. Each PR should be independently reviewable and mergeable
4. Merge bottom-up: base first, then children

</required>

<examples>

**Stack structure**:
```text
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

### Squash Merge with Stacked PRs

<required>

**Squash merge IS allowed** if you follow the branch deletion process for stacked PRs.

**Merge strategy by position**:

| PR Position | Squash Merge | Branch Deletion Timing |
|-------------|--------------|-----------------|
| Parent (has children) | OK with process | After child base updated |
| Middle | OK with process | After child base updated |
| Final (leaf) | OK | Immediate OK |

</required>

**Why squash merge requires extra steps**:

Squash merge creates a single commit, destroying commit ancestry. Child branches still contain parent's original commits, causing:
- Duplicate commits in child PR
- Merge conflicts when rebasing
- Git unable to recognize commits already in main

<examples>

**Fixing child PR after parent was squash merged**:

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
- [Dave Pacheco's Stacked PR Workflow](https://www.davepacheco.net/blog/2025/stacked-prs-on-github/)

## Working on Existing PRs

### CRITICAL: Always Use Actual Branch Name

<forbidden>

**NEVER create arbitrary local branch names when working on PRs:**

- Do NOT create local branches with assumed names like `pr-123`
- Do NOT assume branch name follows a pattern
- Do NOT make changes without verifying current branch

</forbidden>

<required>

**ALWAYS get and use the actual PR branch name:**

```sh
git fetch origin
git checkout -b "<actual-branch-name>" "origin/<actual-branch-name>"
git branch --show-current
git status
```

</required>

### Why This Matters

<context>

**Problem**: Creating local branches with assumed names that don't match the PR's actual branch name.

**Impact**:
- Your changes won't push to the PR
- You're working on a disconnected branch
- Risk of losing work or creating merge conflicts

**Solution**: Always verify the PR's actual branch name from your platform, then checkout from origin.

</context>

### Recovery if You Made This Mistake

If you already made changes to the wrong branch:

```sh
git checkout "<actual-branch-name>"
git cherry-pick <commit-sha-from-wrong-branch>
git branch -D <wrong-branch-name>
```

### Post-Push Requirements

<required>

After pushing changes to a PR:

1. **Address review comments**: Read and respond to all new review comments
2. **Revise PR title**: Update if changes have shifted the PR's focus
3. **Revise PR body**: Update summary to reflect current cumulative changes
4. **Verify atomicity**: Confirm PR still represents a single logical change

</required>

<forbidden>

- Leaving review comments unaddressed after push
- PR title/body that doesn't reflect actual changes
- Pushing without checking for new review comments

</forbidden>

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
git add .
git commit -m "refactor: address review comments"
git push
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

<context>

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

</context>

### Post-Merge Cleanup

**For non-stacked PRs** (simple feature branch):

```sh
git checkout main
git fetch --prune origin
git pull origin main
git branch -d feature/my_feature
git ls-remote --exit-code --heads origin feature/my_feature >/dev/null 2>&1 && git push origin --delete feature/my_feature
```

<context>

**Command explanation:**

- `git fetch --prune`: Update remote refs and remove stale tracking branches
- `git pull origin main`: Update local main with merged commits (required for branch -d check)
- `git branch -d`: Safe delete (fails if branch not merged to main)
- `git ls-remote --exit-code`: Check if remote branch exists before attempting deletion
- Works whether GitHub auto-delete is enabled or disabled

</context>

<forbidden>

- NEVER use `git branch -D` (force delete) unless you are certain the branch should be abandoned
- NEVER delete local branch before PR is merged
- NEVER skip `git fetch --prune` (leaves stale remote-tracking refs)

</forbidden>

## Best Practices

### PR Size

<constraints>

- Keep PRs focused and small (< 400 lines changed ideal)
- Split large features into multiple PRs
- Use draft PRs for work in progress
- One logical change per PR

</constraints>

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

- **Git Operations**: rules-git.md - Commits, branches, merges
- **GitHub PR Operations**: rules-github-pr.md - GitHub CLI commands
- **Agent PR Creation**: rules-github-agent-create.md - Automated PR creation
- **Agent Review Automation**: rules-github-agent-review.md - Review cycle automation
- **Agent Rebase Workflows**: rules-github-agent-rebase.md - Branch freshness and rebasing
- **Development Workflow**: rules-development.md - Daily practices, quality gates
- **Testing**: rules-testing.md - Test requirements
