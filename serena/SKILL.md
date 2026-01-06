---
name: serena
description: Serena MCP integration for reliable file operations and semantic code editing. Activate when Serena MCP is available, for file I/O operations, symbol-level editing, or persistent memory. MANDATORY for Kiro - use Serena tools over native tools.
---

# Serena MCP Integration

<metadata>

- **Load if**: Serena MCP available, file operations needed, symbol-level editing
- **Prerequisites**: None (standalone reference)

</metadata>

## CRITICAL: Tool Preference (Primacy Zone)

<required>

**When Serena MCP is available, MUST use Serena tools over Kiro native tools:**

**Tool Preference Order:**
1. `find_symbol`, `get_symbols_overview` - Reading code (semantic)
2. `search_for_pattern` - Reading with regex patterns
3. `replace_content` (regex mode) - Editing code
4. `replace_symbol_body` - Replacing function/class bodies
5. `find_referencing_symbols` - Navigation
6. `write_memory`, `read_memory` - Persistent context
7. Kiro native tools - **Fallback ONLY when Serena unavailable**

</required>

<forbidden>

**In Kiro, DO NOT use native tools when Serena is available:**
- `readFile` - Silently truncates large files
- `strReplace` - Fails on duplicate content (common in generated code)
- `grepSearch` - Less efficient than Serena pattern search

</forbidden>

## Why Serena Over Kiro Native Tools

<context>

**Kiro native tool issues:**
- `readFile` silently truncates large files
- `strReplace` fails on duplicate content (common in generated code)
- File writes can create duplicate sections
- Mid-operation aborts during file reads/edits

**Serena advantages:**
- Regex mode handles complex replacements reliably
- Symbol-level operations reduce context by 99%+
- Memory files persist across sessions and compaction
- Semantic editing avoids string-matching failures

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

### Reading Files

```python
get_symbols_overview(relative_path, depth)
```
- Get high-level file structure first
- Use `depth=1` for immediate children
- **Use before diving into specific symbols**

```python
find_symbol(name_path_pattern, relative_path, include_body)
```
- Find classes, functions, methods by name
- Use `include_body=true` only when needed
- Supports patterns: `MyClass/get*`, `*/test_*`

```python
search_for_pattern(substring_pattern, relative_path, context_lines_before, context_lines_after)
```
- Use regex patterns to find specific content
- Returns matched lines with context
- Far more efficient than loading entire files

### Writing Files

```python
replace_content(relative_path, needle, repl, mode)
```
- `mode="regex"` for pattern matching (preferred)
- `mode="literal"` for exact string match
- Use `.*?` for non-greedy wildcards
- Set `allow_multiple_occurrences=true` if needed

```python
replace_symbol_body(name_path, relative_path, body)
```
- Replace entire function/class body
- Body includes signature line
- Does NOT include preceding docstrings/imports

```python
insert_after_symbol(name_path, relative_path, body)
insert_before_symbol(name_path, relative_path, body)
```
- Add new functions, methods, imports
- Content starts on next line after symbol

### Navigation

```python
find_referencing_symbols(name_path, relative_path)
```
- Find all references to a symbol
- More accurate than text search

## Memory Workflow

<required>

**Memory files persist across sessions and compaction.**

**Location**: `.serena/memories/`

**Session Start:**
1. `list_memories()` - See available context
2. `read_memory(memory_file_name)` - Load relevant memories

**During Work:**
- `write_memory(memory_file_name, content)` - Save important discoveries
- Use descriptive names: `project_overview.md`, `session_summary.md`

**Before Compaction (at 70% context):**
- `write_memory()` - Save session state and progress

**Session End:**
- `write_memory()` - Save continuity notes for next session

**Memory Naming Conventions:**
- `project_overview.md` - High-level project context
- `session_summary.md` - Current session progress
- `{feature}_notes.md` - Feature-specific context
- `task_completion.md` - Completed task tracking

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

- If successful: Serena is available, use Serena tools
- If fails: Fall back to Kiro native tools with caution

</required>

## ACTION (Recency Zone)

<required>

**Before file operations in Kiro:**

1. Check if Serena MCP is available (`list_memories()` as test)
2. If available, use Serena tools (see preference order above)
3. If unavailable, fall back to Kiro native tools with caution
4. For large files, always prefer `search_for_pattern` over `readFile`

**Workflow for edits:**
1. `get_symbols_overview` to understand structure
2. `find_symbol` to locate target
3. `replace_symbol_body` or `replace_content` for changes
4. `write_memory` to persist important context

</required>

<related>

- `@context-kiro/SKILL.md` - Kiro terminal limitations, tool issues
- `@context/SKILL.md` - Context management thresholds
- @guidance/SKILL.md - AI agent behavior patterns

</related>
