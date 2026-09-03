# Ralph Agent Teams Mode (Pattern C)

**Pattern C = agent teams**: Team lead coordinates, teammates get independent context.

```text
User -> "ralph team" -> Team Lead -> Teammates (own context, shared tasks)
```

**Setup**: Set `"env": {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"}`
in `~/.claude/settings.json` (or export before starting Claude Code).

**Trigger**: "ralph team" or "use team mode"

## Team Lead Workflow

1. Read plan file, create shared task list from `- [ ]` items
2. Set up dependencies (task 2 depends on task 1 if sequential)
3. Spawn N teammates (each gets ralph-worker prompt + plan context)
4. Lead coordinates (see Known Issues before using delegate mode)
5. Teammates self-claim unblocked tasks from shared list
6. Lead monitors progress, handles failures, synthesizes results
7. On completion: clean up team, output summary

## Key Features

- **Plan approval mode**: Require teammates to plan before implementing for risky tasks
- **Direct interaction**: User can message any teammate via Shift+Up/Down
- **Quality gates**: `TeammateIdle` hook for standards, `TaskCompleted` hook to validate
- **File ownership**: Each teammate owns different files (avoid conflicts)
- **Context per teammate**: Fresh context, loads CLAUDE.md + MCP servers + skills

## Parallel Execution Rules

- Independent tasks (different files): parallel teammates OK
- Sequential tasks (same files): use dependency tracking to serialize
- Lead assigns file ownership to avoid conflicts

## Display Modes

**In-process** (default, any terminal):
- Shift+Up/Down: Cycle between teammates
- Enter: View teammate session
- Escape: Interrupt teammate's current turn
- Ctrl+T: Toggle shared task list

**Split panes** (requires tmux or iTerm2):
- Each teammate gets own pane, visible simultaneously
- Click into pane to interact directly
- Config: `"teammateMode": "tmux"` in settings.json
- Override per-session: `claude --teammate-mode in-process`
- Not supported: VS Code terminal, Windows Terminal, Ghostty

**Default** (`"auto"`): Uses split panes if already in tmux, otherwise in-process.

## Known Issues

**Delegate mode permission bug** (Issue #25037):
Teammates spawned after enabling delegate mode (Shift+Tab) inherit the lead's restricted permissions. Teammates lose file tools (Read, Write, Edit, Bash, Glob, Grep) and cannot write code.

**Workaround**: Do not use delegate mode for code-writing teams.
- Tell lead: "Wait for teammates to complete before proceeding"
- Use **plan approval mode** instead for coordination control (require teammates to plan before implementing)
- If lead starts implementing, interrupt and redirect

**Other limitations**:
- No session resumption for in-process teammates
- No nested teams (teammates cannot spawn teams)
- One team per session; lead is fixed for lifetime
- Token-intensive (each teammate = separate Claude instance)
- Experimental - API may change

## Quality Gate Hooks

Hook matchers below are part of the experimental agent teams API and may change. Verify against current Claude Code docs if issues arise.

**TeammateIdle** - Fires when teammate finishes and awaits next task. Exit code 2 sends feedback and keeps teammate working.

```json
{
  "hooks": {
    "TeammateIdle": [{
      "type": "command",
      "command": "echo 'Run tests before marking done'",
      "timeout": 5
    }]
  }
}
```

**TaskCompleted** - Fires when shared task marked complete. Exit code 2 prevents completion and sends feedback.

```json
{
  "hooks": {
    "TaskCompleted": [{
      "type": "command",
      "command": "echo 'Verify test coverage'",
      "timeout": 5
    }]
  }
}
```

## Tasks Integration

**Pattern C**:
- Agent Teams has built-in shared task list - no manual TaskCreate needed
- Team lead creates tasks via team infrastructure
- Dependencies tracked natively (blocks/blockedBy)

**Known limitation**: Tasks orphaned across sessions (bug #20797). Plan file is the durable state.
