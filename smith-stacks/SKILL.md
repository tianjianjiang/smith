---
name: smith-stacks
description: Stacked pull request workflows for large features. Use when creating stacked PRs, managing dependent PRs, or rebasing after parent merges. Covers stack creation, merge order, and squash merge handling.
---

# Stacked Pull Requests

**Scope:** Advanced stacked PR workflows and patterns for large features
**Load if:** Creating stacked PRs, working on PR stacks, managing dependent PRs
**Prerequisites:** `@smith-gh-pr/SKILL.md`, `@smith-git/SKILL.md`, `@smith-gh-cli/SKILL.md`

## CRITICAL

- Merge the parent PR before its child PR.
- Update child branches by merging their immediate parent (not `main`
  directly) — cascade through each level of the stack in order.
- Keep stacks to 3-4 levels deep.
- Retarget the child first, then delete the parent branch after — avoid
  `gh pr merge --delete-branch` on a parent/middle PR while a child PR still
  targets its branch: via the gh CLI this CLOSES the child instead of
  retargeting it (cli/cli#1168, still open; the web-UI delete auto-retargets).
- Squash-merging a non-final stacked PR is fine as long as it's followed by
  the cascade-sync (rebase child `--onto`, retarget, then delete the parent
  branch) — squash itself is allowed; see Squash Merge with Stacked PRs.

## Stack Scope Verification

**Before stack-wide operations (rebase cascade, PR creation):**
1. Load stack metadata from Serena memory (if available)
2. Enumerate ALL branches with commit counts
3. Present scope summary to user
4. Get explicit scope approval before proceeding
5. After completion, report status per branch

**Empty rebase detection:**
- If `git rebase` produces 0 new commits, STOP
- Investigate why (already up-to-date? wrong base?)
- Report the anomaly to user before continuing

For large features, use stacked PRs to maintain atomic, reviewable changes.

**When to stack**:
- Feature requires 500+ lines of changes
- Multiple logical components that can be reviewed independently
- Need to unblock dependent work before full feature is ready

## Creating Stacked PRs

**How to stack**:
1. Create base PR with foundation (e.g., `feat/auth-base`)
2. Create child PR branching from base (e.g., `feat/auth-login` from `feat/auth-base`)
3. Each PR should be independently reviewable and mergeable
4. Merge bottom-up: base first, then children

### Examples

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

## Stacked PR Merge Workflow

**Sequential merge order** (bottom-up):
1. Wait for parent PR approval
2. Merge parent PR into `main`
3. Rebase child PR onto updated `main`
4. Get child PR approved
5. Repeat for each level in stack

### Examples

**Correct merge sequence**:
```text
1. Merge PR #1 (feat/auth-base) → main
2. Rebase PR #2 (feat/auth-login) onto main
3. Merge PR #2 → main
4. Rebase PR #3 (feat/auth-oauth) onto main
5. Merge PR #3 → main (can squash this one)
```

## Rebasing After Parent Merges

When a parent PR merges, child PRs must be rebased:

1. Fetch latest changes
2. Checkout child branch
3. Rebase onto updated main
4. Force push (safe for your PR branch)

```shell
git fetch origin
git checkout feat/auth-login
git rebase --onto origin/main feat/auth-base
git push --force-with-lease
```

**Why `--onto`**: Only transplants commits unique to child branch (commits between parent and child), avoiding duplicate commits.

### Examples

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

## Squash Merge with Stacked PRs

**Squash merge IS allowed** if you follow the branch deletion process for stacked PRs.

Delete a parent branch only AFTER its child is retargeted, and delete it
manually (`git push origin --delete`), never with `gh pr merge --delete-branch`
— the gh CLI closes the still-pointing child instead of retargeting it
(cli/cli#1168). The web-UI merge+delete auto-retargets; the CLI does not.

Retarget every child to `main` (or the next surviving base) BEFORE merging its
parent — not only after. If the repo has "automatically delete head branches"
enabled, merging the parent deletes its branch immediately and GitHub
auto-CLOSES (does not retarget) any child still based on it; recovery is
reopen/recreate. Pre-retargeting avoids the race.

**Merge Strategy by PR Position**:
- **Parent (has children)**: Squash OK with process, delete after child base updated
- **Middle**: Squash OK with process, delete after child base updated
- **Final (leaf)**: Squash OK, immediate deletion OK

**Why squash merge requires extra steps**:

Squash merge creates a single commit, destroying commit ancestry. Child branches still contain parent's original commits, causing:
- Duplicate commits in child PR
- Merge conflicts when rebasing
- Git unable to recognize commits already in main

### Examples

**Fixing child PR after parent was squash merged**:

Option 1 - Rebase with `--fork-point`:
```shell
git fetch origin
git checkout feat/auth-login
git rebase --onto origin/main --fork-point origin/feat/auth-base
git push --force-with-lease
```

Option 2 - Interactive rebase to drop parent's commits:
```shell
git checkout main && git pull
git checkout feat/auth-login
git rebase -i main
```
In the interactive editor, mark all commits from the parent branch as `drop`.

## Keeping Stack Updated

When pulling changes from main into a stack, cascade updates through the stack sequentially:

```shell
git checkout feat/auth-base
git merge main
git push

git checkout feat/auth-login
git merge feat/auth-base
git push
```

- After each cascade step, run `git log --oneline -3` and confirm the tip commit is the merge/rebase you just performed before proceeding downstream

### Avoid

Merging main directly into a child branch corrupts history:

```shell
git checkout feat/auth-login
git merge main
```

## Best Practices

### Good

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

### Avoid

**Bad practices**:
- Creating stacks deeper than 3-4 levels (too complex to manage)
- Merging PRs out of order (breaks dependency chain)
- Forgetting to update child PRs after parent merge (causes conflicts)
- Using stacked PRs for unrelated changes (defeats purpose of atomicity)

## Related

- `@smith-gh-pr/SKILL.md` - Complete GitHub PR lifecycle
- `@smith-git/SKILL.md` - Commits, branches, rebase
- `@smith-gh-cli/SKILL.md` - GitHub CLI commands

## Before You Finish

**Merge stacked PRs bottom-up:**
1. Merge parent PR first, WITHOUT `--delete-branch` (the gh CLI would close
   the child instead of retargeting it — cli/cli#1168)
2. Retarget child base: `gh pr edit {child} --base main`
3. Rebase child: `git rebase --onto origin/main feat/parent`
4. Force push child: `git push --force-with-lease`
5. Delete the parent branch only now: `git push origin --delete feat/parent`

**Verify stack scope before operations:**
```shell
./smith-stacks/scripts/verify-stack-scope.sh 'feat/PROJ-*'
```
