# Stacked Pull Requests

<metadata>

- **Scope**: Advanced stacked PR workflows and patterns for large features
- **Load if**: Creating stacked PRs, working on PR stacks, managing dependent PRs
- **Prerequisites**: @gh-pr.md, @git.md, @gh-cli.md

</metadata>

<context>

## Scope

- **This document**: Advanced stacked PR patterns, merge workflows, rebase strategies
- **GitHub PR workflows**: @gh-pr.md - Complete GitHub PR lifecycle
- **Git operations**: @git.md - Local git commands

## When to Use Stacked PRs

For large features, use stacked PRs to maintain atomic, reviewable changes.

**When to stack**:
- Feature requires 500+ lines of changes
- Multiple logical components that can be reviewed independently
- Need to unblock dependent work before full feature is ready

</context>

## Creating Stacked PRs

<required>

**How to stack**:
1. Create base PR with foundation (e.g., `feat/auth-base`)
2. Create child PR branching from base (e.g., `feat/auth-login` from `feat/auth-base`)
3. Each PR should be independently reviewable and mergeable
4. Merge bottom-up: base first, then children

</required>

<examples>

**Stack structure**:
```text
main
 └── feat/auth-base (PR #1: models, migrations)
      └── feat/auth-login (PR #2: login endpoint)
           └── feat/auth-oauth (PR #3: OAuth integration)
```

**PR description for stacked PRs**:
```markdown
## Stack
- **Depends on**: #123 (feat/auth-base) ← This PR requires #123 to be merged first
- **Blocks**: #125 (feat/auth-oauth) ← PR #125 depends on this PR
```

**Field meanings**:
- `Depends on`: PRs that must merge before this one (upstream dependencies)
- `Blocks`: PRs waiting for this one to merge (downstream dependents)

</examples>

## Stacked PR Merge Workflow

<required>

**Sequential merge order** (bottom-up):
1. Wait for parent PR approval
2. Merge parent PR into `main`
3. Rebase child PR onto updated `main`
4. Get child PR approved
5. Repeat for each level in stack

</required>

<forbidden>

- NEVER merge child PR before parent (merges into parent branch, not main)
- NEVER merge main directly into child branch (corrupts history)
- NEVER use squash merge for non-final PRs in a stack

</forbidden>

<examples>

**Correct merge sequence**:
```text
1. Merge PR #1 (feat/auth-base) → main
2. Rebase PR #2 (feat/auth-login) onto main
3. Merge PR #2 → main
4. Rebase PR #3 (feat/auth-oauth) onto main
5. Merge PR #3 → main (can squash this one)
```

</examples>

## Rebasing After Parent Merges

<required>

When a parent PR merges, child PRs must be rebased:

1. Fetch latest changes
2. Checkout child branch
3. Rebase onto updated main
4. Force push (safe for your PR branch)

```sh
git fetch origin
git checkout feat/auth-login
git rebase --onto origin/main feat/auth-base
git push --force-with-lease
```

**Why `--onto`**: Only transplants commits unique to child branch (commits between parent and child), avoiding duplicate commits.

</required>

<examples>

**Before rebase** (after parent merged):
```text
main ──●──●──●──M (parent merged as M)
                 \
feat/auth-login ──A──B──C (still based on old parent)
```

**After `git rebase --onto origin/main feat/auth-base`**:
```text
main ──●──●──●──M
                 \
                  └──A'──B'──C' (feat/auth-login rebased)
```

</examples>

## Squash Merge with Stacked PRs

<required>

**Squash merge IS allowed** if you follow the branch deletion process for stacked PRs.

**Merge Strategy by PR Position**:

**Parent (has children)**:
- Squash Merge: OK with process
- Branch Deletion Timing: After child base updated

**Middle**:
- Squash Merge: OK with process
- Branch Deletion Timing: After child base updated

**Final (leaf)**:
- Squash Merge: OK
- Branch Deletion Timing: Immediate OK

</required>

**Why squash merge requires extra steps**:

Squash merge creates a single commit, destroying commit ancestry. Child branches still contain parent's original commits, causing:
- Duplicate commits in child PR
- Merge conflicts when rebasing
- Git unable to recognize commits already in main

<examples>

**Fixing child PR after parent was squash merged**:

Option 1 - Rebase with `--fork-point`:
```sh
git fetch origin
git checkout feat/auth-login
git rebase --onto origin/main --fork-point origin/feat/auth-base
git push --force-with-lease
```

Option 2 - Interactive rebase to drop parent's commits:
```sh
git checkout main && git pull
git checkout feat/auth-login
git rebase -i main
```
In the interactive editor, mark all commits from the parent branch as `drop`.

</examples>

## Keeping Stack Updated

<required>

When pulling changes from main into a stack, cascade updates through the stack sequentially:

```sh
git checkout feat/auth-base
git merge main
git push

git checkout feat/auth-login
git merge feat/auth-base
git push
```

</required>

<forbidden>

Merging main directly into a child branch corrupts history:

```sh
git checkout feat/auth-login
git merge main
```

</forbidden>

## Best Practices

<examples>

**Good stack structure**:
- Each PR is independently reviewable (clear purpose, focused changes)
- Clear dependency documentation in PR descriptions
- Commits are atomic within each level
- Bottom-up merge order maintained

**Good communication**:
- Document stack relationships in PR descriptions
- Update child PRs promptly after parent merges
- Notify reviewers when dependencies merge
- Explain the overall feature in parent PR

</examples>

<forbidden>

**Bad practices**:
- Creating stacks deeper than 3-4 levels (too complex to manage)
- Merging PRs out of order (breaks dependency chain)
- Forgetting to update child PRs after parent merge (causes conflicts)
- Using stacked PRs for unrelated changes (defeats purpose of atomicity)

</forbidden>

## Stacked PR References

- [How to handle stacked PRs on GitHub](https://www.nutrient.io/blog/how-to-handle-stacked-pull-requests-on-github/)
- [Stacked pull requests with squash merge](https://echobind.com/post/stacked-pull-requests-with-squash-merge/)
- [How to merge stacked PRs in GitHub](https://graphite.com/guides/how-to-merge-stack-pull-requests-github)
- [Dave Pacheco's Stacked PR Workflow](https://www.davepacheco.net/blog/2025/stacked-prs-on-github/)

## Related Standards

- **GitHub PR Workflows**: @gh-pr.md - Complete GitHub PR lifecycle (creation, review, merge, cleanup)
- **Git Operations**: @git.md - Commits, branches, rebase, force-push
- **GitHub CLI**: @gh-cli.md - GitHub CLI commands
