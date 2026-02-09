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

**Agent prompts for context status**, then recommends action to user.

**Thresholds**: 50% warning, 60% critical

**Action**: Always `/clear`. Stop hook enforcement is handled by the unified `smith-plan-claude` stop hook, which covers both plan-active and non-plan contexts. Uses `stop_hook_active` (official best practice) instead of one-shot flags.

</required>

<forbidden>

- Using `/compact` (not supported for Claude Code)
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

**Enable skill discovery:**
```shell
ln -sf $HOME/.smith $HOME/.claude/skills
```

Claude Code discovers skills matching your tasks and asks before loading.

All skills prefixed with "smith-" to avoid conflicts with 50+ built-in commands.

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
1. At 50%: Warn, prepare retention criteria (advisory from inject-plan.sh)
2. At 60%: Commit work, update plan, save state to Serena (`session_<CWD_KEY>`), then AFTER all tool calls output self-contained "Reload with:" block, recommend `/clear` (stop hook blocks)
3. After `/clear`: Plan auto-reloads; check Serena memories via list_memories()

**Agent RECOMMENDS - user executes the command.**

</required>
