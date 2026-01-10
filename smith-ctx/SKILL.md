---
name: smith-ctx
description: Universal context management with proactive recommendations. Agent checks context levels and recommends compaction/summarization to users. Always active as foundation for context optimization.
---

# Context Management

<metadata>

- **Load if**: Always active (context management foundation)
- **Prerequisites**: @smith-guidance/SKILL.md

</metadata>

## CRITICAL: Proactive Context Management (Primacy Zone)

<required>

**Agent role**: Check context levels proactively, RECOMMEND actions to user.

**Context lifecycle**: 0-50% (explore) → 50-70% (monitor) → 70-90% (compact) → 90%+ (emergency)

**To check context**: Prompt "What is the current context usage?" to get percentage.

**Agent RECOMMENDS - user executes** the platform's compaction command.

</required>

## Platform Reference

| Platform | Warning | Critical | Compact | Clear |
|----------|---------|----------|---------|-------|
| Claude Code | 60% | 70-75% | `/compact` | `/clear` |
| Kiro | 70% | 80% | Auto | New session |
| Cursor | 70% | 80% | `/summarize` | New chat |

## Progressive Disclosure

<required>

**Loading order (cheapest first):**
1. **Metadata scan**: Glob/Grep for file locations
2. **Targeted read**: Specific file sections only
3. **Full file**: Only when actively modifying
4. **Broad explore**: Delegate to subagent (isolated context)

</required>

<forbidden>

- NEVER read entire directories without Grep filtering
- NEVER load full files when targeted sections suffice
- NEVER repeat file reads without using context

</forbidden>

## Serena MCP Preference

<required>

**When Serena MCP is available, prefer Serena tools over native tools:**

**Why**: Kiro's `readFile` truncates, `strReplace` fails on duplicates. Serena's regex mode handles complex replacements reliably.

**Tool preference:**
- **Reading**: `search_for_pattern` > `find_symbol` > native `readFile`
- **Writing**: `replace_content` (regex) > `replace_symbol_body` > native `strReplace`
- **Context savings**: 99%+ reduction with symbol-level operations

</required>

## Information Retention

<required>

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

</required>

## Ralph Loop Context Management

<required>

**Ralph burns ~1-3.5k tokens/iteration.** At 70%, persist state to Serena memory before `/compact`.

See `@smith-ralph/SKILL.md` for full context strategy and retention criteria.

</required>

<related>

- @smith-guidance/SKILL.md - Core agent behavior
- `@smith-ctx-claude/SKILL.md` - Claude Code: agent runs `/context`
- `@smith-ctx-cursor/SKILL.md` - Cursor: UI indicator, `/summarize`
- `@smith-ctx-kiro/SKILL.md` - Kiro: 80% auto-summarize, Serena memory
- `@smith-serena/SKILL.md` - Serena MCP for persistent memory

</related>

## ACTION (Recency Zone)

<required>

**Proactive context checks:**
1. Periodically check context (platform-specific method)
2. At warning threshold: Recommend compaction with retention criteria
3. At critical threshold: Urgently recommend before degradation
4. User executes command, agent continues with focused context

**Before recommending compaction, prepare:**
- Task requirements summary
- File paths with line numbers
- Key design decisions
- Remaining todos

**Recommendation format:**
```text
Context at [X]%. Recommend `/compact` (or `/summarize`).
Keep: [task], [files], [decisions], [todos]
```

</required>
