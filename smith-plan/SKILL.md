---
name: smith-plan
description: Plan tracking protocol (portable). Progress tracking with checkboxes, iteration workflow, completion/blocker signals. Use when executing multi-step plans, tracking task progress, or working from plan files. IMPORTANT - Always update the plan file after completing tasks.
license: MIT
metadata:
  version: "1.0.0"
  tags: ["plan-mode", "workflow", "progress-tracking"]
---

# Plan Tracking Protocol

Portable protocol for tracking plan progress across iterations. Platform-agnostic — works with any AI agent that can read/write files.

<metadata>

- **Load if**: Executing plans, tracking multi-step tasks
- **Prerequisites**: @smith-ctx/SKILL.md

</metadata>

## CRITICAL: Plan Sync Protocol (Primacy Zone)

<required>

**After completing ANY task, you MUST update the plan file.**

This ensures the next iteration sees your progress.

</required>

<forbidden>

- Skipping the sync step after completing work
- Leaving tasks unmarked after completion
- Modifying plan format in ways that break checkbox parsing

</forbidden>

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

### Iteration 1 ([TIMESTAMP])
- Completed: Task 1, Task 2
- Notes: Used PostgreSQL instead of MySQL per user preference

### Iteration 2 ([TIMESTAMP])
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

## Completion Signal

When all tasks are done, output this exact phrase:

```
PLAN COMPLETE: All tasks finished successfully.
```

## Blocker Signal

If you hit a blocker requiring human input:

```
BLOCKER: [description of issue requiring human decision]
```

## Important Rules

1. **ALWAYS update the plan file after completing work**
2. **NEVER skip the sync step** - next iteration depends on it
3. **Use checkbox format** `- [ ]` / `- [x]` for trackable tasks
4. **Add timestamps** to progress log entries
5. **Note file changes** in progress log for traceability

<related>

- @smith-ctx/SKILL.md - Context management
- `@smith-plan-claude/SKILL.md` - Claude Code automation (hooks, scripts)
- `@smith-ralph/SKILL.md` - Ralph Loop iterative development

</related>

## ACTION (Recency Zone)

<required>

**Per iteration:**
1. Read plan file
2. Find first `- [ ]` task
3. Execute the task
4. Mark `- [x]`, add progress log entry
5. Continue or signal completion

</required>
