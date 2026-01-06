---
name: tools
description: Tool configurations for IDEs, MCP integrations, and development tools. Use when configuring IDE settings, MCP tools, or pytest. Covers conditional tool activation, configuration hierarchy, and synchronization patterns.
---

# Tool Configurations

<metadata>

- **Scope**: Configuration standards for development tools, IDEs, and MCP integrations
- **Load if**: Writing/editing IDE config files (.vscode/, .kiro/, .cursor/) OR configuring MCP tools
- **Prerequisites**: @principles/SKILL.md, @standards/SKILL.md

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

**For detailed pytest execution patterns**: See @python/SKILL.md - Virtual Environment Execution section

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

**For MCP server configuration in Kiro**: See @context-kiro/SKILL.md - MCP Integration for Context Efficiency section

## Configuration Hierarchy

- `.smith/` (Personal Standards - @-prefixed files auto-load from project context)
- Project-Level Configurations: AGENTS.md files
- IDE Configurations: VS Code, Cursor, Kiro settings
- Tool Configurations: Serena MCP, Claude Code Extensions
- Project Configurations: `.vscode/`, `.cursor/`, `.kiro/settings/`

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

- **Claude Code Patterns**: @context-claude/SKILL.md - CLAUDE.md configuration, Tool Search Tool
- **Structured Output Patterns**: @prompts/SKILL.md - Structured Output Steering section
- **Python Configuration**: @python/SKILL.md - Virtual environment execution, pytest patterns
- **IDE Path Variables**: @ide/SKILL.md - IDE-specific path syntax

</related>

## ACTION (Recency Zone)

<required>

**Before using MCP tools:**
1. Check codebase and local docs first
2. Use MCP only when local info insufficient
3. Configure tools conditionally per task

</required>
