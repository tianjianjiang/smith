# Context Management

<metadata>

- **Load if**: Context approaching capacity (>70%), optimizing context usage
- **Prerequisites**: @guidance.md

</metadata>

## CRITICAL (Primacy Zone)

**Context lifecycle**: 0-50% (explore) → 50-70% (monitor) → 70-90% (compact) → 90%+ (emergency)

**Take action at your platform's Warning threshold** (see Platform Thresholds below) to maintain control over what's retained. The 70% guideline is approximate; use platform-specific thresholds for precise action timing.

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

## Serena MCP Preference

When Serena MCP is available, prefer Serena tools over Kiro native tools:

**Why**: Kiro's `readFile` truncates, `strReplace` fails on duplicates. Serena's regex mode handles complex replacements reliably.

**Tool preference**:
- **Reading**: `search_for_pattern` > `find_symbol` > Kiro `readFile`
- **Writing**: `replace_content` (regex) > `replace_symbol_body` > Kiro `strReplace`
- **Context savings**: 99%+ reduction with symbol-level operations

## Progressive Disclosure

1. **Metadata scan**: Glob/Grep for file locations (cheapest)
2. **Targeted read**: Specific file sections only
3. **Full file**: Only when actively modifying
4. **Broad explore**: Delegate to subagent (isolated context)

<forbidden>

- NEVER read entire directories without Grep filtering
- NEVER load full files when targeted sections suffice
- NEVER repeat file reads without using context

</forbidden>

## Information Retention

**Always preserve**: Task goals, file:line locations, architectural decisions, incomplete work
**Always discard**: Verbose tool outputs, failed explorations, redundant file reads

<related>

- @guidance.md - Core agent behavior
- @prompts.md - Prompt caching optimization
- @context-claude.md - Claude-specific context patterns
- @context-kiro.md - Kiro-specific context patterns
- @context-cursor.md - Cursor-specific context patterns

</related>

## ACTION (Recency Zone)

**At 70% capacity**:
1. User reports context level
2. Agent recommends retention criteria
3. User executes compact command
4. Continue with focused context

**Reference format**: Use `file:line` (e.g., `auth.ts:234`) instead of embedding content
