# Spec: Checkpoint audit that never ends a turn, and one continuation per checkpoint

Source: `intent.md` in this directory. Status: revision 4, approved by the
owner as a whole on 2026-11-20; the Open questions are not covered by that
approval. The Stop hook states follow `plan.md` in this directory, whose
decisions the owner made on 2026-11-22. Revision 4 takes the worker
isolation from `smith-ctx-claude/references/process-worker-runtime/spec.md` on branch `feat/worker-job-runtime`, whose direction the owner
adopted on 2026-11-20. That spec's job runtime, `worker-job.sh` with detached
jobs, heartbeats, waiter leases and bounded joins, is deferred until a
measured need.

## Objective

Users are the main thread of a Claude Code session that reaches the context
threshold, and the owner who reads its outcome. Success:

- The audit of `/smith-checkpoint` runs every round to its end without the
  main thread ending a turn, so no Stop hook fires inside the procedure.
- Each blinded role is kept from what its definition names by the tools it is
  given, not only by its prompt.
- A checkpoint that no tool call has followed is continued by exactly one
  background session, and the earlier session is told so.

## Capability map

| Module id | Responsibility | Depends on | Owner |
|---|---|---|---|
| `role-catalog` | the one table of every blinded role: given, kept from, bias prevented, enforcement, tool allowlist, model | none | smith-vet panel thread |
| `process-worker-runtime` | isolated workers whose folder is their boundary; jobs with a deadline, a heartbeat and a waiter lease, joined in bounded calls, are deferred until a measured need; spec `smith-ctx-claude/references/process-worker-runtime/spec.md` on branch `feat/worker-job-runtime` | `role-catalog` | this thread |
| `worker-pool-scheduler` | the worker-pool rule adopted on 2026-11-09, single batch first; more only after a measured miss | `process-worker-runtime` | this thread |
| `checkpoint-audit` | first consumer, measured | `worker-pool-scheduler` | this thread |
| `vet-panel` | lenses and aggregator on the same runtime | `worker-pool-scheduler` | smith-vet panel thread |
| `eval-grader`, `review-adapters` | rows of the table only | `role-catalog` | smith-vet panel thread |
| `stop-hook-continuation` | one continuation per checkpoint; the `checkpointing` state for a stop during the audit | none | this thread |

Build order: `role-catalog`, then `process-worker-runtime`, then
`checkpoint-audit`, then `vet-panel`, then the rest. The worker-pool rule is
`~/basic-memory/main/research/agent-scheduling-2026-11-09/candidate-generic-worker-pool.md.txt`.

## Why the turn must not end

