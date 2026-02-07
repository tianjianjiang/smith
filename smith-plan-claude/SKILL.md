---
name: smith-plan-claude
description: Plan automation for Claude Code (hooks, scripts, auto-reload). Handles auto-resume after /clear, context threshold detection, and CWD-keyed isolation. Use when the user says "execute plan", "load plan", "start the plan", "run the plan", or wants to work from a previously created plan. IMPORTANT - Always update the plan file after completing tasks.
license: MIT
compatibility: Requires jq for JSON parsing. Designed for Claude Code plan mode files and Ralph loop integration.
metadata:
  author: claude-code-user
  version: "3.0.0"
  tags: ["plan-mode", "workflow", "automation", "ralph-loop", "context-management", "claude-code"]
---

# Plan Automation (Claude Code)

Claude Code-specific automation for plan execution: hooks, auto-reload after `/clear`, context threshold detection, and CWD-keyed session isolation.

<metadata>

- **Load if**: Using Claude Code with plan files, `!load-plan`, `execute plan`
- **Prerequisites**: `@smith-plan/SKILL.md`, @smith-ctx/SKILL.md

</metadata>

## Auto-Resume Directive

When a plan is auto-loaded (via pending-reload flag or fresh session detection),
the hook prepends an ACTION REQUIRED directive instructing the agent to resume
the current task. This overrides Claude Code's default passive treatment of
additionalContext. For trigger-word loads, no directive is added since the
user's message IS the instruction.

## Clear-and-Reload (Context Management)

Simulates Claude Code's "clear context and auto-accept edits" behavior for plan execution. Triggers create a CWD-specific `.pending-reload-<hash>` flag file that persists through `/clear`, enabling auto-reload of the plan in a fresh context window.

### Triggers

| Trigger | When | Behavior |
|---------|------|----------|
| Context threshold | Transcript > 500KB | Auto-creates flag, outputs CONTEXT CRITICAL warning |
| ExitPlanMode | Native plan mode exit | PostToolUse hook creates flag automatically |

### Workflow: Context Threshold Auto-Detection

```
Every prompt submission
    |
    v
inject-plan.sh checks transcript_path size
    |
    v
Size > PLAN_CONTEXT_THRESHOLD_KB (default: 500)?
    |--- No: normal operation
    |--- Yes + active plan + pending tasks:
         |
         v
    Creates CWD-specific .pending-reload flag
    Outputs "CONTEXT CRITICAL" warning
         |
         v
    Agent saves state, user runs /clear
         |
         v
    Plan auto-reloads on next prompt
```

### Flag File Format

`~/.claude/plans/.pending-reload-<8-char-cwd-hash>`:
```
/absolute/path/to/plan.md       <- line 1: plan path
session_abc123                   <- line 2: session ID
$(date +%Y-%m-%dT%H:%M:%S%z)    <- line 3: ISO timestamp
/path/to/working/directory      <- line 4: CWD (for debugging)
```

- **CWD-based isolation**: Each parallel session gets its own flag file keyed by md5 hash of `$PWD`
- `$PWD` persists across `/clear` but differs between parallel sessions (worktrees)
- Expired flags (>1 hour) auto-cleaned on each hook invocation
- Legacy single `.pending-reload` file auto-cleaned (backward compatibility)
- One-shot: consumed (deleted) after plan is loaded

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PLAN_CONTEXT_THRESHOLD_KB` | `500` | Transcript size threshold in KB (~50% of 200K context) |

## Ralph Loop Integration

This skill integrates with Ralph's autonomous loop in Claude Code:

1. **Fresh Context Each Iteration**: Hook reads plan from disk each time
2. **Progress Persistence**: Updates written to disk survive `/clear`
3. **Completion Detection**: Ralph can detect `PLAN COMPLETE` signal (see `@smith-plan/SKILL.md`)
4. **Phase Boundaries**: Agent recommends `/clear` to user; plan-claude auto-reloads via state-based detection

## Usage Triggers

| Trigger | Action |
|---------|--------|
| `execute plan` | Load most recent plan |
| `!load-plan` | Load most recent plan |
| `!load-plan <name>` | Load specific plan |
| `!plan-status` | Show current progress |

## Scripts

| Script | Hook Type | Purpose |
|--------|-----------|---------|
| `scripts/inject-plan.sh` | UserPromptSubmit | Auto-loads plan, flag detection, context detection |
| `scripts/enforce-clear.sh` | Stop | Blocks stop when context high + pending tasks; auto-creates flag |
| `scripts/on-plan-exit.sh` | PostToolUse (ExitPlanMode) | Creates reload flag on plan mode exit |
| `scripts/list-plans.sh` | Manual | List available plans |
| `scripts/load-plan.sh` | Manual | Manually load a plan |
| `scripts/plan-status.sh` | Manual | Show progress summary |

## File Locations

| Item | Path |
|------|------|
| Plans directory | `~/.claude/plans/` |
| Active plan | Tracked in `.plan-state-<cwd-hash>` state file |
| Reload flag | `~/.claude/plans/.pending-reload-<cwd-hash>` |
| State file | `~/.claude/plans/.plan-state-<cwd-hash>` |
| This skill | `~/.smith/smith-plan-claude/` |

## State File Format

`~/.claude/plans/.plan-state-<8-char-cwd-hash>`:
```
sess_abc123                   <- line 1: session ID
/path/to/transcript.jsonl     <- line 2: transcript path
921600                        <- line 3: transcript size (bytes)
$(date +%Y-%m-%dT%H:%M:%S%z) <- line 4: ISO timestamp
/path/to/plan.md              <- line 5: plan path
```

- **CWD-keyed**: Same as flag files, keyed by md5 hash of `$PWD` (persists across `/clear`)
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
3. At phase boundaries, update plan + write Serena memory, then recommend `/clear`
4. Plan auto-reloads in fresh context via pending-reload flag

</required>
