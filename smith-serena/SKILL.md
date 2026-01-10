---
name: smith-serena
description: Serena MCP integration for file I/O, semantic code editing, and persistent memory. ALWAYS use Serena for file operations and language server features when available. Proactively sync memories at phase/todo/session boundaries.
---

# Serena MCP Integration

<metadata>

- **Load if**: Serena MCP available, file operations needed, symbol-level editing
- **Prerequisites**: None (standalone reference)

</metadata>

## CRITICAL: Serena-First Principle (Primacy Zone)

<required>

**When Serena MCP is available, ALWAYS use Serena for:**

1. **File I/O** - All file reading and writing operations
2. **Language server features** - Symbols, references, navigation, semantic editing
3. **Persistent memory** - Cross-session and cross-compaction context

**Tool Preference Order:**
1. `find_symbol`, `get_symbols_overview` - Reading code (semantic)
2. `search_for_pattern` - Reading with regex patterns
3. `replace_content` (regex mode) - Editing code
4. `replace_symbol_body` - Replacing function/class bodies
5. `find_referencing_symbols` - Navigation, impact analysis
6. `write_memory`, `read_memory` - Persistent context
7. Platform native tools - **Fallback ONLY when Serena unavailable**

</required>

<forbidden>

**DO NOT use platform native tools when Serena is available:**
- Native file read tools may truncate large files silently
- String-based replace tools fail on duplicate content
- Text-based search is less efficient than semantic search

</forbidden>

## Why Serena Over Native Tools

<context>

**Serena advantages:**
- Semantic symbol operations reduce context usage by 99%+
- Regex mode handles complex replacements reliably
- Memory files persist across sessions and compaction
- Language server integration provides accurate navigation
- No silent truncation or string-matching failures

</context>

## Serena Activation Workflow

<required>

**At session start, MUST activate Serena:**

1. `activate_project()` - Activate the project
2. `check_onboarding_performed()` - Verify onboarding status
3. `list_memories()` - Discover available context
4. `read_memory()` - Load relevant project context

**If onboarding not performed:**
- Call `onboarding()` to get instructions
- Follow onboarding steps before proceeding

</required>

## Core Serena Tools

### Reading

- `get_symbols_overview(path, depth=1)` - File structure first
- `find_symbol(pattern, path, include_body=false)` - Locate symbols (`MyClass/get*`)
- `search_for_pattern(regex, path)` - Content search with context

### Writing

- `replace_content(path, needle, repl, mode="regex")` - Pattern replace
- `replace_symbol_body(name, path, body)` - Replace function/class (includes signature)
- `insert_after_symbol` / `insert_before_symbol` - Add new code

### Navigation

- `find_referencing_symbols(name, path)` - All references to symbol

## Proactive Memory Workflow

<required>

**Memory files persist across sessions and compaction. Sync proactively at boundaries.**

**Location**: `.serena/memories/`

**Session Start:**
1. `list_memories()` - Discover available context
2. `read_memory()` - Load `project_overview`, `session_summary`, relevant task memories

**Phase/Todo Boundaries (PROACTIVE):**
- **Before starting phase/todo**: `read_memory()` for relevant context
- **After completing phase/todo**: `write_memory()` with findings, decisions, blockers
- **On status change**: Update `task_completion` memory with progress

**Before Compaction (at 70% context):**
- `write_memory()` - Save full session state, current task, next steps

**Session End:**
- `write_memory()` - Continuity notes: what was done, what's next, blockers

**Memory Naming Conventions:**
- `project_overview` - High-level project context (read at start)
- `session_summary` - Current session progress (update frequently)
- `task_completion` - Completed task tracking (update on todo completion)
- `{feature}_notes` - Feature-specific context
- `{task}_context` - Task-specific discoveries and decisions

</required>

## Project Configuration

**Location**: `.serena/project.yml`

### Standard Project

```yaml
project_name: my_project
language: python  # or typescript, java, etc.
```

### Documentation Project (No Code)

```yaml
project_name: my_docs
language: markdown
```

<required>

**For projects with no code files**, specify `language: markdown` explicitly to avoid onboarding errors.

</required>

## Testing Serena Availability

<required>

**To verify Serena MCP is available:**

```python
list_memories()
```

- If successful: Serena is available, use Serena tools exclusively
- If fails: Fall back to platform native tools with caution

</required>

## ACTION (Recency Zone)

<required>

**Serena-first for all file operations:**

1. Test availability: `list_memories()`
2. Use Serena tools for file I/O and language server features
3. Fall back to platform native tools ONLY if Serena unavailable

**Workflow for code tasks:**
1. `read_memory()` - Load relevant context before starting
2. `get_symbols_overview` - Understand file structure
3. `find_symbol` - Locate target symbols
4. `replace_symbol_body` or `replace_content` - Make changes
5. `write_memory()` - Persist discoveries after completing

**Periodic memory sync:**
- Phase start → `read_memory()`
- Phase end → `write_memory()`
- Todo start → `read_memory()` if context needed
- Todo complete → `write_memory()` with findings

</required>

## Ralph Loop Memory Integration

<required>

**Serena persists Ralph state**: `ralph_[task]_state` with iteration, hypotheses, test_results, next_action.

**Sync**: After each iteration; before/after compaction. See `@smith-ralph/SKILL.md`.

</required>

<related>

- @smith-ctx/SKILL.md - Context management thresholds (70% compaction trigger)
- @smith-guidance/SKILL.md - AI agent behavior patterns
- `@smith-ctx-kiro/SKILL.md` - Kiro-specific: Serena is MANDATORY over native tools

</related>
