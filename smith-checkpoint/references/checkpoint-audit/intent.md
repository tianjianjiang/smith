# Intent: Audit a checkpoint before writing it, verify it after

Status: accepted.

## Problem

`/smith-checkpoint` writes whatever body the agent drafted. Nothing checks
that the body, the paired plan file and the facts they point at are current
and correct, or that the read-merge-write in `write-checkpoint.sh` kept every
prior entry. After `/clear` the resuming session sees only those artifacts,
so a stale plan checkbox, a `file:line` anchor that no longer holds, a
dropped decision or a lost prior entry becomes confusion or lost work.

## Proposed outcome

- The skill's Procedure gains an "Audit before writing" step: sync the plan
  file, re-verify each fact against its source, run a cold-reader test, and
  remove contradictions between body and plan.
- A read-only `audit-checkpoint.sh` checks what a script can decide, and
  `write-checkpoint.sh` runs it before any backend write; a failure writes
  nothing.
- Anchor resolution is made good enough to fail hard rather than downgraded
  to a warning: bare file names, plan-relative names, absolute and `~/`
  paths, and other repositories (`roots=`) all resolve, so a failure means
  the anchor is really wrong.
- Nothing is lost, not merely detected: each backend's prior document is
  backed up before it is overwritten, the document is read back after the
  write, and a lost or misplaced entry restores the backup and fails.

## Constraints

- A missing plan file stays non-fatal (recorded contract: the stop hook may
  pass a plan that was deleted); the audit warns instead.
- `audit=skip` is an explicit, reported override, not a default.
- No new dependencies beyond `git` and standard POSIX tools.
