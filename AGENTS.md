# Personal Coding Standards (.smith)

<metadata>
**Scope**: Personal coding standards for Python development (project-agnostic)
**Load if**: Starting any Python project, personal coding preferences
**Prerequisites**: None (optional - personal preferences)
</metadata>

Personal coding standards library for Python development across all projects.

## Purpose

This directory contains **personal** coding standards extracted from real-world development practices - project-agnostic patterns you can adopt optionally. If files don't exist in your `$HOME/.smith/` directory, coding agents should skip them gracefully.

## Standards Library

### Core Standards

**Core**: `$HOME/.smith/rules-core.md` - Personal NEVER/ALWAYS rules
- Critical coding standards for all languages
- Formatting rules, DateTime standards
- Quality requirements

### Language Standards

**Python**: `$HOME/.smith/rules-python.md` - Python development
- Import rules, type system, code style
- Pytest patterns, virtual environment execution
- Common patterns (error handling, logging, dataclasses)

### File & Path Conventions

**Naming**: `$HOME/.smith/rules-naming.md` - Naming conventions
- File naming patterns (hyphens vs underscores)
- Test file naming, JSON test data patterns
- Path reference standards

### Version Control

**Git**: `$HOME/.smith/rules-git.md` - Git workflow
- Branch strategy, commit standards
- Merge strategies, conflict resolution

**GitHub**: `$HOME/.smith/rules-github.md` - GitHub workflows
- Pull request creation, code reviews
- Issue management, gh CLI reference

### Development Workflow

**Development**: `$HOME/.smith/rules-development.md` - Workflow standards
- Code quality requirements (linting, testing)
- Package management (Poetry, uv, pnpm)
- Script organization, logging patterns

**Testing**: `$HOME/.smith/rules-testing.md` - Testing requirements
- Test structure mirroring source
- Unit vs integration testing
- Environment configuration

### Tool Integration

**Tools**: `$HOME/.smith/rules-tools.md` - Tool configurations
- IDE settings (VS Code, Cursor, Kiro, PyCharm)
- Pytest configuration
- MCP & steering (optional)

**MCP**: `$HOME/.smith/rules-tools-mcp.md` - MCP tools (optional)
- Serena MCP (session persistence)
- Context7 (external library docs)
- Fetch/WebFetch (web content retrieval)

**IDE Mappings**: `$HOME/.smith/rules-ide_mappings.md` - Path variables
- VS Code-based IDEs variable syntax
- JetBrains IDEs macro syntax
- Path variable mappings

## How to Use

### For New Projects

When starting a new Python project, coding agents can reference these standards:

```markdown
## Standards

<personal_standards>
**Note**: Personal standards below are optional preferences. Skip if files don't exist.

**Core**: `$HOME/.smith/rules-core.md` - Personal NEVER/ALWAYS
**Python**: `$HOME/.smith/rules-python.md` - Import rules, pytest
**Git**: `$HOME/.smith/rules-git.md` - Commit, branch strategy
**GitHub**: `$HOME/.smith/rules-github.md` - PR workflow
</personal_standards>

<project_standards>
**Project**: `$WORKSPACE_ROOT/docs/rules-project.md` - Project-specific patterns
</project_standards>
```

### For Existing Projects

Add optional references to your project's AGENTS.md files. Coding agents will use these if available, skip gracefully if not.

### Installation

1. **Copy to dotfiles location**:
   ```bash
   mkdir -p $HOME/.smith
   cp -r .dotfiles-staging/.smith/* $HOME/.smith/
   ```

2. **Reference in projects**:
   Add optional references in project AGENTS.md files using the pattern above.

3. **Update as needed**:
   Modify standards in `$HOME/.smith/` as your preferences evolve.

## Migration from SAT PaaS

This directory was extracted from the SAT PaaS repository to create reusable, project-agnostic standards. The original content has been:

1. **Cleaned** - Removed SAT-specific references (Azure AI Search, S3 logging, Opik tracking)
2. **Generalized** - Kept universal patterns applicable to any Python project
3. **Standalone** - No dependencies on SAT PaaS project structure

### What Was Removed

- **AI Agent specific**: Document verification workflows, S3/Opik logging patterns
- **SAT infrastructure**: Azure AI Search references, production index configs
- **Project paths**: Specific `$WORKSPACE_ROOT` references to SAT structure

### What Was Kept

- **Personal Python**: Import rules, type hints, pytest patterns
- **Personal Git**: Branch strategy, commit format, merge workflows
- **Personal GitHub**: PR templates, code review process
- **Personal Testing**: Test structure, execution patterns
- **Personal Tools**: IDE configs, MCP integration (optional)

## Relationship to Project Standards

These personal standards are **complementary** to project-specific standards:

```
Personal Standards ($HOME/.smith/)
├── Apply to: ALL Python projects
├── Scope: Language, tools, workflows
└── Examples: pytest patterns, git workflows, PR templates

Project Standards ($WORKSPACE_ROOT/docs/)
├── Apply to: Specific project only
├── Scope: Architecture, infrastructure, domain logic
└── Examples: Production configs, API patterns, deployment
```

## Customization

These are **your personal preferences**. Modify them to match your coding style:

1. Edit files in `$HOME/.smith/`
2. Add new standards as you develop patterns
3. Remove standards you don't find useful
4. Share with team or keep private

## Path Variable Conventions

- `$HOME/.smith/` - Universal standards (this directory)
- `$WORKSPACE_ROOT/` - Project workspace root
- `$REPO_ROOT/` - Repository root (monorepos)

See `rules-naming.md` and `rules-ide_mappings.md` for path variable details.

## Dependencies

**None** - These standards are self-contained. Some files reference each other for convenience, but all references use paths within `$HOME/.smith/`.

## Compatibility

**Coding Agents**: Claude Code, Cursor, Windsurf, Kiro, GitHub Copilot
**IDEs**: VS Code, Cursor, Kiro (VS Code-based), PyCharm, IntelliJ IDEA
**Languages**: Primary focus on Python, principles apply to other languages

## Version

**Extracted from**: SAT PaaS repository
**Date**: 2025-11-24
**Status**: Living document, update as preferences evolve

## License

Personal coding standards. Use freely for any project, commercial or personal.

## Related Documentation

- **Path Standards**: See `rules-naming.md` for path conventions
- **IDE Setup**: See `rules-tools.md` and `rules-ide_mappings.md`
- **MCP Tools**: See `rules-tools-mcp.md` for optional tool integration

---

**Note to Coding Agents**: These standards are **optional personal preferences**. If files don't exist at `$HOME/.smith/`, skip them gracefully. Never fail or error when these files are missing - they are purely optional enhancements.
