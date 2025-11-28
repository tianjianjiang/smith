# Tool Configurations

<metadata>
**Scope**: IDE, Editor, and Tool configurations
**Load if**: Configuring IDEs (VS Code, Cursor, Kiro) or setting up tools
**Prerequisites**: None
</metadata>

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

## MCP & Steering (Optional)
- **MCP Tools**: See `$HOME/.smith/rules-tools-mcp.md` for optional MCP tool usage
- **Kiro Steering**: `.kiro/steering/` with `#[[file:<relative_file_name>]]` pattern
- **Standards**: Follow personal coding standards, auto-approve common operations

## Configuration Hierarchy
```
$HOME/.smith/ (Personal Standards)
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
- **Optional Tools**: Configure MCP tools per `rules-tools-mcp.md` when needed
- **Tool Extensions**: Apply these standards in all generated content

## Update Workflow
1. **Master Update**: Modify authoritative documents
2. **Automatic Sync**: Run synchronization script to update all tool configurations
3. **Validation**: Verify consistency across all tools and configurations
4. **Documentation**: Update project-specific documentation with references
