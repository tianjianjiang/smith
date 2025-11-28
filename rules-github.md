# GitHub Workflow Standards

<metadata>
**Scope**: GitHub platform interactions (PRs, Issues, Reviews)
**Load if**: Creating/reviewing PRs, managing issues, using gh CLI
**Prerequisites**: [Git Standards](./rules-git.md)
</metadata>

This document defines **GitHub platform workflows** for pull requests, issues, and code reviews.

## Scope

- **This document**: PRs, issues, code reviews, gh CLI, protected branches, GitHub Actions
- **Local git operations**: See [Git Standards]($HOME/.smith/rules-git.md) for commits, branches, merges, history

## Pull Request Creation

### Prerequisites

<required>
- MUST run all quality checks before creating PR
- MUST ensure branch is up-to-date with base branch
- MUST have meaningful commit messages
- MUST link to related issues
</required>

```bash
poetry run ruff check --fix && poetry run pytest
git pull origin develop
git push -u origin feature/my-feature
```

### Creating PR

**Using GitHub CLI:**
```bash
gh pr create --title "feat: add semantic search" --body "$(cat <<'EOF'
## Summary
- Implement metadata-based filtering
- Add support for AND/OR logic
- Update documentation

## Test Plan
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing completed

Closes #123

Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**PR Title Format:**
```
<type>(<scope>): <description>
```
Examples:
- `feat(rag): add semantic search filtering`
- `fix(api): resolve CORS issues`
- `docs: update deployment guide`

**PR Body Template:**
```markdown
## Summary
- Bullet point 1
- Bullet point 2
- Bullet point 3

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
- MUST have minimum 1 approval (if enforced)
</required>

<forbidden>
- NEVER create PR with failing tests
- NEVER merge PR with unresolved conflicts
- NEVER skip CI checks
- NEVER merge without required approvals
</forbidden>

## Code Review Process

### Requesting Review

**Using GitHub CLI:**
```bash
gh pr create  # Creates PR and auto-requests reviews based on CODEOWNERS
gh pr view 123  # View PR details
gh pr checks 123  # View CI status
```

**Best practices:**
- Request reviews from relevant team members
- Provide context in PR description
- Link to design docs or RFCs if applicable
- Highlight areas needing special attention

### Responding to Reviews

**Address all comments:**
1. Read all review comments carefully
2. Respond to each comment thread
3. Make requested changes
4. Mark conversations as resolved
5. Re-request review after changes

**Using GitHub CLI:**
```bash
git add .
git commit -m "refactor: address review comments"
git push

gh pr review 123 --comment -b "Addressed all comments, please review again"
```

### Giving Reviews

**Review checklist:**
- [ ] Code follows project standards
- [ ] Tests are adequate and passing
- [ ] Documentation is updated
- [ ] No security vulnerabilities
- [ ] Performance considerations addressed
- [ ] Error handling is appropriate

**Using GitHub CLI:**
```bash
gh pr review 123 --approve -b "LGTM! Great implementation"
gh pr review 123 --request-changes -b "Please address the concerns in comments"
gh pr review 123 --comment -b "Minor suggestions, but looks good overall"
```

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

**Merge commit (default for feature branches):**
```bash
gh pr merge 123 --merge
```

**Squash and merge (for small fixes):**
```bash
gh pr merge 123 --squash
```

**Rebase and merge (for clean history):**
```bash
gh pr merge 123 --rebase
```

**When to use each:**
- **Merge commit**: Feature branches with multiple logical commits
- **Squash**: Tiny fixes, documentation updates, single logical change
- **Rebase**: When linear history is required and commits are clean

### Post-Merge Cleanup

```bash
git checkout develop
git pull origin develop
git branch -d feature/my-feature
git push origin --delete feature/my-feature
```

## Issue Management

### Creating Issues

**Using GitHub CLI:**
```bash
gh issue create --title "bug: API returns 500 error" --body "$(cat <<'EOF'
## Description
API endpoint /api/v1/query returns 500 error when...

## Steps to Reproduce
1. Send POST request to /api/v1/query
2. Include payload: {...}
3. Observe 500 response

## Expected Behavior
Should return 200 with results

## Actual Behavior
Returns 500 with error message

## Environment
- Version: 1.2.3
- OS: Ubuntu 22.04
- Python: 3.11
EOF
)"
```

### Issue Labels

**Standard labels:**
- `bug` - Something isn't working
- `feat` - New feature request
- `docs` - Documentation improvements
- `enhancement` - Improvement to existing feature
- `question` - Further information requested
- `wontfix` - This will not be worked on
- `duplicate` - This issue already exists
- `good first issue` - Good for newcomers
- `help wanted` - Extra attention needed
- `priority:high` - High priority issue
- `priority:low` - Low priority issue

### Linking Issues to PRs

**In commit messages:**
```bash
git commit -m "fix(api): resolve 500 error

This fixes the issue where API returned 500 error due to...

Fixes #123"
```

**In PR descriptions:**
```markdown
## Related Issues
Closes #123
Fixes #456
Relates to #789
```

**Using keywords:**
- `Closes #123` - Automatically closes issue when PR is merged
- `Fixes #123` - Same as Closes
- `Resolves #123` - Same as Closes
- `Relates to #123` - Links but doesn't close

## GitHub CLI Reference

**Installation:**
```bash
brew install gh  # macOS
gh auth login
```

**Common commands:**
```bash
gh pr list
gh pr view 123
gh pr diff 123
gh pr checks 123
gh pr create
gh pr merge 123
gh pr review 123 --approve

gh issue list
gh issue view 123
gh issue create
gh issue close 123
```

## Protected Branch Settings

### Main Branch Protection

<required>
- MUST require pull request reviews (minimum 1 approval)
- MUST require status checks to pass before merging
- MUST require branches to be up-to-date before merging
- MUST restrict who can push to main
</required>

### Develop Branch Protection

<required>
- MUST require status checks to pass before merging
- MUST allow force pushes only by admins
</required>

## Best Practices

**PR Size:**
- Keep PRs focused and small (< 400 lines changed ideal)
- Split large features into multiple PRs
- Use draft PRs for work in progress

**Communication:**
- Use PR comments for technical discussions
- Use issue comments for requirements and planning
- Tag relevant team members with @mentions

**Documentation:**
- Update README if public API changes
- Update CHANGELOG for notable changes
- Add inline code comments for complex logic

**CI Integration:**
- Ensure all tests run in CI
- Set up automatic deployment previews
- Configure status checks as required

## Related Standards

- **Git Operations**: `$HOME/.smith/rules-git.md` - Commit, branch, merge
- **Development Workflow**: `$HOME/.smith/rules-development.md` - Daily practices
- **Code Review**: `$HOME/.smith/rules-development.md` - Review guidelines
- **Testing**: `$HOME/.smith/rules-testing.md` - Test requirements
