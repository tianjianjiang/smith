# Plan: One continuation per checkpoint, decided by work done since the write

<!-- checkpoint-label-v1: checkpoint_stop_hook_reentry_and_shared_worker_runtime -->

Source: `intent.md` and `spec.md` in this directory. Status: approved by
the owner on 2026-11-22 and built; tasks 1 to 7 are done and the change is
in review under `/smith-ship`. It replaced an earlier five-state design on
branch `fix/stop-hook-session-state`, which was never committed.

## Overview

The Stop hook hands a checkpoint to a new session only when the session has
done nothing since that checkpoint was written. How that is measured, and
which signals were rejected: "Stop hook states" and "Decisions" in
`spec.md`, in this directory.

## Design decisions

"Decisions" in `spec.md`.

## State table

"Stop hook states" in `spec.md`, in this directory. "The table" in the tasks
below is that one.

## Files that change

- `smith-ctx-claude/scripts/ctx-reset-state.sh`: rewritten to the table.
- `smith-ctx-claude/scripts/enforce-clear.sh`: measures "worked", passes it
  with each stop, records `continued` before the launch.
- `smith-ctx-claude/scripts/inject-plan.sh`: returns to its content at
  `daf6c36`.
- `smith-checkpoint/SKILL.md`: the request command lines go; the start
  command stays.
- `smith-checkpoint/scripts/write-checkpoint.sh`: unchanged call; the state
  script records the write time itself.
- Tests: `ctx-reset-state.test.sh`, `enforce-clear-state.test.sh`,
  `enforce-clear-state-dispatch.test.sh` in
  `smith-ctx-claude/scripts/tests/`, and
  `smith-checkpoint/scripts/tests/write-checkpoint-state.test.sh`.
- Set aside, never committed: `inject-plan-state.test.sh` and
  `fixtures/machine-message-prompts/` in `smith-ctx-claude/scripts/tests/`.
- Documents: `spec.md` and `intent.md` in this directory,
  `smith-mode-plan-claude/references/HOOKS.md`, `smith-ctx-claude/SKILL.md`.

## Tasks

- [x] Task 1: Probe what the transcript holds when the Stop hook runs
- [x] Task 2: State script answers by the table
- [x] Task 3: The hook measures work done since the write
- [x] Task 4: The hook launches at most once
- [x] Task 5: Take out the typed-prompt wiring
- [x] Task 6: The checkpoint procedure sends only the start
- [x] Task 7: Documents match the code
- [ ] Task 8: Full verification <- CURRENT
- [ ] Task 9: `/smith-ship`, on the owner's instruction

### Task 1: Probe what the transcript holds when the Stop hook runs

A live `claude -p` run whose Stop hook copies the transcript, saved as a
record. It answers the one unknown the design rests on.

- Acceptance: the copy holds the `tool_use` entry of the turn's last tool
  call; each `tool_use` entry carries a timestamp; the record and its probe
  script are in `smith-ctx-claude/scripts/tests/records/` with a SHA-256 and
  a line in that folder's `README.md`.
- Verification: `shasum -a 256 -c` on the record.
- Dependencies: none. Size: small, 3 files.
- If the entry is missing, stop and report a blocker; tasks 3 and 4 do not
  start.

### Task 2: State script answers by the table

`ctx-reset-state.sh` takes `worked=0|1` with `stop` and records the write
time on `checkpoint-written`. The events `checkpoint-requested` and
`typed-prompt`, the state `asked`, the attempt marker and the
machine-message opening list go.

- Acceptance: one test case per table row; a sequence where a checkpoint
  written below the threshold with no later tool call is handed on at the
  first stop at the threshold; a sequence where the same checkpoint followed
  by a tool call is asked for again.
- Verification: `sh smith-ctx-claude/scripts/tests/ctx-reset-state.test.sh`,
  red before the script changes, green after.
- Dependencies: none. Size: small, 2 files.

### Task 3: The hook measures work done since the write

`enforce-clear.sh` reads from the transcript whether the session worked
since the write, as `spec.md` defines "worked", and passes the result with
the stop.

- Acceptance: transcript fixtures for "no tool call after the write", "a
  tool call after the write" and "transcript unreadable" give `worked=0`,
  `worked=1` and `worked=1`; a late machine message with no tool call does
  not change the answer.
