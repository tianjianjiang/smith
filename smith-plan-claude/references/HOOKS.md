# Hook Configuration for Plan Sync

This document explains how to configure the hooks for plan syncing, context management, and Ralph autonomous loop integration.

## Overview

Three hooks work together to manage plan execution across context boundaries:

| Hook | Event | Script | Purpose |
|------|-------|--------|---------|
| `inject-plan.sh` | UserPromptSubmit | Every prompt | Load plan, detect flags, detect context threshold |
| `enforce-clear.sh` | Stop | Agent stop | Block stop when context high + pending tasks |
| `on-plan-exit.sh` | PostToolUse (ExitPlanMode) | Plan mode exit | Create reload flag for auto-load after `/clear` |

## Installation

### 1. Copy the Skill

```bash
# Symlink (recommended)
ln -sf ~/.smith/smith-plan-claude ~/.claude/skills/smith-plan-claude

# Make scripts executable
chmod +x ~/.smith/smith-plan-claude/scripts/*.sh
```

### 2. Configure the Hooks

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/skills/smith-plan-claude/scripts/inject-plan.sh",
            "timeout": 5000
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/skills/smith-plan-claude/scripts/enforce-clear.sh",
            "timeout": 5000
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "ExitPlanMode",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/skills/smith-plan-claude/scripts/on-plan-exit.sh",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

### 3. Ensure Plans Directory Exists

```bash
mkdir -p ~/.claude/plans
```

## Hook Details

### inject-plan.sh (UserPromptSubmit)

Fires on every prompt. Three main paths:

1. **Flag detection**: If `.pending-reload-<CWD_KEY>` exists (CWD-keyed, <1hr old), loads the flagged plan and deletes the flag (one-shot).

2. **Context threshold**: If `transcript_path` file size exceeds `PLAN_CONTEXT_THRESHOLD_KB` (default: 500KB) and an active plan has pending tasks, creates the flag and outputs a CONTEXT CRITICAL warning.

3. **Trigger words**: Matches `execute plan`, `!load-plan`, `!plan`, `!plan-status`, etc.

**Input JSON fields used:**
- `prompt` - User's prompt text
- `session_id` - Current session identifier
- `transcript_path` - Path to JSONL transcript file

### enforce-clear.sh (Stop)

Fires when agent attempts to stop. Blocks stop if ALL conditions met:
1. No `.pending-reload-<CWD_KEY>` flag (clear not yet initiated)
2. Transcript size > threshold
3. Active plan has pending `- [ ]` tasks

When blocking, the hook **auto-creates the `.pending-reload` flag** before returning the block. This breaks the infinite loop: on the first stop attempt, the agent is blocked and gets one turn to save state. On the second stop attempt, the flag exists and the stop is allowed.

**Input JSON fields used:**
- `transcript_path` - Path to JSONL transcript file
- `session_id` - Current session identifier (for flag file)

### on-plan-exit.sh (PostToolUse: ExitPlanMode)

Fires after ExitPlanMode tool is used. Creates `.pending-reload-<CWD_KEY>` flag with the most recently modified plan, enabling auto-reload after `/clear`.

**Input JSON fields used:**
- `session_id` - Current session identifier

## Flag File Format

`~/.claude/plans/.pending-reload-<CWD_KEY>` (8-char md5 hash of CWD):

```
/Users/user/.claude/plans/my-plan.md    <- line 1: absolute plan path
sess_abc123def                           <- line 2: session ID
$(date +%Y-%m-%dT%H:%M:%S%z)            <- line 3: ISO 8601 timestamp
/path/to/working/directory              <- line 4: CWD (for debugging)
```

**Properties:**
- **CWD-keyed**: Each parallel session (worktree) gets its own flag file
- Persists through `/clear` (which only clears conversation, not disk files)
- One-shot: deleted after plan is loaded
- Expired flags (>1 hour old) are auto-cleaned on each hook invocation
- Legacy single `.pending-reload` file auto-cleaned (backward compatibility)

## Ralph Loop Integration

### How It Works with Ralph

```
Iteration 1:
  1. Ralph sends prompt
  2. UserPromptSubmit fires
  3. Hook reads ~/.claude/plans/my-plan.md (v1)
  4. Plan v1 injected into context
  5. Claude works on Task 1
  6. Claude updates plan file -> now v2 on disk
  7. Iteration ends

Iteration 2:
  1. Ralph sends next prompt
  2. UserPromptSubmit fires
  3. Hook reads ~/.claude/plans/my-plan.md (v2) <- UPDATED
  4. Plan v2 injected (shows Task 1 complete)
  5. Claude sees progress, works on Task 2
  6. Claude updates plan file -> now v3 on disk
  7. Iteration ends

... continues until all tasks complete ...
```

### Ralph Exit Detection

The skill outputs specific signals for Ralph to detect:

**Completion Signal:**
```
PLAN COMPLETE: All tasks finished successfully.
```

**Blocker Signal:**
```
BLOCKER: [description of issue]
```

## Trigger Phrases

| Pattern | Example |
|---------|---------|
| `execute-plan` | "Let's use execute-plan" |
| `!load-plan` | "!load-plan" or "!load-plan my-project" |
| `!plan` | "!plan" or "!plan feature-auth" |
| `!plan-status` | "!plan-status" |
| `execute the plan` | "Execute the plan now" |
| `load the plan` | "Load the plan" |
| `run the plan` | "Run the plan" |
| `start the plan` | "Start the plan" |
| `continue the plan` | "Continue the plan" |
| `resume the plan` | "Resume the plan" |

## Plan File Format

For best progress tracking, use checkbox format:

