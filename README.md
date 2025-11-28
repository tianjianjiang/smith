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
- **rules-git.md** - Git practices
- **rules-github.md** - GitHub workflows
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
**Testing**: `$HOME/.smith/rules-testing.md` - Test requirements
```

## Philosophy

- **Minimal:** Just markdown files, no scripts
- **Universal:** Works across all coding tools
- **Declarative:** Standards, not automation
- **Portable:** Git clone and go

## References & Citations

Key resources used to define these standards:

### Progressive Loading
- **Anthropic**: Context Efficiency & Prompt Engineering
- **Google Vertex AI**: Grounding & Retrieval
- **Design Patterns**: Progressive Disclosure for Agents

### Git Workflows
- **Stacked PRs**: [Graphite.dev](https://graphite.dev/blog/stacked-pull-requests), [Stacking.dev](https://stacking.dev)
- **Linear History**: [Atlassian Git Tutorials](https://www.atlassian.com/git/tutorials/merging-vs-rebasing)
- **Atomic Commits**: [The Odin Project](https://www.theodinproject.com/lessons/git-atomic-commits), [Conventional Commits](https://www.conventionalcommits.org/)

### Prompt Engineering
- **XML for Structure**: [Anthropic Docs](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/use-xml-tags), [Prompt Engineering Guide](https://www.promptingguide.ai/)
- **Placeholders**: Jinja2 for templates, Shell variables (`$VAR`) for paths


## License

MIT
