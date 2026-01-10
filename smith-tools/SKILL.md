---
name: smith-tools
description: Tool configurations for IDEs, MCP integrations, and development tools. Use when configuring IDE settings, MCP tools, or pytest. Covers conditional tool activation, configuration hierarchy, and synchronization patterns.
---

# Tool Configurations

<metadata>

- **Scope**: Configuration standards for development tools, IDEs, and MCP integrations
- **Load if**: Writing/editing IDE config files (.vscode/, .kiro/, .cursor/) OR configuring MCP tools
- **Prerequisites**: @smith-principles/SKILL.md, @smith-standards/SKILL.md

</metadata>

## CRITICAL: Tool Configuration (Primacy Zone)

<required>

- Check codebase and local docs BEFORE using MCP tools
- Use MCP tools only when task specifically requires them
- Activate tools conditionally, not by default

</required>

<forbidden>

- Mandating Serena MCP for all plans (only multi-session)
- Requiring Context7 for all libraries (only unfamiliar external)
- Loading MCP tools unconditionally

</forbidden>

<context>

This document defines configuration standards for development tools, IDEs, and external integrations.

</context>

## IDE & Extension Settings

- **Global Settings**: `$HOME/Library/Application Support/[Code|Cursor|Kiro]/User/settings.json`
- **Workspace Settings**: `.vscode/settings.json`, `.cursor/settings.json`, `.kiro/settings/`
- **Claude Code**: Same configuration across all IDEs, follow personal coding standards
- **Consistency**: Synchronized extension preferences across all environments

## Pytest Configuration (MANDATORY)

- **Log Level**: `log_cli_level = "WARNING"` in both `pytest.ini` and `pyproject.toml`
- **Purpose**: Suppress INFO/DEBUG logs from external libraries during test execution
- **Exception**: Use DEBUG level only when actively debugging specific issues

**For detailed pytest execution patterns**: See `@smith-python/SKILL.md#action-recency-zone`

## MCP Tool Integration (Optional)

<context>

MCP (Model Context Protocol) tools provide enhanced capabilities for specific scenarios. Use them conditionally when their specific functionality is needed.

**These tools are NOT required** for standard development work.

</context>

### Available MCP Tools

**Serena MCP - Session Persistence**:
- Purpose: Persist plans and context across sessions
- Use for: Complex multi-session tasks, plan recovery, session restarts
- Configuration: `.kiro/settings/mcp.json` or IDE settings
- Avoid: Single-session tasks, simple bug fixes

**Context7 - External Library Documentation**:
- Purpose: Fetch documentation for external libraries
- Use for: Unfamiliar NPM/PyPI packages, external API references
- Configuration: MCP settings
- Avoid: Libraries already in codebase, standard library usage

**Fetch/WebFetch - Web Content Retrieval**:
- Purpose: Retrieve web content from URLs
- Use for: User-provided URLs, web documentation explicitly requested
- Configuration: Use WebFetch tool if available
- Avoid: Content available locally, speculative browsing

**For MCP server configuration in Kiro**: See `@smith-ctx-kiro/SKILL.md#critical-serena-mcp-is-mandatory`

## Configuration Hierarchy

- `$HOME/.smith/` - Global personal standards (symlinked to projects)
- `AGENTS.md` - Project-level agent instructions
- `.vscode/`, `.cursor/`, `.kiro/settings/` - IDE-specific configs
- MCP tool configs - Serena, Context7, etc.

## Synchronization Points

- **IDE Settings**: Automatically sync from master documents
- **Project Files**: Reference personal standards instead of duplicating
- **Optional Tools**: Configure MCP tools conditionally based on task needs
- **Tool Extensions**: Apply these standards in all generated content

## Update Workflow

1. **Master Update**: Modify authoritative documents
2. **Automatic Sync**: Run synchronization script to update all tool configurations
3. **Validation**: Verify consistency across all tools and configurations
4. **Documentation**: Update project-specific documentation with references

<related>

- `@smith-ctx-claude/SKILL.md` - Claude Code patterns
- `@smith-prompts/SKILL.md` - Structured output patterns
- `@smith-python/SKILL.md` - Virtual environment, pytest patterns
- `@smith-ide/SKILL.md` - IDE-specific path syntax

</related>

## ACTION (Recency Zone)

<required>

**Before using MCP tools:**
1. Check codebase and local docs first
2. Use MCP only when local info insufficient
3. Configure tools conditionally per task

</required>
