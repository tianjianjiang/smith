---
name: smith-automation
description: Claude Code scheduling primitives — /loop (interval, dynamic, bare), CronCreate/List/Delete, ScheduleWakeup, Monitor, and /schedule (Routines), with a decision matrix and provider/session-scope caveats. Use when setting up a recurring or scheduled task, polling for external state, self-pacing iterations, or the user mentions /loop, /schedule, cron, ScheduleWakeup, or Monitor.
---

# Claude Code Scheduling & Automation

<metadata>

- **Scope**: `/loop` (three forms), the underlying session-scoped `Cron*` tools, `ScheduleWakeup` (Claude-internal in dynamic `/loop`), `Monitor` (live event stream), and `/schedule` (Routines on claude.ai)
- **Load if**: The user invokes `/loop` or `/schedule`, OR the agent needs to poll for a state change, watch a long-running process, set a one-time reminder, or wait for external work the harness cannot notify about
- **Prerequisites**: `@smith-ctx-claude/SKILL.md` (session model)
- **Authoritative sources**: https://code.claude.com/docs/en/scheduled-tasks, https://code.claude.com/docs/en/tools-reference (Monitor + ScheduleWakeup); https://code.claude.com/docs/en/routines (verified 2026-05-21)

</metadata>

## CRITICAL: Primitive Selection (Primacy Zone)

<forbidden>

- NEVER use a Bash `sleep` loop to poll for state. It holds the turn open, blocks tool calls, burns context, and gives the model no chance to react between checks. Use `Monitor` for event streams, `/loop` for paced polling, or just wait when the harness is already tracking the work.
- NEVER add a `/loop` on top of harness-tracked work. When `Bash(run_in_background: true)` or a subagent finishes, the harness re-invokes the agent automatically — polling is wasted.
- NEVER conflate `/loop` and `/schedule`. `/loop` is session-scoped (lives in this conversation; dies on new session, restored on `--resume`/`--continue` within 7 days). `/schedule` creates Anthropic-cloud **Routines** that run independently of any session and require a Pro/Max/Team/Enterprise plan.
- NEVER assume `ScheduleWakeup`, `Monitor`, or `/schedule` are available on Bedrock/Vertex AI/Foundry. They aren't. On those providers, a bare-prompt `/loop` falls back to a fixed 10-minute schedule.

</forbidden>

<required>

Match the primitive to the signal type:

