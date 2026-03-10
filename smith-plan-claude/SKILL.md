---
name: smith-plan-claude
description: Plan automation for Claude Code (hooks, scripts, auto-reload). Handles auto-resume after /clear, context threshold detection, and session-keyed isolation. Use when the user says "execute plan", "load plan", "start the plan", "run the plan", "reload", or wants to work from a previously created plan. IMPORTANT - Always update the plan file after completing tasks.
license: MIT
compatibility: Requires jq for JSON parsing. Designed for Claude Code plan mode files and Ralph loop integration.
metadata:
  author: claude-code-user
  version: "3.0.0"
  tags: ["plan-mode", "workflow", "automation", "ralph-loop", "context-management", "claude-code"]
---

# Plan Automation (Claude Code)

Claude Code-specific automation for plan execution: hooks, auto-reload after `/clear`, context threshold detection, and session-keyed isolation.

<metadata>

- **Load if**: Using Claude Code with plan files, `!load-plan`, `execute plan`
- **Prerequisites**: `@smith-plan/SKILL.md`, @smith-ctx/SKILL.md

</metadata>

## Auto-Resume Directive

When a plan is auto-loaded (via pending-reload flag after `/clear`),
the hook prepends an ACTION REQUIRED directive instructing the agent
to resume the current task. This overrides Claude Code's default
passive treatment of additionalContext. For trigger-word loads, no
directive is added since the user's message IS the instruction.

Plans only auto-load when a **flag file** exists (explicit reload intent
from enforce-clear.sh or on-plan-exit.sh) or via trigger words. A state
file alone (no flag) is informational — the agent mentions the plan exists
but does NOT auto-resume. New sessions require an explicit request
(e.g. "execute plan", "!load-plan").

### Post-/clear Resume Protocol

The SessionStart:clear hook outputs **state data only** (flag type, plan metadata, signal). The agent interprets this data and follows the protocol below.

**When hook signal = `resume` with flag type `plan-pending`:**
(Flag file exists = explicit reload intent from enforce-clear or on-plan-exit)
1. Reconstruct todos from plan checkboxes: for each `- [ ]` task, TaskCreate(subject=task_text, description="From plan")
2. Set first pending task: TaskUpdate(taskId, status="in_progress")
3. If Serena MCP available: read_memory() for session state (context restoration)
4. Resume current task from plan

**When hook signal = `resume` with flag type `plan-completed` or `no-plan`:**
1. If Serena MCP available: list_memories() then read_memory() for most recent session memory
2. Report restored context to user
3. Ask if user wants to continue previous work or start something new

**When hook signal = `fresh-start`** (no flag file):
1. If state file mentions a plan ("not loaded"), briefly note it exists but do NOT auto-resume
2. If Serena MCP available: list_memories() for any relevant context
3. Ask: "What would you like to work on?" (mention available plan if state file shows one)

If the user's message contains a specific request, address that instead of the protocol above.

## Unified Stop Hook

