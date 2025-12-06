# Agent Smith

> Personal coding standards that follow you everywhere, Mr. Anderson.

**Location:** `$HOME/.smith/`

A minimal, universal standards library that makes AI coding agents smarter across all your projects. Works with your existing tools—no installation required beyond `git clone`.

**What's Included:**
- 12+ standards files covering Python, Git, PRs, testing, and AI agent interaction
- Context-triggered loading (load only rules relevant to your current task)
- Constitutional AI principles (Helpful, Honest, Harmless)
- Token-optimized prompt caching for 90% cost reduction
- Cross-tool compatibility (Claude Code, Codex, Copilot, Cursor, Amp, Kiro, and more)

## Getting Started

### Installation

**New machine:**
```bash
git clone https://github.com/yourusername/smith.git $HOME/.smith
```

**Update existing:**
```bash
cd $HOME/.smith && git pull
```

### Setup for Your AI Coding Tool

Choose the pattern that matches your primary tool. All entrypoints are minimal pointers to `$HOME/.smith/AGENTS.md` where the actual standards live.

**Claude Code (Anthropic):**
```bash
cat > $HOME/.claude/CLAUDE.md << 'EOF'
# Claude Code Global Configuration
**Standards**: See $HOME/.smith/AGENTS.md for complete configuration
**Entry Point**: $HOME/.smith/AGENTS.md handles all context-triggered loading
EOF
```

**AGENTS.md (Recommended - Cross-Tool Standard):**
```bash
# Future-proof XDG standard location
mkdir -p $HOME/.config/agents
cat > $HOME/.config/agents/AGENTS.md << 'EOF'
**Standards**: $HOME/.smith/AGENTS.md
EOF

# Or use OpenAI Codex location
cat > $HOME/.codex/AGENTS.md << 'EOF'
**Standards**: $HOME/.smith/AGENTS.md
EOF
```

**Project-Level (Any Tool):**
```bash
# In your project directory
cat > AGENTS.md << 'EOF'
**Global Standards**: $HOME/.smith/AGENTS.md
EOF

# Symlink for backward compatibility
ln -s AGENTS.md CLAUDE.md
```

**Other Tools:**
- **Codex**: Add comment in `~/.codex/config.toml` referencing `$HOME/.smith/AGENTS.md`
- **Gemini**: Create `~/.gemini/GEMINI.md` pointing to `$HOME/.smith/AGENTS.md`
- **Copilot**: Add `.github/copilot-instructions.md` with `Standards: $HOME/.smith/AGENTS.md`
- **Cursor**: Create `.cursor/rules/smith.mdc` referencing `$HOME/.smith/AGENTS.md`
- **Kiro**: Add `.kiro/steering/standards.md` pointing to `$HOME/.smith/AGENTS.md`
- **Junie**: Create `.junie/guidelines.md` with `Standards: $HOME/.smith/AGENTS.md`

### Verify Installation

```bash
ls -la $HOME/.smith/rules-*.md | wc -l  # Should show 12+ files
cat $HOME/.smith/AGENTS.md | head -10   # Should show Agent Smith entry point
```

## Standards Library

### Core Files (Always Load)
- **AGENTS.md** - Entry point with context-triggered loading rules
- **rules-core.md** - Foundation: NEVER/ALWAYS rules, Constitutional AI principles
- **rules-ai_agents.md** - AI agent steering, exploration-before-implementation, prompt caching

### Language-Specific Standards
- **rules-python.md** - Python imports, type hints, testing (pytest), virtual environments

### Development Workflow
- **rules-development.md** - Quality gates, pre-commit checks, code review patterns
- **rules-testing.md** - Test structure (mirrored paths), pytest patterns, test execution
- **rules-naming.md** - Naming conventions, path standards, separators (hyphens vs underscores)

### Version Control & PR Workflows
- **rules-git.md** - Branch strategy (main/develop/feature), Conventional Commits, git mv patterns
- **rules-pr.md** - Platform-neutral PR workflows, review patterns, merge strategies
- **rules-github.md** - GitHub CLI (gh commands), issue management, GitHub-specific features

### IDE & Tools
- **rules-tools.md** - IDE configuration (VS Code, Cursor, Kiro), tool settings, paths
- **rules-tools-mcp.md** - MCP server setup (Serena, Context7, web fetch)
- **rules-ide_mappings.md** - IDE key mappings across multiple editors

**Total**: 3,695 lines of standards, 12+ files, zero scripts

## Usage Patterns

### Pattern 1: Global Configuration (Recommended)

Set up once in your home directory, works across all projects:

```bash
# Claude Code users
cat > $HOME/.claude/CLAUDE.md << 'EOF'
**Standards**: $HOME/.smith/AGENTS.md
EOF

# Cross-tool users (OpenAI Codex, Amp, GitHub Copilot, etc.)
mkdir -p $HOME/.config/agents
cat > $HOME/.config/agents/AGENTS.md << 'EOF'
**Standards**: $HOME/.smith/AGENTS.md
EOF
```

**Benefit**: Single global config shared across unlimited projects. Standards update automatically when you `git pull` in `$HOME/.smith`.

### Pattern 2: Project-Specific Entry Points

For projects that need custom rules, add minimal pointers:

