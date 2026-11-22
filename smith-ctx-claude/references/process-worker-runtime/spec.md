# Spec: process worker runtime

Status: revision 1, approved by the owner as a whole on 2026-11-20. Module
`process-worker-runtime` of the capability map in
`../auto-context-reset/spec.md`, owned by this thread.

## Objective

One runtime for every blinded worker, whoever consumes it: the checkpoint
audit, the smith-vet lenses and aggregator, the behaviour-eval grader and the
reviewers. Success:

- A worker sees only the files of its role, by construction, never by a
  prompt or a self-report.
- A job of any length runs under the main thread's tool calls without one
  call reaching the Bash timeout and without the turn ending.
- An interrupt, a deadline, a crash of the runtime or a session that stops
  waiting leaves no worker running.

## Isolation: the folder is the boundary

A worker is `claude -p` started in a fresh `mktemp -d` folder that holds
copies of its role's inputs and nothing else, with
`--setting-sources "" --strict-mcp-config --no-session-persistence
--tools Read --model «role model»`, `CLAUDE_JOB_DIR` unset,
`CTX_AUTO_RESET_DISPATCH=0`, and `--` before the prompt. Roles differ only in
the files copied in; the table of roles is data. Evidence, all in
`../../scripts/tests/records/`, described in its `README.md`:

- Reads inside the working folder need no approval and others are refused
  once the user settings are left out: `cold-reader-no-git.personal.json`;
  "No, within the working directory and additional directories",
  https://code.claude.com/docs/en/permissions, "Permission system".
- Loaded user settings admit unnamed reads through their allow rules and
  auto mode: the same record, variants without `--setting-sources ""`.
- A symlink to a file or folder outside the working folder is refused, so
  inputs are copied, never linked: `worker-folder-symlink.personal.json`.
- A Bash prefix rule cannot fence `git`: `git -c alias.«name»=!cat «file»`
  ran under `Bash(git -C «repo» *)`: `verifier-bash-scope.personal.json`.
  No role gets Bash; output a role needs, such as `git log`, is computed by
  the consumer and copied in as a file.
- Without `--tools`, a worker gets non-built-in tools such as
  `SendMessage`, `Workflow` and `Skill`: `cold-reader-no-git.personal.json`.
- The flags authenticate: `worker-isolation-auth.personal.json`.

## Jobs: bounded joins

`smith-ctx-claude/scripts/worker-job.sh`:

- `start --deadline «seconds» -- «command»…` makes a job folder with
  `mktemp -d`, starts a supervisor in a process group of its own, which runs
  the command in another process group of its own with the job folder as its
  working directory, and prints the folder. It exits 64 for a usage error,
  which includes a tunable that is not a whole number, and 70 when the job
  folder or the supervisor cannot be started.
- `join «folder» --max «seconds»` waits at most that long and prints one of
  the codes below on its first line; exit status 0 for `SMITH_JOB_DONE`, 3 for
  `SMITH_JOB_RUNNING`, 2 for every other code, 64 for a usage error.
- The consumer calls `join` again after `SMITH_JOB_RUNNING`, with `--max` below the
  Bash tool's timeout, so no call reaches the point where Claude Code moves a
  command to the background: "When a command reaches its timeout before it
  finishes, Claude Code automatically moves it to the background instead of
  stopping it", https://code.claude.com/docs/en/interactive-mode;
  reproduced in `bash-timeout-ceiling.personal.json`, variant
  `no-ceiling-change`.
- The supervisor writes a heartbeat; every `join` renews a waiter lease. The
  supervisor ends the command's whole process group at the job's deadline,
  when the lease expires, or when `join` asks for cancellation; `join`
  ends it when the supervisor is gone.
- `join` traps TERM, INT and HUP and cancels the job. Pressing Escape in an
  interactive session during `join` ended the job as `SMITH_JOB_CANCELLED`,
  with its runner, both `claude -p` workers and their tool processes; the
  runner received TERM, and the record does not show which signal `join`
  received:
  `foreground-runner-escape.personal.json`, variant
  `worker-job-join-of-runner-with-isolated-claude-workers`.
