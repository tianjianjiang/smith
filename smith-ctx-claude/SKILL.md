---
name: smith-ctx-claude
description: Claude Code context management with /clear command and stop hook enforcement at 60%. CLAUDE.md persistence and Tool Search optimization. Use when operating in Claude Code IDE or when context exceeds 50%. Activate for context optimization in Claude sessions.
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
1. Plan auto-reloads with todo reconstruction (if active)
2. If Serena MCP available: call list_memories(), read relevant memories for session state
3. Re-read relevant files as needed

</required>

## Stop Hook (Unified)

Stop hook enforcement is handled by `smith-plan-claude/scripts/enforce-clear.sh`. Uses real token counts from transcript JSONL (same data as Claude Code statusline) to calculate context percentage. A single unified hook covers both plan-active and non-plan contexts:

- **Real percentage**: Blocks at 60% context (from transcript token usage, not byte count)
- **Three branches**: Plan+pending, plan+completed, no-plan (plan filepath shown first, Serena optional)
- **Loop prevention**: Uses `stop_hook_active` field (official best practice)

**Config**: Only one Stop hook entry in `settings.json` (in `smith-plan-claude`).

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
- `@smith-prompts/SKILL.md` - Prompt caching optimization

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