- **One-off reminder, in session** — natural language to Claude ("remind me at 3pm to push"). Claude uses `CronCreate` single-fire mode.
- **Recurring within session, fixed cadence** — `/loop «interval» «prompt»` (e.g. `/loop 5m /check-pr`). Backed by `CronCreate`.
- **Recurring within session, dynamic cadence** — `/loop «prompt»` (no interval). Claude calls `ScheduleWakeup` at the end of each iteration to pick the next delay (1 min – 1 hr). It may also reach for `Monitor` to skip polling entirely.
- **Default-maintenance loop** — bare `/loop`. Runs the built-in maintenance prompt (continue unfinished work, tend the branch's PR, run cleanup passes) or a custom `loop.md` if present.
- **Live event stream** (log line, file change, status URL) — ask Claude to use the `Monitor` tool.
- **Cross-session, durable, scheduled cron** — `/schedule` (Routines on claude.ai). Use this for daily reports, "run once at 3pm tomorrow", anything that must survive a closed terminal.

</required>

## `/loop` — Three Forms

<context>

Per https://code.claude.com/docs/en/scheduled-tasks:

- **`/loop «interval» «prompt»`** — fixed cadence. Examples: `/loop 5m check the deploy`, `/loop 20m /review-pr 1234`. Units: `s` `m` `h` `d`. Non-cron-aligned intervals (e.g. `7m`, `90m`) get rounded to the nearest cron step and Claude reports the actual cadence.
- **`/loop «prompt»`** (no interval) — dynamic. Claude picks the delay each iteration (1 min – 1 hr) and prints the chosen delay + reason at the end of each pass. May use `Monitor` instead of polling.
- **bare `/loop`** — built-in maintenance prompt at a dynamically chosen interval. Replace with a project-level `.claude/loop.md` or user-level `~/.claude/loop.md`. Edits to `loop.md` take effect on the next iteration. Not available on Bedrock/Vertex/Foundry.

**Stopping a loop:** press `Esc` while it's waiting for the next iteration. (`Esc` does not affect tasks Claude created directly via `CronCreate` — delete those by ID.)

</context>

## Underlying `Cron*` Tools

<context>

`/loop` is a wrapper over `CronCreate`. Claude can also use these directly from natural language ("remind me at 3pm", "what scheduled tasks do I have", "cancel the deploy check"):

- `CronCreate` — 5-field cron expression + prompt + recurring/single-fire
- `CronList` — list with 8-char IDs
- `CronDelete` — cancel by ID

Constraints (session-scoped, on local machine):

- Max **50 tasks per session**
- Recurring tasks **expire 7 days** after creation (one final fire + delete). Renew or use Routines for durable scheduling.
- Tasks fire **between turns**, not mid-response; if Claude is busy, the task waits until the current turn ends.
- All times in the user's **local timezone**.
- Jitter: recurring tasks fire up to 30 min after the scheduled time (or half the interval for sub-hourly); one-shot tasks at `:00`/`:30` fire up to 90s early. Pick a minute other than `:00`/`:30` to avoid the one-shot jitter.
- Disabled when `CLAUDE_CODE_DISABLE_CRON=1`.

</context>

## `ScheduleWakeup` — Dynamic-`/loop` Pacing

<context>

In a dynamic `/loop` (no interval), Claude calls `ScheduleWakeup` at the end of each iteration to schedule the next one. Window: 1 min – 1 hour. The wakeup surfaces in `session_crons` in Stop-hook input. Not available on Bedrock/Vertex/Foundry — those providers fall back to a fixed 10-min schedule.

Picking `delaySeconds` against the prompt-cache TTL (per the tool schema):

- **Under 5 min (60–270s)** — cache stays warm. Right for actively polling external state the harness can't notify about (CI run, deploy queue, remote status URL).
- **5 min to 1 hour (300–3600s)** — pay one cache miss. Right when there's no point checking sooner.
- **Don't pick 300s.** Worst-of-both — cache-miss cost without amortization. Drop to ≤270s (stay warm) or commit to ≥1200s.
- **Idle heartbeat, no specific signal** — default 1200–1800s (20–30 min).

The `reason` field is shown to the user — be specific ("watching CI run", not "waiting").

</context>

## `Monitor` — Live Event Streaming

<context>

`Monitor` (v2.1.98) spawns a background script and feeds each output line back as a new transcript message Claude reacts to immediately. No sleep, no polling — the model is invoked when something happens.

Use cases: tail a log file and flag errors, poll a PR/CI for status changes, watch a directory, track output from any long-running script.

Permission rules: same as Bash (`Bash(npm run *)` etc. apply to Monitor too). Not available on Bedrock/Vertex/Foundry. Also disabled when `DISABLE_TELEMETRY` or `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` is set.

For "wait until X completes" with no event stream, `Bash(run_in_background: true)` plus the harness's automatic re-invocation on completion is usually simpler than either `Monitor` or `/loop`.

</context>

## `/schedule` — Cloud Routines

<context>

`/schedule` creates, lists, updates, or removes **Routines** on claude.ai (Anthropic-managed infrastructure). Backed by the `RemoteTrigger` tool.

Distinct from `/loop`:

- `/loop` runs in the current session, on the user's machine, dies on new session
- `/schedule` runs in the cloud on a calendar/cron, runs without an open terminal, persistent across machine reboots

Constraints: requires Pro/Max/Team/Enterprise plan; cloud-only (no access to local files — runs against a fresh clone); MCP servers configured per task; minimum interval 1 hour.

For local-machine durable scheduling without a cloud account, use Desktop scheduled tasks (separate Claude Code feature) — not covered here.

</context>

<related>

- `@smith-ctx-claude/SKILL.md` - Session model, background tasks, hooks
- `@smith-ralph/SKILL.md` - Ralph Loop iterative-development pattern (uses `/loop` as a primitive)
- `@smith-plan-claude/SKILL.md` - Plan automation (hooks, not `/loop`)

</related>

## ACTION (Recency Zone)

<required>

**Before adding any wait/poll/loop:**
1. Live event signal? → `Monitor`
2. Harness-tracked background work? → just wait
3. One-off natural-language reminder? → ask Claude ("remind me at 3pm…") → `CronCreate` single-fire
4. Recurring fixed cadence? → `/loop «interval» «prompt»`
5. Recurring adaptive cadence? → `/loop «prompt»` (dynamic, Claude self-paces)
6. Cross-session durable / runs while terminal closed? → `/schedule` (cloud Routines)

**Provider guards (Bedrock/Vertex/Foundry):**
- `ScheduleWakeup`, `Monitor`, `/schedule` unavailable
- Bare-prompt `/loop` falls back to fixed 10-min schedule

**`ScheduleWakeup` delay:**
- Active polling 60–270s, idle 1200–1800s, **never 300s**

</required>
