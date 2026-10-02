# Intent: stop the three mistakes the owner keeps correcting

Author: repository owner. Status: accepted by the owner.

## Problem

The owner's complaints about the agent that works under these instructions,
in the owner's words:

1. It "always leaves loose ends". Its own report says "unverified" or "not
   checked yet", or asks whether it should check, and then it stops.
2. It "often ignores smith skills". The owner has to name the skill that
   covers the task before the agent loads it.
3. It writes skills "that contain status/date/PR/ticket that should never be
   in skills in the first place".

The instructions already forbid all three. The owner has repeated each
correction across many sessions and the mistakes return.

## Proposed outcome

- The agent closes what it opened before it ends a turn.
- The agent loads and follows the skill that covers the task without being
  told its name.
- No skill file holds status, a date, or a pull-request or ticket reference.
- What changes follows best practice, and each practice comes with the URL
  of its evidence.
- The owner stops having to make these three corrections.

## Affected users and systems

- The owner, in every project on this machine.
- This repository: the skills, `AGENTS.md`, the hooks.
- The owner's personal profile: its settings and rule files.
- The project-local skills the owner keeps, untracked, in another
  repository.
- The other two profiles on the machine.

## Constraints

- Evidence is a primary source read in full, a comparison with published
  skill libraries, a measurement on this machine, and an independent attempt
  to refute the conclusion. A summary of a source is not evidence.
- Point-in-time content leaves the skill files only. The reference documents
  beside them stay.
- Skills that another repository shares with its team are not touched.
- A profile other than the personal one changes only after the owner has
  seen the exact difference and said yes to it.
- This repository is public: no client name, private path or ticket key.
- The owner is not asked to choose how it is done.

## Open questions

- The same session history shows trouble with checkpoints and plan files.
  That is a separate intent.