- A job outlives the call that started it and the session as well, which is
  why the lease exists: `detached-job-survives-call.personal.json`.

Tunables, environment only: `SMITH_JOB_HEARTBEAT_SECONDS`, default 5;
`SMITH_JOB_LEASE_SECONDS`, default 600; `SMITH_JOB_GRACE_SECONDS`, default
10, the wait between TERM and KILL to a process group. `start` reads them
and stores them in the job folder, where the supervisor and every `join`
read them, so a later call with a different environment cannot change a
running job's timing.

Rejected: raising `BASH_MAX_TIMEOUT_MS`. It works,
`bash-timeout-ceiling.personal.json` and
`bash-ceiling-env-visible.personal.json`, but it widens the limit of every
command in every session of a profile, so one stalled command can hold a
turn for the whole ceiling, and it needs an edit to each profile's
`settings.json`.

Patterns followed: deadline propagation and a check of the time left at each
stage, chapter "Addressing Cascading Failures" of Google's book Site
Reliability Engineering,
https://sre.google/sre-book/addressing-cascading-failures/; cancellation that
reaches every derived context, https://pkg.go.dev/context; children that
never outlive their scope, https://vorpus.org/blog/notes-on-structured-concurrency-or-go-statement-considered-harmful/;
leases, Gray and Cheriton 1989,
http://web.stanford.edu/class/cs240/readings/89-leases.pdf; a
heartbeat for long work, https://docs.temporal.io/encyclopedia/detecting-activity-failures.
Saved copies: `~/basic-memory/main/research/deadline-propagation-2026-11-20/`
and `~/basic-memory/main/research/scheduling-gaps-2026-11-19/`.

## Outcome codes

Matched by code, never by wording, on the first line of `join` output. Names
approved by the owner on 2026-11-20, with the `SMITH_JOB_` prefix the owner
chose.

| Code | Meaning |
|---|---|
| `SMITH_JOB_DONE` | the command exited 0 |
| `SMITH_JOB_RUNNING` | the join reached `--max`; join again |
| `SMITH_JOB_COMMAND_FAILED` | the command exited nonzero; `exit-status` holds the status |
| `SMITH_JOB_DEADLINE_EXCEEDED` | the job's deadline passed and the command was ended |
| `SMITH_JOB_WAITER_LEASE_EXPIRED` | nobody joined within the lease and the command was ended |
| `SMITH_JOB_CANCELLED` | a join was interrupted, or the supervisor itself was signalled, and the command was ended |
| `SMITH_JOB_SUPERVISOR_LOST` | the supervisor died before the command's exit status was recorded; the join ended the command |

## Durations

Real checkpoint audit rounds in the smith transcripts took a median of about
four minutes, a ninetieth percentile of about seven, and up to about
twenty-one: `~/basic-memory/main/research/audit-round-durations-2026-11-20/`.
A round therefore needs several joins at times, and its deadline is the
consumer's choice.

## Testing

- `../../scripts/tests/worker-job.test.sh`, in `run-all.sh`: usage errors;
  `SMITH_JOB_DONE`; `SMITH_JOB_COMMAND_FAILED` with the status; a bounded join returning
  `SMITH_JOB_RUNNING` within its bound and a later join seeing `SMITH_JOB_DONE`; the deadline,
  the lease, a cancelling TERM and a lost supervisor, each ending the
  command's child process. A manual run with the group kill disabled
  failed it; that run is not recorded.
- Live probes in `../../scripts/tests/`, recorded with SHA-256 in
  `records/SHA256SUMS`, opt-in through `SMITH_LIVE_CONTEXT_RESET_EVAL=1`.

## Open

- The consumer side: `run-audit-round.sh` and the copy of each role's inputs
  into its folder, in `../auto-context-reset/spec.md`.
- Whether `claude -p` workers appear in the spawn ledger that
  `/smith-preflight` reads.
- The model per role, owned with the role table by the smith-vet panel thread.
- Only the personal profile and haiku were probed, on Claude Code 2.1.328,
  except `foreground-runner-escape.personal.json`, recorded on 2.1.329.
