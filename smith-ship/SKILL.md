---
name: smith-ship
description: Ship pipeline — review a worktree change to convergence, then atomic commit, push, PR, address review, squash-merge, ff-only sync, cleanup. Invoke with /smith-ship when you want to ship the current change end-to-end.
argument-hint: [scope or PR title]
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

1. **Isolate** — check `git status --porcelain` FIRST: if the checkout is
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
4. **Push & PR** — push the renamed branch; `gh pr create --base <default>
   --assignee @me` with a What/Why/Testing body ending with the `Assisted-by:`
   line (`@smith-style`). Link issues only if real. The body and title are
   content: show them and create on an explicit yes (`@smith-guidance`
   Harmless).
5. **Address review** — follow `@smith-gh-pr` (Code Review Cycle, Posting
   Review Findings) for fetching, replying, attribution, suggestion blocks,
   and the content-vs-mechanics gate. Ship-specific: fix high-confidence
   findings with **fix + amend** (not new commits); after each push rerun the
   `/smith-review` loop to a fresh converged verdict (full receipt + criteria —
   a mechanics-only recheck is not convergence); confirm CodeRabbit actually
   ran before trusting 0 (`@smith-gh-pr` "CodeRabbit fails OPEN").
6. **Merge** — on a converged verdict for the LATEST pushed commit (earlier
   convergence does not carry across new commits), `gh pr merge --squash
   --delete-branch` (targets the current branch's PR). If this branch has an
   open child PR stacked on it, OMIT `--delete-branch` and follow
   `@smith-stacks` instead.
7. **Sync & clean up** — `ExitWorktree` (remove), then ff-only pull the repo's
   DEFAULT branch in the primary checkout; clear any squash-merge orphan branch
   (`@smith-worktree` Sync-After-Squash-Merge).

State results in your own message (in-band); end with a `result:` line.
