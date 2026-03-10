---
name: smith-ctx-claude
description: Claude Code context management with /clear command, stop hook enforcement at 60%, hooks reference (15 events), permission modes, agent features (subagents, teams), and model routing. Use when operating in Claude Code IDE, configuring hooks, managing agents, or when context exceeds 50%.
---

# Claude Code Context Management

<metadata>

- **Load if**: Using Claude Code, context >50%
- **Prerequisites**: @smith-ctx/SKILL.md

</metadata>

## CRITICAL: Context Commands (Primacy Zone)

<required>

**Agent prompts for context status**, then recommends action.

**Thresholds and actions (graduated)**:
- 40-50%: Consider "Summarize from here" (targeted compression)
- 50%: Warning - recommend action (summarize or /clear)
- 60%: Critical - /clear mandatory (stop hook enforced)

**"Summarize from here"** (preserves early context):
- Access: Esc+Esc (or /rewind) -> select checkpoint -> Summarize
- Keeps conversation before checkpoint intact
- Compresses everything after checkpoint into summary
- Optional: provide focus instructions for the summary
- Best when early decisions matter but later exploration is verbose

**"/clear"** (full reset, save state first):
- Stop hook enforced at 60% via `smith-plan-claude`
- Uses `stop_hook_active` (official best practice)

</required>

<forbidden>

- Using `/compact` (use "Summarize from here" or /clear instead)
- `/clear` without checking uncommitted work

</forbidden>

## /clear - Full Context Reset

<required>

**Before `/clear`:**
1. Update plan file with current progress (if active)
2. Commit current work with detailed message
3. Save state to Serena memory with `write_memory()`
4. AFTER all tool calls complete, output a self-contained **Reload with:** block (plan path if applicable, memory name, resume command)

**Preserved**: Project files, CLAUDE.md, plan files
**Lost**: All conversation history

**After `/clear`:**
1. Plan auto-reloads with todo reconstruction ONLY if a flag file exists (explicit reload intent from enforce-clear or on-plan-exit). State file alone = informational, not auto-resume.
2. If Serena MCP available: call list_memories(), read relevant memories for session state
3. Re-read relevant files as needed

</required>

## Commit-Early Pattern

<required>

- Do not batch commits to end of session — context resets lose uncommitted work
- If 15+ tool calls pass without a commit and there are uncommitted changes, commit with `#WIP` prefix to preserve progress
- Before destructive operations (rebase, `/clear`), commit or stash current work

</required>

## Stop Hook (Unified)

<context>

Stop hook enforcement is handled by `smith-plan-claude/scripts/enforce-clear.sh`. Uses real token counts from transcript JSONL (same data as Claude Code statusline) to calculate context percentage. A single unified hook covers both plan-active and non-plan contexts:

- **Real percentage**: Blocks at 60% context (from transcript token usage, not byte count)
- **Three branches**: Plan+pending, plan+completed, no-plan (plan filepath shown first, Serena optional)
- **Loop prevention**: Uses `stop_hook_active` field (official best practice)

**Config**: Only one Stop hook entry in `settings.json` (in `smith-plan-claude`).

</context>

## Recommended Linting Hooks

<context>

