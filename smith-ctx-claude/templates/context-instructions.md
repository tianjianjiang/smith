# Context Management Agent Instructions

Canonical instruction templates for context thresholds.

## 50% Warning (Generic)

**Recommended:**
1. Update plan file with current progress (mark completed as [x])
2. Commit uncommitted work
3. If Serena MCP available: write_memory() with descriptive name (task, decisions, file:line refs)
4. AFTER all tool calls complete, output this block:

**Reload with:**
- Plan: `{{PLAN_PATH}}` ({{PENDING_COUNT}} pending)
- Memory: `«name from step 3»` (read via read_memory() after /clear)
- Resume: «describe current task»

5. Tell user to run /clear

Plan auto-reloads after /clear.

## 50% Warning (Ralph Active)

Ralph loop active (iteration {{ITERATION}}). Will auto-exit at critical threshold ({{CRITICAL_PCT}}%).

Save iteration state to Serena NOW: write_memory() with ralph_«task»_state.

Plan file: `{{PLAN_PATH}}` ({{PENDING_COUNT}} pending tasks)

## 50% Warning (Orchestrator Active)

Orchestrator mode active (iteration {{ITERATION}}).

Save orchestrator state to Serena NOW: write_memory() with orchestrator context.

Plan file: `{{PLAN_PATH}}` ({{PENDING_COUNT}} pending tasks)

## 60% Critical (Generic)

**YOU MUST do these steps NOW:**
1. Save state to Serena: write_memory() with descriptive name
2. Update plan file with current progress
3. Commit uncommitted work
4. AFTER all tool calls, output Reload block (see 50% Warning template)
5. Tell user to run /clear

## 60% Critical (Ralph Active)

Ralph loop auto-exiting (max_iterations set to current).

**YOU MUST do these steps NOW:**
1. Save ALL Ralph state to Serena: write_memory() with full iteration context
2. Update plan file with current progress (if plan active)
3. Commit uncommitted work
4. AFTER all tool calls, tell user to run /clear

Ralph loop will auto-resume after /clear.

## 60% Critical (Orchestrator Active)

Orchestrator mode active (iteration {{ITERATION}}).

**YOU MUST do these steps NOW:**
1. Save orchestrator state to Serena: write_memory() with iteration context
2. Update plan file with current progress
3. Commit uncommitted work
4. AFTER all tool calls, tell user to run /clear

Orchestrator will auto-resume after /clear.

## Template Variables

- `{{PLAN_PATH}}` - absolute path to active plan file
- `{{PENDING_COUNT}}` - number of unchecked tasks
- `{{ITERATION}}` - current Ralph/Orchestrator iteration
- `{{CRITICAL_PCT}}` - critical threshold percentage
- `{{CONTEXT_PCT}}` - current context percentage
- `{{WARNING_PCT}}` - warning threshold percentage
