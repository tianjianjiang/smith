# GitHub CLI Operations

<metadata>

- **Scope**: GitHub platform-specific operations (gh CLI only)
- **Load if**: Using GitHub CLI commands, GitHub-specific features
- **Prerequisites**: @git.md, @gh-pr.md

</metadata>

<context>

## Scope

- **This document**: GitHub CLI commands, GitHub-specific features
- **Platform-neutral workflows**: @gh-pr.md for platform-neutral concepts
- **Agent automation**: @gh-*.md for agent workflows
- **Local git operations**: @git.md for commits, branches, merges

</context>

## GitHub CLI Installation

<examples>

```sh
brew install gh
gh auth login
```

</examples>

## Token Efficiency for GitHub MCP

<required>

**ALWAYS use pagination and filtering parameters** to minimize token usage:

### Pagination Parameters

**CRITICAL: Always use pagination to prevent token truncation**

GitHub MCP returns up to 25,000 tokens. Exceeding this causes:
- "OUTPUT TRUNCATED - exceeded 25000 token limit" errors
- Incomplete data (missing reviews, comments, PRs)
- Workflow failures

**Safe perPage limits by method**:

For `list_pull_requests`:
```text
Use MCP tool: mcp__github__list_pull_requests
Parameters:
  - owner: {owner}
  - repo: {repo}
  - state: "open"
  - perPage: 20          # SAFE: 20-30 for full PR objects
  - page: 1              # Always specify starting page
```

For `pull_request_read` with `get_review_comments`:
```text
Use MCP tool: mcp__github__pull_request_read
Parameters:
  - method: "get_review_comments"
  - owner: {owner}
  - repo: {repo}
  - pullNumber: {PR}
  - perPage: 10          # SAFE: Bot reviews (CodeRabbitAI, Copilot) have massive HTML/analysis
  - page: 1
```

For `pull_request_read` with `get_files`:
```text
Use MCP tool: mcp__github__pull_request_read
Parameters:
  - method: "get_files"
  - owner: {owner}
  - repo: {repo}
  - pullNumber: {PR}
  - perPage: 30          # SAFE: Large refactors have 100+ files
  - page: 1
```

### Minimal Output

For search operations:

```text
Use MCP tool: mcp__github__search_repositories
Parameters:
  - query: "topic:react"
  - minimal_output: true # ALWAYS true unless you need full objects
  - perPage: 20
```

### Request Only What You Need

For PR details, use specific methods:

```text
Use MCP tool: mcp__github__pull_request_read
Parameters:
  - method: "get"        # Basic info only
  # Don't use get_files, get_reviews unless needed
```

### Multi-Page Data Fetching

**When you need data beyond page 1**:

1. **Check if pagination needed**:
   - Review comments: Bot-reviewed PRs can have 50-100+ comments (VERY verbose with analysis, code blocks, HTML)
   - Open PRs: Active repos may have 30+ open PRs
   - Changed files: Large refactors touch 50-200+ files

2. **Fetch first page with safe limit**:
   ```text
   Use MCP tool: mcp__github__pull_request_read
   Parameters:
     - method: "get_review_comments"
     - perPage: 10      # ULTRA-conservative: CodeRabbitAI comments have massive HTML/analysis
     - page: 1
   ```

3. **If more data exists, fetch subsequent pages**:
   ```text
   Use MCP tool: mcp__github__pull_request_read
   Parameters:
     - method: "get_review_comments"
     - perPage: 10
     - page: 2          # Increment for each page
   ```

4. **Combine results** from all pages

**Example: Handling 30 review comments**:
- Page 1: Comments 1-10 (perPage: 10)
- Page 2: Comments 11-20 (perPage: 10)
- Page 3: Comments 21-30 (perPage: 10)

</required>

<context>

**Token Savings**:
- Default `list_pull_requests` returns 30 items
- With `perPage: 10`, saves ~66% tokens when you only need recent PRs
- `minimal_output: true` for repositories saves ~80% tokens

**Sources**:
- [GitHub MCP Pagination Best Practices](https://docs.github.com/en/rest/using-the-rest-api/using-pagination-in-the-rest-api)
- [MCP Optimizer for Token Reduction](https://dev.to/stacklok/cut-token-waste-from-your-ai-workflow-with-the-toolhive-mcp-optimizer-3oo6)
- [Dynamic Toolset Selection](https://www.speakeasy.com/blog/how-we-reduced-token-usage-by-100x-dynamic-toolsets-v2)

</context>

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

**Use `gh pr --help` for common commands**. Key non-obvious patterns:

```sh
# Extract specific field with jq
gh pr view 123 --json headRefName -q .headRefName
```

### Checking Out PRs

<examples>

```sh
BRANCH=$(gh pr view 123 --json headRefName -q .headRefName)
git fetch origin
git checkout -b "$BRANCH" "origin/$BRANCH"

git branch --show-current
```

</examples>

### PR Status and Merging

**Use `gh pr --help` for common merge and check commands**.

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

**Use `gh issue --help` for common commands**. Key non-obvious pattern - HEREDOC for multiline bodies:

```sh
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

**Use `gh run --help` for common workflow commands**.

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

- **PR Workflows**: @gh-pr.md - Platform-neutral PR concepts
- **GitHub PR Operations**: @gh-pr.md - GitHub PR lifecycle
- **GitHub Workflows**: @gh-*.md - GitHub automation workflows
- **Git Operations**: @git.md - Commits, branches, merges
- **Development Workflow**: @dev.md - Quality gates, pre-PR checks

</related>