- Verification:
  `sh smith-ctx-claude/scripts/tests/enforce-clear-state.test.sh`, red
  first.
- Dependencies: tasks 1 and 2. Size: small, 2 files plus fixtures.

### Task 4: The hook launches at most once

`continued` is recorded before `claude --bg`; an unrecognized launch output
is reported and never retried.

- Acceptance: two stops in a row in `checkpointed` at the threshold launch
  once; a launch whose output is not recognized leaves `continued` and
  reports `SMITH_CTX_DISPATCH_FAILED`; the restore flag is set aside only on
  a recognized launch.
- Verification:
  `sh smith-ctx-claude/scripts/tests/enforce-clear-state-dispatch.test.sh`,
  red first; `enforce-clear.test.sh` and `enforce-clear-dispatch.test.sh`
  pass with no assertion edited.
- Dependencies: task 3. Size: small, 2 files.

### Checkpoint: after tasks 1 to 4

- [x] `sh smith-ctx-claude/scripts/tests/run.sh` prints ALL PASS
- [x] Report to the owner before going on

### Task 5: Take out the typed-prompt wiring

- Acceptance: `git diff daf6c36 -- smith-ctx-claude/scripts/inject-plan.sh`
  is empty; `inject-plan-state.test.sh` and
  `fixtures/machine-message-prompts/` are set aside with `/usr/bin/trash`,
  which this plan's approval covers; no file names `typed-prompt`.
- Verification: the suite passes; a search for `typed-prompt` in the
  scripts finds it only in the test that asserts the event is refused.
- Dependencies: task 2. Size: small, 1 file and 3 set aside.

### Task 6: The checkpoint procedure sends only the start

- Acceptance: `smith-checkpoint/SKILL.md` holds no `checkpoint-requested`
  command; the start command stays before the audit and in the correction
  paragraph; `write-checkpoint-state.test.sh` pins the write from
  `checkpointing` and from `idle`.
- Verification: `sh smith-checkpoint/scripts/tests/run-all.sh` prints ALL
  PASS.
- Dependencies: task 2. Size: small, 2 files.

### Task 7: Documents match the code

- Acceptance: the Decisions section of `spec.md` carries the replaced
  decision with its date;
  its code table marks the three kept codes approved and no longer lists
  the three removed ones;
  `intent.md` has no open question; `smith-ctx-claude/SKILL.md` and
  `HOOKS.md` hold what the "Project structure" section of `spec.md` lists
  for each, and no sentence of either says what a stop does in a state.
- Verification: a blind reviewer checks the state table of `spec.md`
  against the code row by row and returns no mismatch; `grep` for the four
  state names finds no line in `smith-ctx-claude/SKILL.md`; a blind
  reviewer given `HOOKS.md` and the state table finds no sentence of
  `HOOKS.md` that repeats a row.
- Dependencies: tasks 2 to 6. Size: medium, 4 files.

### Checkpoint: after tasks 5 to 7

- [x] Both runners print ALL PASS
- [x] Report to the owner before going on

### Task 8: Full verification

- Acceptance: both runners pass after a rebase onto `origin/main`;
  a search of the scripts for the state `asked`, `checkpoint-requested`,
  `typed-prompt` and `SMITH_CTX_CHECKPOINT_SUPERSEDED` finds them only in
  the test that asserts they are refused; the leak scan of every added line has no hit and
  its control is caught.
- Dependencies: task 7. Size: small, no file.

### Task 9: `/smith-ship`

Runs only on the owner's instruction; it owns preflight, review, commit,
push and the pull request.

## Risks

- **The transcript may lag the Stop hook.** If the last tool call is not yet
  written when the hook runs, "worked" reads 0 for a session that worked.
  Task 1 measures this before anything is built on it.
- **Work chained to the write.** Work run in the same command after
  `write-checkpoint.sh` is one tool call and is not seen. A scan of 246
  recorded writes found 3 where a later tool call was sent in the same
  response as the write, which the transcript order now catches.
- **Bookkeeping after the write.** A procedure that calls a tool after
  `write-checkpoint.sh` makes its own checkpoint out of date. The checkpoint
  procedure ends on the write today; a scan of 245 recorded writes found 180
  with no later tool call before the stop.

## Proof

