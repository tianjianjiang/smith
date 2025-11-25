# MCP Tool Integration (Optional)

This document describes **OPTIONAL** MCP tool integrations. These tools are NOT required for standard development work.

## Overview

MCP (Model Context Protocol) tools provide enhanced capabilities for specific scenarios. Use them conditionally when their specific functionality is needed.

## Available Tools

### Serena MCP - Session Persistence

**Purpose**: Persist plans and context across sessions

**Use for**:
- Complex, multi-session tasks requiring context recovery
- User-requested plan documentation or memory storage
- Session restarts needing previous context
- Prompt engineering experiments with variables to track

**Capabilities**:
- Store plan status and outcomes for session recovery
- Document prompt engineering experimental variables
- Persist task context across session restarts

**Configuration**: `.kiro/settings/mcp.json` or IDE settings

**Avoid**:
- Single-session tasks
- Simple bug fixes or feature additions
- When user hasn't requested persistence

### Context7 - External Library Documentation

**Purpose**: Fetch documentation for external libraries

**Use for**:
- User mentions external library not in codebase
- Unfamiliar NPM/PyPI packages requiring API reference
- Integration decisions needing external dependency docs
- User asks "how do I use [library]"

**Capabilities**:
- Fetch current documentation for external libraries
- Retrieve API references for integration decisions
- Access version-specific library information

**Configuration**: MCP settings

**Avoid**:
- Library already in codebase (use codebase search)
- Documentation available in project docs
- Standard library usage (Python/Node built-ins)

### Fetch/WebFetch - Web Content Retrieval

**Purpose**: Retrieve web content from URLs

**Use for**:
- User provides URL to analyze or read
- Documentation from web sources explicitly requested
- API documentation from public URLs
- User asks to "fetch" or "get content from" specific URL

**Capabilities**:
- Fetch and analyze web page content
- Retrieve documentation from URLs
- Access public API references

**Configuration**: Use WebFetch tool if available

**Avoid**:
- Content available locally
- User hasn't provided or requested specific URLs
- Speculative browsing for documentation

## MCP Tool Reference

| Tool | Purpose | When to Use | Configuration |
|------|---------|-------------|---------------|
| **Serena MCP** | Session persistence | Multi-session tasks, plan recovery | `.kiro/settings/mcp.json` |
| **Context7** | External library docs | Unfamiliar libraries, API references | MCP settings |
| **Fetch** | Web content retrieval | User-provided URLs, web documentation | Built-in or MCP |

## Best Practices

<required>
- MUST check codebase and local docs first before using MCP tools
- MUST only use MCP tools when task specifically requires them or user requests
- SHOULD activate tools conditionally based on task needs, not by default
</required>

## Common Misunderstandings

<forbidden>
- NEVER mandate Serena MCP for all plans (only for multi-session tasks)
- NEVER require Context7 for all libraries (only for unfamiliar external ones)
- NEVER load MCP tools unconditionally in every session
- NEVER use MCP tools for simple single-session tasks
</forbidden>

## When to Use Each Tool

**Serena MCP** - Use ONLY when:
- Task requires context persistence across sessions
- User explicitly requests plan documentation
- Multi-session workflow requires session recovery
- Prompt engineering experiments need variable tracking

**Context7** - Use ONLY when:
- User mentions unfamiliar external library not in codebase
- Library not present in codebase (use codebase search first)
- Integration requires external API documentation
- User explicitly asks "how do I use [library]"

**Fetch/WebFetch** - Use ONLY when:
- User provides specific URL to analyze
- Web documentation is explicitly requested
- Public API references need retrieval

## Configuration

For MCP tool setup and configuration, see:
- Kiro: `$HOME/.kiro/settings/mcp.json` or `$WORKSPACE_ROOT/.kiro/settings/mcp.json`
- IDE-specific: `$HOME/.smith/rules-ide_mappings.md`

## Related Standards

- IDE Integration: `$HOME/.smith/rules-ide_mappings.md`
- Tool Configuration: `$HOME/.smith/rules-tools.md`
- Development Workflow: `$HOME/.smith/rules-development.md`
