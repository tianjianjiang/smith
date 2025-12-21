# Serena MCP Integration

<metadata>

- **Load if**: Serena MCP available, file operations needed, symbol-level editing
- **Prerequisites**: None (standalone reference)

</metadata>

## CRITICAL: Tool Preference (Primacy Zone)

<required>

**When Serena MCP is available, prefer Serena tools over Kiro native tools:**

- **Reading**: `search_for_pattern` > `find_symbol` > Kiro `readFile`
- **Writing**: `replace_content` (regex) > `replace_symbol_body` > Kiro `strReplace`
- **Navigation**: `find_symbol` > `find_referencing_symbols` > Kiro `grepSearch`
- **Memory**: `write_memory` / `read_memory` for persistent context

</required>

## Why Serena Over Kiro Tools

<context>

**Kiro native tool issues:**
- `readFile` truncates large files without warning
- `strReplace` fails on duplicate content (common in generated code)
- File writes can create duplicate sections
- Mid-operation aborts during file reads/edits

**Serena advantages:**
- Regex mode handles complex replacements reliably
- Symbol-level operations reduce context by 99%+
- Memory files persist across sessions and compaction
- Semantic editing avoids string-matching failures

</context>

## Core Serena Tools

### Reading Files

```
search_for_pattern(substring_pattern, relative_path, context_lines_before, context_lines_after)
```
- Use regex patterns to find specific content
- Returns matched lines with context
- Far more efficient than loading entire files

```
find_symbol(name_path_pattern, relative_path, include_body)
```
- Find classes, functions, methods by name
- Use `include_body=true` only when needed
- Supports glob patterns: `MyClass/get*`

```
get_symbols_overview(relative_path, depth)
```
- Get high-level file structure
- Use before diving into specific symbols
- `depth=1` for immediate children

### Writing Files

```
replace_content(relative_path, needle, repl, mode)
```
- `mode="regex"` for pattern matching (preferred)
- `mode="literal"` for exact string match
- Use `.*?` for non-greedy wildcards
- Set `allow_multiple_occurrences=true` if needed

```
replace_symbol_body(name_path, relative_path, body)
```
- Replace entire function/class body
- Body includes signature line
- Does NOT include preceding docstrings/imports

```
insert_after_symbol(name_path, relative_path, body)
insert_before_symbol(name_path, relative_path, body)
```
- Add new functions, methods, imports
- Content starts on next line after symbol

### Navigation

`find_referencing_symbols(name_path, relative_path)` - Find all references to a symbol

## Memory Files

**Location**: `.serena/memories/`

**Tools**: `write_memory`, `read_memory`, `list_memories`, `edit_memory`, `delete_memory`

**Use for**: Session summaries, project context

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

**Docs projects:** `language: markdown`

## ACTION (Recency Zone)

<required>

**Before file operations in Kiro:**

1. Check if Serena MCP is available (`list_memories()` as test)
2. If available, use Serena tools (see preference order above)
3. If unavailable, fall back to Kiro native tools with caution
4. For large files, always prefer `search_for_pattern` over `readFile`

</required>

**Workflow for edits:**
1. `find_symbol` to locate target
2. `get_symbols_overview` if structure unclear
3. `replace_symbol_body` or `replace_content` for changes
4. `write_memory` to persist important context

<related>

- **Kiro-specific**: @context-kiro.md (terminal limitations, tool issues)
- **Context management**: @context.md (thresholds, compaction)
- **Agent behavior**: @guidance.md (AI patterns)

</related>