- One test per table row, the two sequences of task 2, and the fixtures of
  task 3.
- The live record of task 1.
- Both runners printing ALL PASS after the rebase.

## Open questions

None.

## Progress Log

### Iteration 1 (2026-11-22T22:20:00+09:00)

- Completed: tasks 1 to 6. Both runners printed ALL PASS after task 6.
- Task 1 ran in two session modes, five sessions each: background, the
  kind the automatic continuation runs in, and print. Records:
  `smith-ctx-claude/scripts/tests/records/stop-transcript-tool-calls.background.json`
  and `stop-transcript-tool-calls.print.json`.
- Table rows refined while writing the tests: a continuation stop in `idle`
  stays with the older path, so its notices are those of `daf6c36`; a
  checkpoint written with no recorded start is recorded from `idle`.
- A block in `idle` writes no state record, so a blocked session that has
  not started a checkpoint is served by the older path as before.

### Iteration 2 (2026-11-22T23:05:00+09:00)

- Completed: task 7. A blind reviewer matched all 17 rows that the table then held in
  `spec.md` to the state script and named a test for each.
- Fixed from that review, tests first, in `enforce-clear.sh`: a tool call
  in the same second as the write, a tool call with no timestamp, and a
  transcript that exists but cannot be opened now count as work.
- Both runners printed ALL PASS after these fixes.
- Corrected after the owner pointed out the deviation: a continuation stop
  at the threshold after work since the write was allowed silently; it now
  blocks and asks for a new checkpoint, as the decision says.
- Remaining in task 8: the rebase onto `origin/main` and the leak scan,
  which `/smith-ship` runs.

### Iteration 3 (2026-11-23T01:30:00+09:00)

- Completed: five review rounds under `/smith-ship`, each with CodeRabbit,
  `/code-review`, the `pr-review-toolkit` agents, a security review and
  `code-simplifier`, every reviewer new and blind.
- Changed by those rounds: "worked" is read from the transcript's order,
  with the call of `write-checkpoint.sh` dated before the second of the
  write time as the write; a checkpoint whose context level reads as
  unmeasured is announced with `SMITH_CTX_CONTEXT_UNMEASURED`; a failed
  launch of a checkpoint without a restore flag says to restore by label;
  `write-checkpoint.sh` warns when the state script is missing.
- Round 5 left one test-only change, an assertion that a stop with a
  missing transcript prints nothing; no code changed after round 5.
- Follow-up outside this change: `smith-mode-plan-claude/references/HOOKS.md`
  says every block reason starts with a code, while the block with dispatch
  off is uncoded; both statements predate this change.
- Next: one more review round on the final diff, then the commit message
  for the owner's yes, the rebase onto `origin/main`, preflight, push and
  pull request. The rule for `smith-sdlc/SKILL.md` about `intent.md`
  holding no technical detail goes in a branch of its own.

### Iteration 4 (2026-11-23T05:36:39+09:00)

- Review rounds 6 and 7. Round 6 removed an unused helper from
  `smith-ctx-claude/scripts/tests/ctx-reset-state.test.sh`. Round 7 found
  that a sentence of `smith-ctx-claude/SKILL.md` contradicted the row
  "`checkpointed`, stop, worked, high" of the state table.
- Reconciled on the owner's instruction: the state table of `spec.md` is
  the only description of what happens in a state. This plan's summary
  table went; `smith-ctx-claude/SKILL.md` and
  `smith-mode-plan-claude/references/HOOKS.md` lost the sentences that
  repeated rows; "Project structure" in `spec.md` now lists what each of
  the two documents holds; task 7's acceptance and verification follow it.
- A command that only names `write-checkpoint.sh`, sent while the write
  runs, is read as the call that wrote the checkpoint and hides a tool call
  before it; reproduced in round 7. The owner chose on 2026-11-23 to leave
  the code and record it as a limit in `spec.md`.
- Review round 8 then found the same facts stated in several documents,
  three of them stale. Reconciled again: this plan's Design decisions and
  Overview refer to `spec.md`; `HOOKS.md`, `smith-ctx-claude/SKILL.md` and
  `smith-ctx-claude/scripts/tests/records/README.md` lost what `spec.md`
  already says. The owner asked on 2026-11-23 for no further review round.
- Next: the commit message for the owner's yes.
