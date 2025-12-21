# GitHub PR Workflows

<metadata>

- **Load if**: Creating PRs, reviewing code, merging, stacked PRs
- **Prerequisites**: @principles.md, @standards.md, @git.md
- **Related**: @gh-cli.md (CLI), @stacks.md (stacked PRs), @style.md (naming)

</metadata>

## CRITICAL (Primacy Zone)

<forbidden>

- NEVER force push to PRs from other authors
- NEVER amend commits already pushed to shared branches
- NEVER merge your own PR without review (unless emergency)
- NEVER create PRs with failing tests or lint errors
- NEVER use `--delete-branch` when merging stacked PRs
- NEVER request review while CI checks failing

</forbidden>

<required>

- MUST run quality checks before creating PR
- MUST ensure branch is up-to-date with base
- MUST link to related issues
- MUST have all CI checks passing before merge

</required>

## Dual-Approach Pattern

**Preferred**: GitHub MCP (`mcp__github__create_pull_request`, `mcp__github__merge_pull_request`)
**Fallback**: gh CLI (`gh pr create`, `gh pr merge`)

## PR Title Format

Follow conventional commits: `type(scope): description`
- Target 50 chars, max 72 chars
- Examples: `feat(auth): add OAuth2 login`, `fix(api): resolve CORS issues`

## PR Creation Workflow

```sh
# Pre-PR checklist
poetry run ruff format . && poetry run ruff check --fix .
poetry run pytest
git fetch origin && git rebase origin/main
git push -u origin feat/my_feature
```

**AI-generated descriptions**: Analyze full diff, read ALL commits, identify tickets, generate structured summary (What/Why/Testing/Dependencies).

## Working on Existing PRs

<required>

- ALWAYS get actual branch name: `gh pr view {PR} --json headRefName`
- ALWAYS check for review comments before making changes
- ALWAYS update PR title/body after pushing changes

</required>

## Code Review Cycle

1. Fetch review comments: `gh api /repos/{owner}/{repo}/pulls/{PR}/comments`
2. Categorize: Actionable > Nitpick > Clarification > Discussion
3. Implement fixes with confidence scoring (high: implement, low: ask)
4. Reply to comments with commit SHA
5. Mark threads resolved via GraphQL API
6. Re-check for new comments after CI passes

<forbidden>

- NEVER mention `@copilot` in replies (triggers unwanted sub-PRs)

</forbidden>

## Rebase Decision Tree

| Scenario                                     | Action                 |
| -------------------------------------------- | ---------------------- |
| Behind base, no conflicts, explicit "update" | AUTO-REBASE            |
| Behind base, no conflicts, not explicit      | ASK user               |
| Behind base, conflicts detected              | INFORM + ASK           |
| Parent PR merged                             | INFORM + OFFER cascade |
| About to request review, outdated            | BLOCK + INFORM         |

**Staleness thresholds**: <5 commits (fresh), 5-10 (notify), >10 (recommend), >20 (urgent)

## Merge Strategies

| Strategy     | Use for                                  |
| ------------ | ---------------------------------------- |
| Merge commit | Feature branches with meaningful history |
| Squash       | Small fixes, docs, single logical change |
| Rebase       | Linear history required, clean commits   |

## Stacked PRs

For stacked PRs, merge parent WITHOUT `--delete-branch`, then:
```sh
gh pr edit {CHILD} --base main
git rebase --onto origin/main feat/parent_branch
git push --force-with-lease
git push origin --delete feat/parent_branch
```

<related>

- @gh-cli.md - GitHub CLI commands
- @stacks.md - Stacked PR workflows
- @git.md - Git operations
- @style.md - Commit naming

</related>

## ACTION (Recency Zone)

**Create PR:**
```sh
gh pr create --title "feat: add feature" --body "..." --assignee @me
```

**Merge PR:**
```sh
gh pr merge {PR} --squash  # or --merge, --rebase
```

**Post-merge cleanup:**
```sh
git checkout main && git fetch --prune origin && git pull
git branch -d feat/my_feature
```

**Check freshness:**
```sh
git fetch origin
BEHIND=$(git rev-list HEAD..origin/main --count)
```
