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

**Action**: Always `/clear`. Stop hook uses a KB-based heuristic (`CTX_CONTEXT_THRESHOLD_KB`, default 500KB) to block agent stop when context is high. Uses a one-shot flag pattern: first stop attempt blocked, second allowed.

</required>

<forbidden>

- Using `/compact` (not supported for Claude Code)
- `/clear` without checking uncommitted work

</forbidden>

## /clear - Full Context Reset

<required>

**Before `/clear`:**
1. Commit current work with detailed message
2. Check for uncommitted changes
3. Persist state to Serena memory with `write_memory()`

**Preserved**: Project files, CLAUDE.md
**Lost**: All conversation history

**After `/clear`:**
1. Use `read_memory()` to resume context
2. Re-read relevant files as needed

</required>

## Stop Hook

The `enforce-clear.sh` stop hook blocks the agent from stopping when context is high.

**Behavior:**
- Checks transcript size against `CTX_CONTEXT_THRESHOLD_KB` (default: 500KB, ~60% of 200K)
- Below threshold: allows stop
- Above threshold (first attempt): blocks stop, creates one-shot flag, outputs guidance
- Above threshold (second attempt): flag exists, allows stop

**Coexistence**: Both this hook and the plan-claude stop hook can fire on the same Stop event. Messages are complementary. Both use one-shot flag patterns so a second stop attempt passes both.

**Script**: `smith-ctx-claude/scripts/enforce-clear.sh`

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
1. At 50%: Warn, prepare retention criteria
2. At 60%: Commit work, persist to Serena with `write_memory()`, recommend `/clear` (stop hook enforces)
3. After `/clear`: Use `read_memory()` to resume

**Agent RECOMMENDS - user executes the command.**

</required>
