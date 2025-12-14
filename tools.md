# Tool Configurations

This document defines configuration standards for development tools, IDEs, and external integrations.

## IDE & Extension Settings
- **Global Settings**: `$HOME/Library/Application Support/[Code|Cursor|Kiro]/User/settings.json`
- **Workspace Settings**: `.vscode/settings.json`, `.cursor/settings.json`, `.kiro/settings/`
- **Claude Code**: Same configuration across all IDEs, follow personal coding standards
- **Consistency**: Synchronized extension preferences across all environments

## Pytest Configuration (MANDATORY)
- **Log Level**: `log_cli_level = "WARNING"` in both `pytest.ini` and `pyproject.toml`
- **Purpose**: Suppress INFO/DEBUG logs from external libraries during test execution
- **Exception**: Use DEBUG level only when actively debugging specific issues

**For detailed pytest execution patterns**: See @python.md - Virtual Environment Execution section

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

### MCP Tool Reference

**MCP Tools**:

**Serena MCP**:
- Purpose: Session persistence
- Use for: Multi-session tasks, plan recovery
- Configuration: `.kiro/settings/mcp.json`

**Context7**:
- Purpose: External library documentation
- Use for: Unfamiliar NPM/PyPI packages, API references
- Configuration: MCP settings

**Fetch**:
- Purpose: Web content retrieval
- Use for: User-provided URLs, web documentation
- Configuration: Built-in or MCP

### MCP Best Practices

<required>

- MUST check codebase and local docs first before using MCP tools
- MUST only use MCP tools when task specifically requires them or user requests
- SHOULD activate tools conditionally based on task needs, not by default

</required>

<forbidden>

- NEVER mandate Serena MCP for all plans (only for multi-session tasks)
- NEVER require Context7 for all libraries (only for unfamiliar external ones)
- NEVER load MCP tools unconditionally in every session
- NEVER use MCP tools for simple single-session tasks

</forbidden>

**For MCP server configuration in Kiro**: See @context-kiro.md - MCP Integration for Context Efficiency section

## Configuration Hierarchy
```text
.smith/ (Personal Standards - @-prefixed files auto-load from project context)
├── Project-Level Configurations
│   ├── AGENTS.md (Project overview + references)
│   └── Component-Specific AGENTS.md files (Component details + references)
├── IDE Configurations
│   ├── VS Code: settings.json files
│   ├── Cursor: settings.json files
│   └── Kiro: settings.json and steering files
├── Tool Configurations
│   ├── Serena MCP: mcp.json files
│   └── Claude Code Extensions: extension settings
└── Project Configurations
    ├── .vscode/settings.json
    ├── .cursor/settings.json
    └── .kiro/settings/
```

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

- **Claude Code Patterns**: @context-claude.md - CLAUDE.md configuration, Tool Search Tool
- **Structured Output Patterns**: @steering.md - Structured Output Steering section
- **Python Configuration**: @python.md - Virtual environment execution, pytest patterns
- **IDE Path Variables**: @ide.md - IDE-specific path syntax

</related>
