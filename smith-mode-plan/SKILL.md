---
name: smith-mode-plan
description: Plan mode definition and plan tracking protocol . Progress tracking
license: MIT
metadata:
  version: "1.0.0"
  tags: ["plan-mode", "workflow", "progress-tracking"]
---

# Plan Mode and Plan Tracking Protocol

Portable protocol for tracking plan progress across iterations. Platform-agnostic — works with any AI agent that can read/write files.

**Load if:** Entering plan mode, executing plans, tracking multi-step tasks
**Prerequisites:** @smith-ctx/SKILL.md

## What Plan Mode Is (Platform-Neutral)

Plan mode is a read-only interview stage that precedes implementation: the
agent explores the codebase and interrogates the request without editing
anything, then produces a written plan (files that change, order of work,
tests, risks) for the human to approve before a single line of code is
written. The plan itself, once approved, becomes the committed artifact
that later stages — implementation, and any downstream review — check
work against.

This definition holds regardless of which coding agent or tool implements
it. `@smith-mode-plan-claude/SKILL.md` covers Claude Code's specific
implementation (the `ExitPlanMode` tool call, its approval modal, and the
hooks that enforce it) — read this section first for what plan mode means,
then that skill for how Claude Code's UI and hooks realize it.

## CRITICAL: Plan Sync Protocol

**After completing ANY task, you MUST update the plan file.**

This ensures the next iteration sees your progress.

- Sync the plan file right after completing work — do not defer it
- Mark tasks complete as soon as they are finished
- Keep plan format changes compatible with checkbox parsing

## Progress Tracking Format

Use this format in plan files for trackable progress:

```markdown
## Tasks

- [x] Task 1: Set up project structure
- [x] Task 2: Create database schema
- [ ] Task 3: Implement API endpoints <- CURRENT
- [ ] Task 4: Add authentication
- [ ] Task 5: Write tests

## Progress Log

### Iteration 1 («TIMESTAMP»)
- Completed: Task 1, Task 2
- Notes: Used PostgreSQL instead of MySQL per user preference

### Iteration 2 («TIMESTAMP»)
- Working on: Task 3
- Blockers: None
```

## Workflow Per Iteration

```
1. LOAD: Read plan file
   -> Locate and read the plan

2. IDENTIFY: Find first uncompleted task (- [ ])
   -> Skip tasks marked [x]

3. EXECUTE: Complete the current task
   -> Do the actual implementation work

4. SYNC: Update plan file with progress
   -> Mark task [x], add progress log entry
   -> Write to SAME file path

5. CONTINUE or COMPLETE
   -> If more tasks: proceed to next
   -> If all done: signal completion
```

## Plan Update Template

When updating the plan, use this pattern:

```bash
# 1. Mark task complete (change - [ ] to - [x])
# 2. Add progress log entry with timestamp
# 3. Note any blockers or changes
# 4. Save to the same file path
```

## Completion-Aware Reload

An auto-loaded or auto-listed plan is **stale, not live**, when its checkboxes
are all `- [x]` (or `git log` / a session memory shows the work merged).
Disregard a stale plan — report it and ask — rather than resuming it. Verify
checkbox state before treating any reloaded plan as work to continue.

## Completion Signal

When all tasks are done, output this exact phrase:

```
PLAN COMPLETE: All tasks finished successfully.
```

## Blocker Signal

If you hit a blocker requiring human input:

```
BLOCKER: «description of issue requiring human decision»
```

## Important Rules

1. **ALWAYS update the plan file after completing work**
2. **NEVER skip the sync step** - next iteration depends on it
3. **Use checkbox format** `- [ ]` / `- [x]` for trackable tasks
4. **Add timestamps** to progress log entries
5. **Note file changes** in progress log for traceability

## Related

- @smith-ctx/SKILL.md - Context management
- `@smith-mode-plan-claude/SKILL.md` - Claude Code automation (hooks, scripts)
- `@smith-ralph/SKILL.md` - Ralph Loop iterative development
- `@smith-sdlc/SKILL.md` - the SDLC's `plan.md` artifact chain (this skill covers plan mode itself; smith-sdlc covers what happens before and after it)

## Before You Finish

**Per iteration:**
1. Read plan file
2. Find first `- [ ]` task
3. Execute the task
4. Mark `- [x]`, add progress log entry
5. Continue or signal completion