```bash
# Project-level AGENTS.md
cd /path/to/project
cat > AGENTS.md << 'EOF'
**Global Standards**: $HOME/.smith/AGENTS.md

# Project-specific overrides
**Python Version**: 3.11+
**CI/CD**: GitHub Actions required
EOF

# Symlink for Claude Code compatibility
ln -s AGENTS.md CLAUDE.md
```

**When to use**: Complex projects with strict requirements, client-specific standards, multi-language repos.

### Pattern 3: Hybrid (Global + Project Override)

```bash
# Global provides foundation
cat $HOME/.config/agents/AGENTS.md
# → Standards: $HOME/.smith/AGENTS.md

# Project supplements with overrides
cat myproject/AGENTS.md
# → Global Standards: $HOME/.smith/AGENTS.md
# → Project Python version: 3.11+
```

**When to use**: Large monorepos, multi-team organizations, evolving standards.

### How Context-Triggered Loading Works

When you use an AI agent, it automatically loads standards based on detected context:

```
Detected: Python files (*.py) → LOAD: $HOME/.smith/rules-python.md
Detected: Git commit → LOAD: $HOME/.smith/rules-git.md
Detected: PR creation → LOAD: $HOME/.smith/rules-pr.md + rules-github.md
Detected: New project → LOAD: $HOME/.smith/rules-development.md
```

**See**: `$HOME/.smith/AGENTS.md` for complete trigger list

### Integration with AI Agents

These tools natively support AGENTS.md or similar patterns:

| Tool | Global Config | Project Config | Notes |
|------|---------------|----------------|-------|
| **Claude Code** | `~/.claude/CLAUDE.md` | `AGENTS.md` or `CLAUDE.md` | Full AGENTS.md support |
| **OpenAI Codex** | `~/.codex/AGENTS.md` | `AGENTS.md` hierarchy | Native AGENTS.md |
| **GitHub Copilot** | `~/.copilot/config.json` | `.github/instructions/` | AGENTS.md support added 2025-08 |
| **Amp (Sourcegraph)** | `~/.config/AGENTS.md` | `AGENTS.md` + subdirs | Native AGENTS.md, fallback to CLAUDE.md |
| **Roo Code** | `~/.roo/rules/` | `AGENTS.md` | AGENTS.md support since 2025 |
| **Cursor** | N/A (project-only) | `.cursor/rules/*.mdc` | Reference via .mdc files |
| **Kiro (AWS)** | N/A | `.kiro/steering/*.md` | Reference in steering files |
| **Google Gemini** | `~/.gemini/settings.json` | `GEMINI.md` files | Reference via GEMINI.md |
| **JetBrains Junie** | `~/.junie/mcp.json` | `.junie/guidelines.md` | Reference in guidelines |

**Note**: Most tools hierarchically load AGENTS.md from parent directories, so `$HOME/.smith/AGENTS.md` is discoverable.

## Philosophy

**Core Tenets:**

- **Minimal:** Just markdown files, no scripts or tooling
  - One git clone, and standards follow you everywhere
  - 3,695 lines of standards, zero dependencies
  - 12+ files organized by context

- **Universal:** Works across all AI coding tools
  - Supports Claude Code, Codex, Copilot, Cursor, Amp, Roo Code, Kiro, Gemini, Junie
  - Tools auto-load from standard locations (`$HOME/.config/agents/`, `AGENTS.md`)
  - Graceful degradation if tool doesn't support auto-loading

- **Declarative:** Standards are instructions, not code
  - No linters that enforce style (use your language linters)
  - No automation that creates files
  - No tooling that needs installation
  - Agent instructions are human-readable markdown

- **Portable:** Works on any machine with git
  - Copy one command to set up on new machine
  - No environment variables to configure
  - No shell rc files to modify
  - Standards follow you across machines via git

**Design Principle**: Make it easy for AI agents to understand your preferences so they help you better.

## Advanced Topics

### Hierarchical AGENTS.md

Many tools support nested AGENTS.md files for scoped rules:

```
$HOME/.smith/AGENTS.md          # Global standards
$HOME/.config/agents/AGENTS.md  # User preferences
~/myproject/AGENTS.md           # Project-specific
~/myproject/auth/AGENTS.md      # Subdirectory-specific
```

Tools read from current directory upward, with closest files taking precedence.

### Proposed Standard: `~/.config/agents/`

The AGENTS.md community is standardizing on `~/.config/agents/AGENTS.md` (Linux/macOS) or `%APPDATA%\agents\AGENTS.md` (Windows) for global user preferences. This location:
- Follows XDG Base Directory specification
- Works across multiple tools
- Separates user config from tool-specific directories
- Is the recommended future-proof choice

**Source**: [GitHub Issue #91](https://github.com/openai/agents.md/issues/91)

## Related Resources

- **Full Standards**: `$HOME/.smith/` directory (all rules files)
- **Agent Entry Point**: `$HOME/.smith/AGENTS.md` (context-triggered loading)
- **Repository**: https://github.com/yourusername/smith
- **AGENTS.md Standard**: https://agents.md
- **OpenAI Codex Guide**: https://developers.openai.com/codex/guides/agents-md/

## License

MIT
