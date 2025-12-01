# Agent Smith

> Personal coding standards that follow you everywhere, Mr. Anderson.

**Location:** `~/.smith/`

Universal coding standards and development practices for AI coding agents.

## Quick Start

**New machine:**
```bash
git clone https://github.com/yourusername/smith.git ~/.smith
```

**Update:**
```bash
cd ~/.smith && git pull
```

## Files

- **AGENTS.md** - Primary entry point for coding agents
- **rules-core.md** - Critical NEVER/ALWAYS rules
- **rules-development.md** - Workflow and quality gates
- **rules-git.md** - Git version control practices
- **rules-pr.md** - Platform-neutral pull request workflows
- **rules-github.md** - GitHub-specific operations (gh CLI)
- **rules-testing.md** - Test requirements
- **rules-naming.md** - Naming conventions
- **rules-python.md** - Python-specific standards
- **rules-tools.md** - IDE and tool configurations
- **rules-tools-mcp.md** - MCP server setup
- **rules-ide_mappings.md** - IDE key mappings

## Usage

Reference in project files via `$HOME/.smith/rules-*.md`

Example in project AGENTS.md or CLAUDE.md:
```markdown
**Standards**: `$HOME/.smith/rules-core.md` - Core standards
**Python**: `$HOME/.smith/rules-python.md` - Python guidelines
**PR Workflows**: `$HOME/.smith/rules-pr.md` - Pull request workflows
**GitHub**: `$HOME/.smith/rules-github.md` - GitHub CLI operations
**Testing**: `$HOME/.smith/rules-testing.md` - Test requirements
```

## Philosophy

- **Minimal:** Just markdown files, no scripts
- **Universal:** Works across all coding tools
- **Declarative:** Standards, not automation
- **Portable:** Git clone and go

## License

MIT
