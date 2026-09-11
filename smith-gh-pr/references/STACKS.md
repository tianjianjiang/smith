# Stacked Pull Requests — full workflows

Detail behind the "Stacked PRs" section of `../SKILL.md`. Load this file when
actually operating on a stack (creation, cascade update, merge, recovery);
the SKILL.md section alone covers the critical rules.

## Native tooling: `gh stack` (github/gh-stack)

When the `gh stack` extension is installed (`gh extension list` to confirm —
never assume it is absent from memory), it is the preferred way to run a stack
and it automates most of the manual dance documented below:

- `gh stack init [branch...]` — start a stack on the trunk, or adopt existing
  branches into one
- `gh stack add <branch>` — put the current commit on a new branch atop the
  stack (the one-commit-per-branch unit)
- `gh stack submit` — push the branches AND create/update the whole PR chain
  on GitHub (the create-the-PRs step)
- `gh stack push` — push the active branches in the stack to the remote only,
  without creating or updating PRs
- `gh stack sync` — fetch, reconcile with the stack on GitHub, fast-forward
  the trunk, cascade-rebase every branch onto its updated parent, push all
  branches with `--force-with-lease --atomic`, and link the open PRs into
  the GitHub stack object. The one command for "update the stack after
  trunk or a parent moved"
- `gh stack rebase` — the cascade rebase alone; `--continue` after resolving
  a conflict, `--abort` restores every branch
- `gh stack checkout <stack#|PR#|PR-URL>` — adopt an existing stack from
  GitHub into the current checkout (fetches the branches and writes local
  tracking)
- `gh stack link <bottom> ... <top>` — register existing PRs as a stack on
  GitHub without local tracking; a stack number as the first argument appends
  to that stack
- `gh stack merge` — merge the chain bottom-up
- `gh stack view` / `modify` / `unstack` — inspect, restructure, or dissolve

The manual `git rebase --onto` cascade and per-child base-retargeting in the
sections below remain the fallback ONLY when the extension is unavailable, and
the explanation for WHY each safeguard exists (e.g. the cli/cli#1168
child-close race) so a manual recovery stays correct.

### Existing stack from a fresh worktree

Local tracking lives per checkout (`.git/gh-stack` for the main checkout,
`.git/worktrees/<name>/gh-stack` for each worktree). A new worktree therefore
starts with none, and `gh stack view` reports:

```text
✗ current branch "feat/child" is not part of a stack
Checkout an existing stack using `gh stack checkout` ...
```

That message is a missing tracking file, not a missing stack. Recovery:

1. `gh stack checkout <stack#>` (the number in the GitHub stack UI; a PR
   number or URL also works) — restores tracking in this worktree from GitHub
2. `gh stack sync` — rebases the cascade and pushes atomically
3. On a conflict, `gh stack rebase`, resolve, `gh stack rebase --continue`
   (or `--abort`)

Never do any of the following while the extension is installed; each one was
the wrong turn in the 2026-09-11 incident (a five-PR stack, twelve hand-rolled
rebases, and a false conflict):

- Hand-roll `git checkout --detach <sha> && git rebase --onto <parent-tip>
  <old-parent-tip>` per branch. The `trunk.head` recorded in the tracking file
  goes stale the moment trunk moves; using it as the `--onto` base replays
  commits that trunk already merged and surfaces them as conflicts.
- Push with `--force-with-lease=<branch>:<sha> origin <sha>:refs/heads/<branch>`
  per branch. The raw-SHA refspec cascade reads as history tampering to the
  model safeguard and has triggered a `[cyber]` model fallback.
- Edit `.git/gh-stack` or `.git/worktrees/*/gh-stack` by hand (`jq`, Python).
  `gh stack sync` rewrites it from GitHub.

A branch checked out in another worktree cannot be rebased; `git -C <that
worktree> checkout --detach` first, then run `gh stack sync` from the
worktree that owns the stack tracking.

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
