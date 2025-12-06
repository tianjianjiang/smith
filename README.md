# Agent Smith

> Personal coding standards that follow you everywhere, Mr. Anderson.

**Location**: `$HOME/.smith/` | **Entry point**: [AGENTS.md](AGENTS.md) | **~3,500 lines across 12+ files**

## Quick Start

```bash
git clone https://github.com/tianjianjiang/smith.git $HOME/.smith
```

Then point your AI coding tool to `$HOME/.smith/AGENTS.md`:

| Tool | Global Config | Project Config |
|------|---------------|----------------|
| **Claude Code** | `~/.claude/CLAUDE.md` | `AGENTS.md` or `CLAUDE.md` |
| **OpenAI Codex** | `~/.codex/AGENTS.md` | `AGENTS.md` hierarchy |
| **GitHub Copilot** | — | `.github/copilot-instructions.md` |
| **Cursor** | — | `.cursor/rules/*.mdc` |
| **Amp** | `~/.config/AGENTS.md` | `AGENTS.md` + subdirs |
| **Roo Code** | `~/.roo/rules/` | `.roo/rules/` |
| **Kiro** | — | `.kiro/steering/*.md` |
| **Google Gemini** | `~/.gemini/settings.json` | `GEMINI.md` |
| **JetBrains Junie** | `~/.junie/mcp.json` | `.junie/guidelines.md` |
| **Continue** | `~/.continue/config.json` | `.continue/` |

### Example: Claude Code

```bash
mkdir -p ~/.claude && echo '**Standards**: $HOME/.smith/AGENTS.md' > ~/.claude/CLAUDE.md
```

### Example: Cross-Tool (XDG Standard)

```bash
mkdir -p ~/.config/agents && echo '**Standards**: $HOME/.smith/AGENTS.md' > ~/.config/agents/AGENTS.md
```

**Tools supporting `~/.config/`**: OpenAI Codex, Amp (native AGENTS.md discovery)

## What's Inside

Standards are organized by context and loaded on-demand. See [AGENTS.md](AGENTS.md) for trigger rules.

| Category | Files |
|----------|-------|
| **Core** | `rules-core.md`, `rules-ai_agents.md` |
| **Python** | `rules-python.md` |
| **Git/PR** | `rules-git.md`, `rules-pr.md`, `rules-github.md` |
| **Testing** | `rules-testing.md` |
| **Development** | `rules-development.md`, `rules-naming.md` |
| **IDE/Tools** | `rules-tools.md`, `rules-tools-mcp.md`, `rules-ide_mappings.md` |

## Philosophy

- **Minimal**: Just markdown files. One `git clone`, standards follow you everywhere.
- **Universal**: Works across Claude Code, Codex, Copilot, Cursor, Amp, Roo Code, Kiro, Gemini, Junie.
- **Declarative**: Instructions, not code. No linters, no automation, no installation.
- **Portable**: Works on any machine with git. No env vars, no shell rc modifications.

## Links

- [AGENTS.md Standard](https://agents.md)
- [OpenAI Codex Guide](https://developers.openai.com/codex/guides/agents-md/)

## License

MIT
