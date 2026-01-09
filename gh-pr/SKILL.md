---
name: gh-pr
description: GitHub PR workflows including creation, review cycles, merge strategies, and stacked PRs. Use when creating PRs, reviewing code, merging branches, or managing stacked PR workflows. Covers rebase decision trees and AI-generated descriptions.
---

# GitHub PR Workflows

<metadata>

- **Load if**: Creating PRs, reviewing code, merging, stacked PRs
- **Prerequisites**: @principles/SKILL.md, @standards/SKILL.md, @git/SKILL.md

</metadata>

## CRITICAL (Primacy Zone)

<required>

- MUST run quality checks before creating PR
- MUST ensure branch is up-to-date before requesting review or merging
- MUST link to related issues
- MUST have all CI checks passing before merge

</required>

## Dual-Approach Pattern

**Preferred**: GitHub MCP (`mcp__github__create_pull_request`, `mcp__github__merge_pull_request`)
**Fallback**: gh CLI (`gh pr create`, `gh pr merge`)

## PR Title Format

Follow conventional commits format. See `@style/SKILL.md` for details.

## PR Creation Workflow

<required>

**Pre-PR checklist:**
1. Run linter and formatter
2. Run tests
3. Rebase onto parent branch (not always main - check stacked PRs)
4. Push to remote

</required>

**AI-generated descriptions**: Analyze full diff, read ALL commits, identify tickets, generate structured summary (What/Why/Testing/Dependencies).

## Working on Existing PRs

<required>

- ALWAYS get actual branch name: `gh pr view {PR} --json headRefName`
- ALWAYS check for review comments before making changes
- ALWAYS update PR title/body after pushing changes

</required>

## Code Review Cycle

1. Fetch review comments (see "Fetching Review Comments" below)
2. Categorize: Actionable > Nitpick > Clarification > Discussion
3. Implement fixes with confidence scoring (high: implement, low: ask)
   - **High confidence**: Small surface area change, aligns with existing patterns, covered by tests
   - **Low confidence**: Ambiguous behavior, architectural impact, requires design discussion
4. Reply to comments with commit SHA
5. Mark threads resolved
6. Re-check for new comments after CI passes

<required>

**Do not blindly follow review comments.** Research best practices with strong evidence before implementing questionable suggestions. See `@research/SKILL.md`.

</required>

<forbidden>

- NEVER mention `@copilot` in replies (triggers unwanted sub-PRs)

</forbidden>

## Fetching Review Comments

<required>

**Install gh-pr-review extension** for inline review comments:
```shell
gh extension install agynio/gh-pr-review
```

**Security note**: Third-party extensions run with gh CLI privileges. Consider pinning to a vetted commit SHA for production environments and periodically reviewing updates.

</required>

### URL Pattern Recognition

**Issue/PR comment** (`#issuecomment-{id}`):
`gh api repos/{owner}/{repo}/issues/comments/{id}`

**Inline review comment** (`#discussion_r{id}`):
`gh api repos/{owner}/{repo}/pulls/comments/{id}`

**Review summary** (`#pullrequestreview-{id}`):
`gh api repos/{owner}/{repo}/pulls/{pr}/reviews/{id}`

### Fetching Single Comments (REST)

**Inline review comment** (`discussion_r`):
```shell
gh api repos/{owner}/{repo}/pulls/comments/{comment_id} --jq '.body'
```

**Issue/PR conversation comment** (`issuecomment`):
```shell
gh api repos/{owner}/{repo}/issues/comments/{comment_id} --jq '.body'
```

**Review summary** (`pullrequestreview`):
```shell
gh api repos/{owner}/{repo}/pulls/{pr}/reviews/{review_id} --jq '.body'
```

### Review Threads with gh-pr-review

<required>

**Use `gh-pr-review` for thread context** - REST API cannot access review threads:

</required>

**View all reviews with inline comments and threads:**
```shell
gh pr-review review view {pr} -R {owner}/{repo}
```

**Filter unresolved threads only:**
```shell
gh pr-review review view {pr} --unresolved
```

**Filter by reviewer:**
```shell
gh pr-review review view {pr} --reviewer username
```

**Filter by state:**
```shell
gh pr-review review view {pr} --states CHANGES_REQUESTED,COMMENTED
```

**Output schema:**
```json
{
  "reviews": [{
    "id": "PRR_...",
    "state": "CHANGES_REQUESTED",
    "author_login": "reviewer",
    "comments": [{
      "thread_id": "PRRT_...",
      "path": "src/file.ts",
      "line": 42,
      "body": "Comment text",
      "is_resolved": false,
      "thread": [{ "author_login": "...", "body": "Reply" }]
    }]
  }]
}
```

### Replying and Resolving Threads

**Reply to a thread:**
```shell
gh pr-review comments reply --thread-id PRRT_xxx --body "Fixed in abc123"
```

**Resolve a thread:**
```shell
gh pr-review threads resolve PRRT_xxx
```

**Unresolve a thread:**
```shell
gh pr-review threads unresolve PRRT_xxx
```

### Creating Reviews Programmatically

**Start a pending review:**
```shell
gh pr-review review --start {pr} -R {owner}/{repo}
```

**Add inline comment to pending review:**
```shell
gh pr-review review --add-comment --review-id PRR_xxx \
  --path src/file.ts --line 42 --body "Consider refactoring"
```

**Submit the review:**
```shell
gh pr-review review --submit --review-id PRR_xxx \
  --event COMMENT --body "Review complete"
```

## Rebase Decision Tree

**Behind base, no conflicts, explicit "update"**: AUTO-REBASE
**Behind base, no conflicts, not explicit**: ASK user
**Behind base, conflicts detected**: INFORM + ASK
**Parent PR merged**: INFORM + OFFER cascade
**About to request review, outdated**: BLOCK + INFORM

**Staleness thresholds**: <5 commits (fresh), 5-10 (notify), >10 (recommend), >20 (urgent)

**Note**: The above decision tree provides guidance during active development. The MUST requirement for up-to-date branches is enforced when requesting review or merging.

## Merge Strategies

**Merge commit**: Feature branches with meaningful history
**Squash**: Small fixes, docs, single logical change
**Rebase**: Linear history required, clean commits

## Stacked PRs

For stacked PRs, merge parent WITHOUT `--delete-branch`, then:
```shell
gh pr edit {CHILD} --base main
git rebase --onto origin/main feat/parent_branch
git push --force-with-lease
git push origin --delete feat/parent_branch
```

<related>

- `@gh-cli/SKILL.md` - GitHub CLI commands, pagination limits
- `@stacks/SKILL.md` - Stacked PR workflows
- `@git/SKILL.md` - Git operations, rebase
- `@style/SKILL.md` - Conventional commits, branch naming
- `@tests/SKILL.md` - Testing standards (pre-PR checklist)
- `@research/SKILL.md` - Research best practices before implementing review feedback
- `@validation/SKILL.md` - Debugging, root cause analysis for review issues

</related>

## ACTION (Recency Zone)

**Create PR:**
```shell
gh pr create --title "feat: add feature" --body "..." --assignee @me
```

**Merge PR:**
```shell
gh pr merge {PR} --squash
```

Options: `--squash`, `--merge`, or `--rebase`

**Post-merge cleanup:**
```shell
git checkout main && git fetch --prune origin && git pull
git branch -d feat/my_feature
```

**Check freshness:**
```shell
git fetch origin
BEHIND=$(git rev-list HEAD..origin/main --count)
```
