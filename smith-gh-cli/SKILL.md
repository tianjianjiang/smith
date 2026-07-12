---
name: smith-gh-cli
description: GitHub CLI gotchas and best practices. Use when executing gh commands. Covers token efficiency, pagination limits, and common pitfalls.
---

# GitHub CLI Best Practices

**Load if:** Using GitHub CLI commands
**Prerequisites:** `@smith-git/SKILL.md`, `@smith-gh-pr/SKILL.md`

## CRITICAL: Avoid GitHub MCP

Prefer the `gh pr-review` extension, `gh api`, or GraphQL queries over GitHub
MCP tools — MCP tools are hard to control pagination on (25k token
truncation), less complete than the CLI, and require a personal token.

## Token Efficiency

**Safe perPage limits:**
- `list_pull_requests`: perPage 20-30
- `get_review_comments`: perPage 10 (bot reviews are massive)
- `get_files`: perPage 30
- `search_repositories`: minimal_output: true

## Common Pitfalls

- **ALWAYS assign yourself**: `--assignee @me`
- **Draft PRs**: Use `--draft` with `#WIP` in title for work-in-progress
- **Ensure gh installed**: If `gh` not found, prompt user/agent to install

## Issue Linking

In PR descriptions:
- `Closes #123` - Auto-closes on merge
- `Fixes #123` - Same as Closes
- `Relates to #123` - Links without closing

## Resolving Identities and Reviewer Eligibility

- A corporate-email commit author does NOT map 1:1 to a GitHub login. Resolve
  from source: `gh api 'repos/{owner}/{repo}/commits?author={email}' --jq
  '.[0].author.login'`.
- A review approval clears a CODEOWNERS rule ONLY if the approver is a named
  owner of that path. Check CODEOWNERS before recommending a reviewer —
  "wrote it" does not imply "can approve it".

## Related

- `@smith-gh-pr/SKILL.md` - PR workflows, review comment fetching
- `@smith-git/SKILL.md` - Git operations
