# GitHub Agent Post-Merge Workflows

<metadata>

- **Scope**: Agent automation for post-merge operations and stack updates
- **Load if**: PR just merged, immediately after merge operation
- **Prerequisites**: [PR Concepts](./rules-pr-concepts.md), [GitHub PR Operations](./rules-github-pr.md)

</metadata>

<context>

## Scope

- **This document**: Post-merge workflows, child PR detection, cascade updates for stacked PRs
- **Basic PR operations**: See [GitHub PR Operations](./rules-github-pr.md)
- **Other agent workflows**: See [Review Automation](./rules-github-agent-review.md), [Rebase](./rules-github-agent-rebase.md), [PR Creation](./rules-github-agent-create.md)

</context>

## Agent Post-Merge Workflow

<scenario>

**Context**: Agent just merged PR or user informs agent of merge

**Agent workflow**:
1. Check if merged PR has child PRs (parse "Blocks: #{number}" in PR body)
2. If children exist, trigger cascade update workflow
3. If no children, perform standard cleanup
4. Sync local repository

```sh
# After merging PR #123
MERGED_BRANCH=$(gh pr view 123 --json headRefName -q .headRefName)

# Check for child PRs
CHILD_PRS=$(gh pr list --json number,body --jq '.[] | select(.body | contains("Depends on: #123")) | .number')

if [ -n "$CHILD_PRS" ]; then
  # Agent: "I found {N} child PR(s). Shall I update them now?"
  # Trigger cascade update workflow (see Rebase Automation)
else
  # Standard cleanup
  git checkout main
  git fetch --prune origin
  git pull origin main
  git branch -d "$MERGED_BRANCH"
  git ls-remote --exit-code --heads origin "$MERGED_BRANCH" >/dev/null 2>&1 && \
    git push origin --delete "$MERGED_BRANCH"
fi
```

**Stacked PR cascade example**:
```
User: "PR #123 merged"
Agent: "PR #123 (feature/auth_base) merged. Found stack:
  main
   └─ PR #123 (merged) ← feature/auth_base
       ├─ PR #124 ← feature/auth_login (child, 245 lines)
       └─ PR #125 ← feature/auth_session (child, 180 lines)

Auto-updating stack..."
Agent: [Updates #124 base to main, rebases onto origin/main]
Agent: "✓ PR #124 rebased successfully. No conflicts."
Agent: [Updates #125 base, rebases]
Agent: "✓ PR #125 rebased successfully. No conflicts."
Agent: [Deletes local and remote feature/auth_base]
Agent: "Stack updated. All PRs ready for continued review."
```

</scenario>

<forbidden>

- NEVER use `git branch -D` (force delete) unless you are certain the branch should be abandoned
- NEVER delete local branch before PR is merged
- NEVER skip `git fetch --prune` (leaves stale remote-tracking refs)

</forbidden>

## Related Standards

- **PR Concepts**: `$HOME/.smith/rules-pr-concepts.md` - Platform-neutral PR workflows (see Stacked PRs)
- **GitHub PR Operations**: `$HOME/.smith/rules-github-pr.md` - Basic GitHub operations
- **Rebase Automation**: `$HOME/.smith/rules-github-agent-rebase.md` - Post-parent-merge cascade workflow
- **Review Automation**: `$HOME/.smith/rules-github-agent-review.md` - Review cycle automation
- **PR Creation Automation**: `$HOME/.smith/rules-github-agent-create.md` - Agent PR creation
- **Agent Utilities**: `$HOME/.smith/rules-github-agent-utils.md` - Workflow coordination
- **Git Standards**: `$HOME/.smith/rules-git.md` - Post-merge local sync (lines 321-339)
