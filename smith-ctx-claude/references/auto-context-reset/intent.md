# Intent: One continuation per checkpoint for the automatic context reset

Status: draft.

## Problem

When a Claude Code session nears its context limit, the automatic context
reset asks it to save a checkpoint and hands the work to a new session. The
reset cannot tell what the session has already done, and the person running
the session sees three failures:

- A checkpoint still being checked is taken for one never started. The
  session is asked again while it checks, and it saves the checkpoint before
  the checks finish.
- A session whose work has already moved on is taken for one that has not.
  The same work goes to more than one new session, and those sessions compete
  for one working copy.
- A checkpoint saved just before the request is taken for an outdated one.
  The work is not handed on at all.

The earlier session is also never told, in a way it reads, that its work has
moved, so it carries on.

## Proposed outcome

- A checkpoint's checks finish without the session being interrupted or
  asked again.
- Each saved checkpoint leads to at most one new session, and the earlier
  session learns that its work moved and stops.
- A checkpoint is handed on only while the session has done nothing since
  saving it.
- Each checker of a checkpoint sees only what it is meant to see.
- The same situation always gets the same answer from the reset.

## Affected users and systems

- People who run long Claude Code sessions with the automatic context reset,
  in every profile that uses it.
- The checkpoint procedure and the automatic context reset of this
  repository.

## Constraints

- Restoring a session after a manual reset keeps working as it does now.
- Setting it up in a profile stays as it is now.
- No new dependency.

## Open questions

None.
