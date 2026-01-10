---
name: smith-ctx-claude
description: Claude Code context management with /compact and /clear commands, CLAUDE.md persistence, and Tool Search optimization. Use when operating in Claude Code IDE or when context exceeds 60%. Activate for context optimization in Claude sessions.
---

# Claude Code Context Management

<metadata>

- **Load if**: Using Claude Code, context >60%
- **Prerequisites**: @smith-ctx/SKILL.md

</metadata>

## CRITICAL: Context Commands (Primacy Zone)

<required>

**Agent prompts for context status**, then recommends action to user.

**Thresholds:**
- 60%: Recommend `/compact` with retention criteria
- 70%: Warn of degradation risk, prepare criteria urgently
- 90%: Recommend `/clear` or aggressive compaction

**Decision tree:**
- Same task, need space → `/compact keep [specifics]`
- New unrelated task → commit first, then `/clear`
- Dead ends only → document failures, `/clear`

</required>

## /compact - Selective Retention

**Syntax**: `/compact keep [retention criteria]`

<required>

**Always specify what to keep:**
- Task goals and requirements
- File paths with line numbers (file:line)
- Architectural decisions
- Incomplete todos/next steps

**Recommendation format:**
```text
/compact keep task requirements, files (auth.ts:234, tokens.ts:89), 
design decisions, remaining todos
```

</required>

<forbidden>

- Claiming to execute `/compact` directly (user must run it)
- Vague criteria like "important stuff"
- Compacting away file:line references
- Compacting away incomplete work

</forbidden>

## /clear - Full Reset

**Use when**: Switching to unrelated task after committing work

<required>

**Before /clear:**
1. Commit current work with detailed message
2. Check for uncommitted changes
3. Document session state

**Preserved**: Project files, CLAUDE.md
**Lost**: All conversation history

</required>

<forbidden>

- `/clear` without checking uncommitted work
- `/clear` mid-task (use `/compact` instead)
- `/clear` when context <90%

</forbidden>

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
1. Prompt for context status
2. At 60%: Recommend `/compact` with retention criteria
3. At 70%: Warn of degradation, prepare criteria urgently
4. At 90%: Recommend `/clear` or aggressive compaction

**Agent RECOMMENDS - user executes the command.**

**Workflow:**
1. Periodically prompt for context usage percentage
2. Prepare retention criteria before hitting limits
3. Recommend action with specific criteria
4. Commit frequently for session recovery

</required>
