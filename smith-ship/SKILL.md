---
name: smith-ship
description: User-invoked ship pipeline — review a worktree change to convergence, then atomic commit, push, PR, address review, squash-merge, ff-only sync, cleanup. Invoke with /smith-ship when you want to ship the current change end-to-end.
disable-model-invocation: true
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

1. **Isolate** — if not already in a worktree and this is a background session,
   `EnterWorktree` first (see `@smith-worktree`); rename the branch to the
   `@smith-style` convention before any push.
2. **Review to convergence** — run the `/smith-review` loop (smith review
   skills + `/code-review` + CodeRabbit). Iterate until a clean round (0
   actionable); treat each return as a claim and verify against the diff. Cost
   guard: bounded reviewers, no blind subagent fan-out.
3. **Commit** — logically and semantically atomic; conventional subject ≤72,
   body ≤72/line, `Co-Authored-By` trailer. One concern per commit.
4. **Push & PR** — push the renamed branch; `gh pr create --base <default>
   --assignee @me` with a What/Why/Testing body. Link issues only if real.
5. **Address review** — fetch and reply to comments via the `gh pr-review`
   extension (see `@smith-gh-pr`); fix high-confidence findings with **fix +
   amend** (not new commits), reply with SHA + attribution ("on behalf of
   @<user>"), resolve threads. Re-review after each push. Confirm CodeRabbit
   actually ran (it fails open) before trusting 0.
6. **Merge** — on convergence, `gh pr merge --squash --delete-branch` (targets
   the current branch's PR).
7. **Sync & clean up** — `ExitWorktree` (remove), then ff-only pull the repo's
   DEFAULT branch in the primary checkout; clear any squash-merge orphan branch
   (`@smith-worktree` Sync-After-Squash-Merge).

State results in your own message (in-band); end with a `result:` line.