**PostToolUse auto-format** — runs formatter after every Edit/Write (strongest enforcement, zero friction):

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{
          "type": "command",
          "command": "input=$(cat) && file=$(printf '%s' \"$input\" | jq -r '.tool_input.file_path // empty') && [ -n \"$file\" ] && { case \"$file\" in *.py) ruff format \"$file\" 2>/dev/null;; *.ts|*.tsx|*.js|*.jsx) npx prettier --write \"$file\" 2>/dev/null;; esac; } || true",
          "timeout": 10
        }]
      }
    ]
  }
}
```

**Prerequisites**: Requires `jq` for JSON parsing (`brew install jq` / `apt install jq`). The `2>/dev/null` and `|| true` suppress errors for non-matching file types; remove them when debugging hook setup.

**Timeout unit**: All hook timeouts are in **seconds** (10 = 10s, default 600s for command hooks).

**Adapt per project**: Replace `ruff format`/`prettier` with project's formatter. Add to project-level `.claude/settings.json`.

**Why not just instructions?** Research shows agents treat "always run lint" as suggestions. PostToolUse hooks are invisible and automatic — the strongest enforcement layer. See [Anthropic best practices](https://www.anthropic.com/engineering/claude-code-best-practices) and [claude-format-hook](https://github.com/ryanlewis/claude-format-hook).

</context>

## Hooks Reference

<context>

**17 hook events** (4 handler types: command, http, prompt, agent):

**Tool lifecycle:**
- PreToolUse — before tool runs; exit 2 = reject
- PostToolUse — after tool succeeds; format, validate
- PostToolUseFailure — after tool fails; recovery

**Session lifecycle:**
- SessionStart — session begins; init, context inject
- SessionEnd — session ends; final cleanup
- Stop — context limit reached; save state
- UserPromptSubmit — user sends message; transform
- InstructionsLoaded — CLAUDE.md/skills loaded
- PreCompact — before context compaction

**Multi-agent:**
- SubagentStart/SubagentStop — subagent lifecycle
- TeammateIdle — teammate awaits task; quality gate
- TaskCompleted — shared task done; exit 2 = reject

**Infrastructure:**
- WorktreeCreate/WorktreeRemove — worktree lifecycle
- Notification — system notification
- PermissionRequest — permission prompt
- ConfigChange — settings.json changed

**Handler types:**
- command — shell script; event JSON on stdin; exit 0=allow, 2=reject
- http — HTTP POST to endpoint; event JSON as body
- prompt — sends text to Claude model (Haiku default)
- agent — spawns subagent with prompt + event JSON

**Config:** `.claude/settings.json` (project) or
`~/.claude/settings.json` (global). Project overrides
global. Matchers filter by tool name. Timeout: command 600s,
prompt 30s, agent 60s (defaults).

Cross-ref: `@smith-plan-claude/SKILL.md` for plan-specific hooks.

</context>

## Permission Modes

<context>

**5 permission modes** (`permissions.defaultMode` in settings):
- `default` — approve each tool call individually
- `acceptEdits` — auto-approves file edits/writes; Bash still requires approval
- `plan` — read-only; agent plans but cannot execute
- `dontAsk` — approve all, persists across sessions (TypeScript SDK)
- `bypassPermissions` — `--dangerously-skip-permissions` flag

**Note:** "Yes, don't ask again" is a per-tool approval behavior (remembered per directory/command), not a global mode. Permission rules (`allow`/`ask`/`deny`) are evaluated deny-first.

**When to use:**
- `plan` for research, architecture review
- `acceptEdits` for trusted execution (tests green)
- `default` for unfamiliar codebases
- `bypassPermissions` for CI/automation only

</context>

## Agent Features

<context>

**Subagents** (`Agent` tool):
- Fresh 200k context per subagent
- `run_in_background: true` for async work
- `isolation: "worktree"` for repo isolation
- `model` parameter overrides model per subagent

**Custom agents** (`/agents` or `.claude/agents/*.md`):
- Frontmatter: model, tools, permissions, memory
- Loaded via `subagent_type` parameter
- Project-scoped or user-scoped (`~/.claude/agents/`)

**Agent Teams** (experimental):
- Enable: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
- Team lead + teammates, independent context each
- `SendMessage` for inter-agent communication
- Shared task list with dependency tracking
- See `@smith-ralph/SKILL.md` Pattern C for full workflow

</context>

## Model Routing

<context>

**Model selection guidance:**
- Opus — orchestration, complex reasoning
- Sonnet — focused subagents, code generation
- Haiku — quick lookups, classification

**Commands:**
- `/model` — switch model mid-session
- `model` param on Agent tool — per-subagent
- `opusplan` alias — Opus for planning

**Cost-aware patterns:**
- Orchestrator (Opus) spawns workers (Sonnet)
- Haiku for repetitive/mechanical subtasks
- Match model to task complexity, not habit

</context>

## CLAUDE.md Persistence

**Location**: `$WORKSPACE_ROOT/.claude/CLAUDE.md` or `$HOME/.claude/CLAUDE.md`

<required>

**Put in CLAUDE.md** (always active):
- Critical guardrails (NEVER/ALWAYS)
- Reference to @AGENTS.md
- Project-specific preferences

**Put in skill files** (context-triggered):
- Detailed technical guidelines
- Platform-specific patterns

</required>

## Tool Search Tool

85% token reduction - tools loaded on-demand, not upfront.

<required>

- Rely on Tool Search for documentation
- Use specific tool names for better retrieval
- Don't request full tool documentation dumps

</required>

## Skills Directory Integration

<context>

**Primary method (symlink, recommended for smith):**

```bash
ln -sf $HOME/.smith $HOME/.claude/skills
```

Claude Code discovers skills at `~/.claude/skills/smith-*/SKILL.md`.
All skills prefixed with "smith-" to avoid conflicts.

**Alternative**: `claude --add-dir /path/to/skills-repo` for
cross-repo sharing (see `@smith-tools/SKILL.md` for details).

</context>

## Claude Code Features

<context>

**Unique capabilities:**
- Web search for current information
- Browser automation for testing
- MCP server integration (including Serena)
- 200k token context window
- Tool Search for on-demand tool loading

</context>

## Auto Memory (Claude Code Native)

<context>

**Claude Code auto memory** stores agent-generated notes at:
`~/.claude/projects/<project-slug>/memory/`

- `MEMORY.md` - First 200 lines auto-loaded every session
- Topic files (e.g. `debugging.md`) - Read on demand
- Browse: `/memory` command
- Disable: `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`

</context>

<required>

**Auto memory vs Serena memory - complementary, not competing:**

**Auto memory** (long-lived project knowledge):
- Project architecture and conventions
- Recurring debugging patterns
- User preferences discovered during sessions
- Build/test/deploy quirks

**Serena memory** (task-scoped continuity):
- Session state (current task, progress, next steps)
- Ralph loop state (iteration, hypotheses, test results)
- Phase boundary checkpoints
- Cross-context-reset continuity

**No sync needed** - different lifecycles, different purposes.
Auto memory accumulates knowledge. Serena handles continuity.

</required>

## Plugin Discovery

<context>

**Available plugin commands:**
- `/code-review` - Automated PR review with 4 parallel agents
- `/commit` - Auto-commit with message generation
- `/commit-push-pr` - Full PR workflow
- `/clean_gone` - Branch cleanup

**Check installed plugins:** `/plugins` or `cat ~/.claude/plugins/installed_plugins.json`

**Official marketplace:** `anthropics/claude-plugins-official`

</context>

<related>

- @smith-ctx/SKILL.md - Universal context strategies
- `@smith-ctx-cursor/SKILL.md` - Cursor IDE context
- `@smith-ctx-kiro/SKILL.md` - Kiro platform context
- `@smith-plan-claude/SKILL.md` - Plan-specific hooks
- `@smith-ralph/SKILL.md` - Orchestration patterns (B/C)
- `@smith-git/SKILL.md` - Git commits, worktrees
- `@smith-prompts/SKILL.md` - Prompt caching optimization
- `@smith-style/SKILL.md` - Commit message conventions, `#WIP` prefix

</related>

## ACTION (Recency Zone)

<required>

**Proactive context management:**
1. At 40-50%: Try "Summarize from here" first
   - Esc+Esc -> select checkpoint -> Summarize
   - Guide: "Focus on [task], [decisions], [file:line refs]"
2. At 50%: Warn, prepare retention criteria
3. At 60%: Commit, update plan, save to Serena, "/clear"
4. After /clear: Plan auto-reloads; check Serena memories

**Agent RECOMMENDS - user executes the command.**

</required>
