# Stacked Pull Requests — full workflows

Detail behind the "Stacked PRs" section of `../SKILL.md`. Load this file when
actually operating on a stack (creation, cascade update, merge, recovery);
the SKILL.md section alone covers the critical rules.

## When to stack

- Feature requires 500+ lines of changes
- Multiple logical components that can be reviewed independently
- Need to unblock dependent work before the full feature is ready

## Creating a stack

1. Create the base PR with the foundation (e.g., `feat/auth-base`)
2. Create each child PR branching from its parent (e.g., `feat/auth-login`
   from `feat/auth-base`); open each PR with its base set to the parent
   branch, not the default branch
3. Each PR must be independently reviewable and mergeable
4. Isolate each unit in its own worktree — a stack built without
   per-unit worktrees invites cross-unit contamination
5. Merge bottom-up: base first, then children

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
- **Depends on**: #123 (feat/auth-base) ← must merge before this PR
- **Blocks**: #125 (feat/auth-oauth) ← waits for this PR
```

Every stacked PR body also ends with the `Assisted-by:` line (see
`@smith-style`). The stack's PR titles and bodies are content: show them
together and open on an explicit yes — reviewed together they count as one
enumerated list (`@smith-guidance` Harmless, batched consent).

**Field meanings**:
- `Depends on`: PRs that must merge before this one (upstream dependencies)
- `Blocks`: PRs waiting for this one to merge (downstream dependents)

## Stack scope verification (existing branches only)

This gate enumerates existing branches (`git branch -r`), so it can only run
once branches exist; the decomposition/scope approval BEFORE branches exist
is a distinct, earlier gate owned by the shipping pipeline (`@smith-ship`
stacked mode).

**Before stack-wide operations (rebase cascade, PR creation):**
1. Load stack metadata from Serena memory (if available)
2. Enumerate ALL branches with commit counts:
   `./smith-gh-pr/scripts/verify-stack-scope.sh 'feat/PROJ-*'`
3. Present the scope summary and get explicit approval before proceeding
4. After completion, report status per branch

**Empty rebase detection:** if `git rebase` produces 0 new commits, STOP,
investigate (already up-to-date? wrong base?), and report the anomaly before
continuing.

## Merge workflow (bottom-up)

1. Wait for parent PR approval
2. Retarget the child PR's base onto the parent's base (its grandparent, or
   the default branch if the parent is the stack's base) — BEFORE merging
   the parent, to avoid GitHub auto-closing the child (cli/cli#1168)
3. Merge the parent PR
4. Rebase the child onto the updated default branch
5. Get the child approved; repeat per level

**Correct merge sequence**:
```text
1. Retarget PR #2 (feat/auth-login) onto main (before merging PR #1)
2. Merge PR #1 (feat/auth-base) → main
3. Rebase PR #2 onto main
4. Retarget PR #3 (feat/auth-oauth) onto main (before merging PR #2)
5. Merge PR #2 → main
6. Rebase PR #3 onto main
7. Merge PR #3 → main (can squash this one)
```

## Rebasing after a parent merges

```shell
git fetch origin
git checkout feat/auth-login
git rebase --onto origin/main feat/auth-base
git push --force-with-lease
```

**Why `--onto`**: only transplants commits unique to the child branch,
avoiding duplicate commits.

**Before** (parent merged as M):
```text
main ──●──●──●──M
                 \
feat/auth-login ──A──B──C (still based on old parent)
```

**After `git rebase --onto origin/main feat/auth-base`**:
```text
main ──●──●──●──M
                 \
                  └──A'──B'──C' (rebased)
```

## Squash merge with stacked PRs

Squash merge IS allowed if the branch-deletion process is followed.

Delete a parent branch only AFTER its child is retargeted, and delete it
manually (`git push origin --delete`), never with `gh pr merge
--delete-branch` — the gh CLI closes the still-pointing child instead of
retargeting it (cli/cli#1168, still open; the web-UI delete auto-retargets).

Retarget every child BEFORE merging its parent — not only after. If the repo
has "automatically delete head branches" enabled, merging the parent deletes
its branch immediately and GitHub auto-CLOSES (does not retarget) any child
still based on it; recovery is reopen/recreate. Pre-retargeting avoids the
race.

**Merge strategy by PR position**:
- **Parent / middle (has children)**: squash OK with the process above;
  delete only after the child base is updated
- **Final (leaf)**: squash OK, immediate deletion OK

**Why squash needs the extra steps**: squash creates a single commit,
destroying commit ancestry; child branches still contain the parent's
original commits, causing duplicate commits, rebase conflicts, and Git
failing to recognize commits already merged.

**Fixing a child after its parent was squash-merged**:

Option 1 — rebase with `--fork-point`:
```shell
git fetch origin
git checkout feat/auth-login
git rebase --onto origin/main --fork-point origin/feat/auth-base
git push --force-with-lease
```

Option 2 — interactive rebase, mark the parent's commits as `drop`:
```shell
git checkout main && git pull
git checkout feat/auth-login
git rebase -i main
```

## Keeping a stack updated

Cascade updates through the stack sequentially — update each child by
merging its immediate parent, never the default branch directly:

```shell
git checkout feat/auth-base
git merge main
git push

git checkout feat/auth-login
git merge feat/auth-base
git push
```

- After each cascade step, run `git log --oneline -3` and confirm the tip
  commit is the merge/rebase you just performed before proceeding downstream

**Avoid** merging main directly into a child branch — it corrupts history.

## Best practices

**Good stack structure**: each PR independently reviewable; dependencies
documented in PR descriptions; atomic commits within each level; bottom-up
merge order; stacks no deeper than 3-4 levels.

**Good communication**: document stack relationships in PR descriptions;
update child PRs promptly after a parent merges; notify reviewers when
dependencies merge; explain the overall feature in the base PR.

**Avoid**: stacks deeper than 3-4 levels; merging out of order; forgetting
to update children after a parent merge; stacking unrelated changes.
