# GitHub CLI Operations

<metadata>

- **Scope**: GitHub platform-specific operations (gh CLI only)
- **Load if**: Using GitHub CLI commands, GitHub-specific features
- **Prerequisites**: [Git Standards](./rules-git.md), [PR Workflows](./rules-pr.md)

</metadata>

This document defines **GitHub-specific operations** using the `gh` CLI and GitHub platform features.

## Scope

- **This document**: GitHub CLI commands, GitHub-specific features
- **Platform-neutral workflows**: See [PR Workflows]($HOME/.smith/rules-pr.md) for concepts, agent guidelines, best practices
- **Local git operations**: See [Git Standards]($HOME/.smith/rules-git.md) for commits, branches, merges

## GitHub CLI Installation

```bash
# macOS
brew install gh

# Authenticate
gh auth login
```

## Pull Request Operations

### Creating PRs

```bash
# Basic PR creation
gh pr create --title "feat: add feature" --body "Description"

# With full template
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

# Create draft PR
gh pr create --draft --title "WIP: feature" --body "Work in progress"

# Create PR with specific reviewers
gh pr create --title "feat: feature" --body "Description" --reviewer @user1,@user2

# Create PR targeting specific branch
gh pr create --base develop --title "feat: feature" --body "Description"
```

### Viewing PRs

```bash
# List all open PRs
gh pr list

# List PRs with filters
gh pr list --state all
gh pr list --author @me
gh pr list --label bug
gh pr list --limit 20

# View specific PR
gh pr view 123

# View PR in browser
gh pr view 123 --web

# Get PR metadata (JSON)
gh pr view 123 --json number,title,body,state,author

# Get PR branch name (CRITICAL for agents)
gh pr view 123 --json headRefName -q .headRefName

# View PR diff
gh pr diff 123

# View PR commits
gh pr view 123 --json commits

# View PR comments
gh pr view 123 --comments
```

### Checking Out PRs

```bash
# Get the actual branch name first (CRITICAL)
BRANCH=$(gh pr view 123 --json headRefName -q .headRefName)

# Fetch and checkout
git fetch origin
git checkout -b "$BRANCH" "origin/$BRANCH"

# Verify you're on the correct branch
git branch --show-current  # Must match $BRANCH
```

### PR Status and Checks

```bash
# View CI check status
gh pr checks 123

# Watch checks in real-time
gh pr checks 123 --watch

# View specific check run
gh run view <run-id>

# View check logs
gh run view <run-id> --log

# Re-run failed checks
gh run rerun <run-id>

# Re-run all checks
gh pr checks 123 --rerun
```

### Merging PRs

```bash
# Merge commit
gh pr merge 123 --merge

# Squash and merge
gh pr merge 123 --squash

# Rebase and merge
gh pr merge 123 --rebase

# Auto-merge when checks pass
gh pr merge 123 --auto --squash

# Merge and delete branch
gh pr merge 123 --squash --delete-branch
```

## Code Review Operations

### Requesting Reviews

```bash
# Request review from user
gh pr edit 123 --add-reviewer @username

# Request review from team
gh pr edit 123 --add-reviewer @org/team

# Remove reviewer
gh pr edit 123 --remove-reviewer @username
```

### Giving Reviews

```bash
# Approve PR
gh pr review 123 --approve

# Approve with comment
gh pr review 123 --approve -b "LGTM! Great implementation"

# Request changes
gh pr review 123 --request-changes -b "Please address the concerns in comments"

# Comment without approval
gh pr review 123 --comment -b "Minor suggestions, but looks good overall"
```

### PR Comments

```bash
# Add comment to PR
gh pr comment 123 --body "Great work!"

# Add comment with multiline text
gh pr comment 123 --body "$(cat <<'EOF'
Addressed all review comments:
- Extracted validation into separate function
- Added error handling for edge cases
- Updated tests to cover new scenarios
EOF
)"

# Edit PR description
gh pr edit 123 --body "Updated description"

# Edit PR title
gh pr edit 123 --title "feat: updated title"

# Add/remove labels
gh pr edit 123 --add-label bug,priority:high
gh pr edit 123 --remove-label wontfix
```

## Issue Operations

### Creating Issues

```bash
# Basic issue creation
gh issue create --title "Bug: error message" --body "Description"

# With template
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

# Assign issue
gh issue create --title "Bug" --body "Description" --assignee @me

# Add labels
gh issue create --title "Bug" --body "Description" --label bug,priority:high
```

### Viewing Issues

```bash
# List issues
gh issue list

# List with filters
gh issue list --state all
gh issue list --assignee @me
gh issue list --label bug
gh issue list --author @username

# View specific issue
gh issue view 123

# View in browser
gh issue view 123 --web
```

### Managing Issues

```bash
# Close issue
gh issue close 123

# Close with comment
gh issue close 123 --comment "Fixed in PR #456"

# Reopen issue
gh issue reopen 123

# Edit issue
gh issue edit 123 --title "Updated title"
gh issue edit 123 --body "Updated description"
gh issue edit 123 --add-label bug
gh issue edit 123 --add-assignee @user

# Add comment
gh issue comment 123 --body "Update on progress..."
```

## Issue and PR Linking

### In Commit Messages

```bash
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

```bash
# Link PR to issue (in PR body)
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

```bash
# List workflow runs
gh run list

# List runs for specific workflow
gh run list --workflow ci.yml

# View specific run
gh run view <run-id>

# View run logs
gh run view <run-id> --log

# Download run artifacts
gh run download <run-id>
```

### Re-running Workflows

```bash
# Re-run failed jobs
gh run rerun <run-id> --failed

# Re-run all jobs
gh run rerun <run-id>
```

### Workflow Status in PRs

```bash
# Check workflow status for PR
gh pr checks 123

# View specific workflow run
gh pr view 123 --json statusCheckRollup
```

## CODEOWNERS

CODEOWNERS file automatically requests reviews from code owners.

**File location**: `.github/CODEOWNERS`

**Example:**
```
# Default owners for everything
* @org/core-team

# Python code owners
*.py @org/python-team

# Documentation owners
/docs/ @org/docs-team

# Specific file owners
/src/critical-file.py @user1 @user2
```

When PR is created, GitHub automatically requests reviews from matching owners.

## Common Command Patterns

### Check PR status before making changes

```bash
# Get PR info
gh pr view 123

# Check CI status
gh pr checks 123

# Get branch name
BRANCH=$(gh pr view 123 --json headRefName -q .headRefName)

# Checkout and work
git checkout "$BRANCH"
```

### Complete review response workflow

```bash
# View PR comments
gh pr view 123 --comments

# Make changes and commit
git add .
git commit -m "refactor: address review feedback"
git push

# Respond to review
gh pr comment 123 --body "Addressed all feedback, ready for re-review"

# Request re-review
gh pr edit 123 --add-reviewer @reviewer
```

### Monitor CI and merge

```bash
# Watch CI checks
gh pr checks 123 --watch

# Once passed, merge
gh pr merge 123 --squash --delete-branch
```

## Related Standards

- **PR Workflows**: `$HOME/.smith/rules-pr.md` - Platform-neutral concepts, agent guidelines, best practices
- **Git Operations**: `$HOME/.smith/rules-git.md` - Commits, branches, merges
- **Development Workflow**: `$HOME/.smith/rules-development.md` - Quality gates, pre-PR checks
