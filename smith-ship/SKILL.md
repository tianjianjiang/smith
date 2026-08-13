---
name: smith-ship
description: Ship pipeline — review a worktree change to convergence, then atomic commit, push, PR, address review, squash-merge, ff-only sync, cleanup. Invoke with /smith-ship for a single change, or /smith-ship stack to split multi-part work into atomic stacked branches and ship them as stacked PRs.
argument-hint: [scope or PR title | stack]
allowed-tools: Bash(git *), Bash(gh *)
---

# /smith-ship — ship the current change end-to-end

Drive the change in the current worktree from review to merged, following smith
conventions. Run phases in order; stop and surface only on the must-ask triggers
in `@smith-gh-pr/SKILL.md` (Review Convergence Protocol). Argument (if given) is
the intended PR scope/title.

## Live state

- Status: !`git status -s`
- Branch: !`git branch --show-current`
- Open PR (if any): !`gh pr status 2>/dev/null | head -20`

## Procedure

Load and follow `@smith-gh-pr/SKILL.md`, `@smith-git/SKILL.md`,
`@smith-style/SKILL.md`, `@smith-worktree/SKILL.md`, and
`@smith-subagents/SKILL.md`.

0. **Preflight** — run `/smith-preflight` to see which invariants the change
   already violates. Exactly one result routes instead of blocking: a
   `branch-first FAIL` caused by the checkout sitting on a protected branch,
   and only when it is the ONLY failing check — paired with any other `FAIL`
   it stops here like the rest, or the companion failure rides along
   unaddressed. A `branch-first FAIL` from a detached HEAD is never that case.
   Every other `FAIL` stops here — a secret-scan failure in particular must
   not reach review or commit. The binding refusal on push stays at step 4.
1. **Isolate** — a `branch-first FAIL` from step 0 is not cleared by being
   clean: if the checkout sits on a protected branch with nothing modified,
   branch or `EnterWorktree` before any edit, then re-run the gate. Never
   take path (a) below while still on a protected branch — committing there
   is what `@smith-guidance` Harmless forbids; branch first, then commit.
   Otherwise check `git status --porcelain`: if the checkout is
   dirty, STOP and pick ONE path: (a) commit or stash the changes, then
   `EnterWorktree`; or (b) branch in place (`git switch -c …`) and continue in
   the current checkout — no `EnterWorktree` at all (the tree is still dirty
   and the `worktree-dirty-guard` hook would block it; a new worktree starts
   clean, stranding uncommitted changes). `worktree.baseRef: head` only
   preserves already-committed unpushed work, never uncommitted changes.
   Then, if on the EnterWorktree path in a background session, enter the
   worktree (see `@smith-worktree`) and rename the branch to the
   `@smith-style` convention before any push.
2. **Review to convergence** — run the `/smith-review` loop; it owns the tool
   marshaling, per-round receipts, and convergence criteria. Do not ship until
   it reports converged.
3. **Commit** — logically and semantically atomic; conventional subject ≤72,
   body ≤72/line, `Assisted-by:` trailer (see `@smith-style`). One concern per
   commit.
4. **Push & PR** — re-run `/smith-preflight` on the finished commit first and
   do NOT push on a `NO-GO` (step 0's verdict was taken before the branch and
   commit existed, so it does not carry). Then push the renamed branch;
   `gh pr create --base <default> --assignee @me` with a What/Why/Testing
   body ending with the `Assisted-by:`
   line (`@smith-style`). Link issues only if real. The body and title are
   content: show them and create on an explicit yes (`@smith-guidance`
   Harmless).
5. **Address review** — follow `@smith-gh-pr` (Code Review Cycle, Posting
   Review Findings) for fetching, replying, attribution, suggestion blocks,
   and the content-vs-mechanics gate. Ship-specific: fix high-confidence
   findings with **fix + amend** (not new commits); re-run `/smith-preflight`
   before each of those pushes too — an amended commit is content step 4's
   verdict never saw, so a token introduced while fixing a review finding
   would otherwise reach the remote unscanned; after each push rerun the
   `/smith-review` loop to a fresh converged verdict (full receipt plus
   criteria — a mechanics-only recheck is not convergence); confirm
   CodeRabbit actually
   ran before trusting 0 (`@smith-gh-pr` "CodeRabbit fails OPEN").
6. **Merge** — re-run `/smith-preflight` once more first: the PR title, body
   and every review reply are external writes authored AFTER step 4 gated,
   so this is the only point that measures them. Do NOT merge on a `NO-GO`:
   the refusal binds here exactly as it does at step 4, and a gate that runs
   without being able to stop the merge is decoration. Then, on both a `GO`
   and a converged verdict for the LATEST pushed commit (earlier
   convergence does not carry across new commits), `gh pr merge --squash
   --delete-branch` (targets the current branch's PR). If this branch has an
   open child PR stacked on it, OMIT `--delete-branch` and follow
   `@smith-gh-pr` "Stacked PRs" instead.
7. **Sync & clean up** — `ExitWorktree` (remove), then ff-only pull the repo's
   DEFAULT branch in the primary checkout; clear any squash-merge orphan branch
   (`@smith-worktree` Sync-After-Squash-Merge).

## Stacked mode — `/smith-ship stack`

For multi-part work that should ship as a dependent stack of PRs. Also load
`@smith-gh-pr` "Stacked PRs" (+ its `references/STACKS.md` when operating on
the stack) and `@smith-worktree`.

- **Decompose first** — split into logically AND semantically atomic units,
  each one branch/PR. Present the numbered decomposition and get scope
  approval BEFORE any branch exists (`@smith-guidance` Operating Discipline;
  this is a distinct, earlier gate than the existing-branch scope
  verification in `@smith-gh-pr` Stacked PRs).
- **Per unit, run phases 0-4 above** in that unit's own worktree, with two
  stack overrides: the PR base is the parent branch (not the default
  branch), and the PR body carries `Depends on:` / `Blocks:`. Branch names
  follow `@smith-style`. The stack's PR titles and bodies are shown together
  and opened on one explicit yes (batched consent).
- **Phases 5-7 are stack-wide, not per unit** — address review across the
  stack, then merge bottom-up with retarget-before-merge and manual parent
  branch deletion per `@smith-gh-pr` Stacked PRs (cli/cli#1168); cascade
  rebases; ff-only sync once per merge.
- **Report per branch** — verify the stack scope (no omissions) and state
  status per branch in-band.

State results in your own message (in-band); end with a `result:` line.