```markdown
# My Project Plan

## Objective
Build a REST API for user management

## Tasks

- [x] Task 1: Set up project structure
- [x] Task 2: Create database models
- [ ] Task 3: Implement CRUD endpoints <- CURRENT
- [ ] Task 4: Add authentication
- [ ] Task 5: Write tests
- [ ] Task 6: Documentation

## Progress Log

### Iteration 1 (2024-01-15 10:30)
- Completed: Task 1
- Notes: Using Express.js with TypeScript

### Iteration 2 (2024-01-15 10:45)
- Completed: Task 2
- Files: src/models/user.ts, src/db/schema.sql
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PLAN_CONTEXT_THRESHOLD_KB` | `500` | Transcript size threshold in KB for context warnings |

## Manual Testing

### Test flag consumption (auto-reload)

```bash
# CWD_KEY is the first 8 chars of md5(CWD)
CWD_KEY=$(printf '%s' "$PWD" | md5 -q 2>/dev/null || printf '%s' "$PWD" | md5sum | cut -d' ' -f1)
CWD_KEY=${CWD_KEY:0:8}

echo '{"prompt":"go","session_id":"test1","cwd":"'$PWD'"}' | \
  ~/.smith/smith-plan-claude/scripts/inject-plan.sh
ls ~/.claude/plans/.pending-reload-${CWD_KEY} 2>&1  # Should show "No such file"
```

### Test context threshold detection

```bash
dd if=/dev/zero bs=1024 count=900 of=/tmp/test-transcript.jsonl 2>/dev/null
echo '{"prompt":"hello","session_id":"test2","transcript_path":"/tmp/test-transcript.jsonl","cwd":"'$PWD'"}' | \
  ~/.smith/smith-plan-claude/scripts/inject-plan.sh
```

### Test Stop hook blocking

```bash
CWD_KEY=$(printf '%s' "$PWD" | md5 -q 2>/dev/null || printf '%s' "$PWD" | md5sum | cut -d' ' -f1)
CWD_KEY=${CWD_KEY:0:8}
rm -f ~/.claude/plans/.pending-reload-${CWD_KEY}
echo '{"transcript_path":"/tmp/test-transcript.jsonl","cwd":"'$PWD'"}' | \
  ~/.smith/smith-plan-claude/scripts/enforce-clear.sh
```

### Test Stop hook allow (flag exists)

```bash
CWD_KEY=$(printf '%s' "$PWD" | md5 -q 2>/dev/null || printf '%s' "$PWD" | md5sum | cut -d' ' -f1)
CWD_KEY=${CWD_KEY:0:8}
printf '/tmp/plan.md\ntest\n'"$(date +%Y-%m-%d)"'\n/tmp\n' > ~/.claude/plans/.pending-reload-${CWD_KEY}
echo '{"transcript_path":"/tmp/test-transcript.jsonl","cwd":"'$PWD'"}' | \
  ~/.smith/smith-plan-claude/scripts/enforce-clear.sh
```

### Test stale flag cleanup

```bash
CWD_KEY=$(printf '%s' "$PWD" | md5 -q 2>/dev/null || printf '%s' "$PWD" | md5sum | cut -d' ' -f1)
CWD_KEY=${CWD_KEY:0:8}
printf '/path/plan.md\nold_session\n'"$(date +%Y-%m-%dT%H:%M:%S%z)"'\n/old/path\n' > ~/.claude/plans/.pending-reload-${CWD_KEY}
# Set file mtime to 2 hours ago to trigger cleanup
touch -t $(date -v-2H +%Y%m%d%H%M 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M) ~/.claude/plans/.pending-reload-${CWD_KEY}
echo '{"prompt":"go","session_id":"different_session","cwd":"'$PWD'"}' | \
  ~/.smith/smith-plan-claude/scripts/inject-plan.sh
ls ~/.claude/plans/.pending-reload-${CWD_KEY} 2>&1  # Should show "No such file"
```

## Troubleshooting

### Hook Not Firing

1. Check settings.json syntax:
   ```bash
   cat ~/.claude/settings.json | jq .
   ```

2. Verify scripts are executable:
   ```bash
   ls -la ~/.smith/smith-plan-claude/scripts/*.sh
   ```

3. Test hook manually:
   ```bash
   echo '{"prompt":"execute the plan"}' | ~/.smith/smith-plan-claude/scripts/inject-plan.sh
   ```

### Plan Not Updating Between Iterations

1. Verify Claude is writing to the correct file path
2. Check the plan file manually between iterations:
   ```bash
   cat ~/.claude/plans/my-plan.md
   ```

### Stale Flag File

Expired flag files (>1 hour old) are auto-cleaned. To manually clear all flags:
```bash
rm -f ~/.claude/plans/.pending-reload-*
```

### jq Not Found

Install jq:
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq
```

## Dependencies

- **bash** 4.0+
- **jq** for JSON parsing
- **Claude Code** with hooks support
- **Ralph** (optional, for autonomous loop)

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Context high, no active plan | Stop hook allows stop, no flag created |
| Context high, all tasks done | Stop hook allows stop (PENDING=0) |
| Expired flag (>1 hour) | Auto-cleaned on next hook invocation |
| User ignores /clear | Flag persists; plan loads on any prompt in same CWD |
| Multiple threshold warnings | Flag overwritten each time (idempotent) |
| Auto-load after /clear | Directive prepended: "Resume working on current task" |
| Stop hook blocks | Flag auto-created, loop breaks after one iteration |
| Fresh session with pending plan | Directive prepended: "This plan was auto-loaded in a fresh session" |
| Trigger-word load | No directive added (user's message is the instruction) |