Two designs that let the main thread end turns while background checkers ran
were reviewed adversarially and failed: a Stop hook cannot tell a waiting
session from a stalled one. Its documented signal, `background_tasks` in the
Stop input (https://code.claude.com/docs/en/hooks#stop), errs both ways in
open upstream issues: empty while a notification is queued
(https://github.com/anthropics/claude-code/issues/102617), and `running`
for idle teammates, watchers and subagents that dropped out
(https://github.com/anthropics/claude-code/issues/109427,
https://github.com/anthropics/claude-code/issues/98816,
https://github.com/anthropics/claude-code/issues/102765). Telling slow from
dead without a time bound is impossible in an asynchronous system
(https://doi.org/10.1145/3149.214121). The Stop hook therefore reads neither
signal: a stop during the audit finds the session in the Stop hook state
`checkpointing` below, entered when the audit starts, and is allowed; neither
a heartbeat nor `background_tasks` is read. Running the audit as a job of
`smith-ctx-claude/scripts/worker-job.sh` that the main thread joins in
bounded calls, each below the Bash tool's timeout, with the checkers as child
processes of the job, is deferred until a measured need. One call holding the whole round was rejected: real
rounds ran up to about twenty-one minutes,
`~/basic-memory/main/research/audit-round-durations-2026-11-20/`, beyond the
ten-minute default ceiling, and raising the ceiling widens it for every
command of a profile.

## Roles and blinding

The labels single, double and triple blind are not used; each role is defined
by what it is given, what it is kept from, which bias that prevents, and the
mechanism that enforces it.

| Role | Given | Kept from | Bias prevented | Enforced by |
|---|---|---|---|---|
| Author, the main thread | the conversation; the reports only after its expected answers are written | the reports before the expected-answers file exists | fitting the expectations to the returns | the runner refuses to start a round without that file |
| VERIFIER | copies of the body, the plan, the worktree files they name, the skill files, and the output of `git log`, `git diff «base ref»...HEAD`, `git status` and `gh pr view --json state,headRefName,baseRefName,mergedAt`, computed by the runner | conversation, transcripts, memories, task output, review threads, the other checker, earlier rounds, the expected answers | anchoring on the author's judgments | its own folder and `claude -p` process with `Read` only, per `smith-ctx-claude/references/process-worker-runtime/spec.md` on branch `feat/worker-job-runtime` |
| COLD READER | copies of the body, the plan and the files they name by path | everything the VERIFIER is kept from, plus the worktree and every `git` output | knowledge a resuming session would not have | the same, with fewer files copied in |
| AGGREGATOR, draft | copies of both reports, the expected-answers file, the body and the plan | conversation and the author's reasoning | the author grading its own body while reconciling | the same; returns a fix list the author only applies |

A claim the copied files cannot settle, such as the history of one line, is
reported as not checkable; a measured run of such misses decides which
further output the runner copies in.

The AGGREGATOR follows the owner's comparison of an aggregating subagent to
"triple blind" for data analysis, recorded for smith-vet in
`~/.claude/plans/i-usually-ask-for-cached-pearl.md:1519`;
applying it to the checkpoint is new and needs approval.

## Audit runner

`smith-checkpoint/scripts/run-audit-round.sh «body» «plan» «expected» «worktree» «base ref» «record dir» «deadline»`,
not written yet. Starting it with `worker-job.sh start` and joining it with
`worker-job.sh join «folder» --max «seconds»` is deferred with the job
runtime; until the runner exists, SKILL step 6 item 5 spawns the two checkers
as subagents.

- Refuses to run unless the expected-answers file exists and is not empty.
- Copies each role's inputs into a fresh folder per role, then starts the
  VERIFIER and the COLD READER as isolated workers in parallel, waits for
  both, and starts the AGGREGATOR only when the time left before «deadline»
  allows it.
- Gives each worker a `timeout` of the time left before «deadline», minus a
  margin, so the deadline set by the main thread holds for every stage.
- A worker that exits nonzero or runs out of time voids the round, as SKILL
  step 6 item 5 already rules; the runner says which. A read outside a
  role's set cannot happen, so the rule voiding a round for one is dropped.
- Traps TERM, ends its own workers and exits. A job supervisor that ends the
  runner's process group on cancellation, deadline or an expired lease is
  deferred with the job runtime.
- Each round's prompts, reports and copied inputs are written under «record
  dir» in `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/checkpoint-backups/«label»/`,
  with a SHA-256 for each file.
- Outside Claude Code, or when `claude` is missing, SKILL keeps its inline
  path and the body records "double-blind audit not run: «reason»".

## Stop hook states

| State | Event | Condition | Action | Outcome code | Next state |
|---|---|---|---|---|---|
| `idle` | stop | `stop_hook_active` false, below the threshold | allow | none | `idle` |
| `idle` | stop | `stop_hook_active` false, high, dispatch on | block; nothing recorded | `SMITH_CTX_AUTO_RESET_BLOCKED` | `idle` |
| `idle` | stop | `stop_hook_active` false, high, dispatch off | block with an uncoded reason that gives the context level and ends "Checkpoint this session, then /clear."; nothing recorded | none | `idle` |
| `idle` | stop | `stop_hook_active` true | unspecified; nothing recorded; the older path of `enforce-clear.sh` decides | none | `idle` |
| `idle`, `checkpointed` | checkpoint started | none | record; from `checkpointed` the earlier label, restore flag and write time are dropped | none | `checkpointing` |
| `checkpointing` | checkpoint started | none | record; nothing changes | none | `checkpointing` |
| `checkpointing` | stop | any | allow | `SMITH_CTX_CHECKPOINT_IN_PROGRESS` | `checkpointing` |
| `idle`, `checkpointing`, `checkpointed` | checkpoint written | none | record label, restore flag and write time, replacing earlier ones | none | `checkpointed` |
| `checkpointed` | stop | worked, high, whichever value `stop_hook_active` has | the record becomes `state=idle`, without label, restore flag or write time; block, and the reason adds that a tool call followed the earlier checkpoint and that the session is to stop without another tool call after the new one | `SMITH_CTX_AUTO_RESET_BLOCKED` with dispatch on, none with dispatch off | `idle` |
| `checkpointed` | stop | worked, below the threshold | the record becomes `state=idle` as above; the stop is then answered by the `idle` rows | as the `idle` row gives | `idle` |
| `checkpointed` | stop | not worked, below the threshold | allow; when the context level could not be measured, which reads as 0%, the hook says that no background session was started and names the label and `/clear` | none, or `SMITH_CTX_CONTEXT_UNMEASURED` when unmeasured | `checkpointed` |
| `checkpointed` | stop | not worked, high, dispatch on, whichever value `stop_hook_active` has | record `continued`, then answer `dispatch`; the hook then runs `claude --bg` and reports the launch | none | `continued` |
| `checkpointed` | stop | not worked, high, dispatch off | allow, naming the label and `/clear`; when no restore flag was recorded, naming the label and saying that no restore flag was written | `SMITH_CTX_CHECKPOINT_WRITTEN` | `checkpointed` |
| `continued` | launch recognized | no launch report recorded | record the new session; the hook blocks once naming it, even when the state cannot record it, and renames the restore flag by `mv` to `.consumed-memory-restore-*` | `SMITH_CTX_CONTINUED` | `continued` |
| `continued` | launch output not recognized | no launch report recorded | record; allow; the restore flag stays; never retried | `SMITH_CTX_DISPATCH_FAILED` | `continued` |
| `continued` | stop | any | allow, naming the new session when one is recorded, otherwise saying that the launch is not tried again | `SMITH_CTX_ALREADY_CONTINUED` | `continued` |
| `continued` | checkpoint started, checkpoint written, a second launch report | none | unspecified; nothing changes | none | `continued` |
| `idle`, `checkpointing`, `checkpointed` | launch recognized, launch output not recognized | none | unspecified; nothing changes | none | unchanged |

The state lives in `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plans/.ctx-reset-state-«session id»`,
one file per session id, and `ctx-reset-state.sh` answers each event with an
action, a code and the next state. Its events are
`stop high=0|1 active=0|1 dispatch=on|off worked=0|1`, `checkpoint-started`,
`checkpoint-written label=… flag=…`, `dispatched successor=…` for a
recognized launch, `dispatch-unrecognized`, and the read-only `known`,
`show` and `show-field`. A stop with `stop_hook_active` true is sent
like any other stop; "high" means the context is at or above the threshold,
whichever value `stop_hook_active` has. SessionStart `clear` sends nothing:
`/clear` starts a new session id, which has no record and is therefore
`idle`, and the earlier id's record is kept, not swept. A session has no
record until its first `checkpoint-started` or `checkpoint-written`: a block
in `idle` writes none.

"Worked" is read from the transcript, in its order. The state script
records the write time as `written_at`, to the second, when
`checkpoint-written` arrives. `enforce-clear.sh` takes the last assistant
`tool_use` block whose command names `write-checkpoint.sh` and whose
timestamp is before that second as the call that wrote the checkpoint;
every `tool_use` block that comes after it in the transcript counts as
work, whatever its timestamp, so a call sent in the same response as the
write counts. A call dated in or after the second of the write time always counts,
even one that names `write-checkpoint.sh`: of 238 recorded writes the
shortest took 8.9 seconds from its call to its result, so the call that
wrote a checkpoint is never dated in the second the write finished. When no such call is found, a `tool_use` block counts when
its timestamp is in or after the second of the write time. A `tool_use`
entry with no timestamp counts too. Any tool call counts, with no list of
exempt tools. Limits: work chained in the same command after
`write-checkpoint.sh` is one tool call and is not seen; a command that only
names `write-checkpoint.sh`, sent while the write runs and so dated before
the write time, is read as the call that wrote the checkpoint, and a tool
call before it is not seen; and only the file named by `transcript_path` is
read. `enforce-clear.sh` computes
it only when the state is `checkpointed` and sends `worked=0` otherwise; a
write time that is missing or cannot be parsed, a transcript that cannot be
read, and a stop sent without `worked` all count as worked. Messages after the
write that carry no tool call do not make a checkpoint out of date, whoever
sent them. The transcript's timestamps are in Coordinated Universal Time
and the write time is local with an offset; both are compared as instants.

At most one launch follows a checkpoint: the state becomes `continued`
before `claude --bg` runs, so a launch that never reports leaves the session
`continued`, and every later stop is allowed and says that the launch is not
tried again.

An event of the table in a state that no row names answers `unspecified`,
as do a stop without a session id and a missing or failing state script; an
event name the script does not know is a usage error, which the hook reads
the same way. A state write that fails
prints `state write failed: «file»` on stderr, exits non-zero and gives no
answer, which the hook reads as `unspecified`. For a stop answered `unspecified`, `enforce-clear.sh` still runs its
older path, which compares the times of the `.pending-reload-«key»` and
`.pending-memory-restore-*` files: a stop at the threshold blocks and writes
the `.pending-reload` file, and a continuation stop in a background session
may dispatch from a restore flag newer than that file. That older dispatch
runs only for a session the state holds no record of: a stop without a
session id, or a session id with no `.ctx-reset-state-«session id»` file,
which the hook learns by sending the read-only event `known`. A session with
a record never reaches it, so a checkpoint that a tool call followed, or
whose launch failed, is not dispatched later from its restore flag. A
session blocked at the threshold that has not yet started a checkpoint has
no record, so its continuation stops get the older path's notices as
before this change: `SMITH_CTX_NO_CHECKPOINT`,
`SMITH_CTX_CONTEXT_NO_LONGER_CRITICAL` and `SMITH_CTX_CONTEXT_UNMEASURED`.
The older path is kept and not changed: code not directly related to this
change is not removed, as `plan.md` in this directory records.

Two stops are allowed before the state is asked, and change no state; both
are stops with `stop_hook_active` false. One is a stop that finds the
ExitPlanMode exit marker of `on-plan-exit.sh` naming this session; the other
is a stop whose transcript path is empty or names no file. A continuation
stop whose transcript is missing or unreadable is answered `unspecified`
without asking the state, and a session with a state record then stops
silently. Known limit: in
`checkpointed` at the threshold with dispatch on, a turn that ends with this
session's exit marker does not hand the checkpoint on; a later stop at or
above the threshold hands it on, unless a tool call followed the write.

Every `name=value` argument must hold no newline; one that does is a usage
error, exit 64, and nothing is written.

The `SMITH_CTX_CONTINUED` block tells the model that the work moved to the
named session and to end the turn without further work. Faults keep the
existing codes and checks of the older path: `SMITH_CTX_TRANSCRIPT_UNREADABLE`,
`SMITH_CTX_CONTEXT_UNMEASURED`, `SMITH_CTX_TRANSCRIPT_FORMAT_UNKNOWN` and
`SMITH_CTX_PENDING_RELOAD_MISSING`.

## Outcome codes

Each code is a type, matched by the code and never by its wording, written in
full with its module prefix, as `[«code»]` at the start of one channel, and
written as a literal where it is emitted. Prefixes: `SMITH_CTX_` for the context hooks of `smith-ctx-claude`,
`SMITH_JOB_` for `worker-job.sh`, `SMITH_CHECKPOINT_` for the audit runner of
`smith-checkpoint`; the owner asked on 2026-11-20 that every type constant
carry such a prefix.

| Code | Kind | Channel | Status |
|---|---|---|---|
| `SMITH_CTX_AUTO_RESET_BLOCKED` | request | block reason | kept |
| `SMITH_CTX_NO_CHECKPOINT` | notice | `systemMessage` | kept |
| `SMITH_CTX_CONTINUED` | outcome | block reason | kept; the older path still sends it as a `systemMessage` |
| `SMITH_CTX_DISPATCH_FAILED` | error | `systemMessage` | kept; no retry |
| `SMITH_CTX_CONTEXT_NO_LONGER_CRITICAL` | notice | `systemMessage` | kept |
| `SMITH_CTX_CONTEXT_UNMEASURED` | error | `systemMessage` | kept |
| `SMITH_CTX_TRANSCRIPT_UNREADABLE` | error | `systemMessage` | kept |
| `SMITH_CTX_TRANSCRIPT_FORMAT_UNKNOWN` | error | `systemMessage` | kept |
| `SMITH_CTX_PENDING_RELOAD_MISSING` | error | `systemMessage` | kept |
| `SMITH_CTX_CHECKPOINT_WRITTEN` | notice | `systemMessage` | new, approved |
| `SMITH_CTX_ALREADY_CONTINUED` | notice | `systemMessage` | new, approved |
| `SMITH_CTX_CHECKPOINT_IN_PROGRESS` | notice | `systemMessage` | new, approved |
| `SMITH_JOB_` codes of `smith-ctx-claude/references/process-worker-runtime/spec.md` on branch `feat/worker-job-runtime` | outcome or error | `worker-job.sh join` output | new, approved; deferred with the job runtime |

## Decisions

- **A checkpoint is out of date when a tool call follows its write.**
  "Stop hook states" defines what counts. A wrong answer costs one extra
  checkpoint and, outside the limits listed there, never hands on an
  incomplete one. Rejected, each an inference where the tool
  calls are a measurement:
  deciding by who asked for the checkpoint;
  deciding by the context level at the write;
  deciding by who sent the next message, as the replaced decision did.
  Evidence: a scan on 2026-11-22 of 245 recorded checkpoint writes found 180
  with no later tool call before the stop and 54 whose last write before the
  stop was followed by tool calls, with no typed prompt in between; and in
  ten live sessions of that day the transcript a Stop hook reads held the
  turn's last tool call with a timestamp, records
  `stop-transcript-tool-calls.background.json` and
  `stop-transcript-tool-calls.print.json` in
  `smith-ctx-claude/scripts/tests/records/`. Approved by the owner on
  2026-11-22; it replaces the decision of 2026-11-19 that only a typed
  prompt supersedes a checkpoint.
- **One table defines every blinded role.** The table of who is given what,
  kept from what, which bias that prevents and what enforces it covers every
  blinded role, whatever runs it: the checkpoint checkers, the smith-vet
  lenses and aggregator, the behaviour-eval grader and the reviewers. It lives
  once in `smith-subagents/SKILL.md`; this spec's role table becomes rows of
  it. Rejected: a table of subagents only, which leaves processes and the
  grader with a second definition. Approved by the owner on 2026-11-19.
- **One worker architecture, split by owner.** The checkpoint audit, the
  smith-vet panel, the behaviour evals and the reviews share one scheduling,
  dispatching and worker-management architecture. The smith-vet panel thread
  owns `role-catalog` in `smith-subagents/SKILL.md`, merged with its queued
  scheduling and batch rule, and the `vet-panel` consumer, both after its
  stack of branches, shipped through `/smith-ship`, merges; this thread owns `process-worker-runtime`,
  `worker-pool-scheduler`, `checkpoint-audit` and `stop-hook-continuation`.
  "Individual subagents" on line 19 of `smith-vet/SKILL.md`, which lives
  on branch `feat/vet-command`, means independent, so
  lenses may run as separate processes. Conditions: this thread edits no
  file under `smith-subagents/`, and not the VERIFIER line of
  `smith-checkpoint/SKILL.md`, before that merge, after which the line
  names `@smith-verification`; leaving `smith-vet/` alone was agreed in
  messages between the sessions, not in the plan record; every worker names its model per role; a
  runtime extracted from `smith-skills/scripts/behaviour-eval.mjs:110-130`
  takes the environment as an explicit parameter, leaves the `run.children`
  registry to each consumer, keeps the behaviour-eval tests unchanged and
  green, and is sequenced with that script's open review follow-ups. Approved
  by the owner on 2026-11-20, recorded in
  `~/.claude/plans/i-usually-ask-for-cached-pearl.md:1781`.
- **No tracked file runs `rm`.** Scratch is created with `mktemp`,
  `mktemp -d` or `fs.mkdtempSync` under `$TMPDIR` and left to the operating
  system; a test that needs a clean state takes a fresh `mktemp -d` folder or
  moves a file away with `set_aside` from `smith-ctx-claude/scripts/tests/lib/set-aside.sh`;
  a durable erase moves to the Trash with `/usr/bin/trash`. A consumed restore
  flag is renamed by `mv` to `.consumed-memory-restore-*`, outside the
  `.pending-memory-restore-*` glob that `on-session-clear.sh` scans. Older
  `rm` lines remain, for example in the older path of `enforce-clear.sh` and
  in `inject-plan.sh`. Owner, 2026-11-20, as relayed by session `followup
  smith review scope`, not yet read here first-hand; whether in-code calls
  such as `fs.rmSync` are covered is open.
- **Every round of the audit completes before the handover.** Owner,
  2026-11-16: "3 rounds must be completed and then follow the instructions to
  handover to a new session automatically", transcript `c7933c88`, line
  7319.
- **No checker reads a session transcript**, since a transcript mixes
  evidence with judgments. Owner, 2026-11-05: "i suspect they both are
  illogical", transcript `1918fb43`, line 1138, and the rejected alternative
  of giving the VERIFIER the raw transcript, line 1158.

- **Outcome codes.** Of the six codes this branch adds, three stay and are
  approved: `SMITH_CTX_CHECKPOINT_IN_PROGRESS`,
  `SMITH_CTX_ALREADY_CONTINUED` and `SMITH_CTX_CHECKPOINT_WRITTEN`. Three
  go, since no row emits them: `SMITH_CTX_CHECKPOINT_SUPERSEDED`,
  `SMITH_CTX_STATE_MISSING` and `SMITH_CHECKPOINT_AUDIT_ROUND_VOID`. Codes
  that exist at `daf6c36` are untouched. Decided by the owner on
  2026-11-22.

## Project structure

- `smith-ctx-claude/scripts/ctx-reset-state.sh`: the states above, the
  write time and the `unspecified` answer
- `smith-ctx-claude/scripts/enforce-clear.sh`: measures whether the session
  worked since the write, sends each stop it does not settle first, decides allow, block or dispatch
  from the answer, reports the launch, and runs the older path on
  `unspecified`
- `smith-checkpoint/SKILL.md` Procedure: sends `checkpoint-started` before
  the scripted audit of step 6 item 4, and again when a user correction
  re-runs the audit
- `smith-checkpoint/scripts/write-checkpoint.sh`, function
  `record_checkpoint_in_state`: sends `checkpoint-written` with the label and
  the restore flag; the state script records the write time; a failing state
  script is reported and does not fail the checkpoint
- `smith-ctx-claude/scripts/inject-plan.sh` and
  `smith-ctx-claude/scripts/on-session-clear.sh` send nothing
- Tests: `smith-ctx-claude/scripts/tests/ctx-reset-state.test.sh`,
  `enforce-clear-state.test.sh` and `enforce-clear-state-dispatch.test.sh`
  in the same folder, and
  `smith-checkpoint/scripts/tests/write-checkpoint-state.test.sh`
- "Stop hook states" in this spec is the only place that says what a stop
  or another event does in a given state. No other document says it again.
- `smith-ctx-claude/SKILL.md`, read by the model in a session, holds: the
  action for each message the model must act on, namely the block reasons
  `SMITH_CTX_AUTO_RESET_BLOCKED` and `SMITH_CTX_CONTINUED` and the uncoded
  block reason of dispatch off; when to tell the user to `/clear`; and one
  reference to "Stop hook states". It names no state.
- `smith-mode-plan-claude/references/HOOKS.md`, read by a person who
  installs or debugs the hook, holds: the hook's input fields; the files it
  writes and renames; the launch command, the new session's name and the
  limits; the older path's dispatch; and one reference to "Stop hook
  states". It says of no state what a stop does in it.
- Deferred: `smith-checkpoint/scripts/run-audit-round.sh` with role prompts
  beside it and `smith-checkpoint/scripts/tests/run-audit-round.test.sh`
  with a fake `claude`, after which step 6 item 5 of
  `smith-checkpoint/SKILL.md` runs the runner instead of the two subagent
  spawns; and the job runtime, `smith-ctx-claude/scripts/worker-job.sh` with
  `smith-ctx-claude/scripts/tests/worker-job.test.sh`

## Testing strategy

- Tests first, run red, not edited by the implementation; a later change
  needs the owner's yes.
- One test per state-table row and per fault, matching codes only.
- Runner tests with a fake `claude`: both checkers run in parallel; the
  AGGREGATOR starts only after both and only with time left; a missing
  expected file refuses; a nonzero or overdue checker voids the round; each
  role's folder holds exactly its inputs; TERM leaves no child; every record
  carries a SHA-256.
- Job runtime tests, `smith-ctx-claude/scripts/tests/worker-job.test.sh`,
  are deferred with the job runtime.
- Transcript replays, not written yet: `17b44d1f` never blocks inside the
  audit and dispatches once; `08061499` dispatches on the stop after its
  write.
- Live probes, each a script with a saved record in
  `smith-ctx-claude/scripts/tests/records/`, listed in its `README.md`:
  done for the personal profile; still open: one real round's duration under
  the runner, and the other profiles.
  `smith-ctx-claude/scripts/tests/stop-transcript-tool-calls.live-eval.mjs`,
  records `stop-transcript-tool-calls.background.json` and
  `stop-transcript-tool-calls.print.json`, five sessions each.

## Boundaries

- Always: tests first; codes from the one table; records durable with SHA-256.
- Ask first: an edit to an existing test assertion; any profile's
  `settings.json`; the AGGREGATOR role; any commit, push or pull request.
- Never: a transcript as checker input; an MCP server in a checker; a client
  or employer term in this public repository.

## Success criteria

- Every state-table, fault and runner test passes, and both suites pass.
- A live checkpoint at the threshold finishes all its rounds inside tool calls,
  with no Stop hook record between `new-body-file.sh` and
  `write-checkpoint.sh` other than `SMITH_CTX_CHECKPOINT_IN_PROGRESS`, and starts exactly
  one background session.

## Open questions

- Must `claude -p` worker processes appear in the spawn ledger that
  `/smith-preflight` reads through
  `smith-ctx-claude/scripts/spawn-ledger-report.mjs`? They bypass the Agent
  tool, so today they would not.
- Does the AGGREGATOR join the audit now, or after a measured miss of the
  author's own reconciliation?
- Which model runs each role? The owner's draft rule, not yet approved, puts a
  lens or reviewer on the mid model and the largest on a skeptic:
  `~/.claude/plans/i-usually-ask-for-cached-pearl.md:676`.
