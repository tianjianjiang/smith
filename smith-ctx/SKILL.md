---
name: smith-ctx
description: Universal context-management foundation — proactive context-level checks and reset recommendations. Use when context usage grows high, when deciding whether to /clear or /compact, or when choosing what to retain across a context reset.
---

# Context Management

**Load if:** Always active (context management foundation)
**Prerequisites:** @smith-guidance/SKILL.md

## Proactive Context Management

**Agent role**: Check context levels proactively, RECOMMEND actions to user.

**Context lifecycle**: explore → monitor → prepare (at warning threshold) → reset (at critical threshold)

**To check context**: Prompt "What is the current context usage?" to get percentage.

**Agent RECOMMENDS - user executes** the platform's context reset command.

## Platform Reference

- **Claude Code**: Warning 50%, Critical 60%,
  Targeted: "Summarize from here" (Esc+Esc),
  Action: `/clear` (stop hook enforced)
- **Kiro**: Warning 70%, Critical 80%, Compact Auto, Clear New session
- **Cursor**: Warning 70%, Critical 80%, Compact `/summarize`, Clear New chat

## Progressive Disclosure

**Loading order (cheapest first):**
1. **Metadata scan**: Glob/Grep for file locations
2. **Targeted read**: Specific file sections only
3. **Full file**: Only when actively modifying
4. **Broad explore**: Delegate to subagent (isolated context)

**Rules:**
- Filter with Grep before reading entire directories
- Load targeted sections instead of full files when they suffice
- Reuse context from files already read instead of re-reading them

## Serena MCP Preference

**When Serena MCP is available, prefer Serena tools over native tools:**

**Why**: Kiro's `readFile` truncates, `strReplace` fails on duplicates. Serena's regex mode handles complex replacements reliably.

**Tool preference:**
- **Reading**: `search_for_pattern` > `find_symbol` > native `readFile`
- **Writing**: `replace_content` (regex) > `replace_symbol_body` > native `strReplace`
- **Context savings**: 99%+ reduction with symbol-level operations

## Information Retention

**Always preserve:**
- Task goals
- File:line locations
- Architectural decisions
- Incomplete work

**Always discard:**
- Verbose tool outputs
- Failed explorations
- Redundant file reads

**Reference format**: Use `file:line` (e.g., `auth.ts:234`) instead of embedding content

## Ralph Loop Context Management

**Ralph burns ~1-3.5k tokens/iteration.** At critical threshold, persist state to Serena memory before context reset.

See `@smith-ralph/SKILL.md` for full context strategy and retention criteria.

## Related

- @smith-guidance/SKILL.md - Core agent behavior
- `@smith-ctx-claude/SKILL.md` - Claude Code: `/clear` (stop hook enforced)
- `@smith-ctx-cursor/SKILL.md` - Cursor: UI indicator, `/summarize`
- `@smith-ctx-kiro/SKILL.md` - Kiro: 80% auto-summarize, Serena memory
- `@smith-serena/SKILL.md` - Serena MCP for persistent memory

## Before You Finish

**Proactive context checks:**
1. Periodically check context (platform-specific method)
2. At warning threshold: Recommend context reset with retention criteria
3. At critical threshold: Urgently recommend before degradation
4. User executes command, agent continues with focused context

**Before recommending context reset, prepare:**
- Task requirements summary
- File paths with line numbers
- Key design decisions
- Remaining todos

**Recommendation format:**
```text
Context at «X»%. Recommend context reset (see platform skill for command).
Keep: «task», «files», «decisions», «todos»
```
