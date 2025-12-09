# Pull Request Workflows

<metadata>

- **Scope**: Platform-neutral pull request concepts and best practices
- **Load if**: Creating PRs, reviewing code, merging changes, working with any Git platform
- **Prerequisites**: rules-core.md, rules-git.md

</metadata>

<context>

## Scope

- **This document**: Platform-neutral PR concepts, code review workflows, merge strategies
- **GitHub PR operations**: rules-github-pr-automation.md
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
git push -u origin feat/my_feature
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

For large features (500+ lines), use stacked PRs to maintain atomic, reviewable changes.

**See**: rules-pr-stacked.md for complete stacked PR workflows, merge strategies, and rebase patterns.

</context>

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

### Pre-Work Requirements

<required>

Before making changes to an existing PR:

1. **Check for review comments**: Fetch all inline review comments
2. **Verify comment types**: Check for CHANGES_REQUESTED AND COMMENT reviews
3. **Alert on pending feedback**: Inform user of unaddressed comments
4. **Confirm approach**: Ask if user wants to address comments first

</required>

<context>

**Rationale**: Bot reviewers (CodeRabbitAI, Copilot) often post informational COMMENT reviews that don't change PR state. Without proactive checking, these are easily missed.

</context>

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
git branch -d feat/my_feature
git ls-remote --exit-code --heads origin feat/my_feature >/dev/null 2>&1 && git push origin --delete feat/my_feature
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
- **Stacked PRs**: rules-pr-stacked.md - Advanced stacked PR patterns and workflows
- **GitHub PR Automation**: rules-github-pr-automation.md - GitHub PR workflows (creation, review, rebase, merge)
- **GitHub CLI**: rules-github-cli.md - GitHub CLI commands
- **Development Workflow**: rules-development.md - Daily practices, quality gates
- **Testing**: rules-testing.md - Test requirements
