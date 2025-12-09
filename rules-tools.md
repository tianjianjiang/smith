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

## MCP Tool Integration (Optional)

<context>

MCP (Model Context Protocol) tools provide enhanced capabilities for specific scenarios. Use them conditionally when their specific functionality is needed.

**These tools are NOT required** for standard development work.

</context>

### Available MCP Tools

**Serena MCP - Session Persistence**:
- **Purpose**: Persist plans and context across sessions
- **Use for**: Complex multi-session tasks, plan recovery, session restarts
- **Configuration**: `.kiro/settings/mcp.json` or IDE settings
- **Avoid**: Single-session tasks, simple bug fixes

**Context7 - External Library Documentation**:
- **Purpose**: Fetch documentation for external libraries
- **Use for**: Unfamiliar NPM/PyPI packages, external API references
- **Configuration**: MCP settings
- **Avoid**: Libraries already in codebase, standard library usage

**Fetch/WebFetch - Web Content Retrieval**:
- **Purpose**: Retrieve web content from URLs
- **Use for**: User-provided URLs, web documentation explicitly requested
- **Configuration**: Use WebFetch tool if available
- **Avoid**: Content available locally, speculative browsing

### MCP Tool Reference

| Tool | Purpose | When to Use | Configuration |
|------|---------|-------------|---------------|
| **Serena MCP** | Session persistence | Multi-session tasks, plan recovery | `.kiro/settings/mcp.json` |
| **Context7** | External library docs | Unfamiliar libraries, API references | MCP settings |
| **Fetch** | Web content retrieval | User-provided URLs, web documentation | Built-in or MCP |

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

## Claude Code Patterns

<context>

**Context**: Project-level Claude Code configuration

</context>

### Slash Commands

**Location**: `.claude/commands/` in project root

**Pattern**: Markdown files with prompts
```markdown
# .claude/commands/review.md
Review the code changes in the current branch and provide feedback on:
- Code quality and style
- Potential bugs or security issues
- Performance considerations
- Test coverage

Follow standards in @rules-*.md
```

**Usage**: `/review` in Claude Code

**Best practices**:
- Reference personal standards with @rules-*.md
- Keep commands focused and single-purpose
- Include context about what to analyze
- Specify output format if needed

### MCP Server Configuration

**Location**: `.claude/mcp.json` or global Claude Code settings

**Pattern**: JSON configuration for Model Context Protocol servers
```json
{
  "mcpServers": {
    "serena": {
      "command": "mcp-server-serena",
      "args": ["--workspace", "/path/to/workspace"]
    }
  }
}
```

**Common MCP servers**:
- **serena**: Symbol-level code navigation and editing
- **filesystem**: File operations
- **git**: Git repository operations
- **web**: Web search and fetch capabilities

**See**: MCP Tool Integration section above for MCP usage guidelines

## Structured Output Patterns

<context>

**Context**: Agent-generated structured content

</context>

### Code Generation Schema

**Use case**: Requesting complete implementations from agents

**Pattern**:
```markdown
Generate user authentication module with structured output:
- `code`: Complete implementation code
- `tests`: Array of test cases
- `dependencies`: Required packages/imports
- `migration`: Database schema changes (if applicable)

Follow project patterns in auth/ directory.
```

### Code Analysis Schema

**Use case**: Requesting code reviews or analysis

**Pattern**:
```markdown
Analyze this function for issues:
- `issues`: Array of {severity, location, description, suggestion}
- `metrics`: {complexity, maintainability_score}
- `recommendations`: Array of improvement suggestions

Return structured JSON for tooling integration.
```

### Test Generation Schema

**Use case**: Requesting test suites

**Pattern**:
```markdown
Generate tests for authentication service:
- `unit_tests`: Array of {name, description, assertions}
- `integration_tests`: Array of {name, setup, scenario, expected}
- `edge_cases`: Array of {case, rationale}

Follow test patterns in tests/unit/ and tests/integration/.
```

**Platform compatibility**:
- OpenAI: Use `strict: true` for 100% schema compliance
- Anthropic: Best-effort compliance (very high accuracy)
- Google Gemini: Use responseSchema for guided generation

**See**: @rules-ai_agents.md - Structured output steering section

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
