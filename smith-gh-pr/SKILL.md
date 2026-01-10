---
name: smith-gh-pr
description: GitHub PR workflows including creation, review cycles, merge strategies, and stacked PRs. Use when creating PRs, reviewing code, merging branches, or managing stacked PR workflows. Covers rebase decision trees and AI-generated descriptions.
---

# GitHub PR Workflows

<metadata>

- **Load if**: Creating PRs, reviewing code, merging, stacked PRs
- **Prerequisites**: @smith-principles/SKILL.md, @smith-standards/SKILL.md, @smith-git/SKILL.md

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

Follow conventional commits format. See `@smith-style/SKILL.md` for details.

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
5. **Resolve threads after addressing** - don't leave resolved issues open
6. Re-check for new comments after CI passes

<required>

**After addressing review comments**: Always reply with commit SHA, then resolve the thread. Use `gh pr-review threads resolve` or GitHub MCP `resolve_review_thread`.

</required>

<required>

**Do not blindly follow review comments.** Research best practices with strong evidence before implementing questionable suggestions. See `@smith-research/SKILL.md`.

</required>

<forbidden>

- NEVER mention `@copilot` in replies (triggers unwanted sub-PRs)

</forbidden>

## Fetching Review Comments

<required>

**Install gh-pr-review extension** (third-party - consider pinning to vetted commit SHA):
```shell
gh extension install agynio/gh-pr-review
```

</required>

### gh-pr-review Commands

<required>

**CRITICAL**: All commands require `--pr {number} -R {owner}/{repo}` when using numeric PR selectors.

</required>

**View reviews** (use `--unresolved`, `--reviewer`, `--states` to filter):
`gh pr-review review view --pr {number} -R {owner}/{repo}`

**Reply to thread**:
`gh pr-review comments reply --pr {number} -R {owner}/{repo} --thread-id {PRRT_xxx} --body "..."`

**Resolve/unresolve thread**:
`gh pr-review threads resolve --pr {number} -R {owner}/{repo} --thread-id {PRRT_xxx}`

Output includes `thread_id` (PRRT_xxx format) needed for reply/resolve operations.

### REST API (Single Comments)

URL patterns map to API endpoints:
- `#issuecomment-{id}` → `gh api repos/{owner}/{repo}/issues/comments/{id}`
- `#discussion_r{id}` → `gh api repos/{owner}/{repo}/pulls/comments/{id}`
- `#pullrequestreview-{id}` → `gh api repos/{owner}/{repo}/pulls/{pr}/reviews/{id}`

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

- `@smith-gh-cli/SKILL.md` - GitHub CLI commands, pagination limits
- `@smith-stacks/SKILL.md` - Stacked PR workflows
- `@smith-git/SKILL.md` - Git operations, rebase
- `@smith-style/SKILL.md` - Conventional commits, branch naming
- `@smith-tests/SKILL.md` - Testing standards (pre-PR checklist)
- `@smith-research/SKILL.md` - Research best practices before implementing review feedback
- `@smith-validation/SKILL.md` - Debugging, root cause analysis for review issues

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
