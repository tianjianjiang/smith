# GitHub Post-Merge Workflows

<metadata>

- **Scope**: Automation for post-merge operations and cascade updates
- **Load if**: PR just merged, immediately after merge operation
- **Prerequisites**: rules-pr-concepts.md, rules-github.md, rules-ai_agents.md
- **Token efficiency**: Use perPage, minimal_output parameters (see rules-github.md)

</metadata>

<context>

## Scope

- **This document**: Workflows for post-merge cleanup and cascade updates
- **Platform-neutral PR concepts**: rules-pr-concepts.md
- **GitHub PR operations**: rules-github-pr.md
- **Other workflows**: rules-github-*.md

## Dual-Approach Pattern

**Two approaches for GitHub PR operations**:

**Preferred: GitHub MCP Server** - Use `mcp__github__pull_request_read` and `mcp__github__list_pull_requests`
**Fallback: gh CLI** - Use `gh pr view` and `gh pr list`

**Decision logic**: Try MCP tools first. If not available, fall back to gh CLI.

</context>

## Post-Merge Workflow

<scenario>

**Context**: Just merged PR or user informs of merge

**Workflow**:
1. Check if merged PR has child PRs (parse "Blocks: #{number}" in PR body)
2. If children exist, trigger cascade update workflow (see rules-github-rebase.md)
3. If no children, perform standard cleanup
4. Sync local repository

**Option A: Using GitHub MCP** (preferred):
```text
# Get merged PR details
Use MCP tool: mcp__github__pull_request_read
Parameters:
  - owner: {owner}
  - repo: {repo}
  - pullNumber: 123
  - method: "get"

MERGED_BRANCH = response.headRefName

# List all open PRs to find children
Use MCP tool: mcp__github__list_pull_requests
Parameters:
  - owner: {owner}
  - repo: {repo}
  - state: "open"
  - perPage: 20          # Limit to 20 most recent
  - page: 1

CHILD_PRS = filter PRs where body contains "Depends on: #123"

if CHILD_PRS exist:
  echo "Found child PRs. Triggering cascade update workflow."
  # See rules-github-rebase.md Workflow 2
else:
  git checkout main
  git fetch --prune origin
  git pull origin main
  git branch -d "$MERGED_BRANCH"
  git push origin --delete "$MERGED_BRANCH"
```

**Option B: Using gh CLI** (fallback):
```sh
MERGED_BRANCH=$(gh pr view 123 --json headRefName -q .headRefName)

CHILD_PRS=$(gh pr list --json number,body --jq '.[] | select(.body | contains("Depends on: #123")) | .number')

if [ -n "$CHILD_PRS" ]; then
  echo "Found child PRs. Triggering cascade update workflow."
else
  git checkout main
  git fetch --prune origin
  git pull origin main
  git branch -d "$MERGED_BRANCH"
  git ls-remote --exit-code --heads origin "$MERGED_BRANCH" >/dev/null 2>&1 && \
    git push origin --delete "$MERGED_BRANCH"
fi
```

**Stacked PR cascade example**:
```text
User: "PR #123 merged"
Agent: "PR #123 (feature/parent_feature) merged. Found stack:
  main
   └─ PR #123 (merged) ← feature/parent_feature
       ├─ PR #124 ← feature/child_feature_1 (child, 245 lines)
       └─ PR #125 ← feature/child_feature_2 (child, 180 lines)

Auto-updating stack..."
Agent: [Updates #124 base to main, rebases onto origin/main]
Agent: "PR #124 rebased successfully. No conflicts."
Agent: [Updates #125 base, rebases]
Agent: "PR #125 rebased successfully. No conflicts."
Agent: [Deletes local and remote feature/parent_feature]
Agent: "Stack updated. All PRs ready for continued review."
```

</scenario>

<forbidden>

- NEVER use `git branch -D` (force delete) unless you are certain the branch should be abandoned
- NEVER delete local branch before PR is merged
- NEVER skip `git fetch --prune` (leaves stale remote-tracking refs)

</forbidden>

## Related Standards

- **PR Concepts**: rules-pr-concepts.md - Stacked PRs, post-merge cleanup
- **GitHub PR Operations**: rules-github-pr.md - Branch deletion with stacked PRs
- **Rebase Workflows**: rules-github-rebase.md - Cascade rebase after parent merge
- **Git Standards**: rules-git.md - Post-merge local sync
