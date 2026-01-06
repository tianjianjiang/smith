---
name: gh-cli
description: GitHub CLI operations with token efficiency and pagination best practices. Use when executing gh commands for PR operations, issue management, code review, or repository interactions. Covers safe perPage limits and protected branch configuration.
---

# GitHub CLI Operations

<metadata>

- **Load if**: Using GitHub CLI commands
- **Prerequisites**: @git/SKILL.md, @gh-pr/SKILL.md

</metadata>

## CRITICAL: Token Efficiency (Primacy Zone)

<required>

**ALWAYS use pagination** - GitHub MCP truncates at 25,000 tokens

**Safe perPage limits:**
- `list_pull_requests`: perPage 20-30
- `get_review_comments`: perPage 10 (bot reviews are massive)
- `get_files`: perPage 30
- `search_repositories`: minimal_output: true

</required>

## Installation

```shell
brew install gh
gh auth login
```

## Pull Request Operations

### Creating PRs

```shell
gh pr create --title "feat: add feature" --body "Description" --assignee @me
gh pr create --draft --title "feat: add feature #WIP" --body "Work in progress"
gh pr create --title "feat: feature" --reviewer @user1,@user2
```

<required>

**ALWAYS assign yourself** when creating PRs: `--assignee @me`

</required>

### Viewing and Checking Out

```shell
gh pr view 123
BRANCH=$(gh pr view 123 --json headRefName -q .headRefName)
git checkout -b "$BRANCH" "origin/$BRANCH"
```

### Merging

```shell
gh pr checks 123 --watch
gh pr merge 123 --squash --delete-branch
```

## Code Review

```shell
gh pr edit 123 --add-reviewer @username
gh pr review 123 --approve -b "LGTM!"
gh pr review 123 --request-changes -b "Please address concerns"
gh pr comment 123 --body "Addressed feedback"
```

## Issue Operations

```shell
gh issue create --title "fix: description" --body "Details"
gh issue list --state open
```

### Linking Issues

In PR descriptions:
- `Closes #123` - Auto-closes on merge
- `Fixes #123` - Same as Closes
- `Relates to #123` - Links without closing

## Protected Branches

<required>

**Main branch:**
- Require PR reviews (min 1)
- Require status checks
- Require up-to-date branches

</required>

Configure in: Repository Settings → Branches → Protection rules

<related>

- `@gh-pr/SKILL.md` - PR workflows
- `@git/SKILL.md` - Git operations

</related>

## ACTION (Recency Zone)

<required>

**Before PR operations:**
1. Use pagination (perPage, page)
2. Use minimal_output for searches
3. Assign yourself to PRs

**Common workflow:**
```shell
gh pr view 123 --comments
git commit -m "refactor: address feedback"
git push
gh pr comment 123 --body "Ready for re-review"
```

</required>
