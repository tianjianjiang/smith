---
name: smith-gh-cli
description: GitHub CLI gotchas and best practices. Use when executing gh commands. Covers token efficiency, pagination limits, and common pitfalls.
---

# GitHub CLI Best Practices

<metadata>

- **Load if**: Using GitHub CLI commands
- **Prerequisites**: `@smith-git/SKILL.md`, `@smith-gh-pr/SKILL.md`

</metadata>

## CRITICAL: Avoid GitHub MCP (Primacy Zone)

<forbidden>

- GitHub MCP tools - hard to control pagination (25k token truncation), less complete than CLI, requires personal token

</forbidden>

**Use instead**: `gh pr-review` extension, `gh api`, or GraphQL queries

## Token Efficiency

<required>

**Safe perPage limits:**
- `list_pull_requests`: perPage 20-30
- `get_review_comments`: perPage 10 (bot reviews are massive)
- `get_files`: perPage 30
- `search_repositories`: minimal_output: true

</required>

## Common Pitfalls

<required>

- **ALWAYS assign yourself**: `--assignee @me`
- **Draft PRs**: Use `--draft` with `#WIP` in title for work-in-progress
- **Ensure gh installed**: If `gh` not found, prompt user/agent to install

</required>

## Issue Linking

In PR descriptions:
- `Closes #123` - Auto-closes on merge
- `Fixes #123` - Same as Closes
- `Relates to #123` - Links without closing

<related>

- `@smith-gh-pr/SKILL.md` - PR workflows, review comment fetching
- `@smith-git/SKILL.md` - Git operations

</related>
