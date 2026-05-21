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
- **Claude Code**: Same configuration across all IDEs, follow skill standards
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

**Browser MCP plugins (chrome-devtools-mcp, @playwright/mcp)**:
- Purpose: Drive a real browser via Chrome DevTools Protocol
- Configuration: Browser-channel choice is constrained — default to Chrome for Testing for chrome-devtools-mcp; bundled Chromium for Playwright MCP
- Avoid: `--executablePath` pointing at Vivaldi / Edge / consumer Chrome — see `@smith-browser-mcp/SKILL.md`

**For MCP server configuration in Kiro**: See `@smith-ctx-kiro/SKILL.md#critical-serena-mcp-is-mandatory`

## MCP Server Lifecycle

<context>

**Installation:**

```shell
claude mcp add --transport stdio --scope user server-name -- command args
```

**Option ordering matters**: all flags (`--transport`, `--env`, `--scope`, `--header`) must come **before** the server name; `--` (double dash) separates the server name from the command + args passed to the server. Wrong ordering causes flag conflicts.

**Scopes** (set via `--scope`):
- `local` (default) — current project, just you (was `project` in older versions); written to `~/.claude.json` per-project section
- `project` — shared with team via `.mcp.json` at repo root
- `user` — across all your projects (was `global` in older versions); written to `~/.claude.json` top-level

**Transports** in `.mcp.json` / `claude mcp add-json`:
- `stdio` — local process spawned by Claude Code; ideal for tools needing direct system access
- `http` (alias `streamable-http`) — remote HTTP server
- `sse` — Server-Sent Events; **deprecated**, prefer `http`

**Discovery + management:**

```shell
claude mcp list
claude mcp get <name>
claude mcp remove <name>
```

In-session: `/mcp` shows tool count per server, flags servers advertising the tools capability but exposing none, and authenticates remote OAuth 2.0 servers.

**Env vars affecting MCP runtime:**
- `MCP_TIMEOUT=10000 claude` — raise startup timeout (default low; bump for slow servers)
- `MAX_MCP_OUTPUT_TOKENS=50000` — raise per-tool-call output cap (default warns at 10k)

**Path variables in server config:**
- `${CLAUDE_PROJECT_DIR}` — project root. Set in the spawned server's env; in user/project `.mcp.json` use `${CLAUDE_PROJECT_DIR:-.}` (with default) since shell expansion doesn't see it
- `${CLAUDE_PLUGIN_ROOT}` — plugin asset root; only in plugin-provided MCP configs

**Server-connecting waits:** Claude waits for in-flight server connections before running tools that need them. With tool search enabled (default), the wait happens inside `ToolSearch`; otherwise (Vertex AI, custom `ANTHROPIC_BASE_URL`, `ENABLE_TOOL_SEARCH=false`) `WaitForMcpServers` is used.

**Debugging failures:**
- Check logs: `~/.claude/logs/mcp-*.log`
- Startup timeout → raise `MCP_TIMEOUT`
- Restart: remove + re-add the server, or restart the Claude Code session
- Config reload: restart session after edits to `.mcp.json` or settings (MCP server list isn't hot-reloaded)

**Common issues:**
- Server not found → verify command path is absolute
- Permission denied → check executable permissions
- Startup timeout → increase `MCP_TIMEOUT`
- Option ordering → flags before server name, `--` before server command

</context>

## Plugin Marketplaces

<context>

A **marketplace** is a catalog at `.claude-plugin/marketplace.json` listing plugins. Anyone can host one (git repo, local path, URL); the smith-* ecosystem treats `anthropics/claude-plugins-official` as the canonical official marketplace.

**Install a marketplace + plugin:**

```shell
/plugin marketplace add <git-url-or-path>
/plugin install <plugin-name>@<marketplace-name>
/plugin marketplace update
/plugin list
```

**marketplace.json** structure:

```json
{
  "name": "my-plugins",
  "owner": { "name": "Your Name" },
  "plugins": [
    { "name": "quality-review-plugin",
      "source": "./plugins/quality-review-plugin",
      "description": "..." }
  ]
}
```

**plugin.json** (per-plugin, at `<plugin>/.claude-plugin/plugin.json`):

```json
{ "name": "quality-review-plugin",
  "description": "...",
  "version": "1.0.0" }
```

- **Version**: omit to use git-commit-as-version (every push is a new version); set explicitly to control update cadence — users only pull when this field changes.
- **Plugin caching**: plugins are copied to a cache dir on install. Plugin code **cannot** reference `../sibling` paths; use symlinks if cross-plugin sharing is needed.
- **Plugin dependencies** (v2.1.143+): `claude plugin disable` refuses if another enabled plugin depends on the target.

**Plugin-provided MCP servers**: declared in `.mcp.json` at plugin root OR inline in `plugin.json` under `mcpServers`. Start automatically when the plugin is enabled. Use `${CLAUDE_PLUGIN_ROOT}` to reference plugin assets. Plugin MCP servers appear in `/mcp` alongside user-configured ones.

**enabledPlugins** in `~/.claude/settings.json` controls per-user enable state:

```json
{ "enabledPlugins": {
    "<plugin>@<marketplace>": true,
    ...
  } }
```

</context>

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
- `@smith-browser-mcp/SKILL.md` - Browser MCP plugin reliability

</related>

## ACTION (Recency Zone)

<required>

**Before using MCP tools:**
1. Check codebase and local docs first
2. Use MCP only when local info insufficient
3. Configure tools conditionally per task

</required>
