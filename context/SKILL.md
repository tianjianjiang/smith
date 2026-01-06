---
name: context
description: Universal context management strategies including lifecycle phases, platform thresholds, progressive disclosure, and Serena MCP preference. Use when context approaches capacity (>70%) or optimizing context usage across any AI coding platform.
---

# Context Management

<metadata>

- **Load if**: Context approaching capacity (>70%), optimizing context usage
- **Prerequisites**: @guidance/SKILL.md

</metadata>

## CRITICAL (Primacy Zone)

<required>

**Context lifecycle**: 0-50% (explore) → 50-70% (monitor) → 70-90% (compact) → 90%+ (emergency)

**Take action at your platform's Warning threshold** to maintain control over what's retained.

</required>

## Platform Thresholds

**Claude Code**:
- Warning: 60%
- Critical: 70-75%
- Auto-Action: `/compact` at 95%

**Kiro**:
- Warning: 70%
- Critical: 80%
- Auto-Action: Auto-summarize

**Cursor**:
- Warning: 70%
- Critical: 80%
- Auto-Action: `/summarize`

## Compaction Commands

**Claude Code**:
- Inspect: `/context`
- Compact: `/compact`
- Clear: `/clear`

**Kiro**:
- Inspect: Context meter
- Compact: Auto at 80%
- Clear: New session

**Cursor**:
- Inspect: UI indicator
- Compact: `/summarize`
- Clear: New chat

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

<related>

- @guidance/SKILL.md - Core agent behavior
- `@prompts/SKILL.md` - Prompt caching optimization
- `@context-claude/SKILL.md` - Claude-specific context patterns
- `@context-kiro/SKILL.md` - Kiro-specific context patterns
- `@context-cursor/SKILL.md` - Cursor-specific context patterns

</related>

## ACTION (Recency Zone)

<required>

**At 70% capacity:**
1. User reports context level
2. Agent recommends retention criteria
3. User executes compact command
4. Continue with focused context

**Before compaction, preserve:**
- Task requirements
- File paths with line numbers
- Design decisions
- Remaining todos

</required>
