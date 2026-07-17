---
name: smith-stack
description: Stacked-PR pipeline — split work into logically/semantically atomic stacked branches in separate worktrees, review each to convergence, then push and open stacked PRs. Invoke with /smith-stack.
argument-hint: [feature or scope]
allowed-tools: Bash(git *), Bash(gh *)
---

# /smith-stack — atomic stacked branches → stacked PRs

For multi-part work that should ship as a dependent stack. For a single change
use `/smith-ship`.

## Procedure

Load `@smith-stacks/SKILL.md`, `@smith-worktree/SKILL.md`,
`@smith-gh-pr/SKILL.md`, `@smith-git/SKILL.md`, `@smith-style/SKILL.md`,
`@smith-subagents/SKILL.md`.

1. **Plan the stack** — decompose into logically AND semantically atomic
   units, each one branch/PR. Present the numbered decomposition and get scope
   approval before creating branches (`@smith-guidance` Scope Verification).
2. **Isolate per unit** — a separate worktree per branch; base each branch on
   the previous one in the stack. Rename branches to the `@smith-style`
   convention.
3. **Review each to convergence** — run `/smith-review` in each worktree
   independently; fix to a clean round per unit.
4. **Push & open stacked PRs** — push bottom-up; open each PR with its base set
   to the parent branch (not the default branch). Note the stack order in each
   body, and end each body with the `Assisted-by:` line (`@smith-style`). Each
   PR's title and body are content: show them and open on an explicit yes — the
   stack's titles and bodies reviewed together count as one enumerated list
   (`@smith-guidance` Harmless).
5. **Merge order & sync** — merge parent-first; per
   `@smith-stacks`/`@smith-gh-pr` OMIT `--delete-branch` when an open child
   exists, then retarget the child to the default branch and rebase. After each
   merge, ff-only pull the default branch in the primary checkout; clean up
   merged worktrees/branches.

Verify the stack scope (no omissions) and report status per branch in-band.
