# GitHub Pull Request Operations

<metadata>

- **Scope**: Basic GitHub PR merge and branch deletion operations
- **Load if**: Creating or managing PRs on GitHub, working with GitHub CLI
- **Prerequisites**: rules-core.md, rules-pr-concepts.md, rules-github.md

</metadata>

<context>

## Scope

- **This document**: GitHub-specific PR operations, gh CLI commands
- **Platform-neutral concepts**: rules-pr-concepts.md
- **Automation workflows**: rules-github-*.md
- **GitHub general operations**: rules-github.md

## Dual-Approach Pattern

**Two approaches for GitHub PR operations**:

**Preferred: GitHub MCP Server** - Use `mcp__github__merge_pull_request`, `mcp__github__update_pull_request`
**Fallback: gh CLI** - Use `gh pr merge`, `gh pr edit`

**Decision logic**: Try MCP tools first. If not available, fall back to gh CLI.

</context>

## Branch Deletion with Stacked PRs

<forbidden>

**NEVER use `--delete-branch` when merging a PR that has dependent child PRs.**

The GitHub API immediately deletes the branch, closing all child PRs before their base can be updated. This is a known GitHub API limitation ([cli/cli#1168](https://github.com/cli/cli/issues/1168)).

</forbidden>

<required>

**Process for stacked PRs:**

1. Merge parent PR WITHOUT deleting branch:

   **Option A: Using GitHub MCP** (preferred):
   ```text
   Use MCP tool: mcp__github__merge_pull_request
   Parameters:
     - owner: {owner}
     - repo: {repo}
     - pullNumber: 123
     - merge_method: "squash"
   ```

   **Option B: Using gh CLI** (fallback):
   ```sh
   gh pr merge 123 --squash
   ```

2. Update child PR base and rebase:

   **Option A: Using GitHub MCP** (preferred):
   ```text
   Use MCP tool: mcp__github__update_pull_request
   Parameters:
     - owner: {owner}
     - repo: {repo}
     - pullNumber: 124
     - base: "main"

   git fetch origin
   git checkout feat/child_branch
   git rebase --onto origin/main feat/parent_branch
   git push --force-with-lease
   ```

   **Option B: Using gh CLI** (fallback):
   ```sh
   gh pr edit 124 --base main
   git fetch origin
   git checkout feat/child_branch
   git rebase --onto origin/main feat/parent_branch
   git push --force-with-lease
   ```

3. Delete parent branch AFTER child is updated:
   ```sh
   git push origin --delete feat/parent_branch
   ```

</required>

## Post-Merge Cleanup

**For stacked PRs** (parent with children):

See rules-github-merge.md for automated cascade update workflows.

**For non-stacked PRs** (simple feature branch):

See rules-pr-concepts.md for standard cleanup workflow.

## Related Standards

- **PR Concepts**: rules-pr-concepts.md - Platform-neutral PR workflows
- **PR Creation**: rules-github-create.md - Automated PR description generation
- **Review Automation**: rules-github-review.md - Review cycle automation
- **Post-Merge**: rules-github-merge.md - Cascade updates after merge
- **GitHub Operations**: rules-github.md - GitHub CLI commands
- **Git Operations**: rules-git.md - Local git operations