The stop hook (`enforce-clear.sh`) handles both plan-active and non-plan contexts in a single hook. Uses real token counts from transcript JSONL (same data as Claude Code statusline) and `stop_hook_active` (official best practice, see [hooks docs](https://code.claude.com/docs/en/hooks)).

- **Real percentage**: Blocks at 60% context (from transcript token usage, not byte count)
- **Three branches**: Plan+pending, plan+completed, no-plan (each with imperative save + reload block instructions)
- **Self-contained "Reload with:" block**: Includes plan path, output AFTER all tool calls complete
- **Loop prevention**: When `stop_hook_active: true`, allows stop immediately

## SessionStart:clear Hook

The `on-session-clear.sh` hook fires after manual `/clear` and reliably injects plan content with skill/todo reconstruction instructions. This is the primary injection point for post-/clear plan restoration. When no plan state exists, it still emits a Serena memory restoration directive (graceful degradation).

## Plan Mode State Saving

During plan mode (`permission_mode: "plan"`), `inject-plan.sh` saves state on every prompt submission. This ensures the state file has the plan path BEFORE the user exits plan mode -- critical because PostToolUse:ExitPlanMode doesn't fire with "clear context and auto-accept edits" (upstream bug [#20397](https://github.com/anthropics/claude-code/issues/20397)).

## Clear-and-Reload (Context Management)

Simulates Claude Code's "clear context and auto-accept edits" behavior for plan execution. Multiple injection points ensure plan restoration across different scenarios:

### Injection Points

- `on-session-clear.sh` (SessionStart:clear) -- after manual `/clear`:
  reliable plan injection with todo/skill instructions
- `inject-plan.sh` (UserPromptSubmit) -- flag or trigger word:
  flag-based reload for plan-mode "clear context" case
- `enforce-clear.sh` (Stop) -- context > threshold:
  creates flag, blocks stop, outputs save + reload instructions
- `on-plan-exit.sh` (PostToolUse:ExitPlanMode) -- manual plan exit:
  creates flag for later `/clear`

### Known Limitations (upstream bugs)

- Plan mode "clear context and auto-accept edits" does not fire PostToolUse:ExitPlanMode ([#20397](https://github.com/anthropics/claude-code/issues/20397))
- Plan mode "clear context" does not fire SessionStart:clear ([#20900](https://github.com/anthropics/claude-code/issues/20900))
- Tasks are orphaned across session boundaries ([#20797](https://github.com/anthropics/claude-code/issues/20797)) -- todo reconstruction from plan checkboxes is the workaround

### Workflow: Context Threshold Auto-Detection

Uses real token counts from transcript JSONL (same data as Claude Code statusline). The last assistant message's `usage` object provides `input_tokens`, `cache_read_input_tokens`, and `cache_creation_input_tokens`. Context percentage = total input tokens / context window size.

```text
Every prompt submission
    |
    v
inject-plan.sh calculates context % from transcript token usage
    |
    v
Context >= PLAN_CONTEXT_WARNING_PCT (default: 50%)?
    |--- No: normal operation
    |--- Yes + active plan + pending tasks:
         |
         v
    Creates CWD-specific .pending-reload flag
    Outputs "CONTEXT WARNING: XX% used" advisory
         |
         v
    Agent saves state, then AFTER all tool calls outputs self-contained "Reload with:" block (with plan path), user runs /clear
         |
         v
    SessionStart:clear hook injects plan (primary)
    OR inject-plan.sh detects flag file (fallback)

Stop hook (enforce-clear.sh) blocks at 60% (critical threshold).
```

### Flag File Format

`~/.claude/plans/.pending-reload-<session-hash>`:
```
/absolute/path/to/plan.md       <- line 1: plan path (empty if no plan)
session_abc123                   <- line 2: session ID
$(date +%Y-%m-%dT%H:%M:%S%z)    <- line 3: ISO timestamp
/path/to/working/directory      <- line 4: CWD (for debugging)
plan-pending                     <- line 5: type (plan-pending|plan-completed|no-plan)
```

- **Backward compatibility**: Old flags without line 5 default to `plan-pending`

- **Session-based isolation**: Each parallel session gets its own flag file keyed by hash of `PPID:CWD`
- `$PWD` persists across `/clear` but differs between parallel sessions (worktrees)
- Expired flags (>1 hour) auto-cleaned on each hook invocation
- Legacy single `.pending-reload` file auto-cleaned (backward compatibility)
- One-shot: consumed (deleted) after plan is loaded

### Environment Variables

- `PLAN_CONTEXT_WARNING_PCT` (default: `50`) — Advisory warning threshold (% of context window)
- `PLAN_CONTEXT_CRITICAL_PCT` (default: `60`) — Stop hook blocking threshold (% of context window)
- `CONTEXT_WINDOW_TOKENS` (default: `200000`) — Context window size in tokens

## Serena Memory Convention

Hooks instruct the agent to use Serena's semantic naming
conventions rather than computing deterministic memory names.
The agent chooses descriptive names (e.g. `auth_refactor_notes`,
`session_summary`) via `write_memory()` when saving state.

- **Save**: hooks say `write_memory() with descriptive name`
  at 50% warning, 60% stop, or plan exit
- **Restore**: hooks say `list_memories() then read_memory()`
  in post-`/clear` ACTION REQUIRED directive
- **Graceful degradation**: all instructions prefixed with
  "If Serena MCP available:" -- no failure if Serena is not
  configured

## Ralph Loop Integration

This skill integrates with Ralph's autonomous loop in Claude Code:

1. **Fresh Context Each Iteration**: Hook reads plan from disk each time
2. **Progress Persistence**: Updates written to disk survive `/clear`
3. **Completion Detection**: Ralph can detect `PLAN COMPLETE` signal (see `@smith-plan/SKILL.md`)
4. **Phase Boundaries**: Agent recommends `/clear` to user; plan-claude auto-reloads via flag file or SessionStart:clear

### Coordinated Context Clearing

When Ralph is active and context gets high, three hooks coordinate to prevent deadlock:

- `inject-plan.sh` — Detects Ralph + high context. At 50%: saves resume preemptively. At 60%: forces exit (sets max_iterations = iteration), saves resume.
- `enforce-clear.sh` — Detects Ralph state file or resume file and defers (exit 0). Prevents double-blocking.
- `on-session-clear.sh` — After /clear: detects resume file, injects plan + Ralph auto-invoke instruction. Agent restarts loop via Skill tool.

### Resume File Format

`~/.claude/plans/.ralph-resume-<session-hash>`:
```text
20                                  <- line 1: max_iterations
5                                   <- line 2: current iteration
TASK COMPLETE                       <- line 3: completion promise
/path/to/plan.md                    <- line 4: plan path (optional)
2026-02-10T14:30:45+0800            <- line 5: timestamp
```

`~/.claude/plans/.ralph-resume-<session-hash>.prompt`:
```text
Raw prompt text (may contain newlines)
```

### Proactive Phase Boundaries

At EVERY phase boundary (regardless of context level), the agent should exit Ralph naturally, save state to Serena, and tell user to `/clear`. See `@smith-ralph/SKILL.md` Phase Boundary Protocol.

## Usage Triggers

- `execute plan` — Load most recent plan
- `!load-plan` — Load most recent plan
- `!load-plan <name>` — Load specific plan
- `reload` — Load plan from state file (post-/clear shortcut)
- `reload plan` / `reload the plan` — Load plan from state file
- `!plan-status` — Show current progress

## Scripts

- `scripts/inject-plan.sh` (UserPromptSubmit) — Auto-loads plan (flag/trigger), context % warning (50%), plan mode state saving
- `scripts/enforce-clear.sh` (Stop) — Unified stop hook: blocks at 60% context, three branches (uses `stop_hook_active`)
- `scripts/on-session-clear.sh` (SessionStart:clear) — Reliable post-`/clear` plan injection with todo/skill instructions
- `scripts/on-plan-exit.sh` (PostToolUse:ExitPlanMode) — Creates reload flag on plan mode exit
- `scripts/list-plans.sh` (Manual) — List available plans
- `scripts/load-plan.sh` (Manual) — Manually load a plan
- `scripts/plan-status.sh` (Manual) — Show progress summary

## File Locations

- Plans directory — `~/.claude/plans/`
- Active plan — Tracked in `.plan-state-<session-hash>` state file
- Reload flag — `~/.claude/plans/.pending-reload-<session-hash>`
- State file — `~/.claude/plans/.plan-state-<session-hash>`
- This skill — `~/.smith/smith-plan-claude/`

## State File Format

`~/.claude/plans/.plan-state-<session-hash>`:
```
sess_abc123                   <- line 1: session ID
/path/to/transcript.jsonl     <- line 2: transcript path
921600                        <- line 3: transcript size (bytes)
$(date +%Y-%m-%dT%H:%M:%S%z) <- line 4: ISO timestamp
/path/to/plan.md              <- line 5: plan path
```

- **Session-keyed**: Same as flag files, keyed by hash of `PPID:CWD` (persists across `/clear`)
- **60-min auto-load window**: State files older than 60 minutes are skipped for auto-load (prevents loading old plan in new session)
- **24-hour cleanup**: State files older than 24 hours are auto-cleaned on each hook invocation

<related>

- `@smith-plan/SKILL.md` - Portable plan tracking protocol
- @smith-ctx/SKILL.md - Context management
- `@smith-ctx-claude/SKILL.md` - Claude Code context management
- `@smith-ralph/SKILL.md` - Ralph Loop iterative development

</related>

## ACTION (Recency Zone)

<required>

**Plan execution in Claude Code:**
1. Hook auto-loads plan into context on each prompt
2. Follow `@smith-plan/SKILL.md` iteration workflow
3. At phase boundaries, update plan + commit work, save state to Serena memory, then AFTER all tool calls output self-contained "Reload with:" block (with plan path), recommend `/clear`
4. Plan auto-reloads in fresh context via pending-reload flag

</required>
