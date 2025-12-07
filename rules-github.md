# GitHub CLI Operations

<metadata>

- **Scope**: GitHub platform-specific operations (gh CLI only)
- **Load if**: Using GitHub CLI commands, GitHub-specific features
- **Prerequisites**: [Git Standards](./rules-git.md), [PR Concepts](./rules-pr-concepts.md), [GitHub PR Operations](./rules-github-pr.md)

</metadata>

<context>

## Scope

- **This document**: GitHub CLI commands, GitHub-specific features
- **Platform-neutral workflows**: See [PR Concepts]($HOME/.smith/rules-pr-concepts.md) for platform-neutral concepts
- **Agent automation**: See `$HOME/.smith/rules-github-agent-*.md` for agent workflows
- **Local git operations**: See [Git Standards]($HOME/.smith/rules-git.md) for commits, branches, merges

</context>

## GitHub CLI Installation

<examples>

```sh
brew install gh
gh auth login
```

</examples>

## Pull Request Operations

### Creating PRs

<examples>

```sh
gh pr create --title "feat: add feature" --body "Description"
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
gh pr create --draft --title "WIP: feature" --body "Work in progress"
gh pr create --title "feat: feature" --body "Description" --reviewer @user1,@user2
gh pr create --base develop --title "feat: feature" --body "Description"
```

</examples>

### PR Self-Assignment

<required>

**ALWAYS assign yourself** when creating or updating a PR where you are not already an assignee.

```sh
gh pr create --title "feat: feature" --body "Description" --assignee @me
gh pr edit <pr-number> --add-assignee @me
```

</required>

### Viewing PRs

<examples>

```sh
gh pr list
gh pr list --state all
gh pr list --author @me
gh pr list --label bug
gh pr list --limit 20
gh pr view 123
gh pr view 123 --web
gh pr view 123 --json number,title,body,state,author
gh pr view 123 --json headRefName -q .headRefName
gh pr diff 123
gh pr view 123 --json commits
gh pr view 123 --comments
```

</examples>

### Checking Out PRs

<examples>

```sh
BRANCH=$(gh pr view 123 --json headRefName -q .headRefName)
git fetch origin
git checkout -b "$BRANCH" "origin/$BRANCH"

git branch --show-current
```

</examples>

### PR Status and Checks

<examples>

```sh
gh pr checks 123
gh pr checks 123 --watch
gh run view <run-id>
gh run view <run-id> --log
gh run rerun <run-id>
gh pr checks 123 --rerun
```

</examples>

### Merging PRs

<examples>

```sh
gh pr merge 123 --merge
gh pr merge 123 --squash
gh pr merge 123 --rebase
gh pr merge 123 --auto --squash
gh pr merge 123 --squash --delete-branch
```

</examples>

## Code Review Operations

### Requesting Reviews

<examples>

```sh
gh pr edit 123 --add-reviewer @username
gh pr edit 123 --add-reviewer @org/team
gh pr edit 123 --remove-reviewer @username
```

</examples>

### Giving Reviews

```sh
gh pr review 123 --approve
gh pr review 123 --approve -b "LGTM! Great implementation"
gh pr review 123 --request-changes -b "Please address the concerns in comments"
gh pr review 123 --comment -b "Minor suggestions, but looks good overall"
```

### PR Comments

```sh
gh pr comment 123 --body "Great work!"
gh pr comment 123 --body "$(cat <<'EOF'
Addressed all review comments:
- Extracted validation into separate function
- Added error handling for edge cases
- Updated tests to cover new scenarios
EOF
)"
gh pr edit 123 --body "Updated description"
gh pr edit 123 --title "feat: updated title"
gh pr edit 123 --add-label bug,priority:high
gh pr edit 123 --remove-label wontfix
```

## Issue Operations

### Creating Issues

```sh
gh issue create --title "Bug: error message" --body "Description"
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
gh issue create --title "Bug" --body "Description" --assignee @me
gh issue create --title "Bug" --body "Description" --label bug,priority:high
```

### Viewing Issues

```sh
gh issue list
gh issue list --state all
gh issue list --assignee @me
gh issue list --label bug
gh issue list --author @username
gh issue view 123
gh issue view 123 --web
```

### Managing Issues

```sh
gh issue close 123
gh issue close 123 --comment "Fixed in PR #456"
gh issue reopen 123
gh issue edit 123 --title "Updated title"
gh issue edit 123 --body "Updated description"
gh issue edit 123 --add-label bug
gh issue edit 123 --add-assignee @user
gh issue comment 123 --body "Update on progress..."
```

## Issue and PR Linking

### In Commit Messages

```sh
git commit -m "fix(api): resolve 500 error

This fixes the issue where API returned 500 error due to...

Fixes #123"
```

### In PR Descriptions

Use these keywords to auto-close issues:
- `Closes #123` - Closes issue when PR merges
- `Fixes #123` - Same as Closes
- `Resolves #123` - Same as Closes
- `Relates to #123` - Links but doesn't close

```markdown
## Related Issues
Closes #123
Fixes #456
Relates to #789
```

### Link Issues to PRs

```sh
gh pr edit 123 --body "Fixes #456

Original description..."
```

## Protected Branch Settings

Protected branches are configured in repository settings, not via CLI.

### Main Branch Protection

<required>

- MUST require pull request reviews (minimum 1 approval)
- MUST require status checks to pass before merging
- MUST require branches to be up-to-date before merging
- MUST restrict who can push to main

</required>

**Configuration**: Repository Settings → Branches → Branch protection rules

### Develop Branch Protection

<required>

- MUST require status checks to pass before merging
- MUST allow force pushes only by admins

</required>

## GitHub Actions Integration

### Viewing Workflow Runs

```sh
gh run list
gh run list --workflow ci.yml
gh run view <run-id>
gh run view <run-id> --log
gh run download <run-id>
```

### Re-running Workflows

```sh
gh run rerun <run-id> --failed
gh run rerun <run-id>
```

### Workflow Status in PRs

```sh
gh pr checks 123
gh pr view 123 --json statusCheckRollup
```

## CODEOWNERS

CODEOWNERS file automatically requests reviews from code owners.

**File location**: `.github/CODEOWNERS`

**Example:**
```
* @org/core-team
*.py @org/python-team
/docs/ @org/docs-team
/src/critical-file.py @user1 @user2
```

When PR is created, GitHub automatically requests reviews from matching owners.

## Common Command Patterns

### Check PR status before making changes

```sh
gh pr view 123
gh pr checks 123
BRANCH=$(gh pr view 123 --json headRefName -q .headRefName)
git checkout "$BRANCH"
```

<scenario>

### Complete review response workflow

```sh
gh pr view 123 --comments
git add .
git commit -m "refactor: address review feedback"
git push
gh pr comment 123 --body "Addressed all feedback, ready for re-review"
gh pr edit 123 --add-reviewer @reviewer
```

</scenario>

### Monitor CI and merge

```sh
gh pr checks 123 --watch
gh pr merge 123 --squash --delete-branch
```

## Related Standards

<related>

- **PR Workflows**: `$HOME/.smith/rules-pr-concepts.md` - Platform-neutral PR concepts
- **GitHub PR Operations**: `$HOME/.smith/rules-github-pr.md` - GitHub PR workflows
- **GitHub Agent Workflows**: `$HOME/.smith/rules-github-agent-*.md` - Agent automation
- **Git Operations**: `$HOME/.smith/rules-git.md` - Commits, branches, merges
- **Development Workflow**: `$HOME/.smith/rules-development.md` - Quality gates, pre-PR checks

</related>
