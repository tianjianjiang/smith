# Ralph Orchestration Mode (Pattern B)

**Pattern B = subagent orchestration**: Parent stays light, workers get fresh 200k context each.

```text
User -> "ralph orch" -> Parent (light) -> Task tool -> Worker (fresh 200k each)
```

**Trigger**: "ralph orchestrate", "ralph orch", or "use orchestration mode"

**When to use**: Multi-step plans (>3 tasks), complex features, tasks prone to context accumulation.

## Parent Orchestrator Loop

1. Read plan file, parse `- [ ]` tasks
2. Select next unchecked task
3. Build worker context (plan path, iteration number, task text, memory keys)
4. Spawn worker:
   ```
   Task(subagent_type="general-purpose", prompt=«worker_prompt»)
   ```
   Worker prompt includes: plan path, task text, iteration N, memory keys for prior iterations, completion promise. See `agents/ralph-worker.md` for worker behavior.
5. Read worker result + verify plan file updated (`[x]`)
6. Optionally create/update Claude Code Task for UI tracking
7. If worker succeeded: increment iteration, save state, loop to step 2
8. If worker failed: ask user (retry / skip / modify / manual intervention)
9. On all tasks complete: clean up state, output summary

## Parent Stays Light By

- Reading only plan diffs and memory keys, not full source files
- Reading worker summaries and discarding details, not accumulating worker output
- Using Serena memory keys as references (read only when needed)
- Periodically checking context %

**Prompt-based fallback**: If `agents/ralph-worker.md` is not found, parent builds equivalent prompt inline for `Task(subagent_type="general-purpose", prompt=...)`.

## Delegation Best Practices

**Well-scoped worker prompts MUST include:**
- Specific task description (what, not how)
- Success criteria (testable outcome)
- File scope (which files to read/modify)
- Constraints (don't touch X, preserve Y)

**Failure recovery:**
- Worker fails once: retry with more context
- Worker fails twice: escalate to user
- Worker produces wrong output: revert, rephrase task

**When to parallelize vs serialize:**
- Parallel: independent files, no shared state
- Serial: shared files, output of A feeds into B
- Hybrid: parallel batch, then serial integration

**Model routing for workers:**
See `@smith-ctx-claude/SKILL.md` for model routing guidance (added in PR #60).

## Orchestrator State File

Persists at `~/.claude/plans/.ralph-orchestrator-«CWD_KEY»` (16-char hash of `PPID:CWD` via `session_key()` in `lib-common.sh`):

```yaml
---
active: true
mode: orchestration
iteration: 3
max_iterations: 20
plan_path: "/path/to/plan.md"
completion_promise: "DONE"
current_task: "Implement auth API"
started_at: "2026-02-10T12:00:00+00:00"
---
```

Hook scripts detect this file to manage context cycling (save state before `/clear`, restore after).

## Tasks Integration

Claude Code Tasks provide visual progress tracking. Used as optional UI layer.

**Pattern B**:
- Parent creates `TaskCreate` for each plan `- [ ]` item at orchestration start
- `TaskUpdate(status="in_progress")` before spawning worker
- `TaskUpdate(status="completed")` after worker succeeds

**Known limitation**: Tasks orphaned across sessions (bug #20797). Plan file is the durable state.
