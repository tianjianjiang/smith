# Agent Smith

> Personal coding standards that follow you everywhere, Mr. Anderson.

**Location**: `$HOME/.smith/` | **Entry point**: [AGENTS.md](AGENTS.md) | **~3,500 lines across 12+ files**

## Quick Start

```bash
git clone https://github.com/tianjianjiang/smith.git $HOME/.smith
```

Then point your AI coding tool to `$HOME/.smith/AGENTS.md`:

| Tool | Global | Project | [AGENTS.md] |
|------|--------|---------|:-----------:|
| [Claude Code][claude] | `~/.claude/CLAUDE.md` | `AGENTS.md` | ✓ |
| [OpenAI Codex][codex] | `~/.codex/AGENTS.md` | `AGENTS.md` | ✓ |
| [GitHub Copilot][copilot] | — ¹ | `.github/copilot-instructions.md` | ✓ |
| [Cursor][cursor] | — ² | `.cursor/rules/*.mdc` | ✓ |
| [Windsurf][windsurf] | `.windsurf/rules` | `AGENTS.md` | ✓ |
| [Amp][amp] | `~/.config/AGENTS.md` | `AGENTS.md` | ✓ |
| [Zed][zed] | — | `AGENTS.md` | ✓ |
| [Roo Code][roo] | `~/.roo/rules/` | `.roo/rules/` | ✓ |
| [Kiro][kiro] | `~/.kiro/steering/` | `.kiro/steering/` | ✓ |
| [Aider][aider] | `~/.aider.conf.yml` | `AGENTS.md` | ✓ |
| [Continue][continue] | `~/.continue/config.yaml` | `.continue/` | ✓ |
| [Gemini CLI][gemini] | `~/.gemini/` | `GEMINI.md` | ✓ |
| [JetBrains Junie][junie] | — ³ | `.junie/guidelines.md` | — |

¹ VS Code: IDE settings only. JetBrains: `~/.config/github-copilot/`
² [Feature requested][cursor-req], not yet implemented
³ Uses own format; MCP config at `~/.junie/mcp/mcp.json`

### Example: Claude Code

```bash
mkdir -p ~/.claude && echo '**Standards**: $HOME/.smith/AGENTS.md' > ~/.claude/CLAUDE.md
```

### Tools Supporting `~/.config/`

OpenAI Codex, Amp, GitHub Copilot (JetBrains) support XDG-style `~/.config/` paths.

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
- **Universal**: Works across 20+ AI coding tools via [AGENTS.md] standard.
- **Declarative**: Instructions, not code. No linters, no automation, no installation.
- **Portable**: Works on any machine with git. No env vars, no shell rc modifications.

## References

### Standards
- [AGENTS.md] — Open standard for AI coding agents (20k+ repos)
- [OpenAI Codex Guide](https://developers.openai.com/codex/guides/agents-md/)

### Tool Documentation
[AGENTS.md]: https://agents.md
[claude]: https://docs.anthropic.com/en/docs/claude-code
[codex]: https://developers.openai.com/codex/guides/agents-md/
[copilot]: https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot
[cursor]: https://docs.cursor.com/context/rules
[cursor-req]: https://forum.cursor.com/t/support-for-cursor-rules-for-global-mdc-rules/144819
[windsurf]: https://docs.windsurf.com/
[amp]: https://ampcode.com/docs
[zed]: https://zed.dev/docs/ai/agent-panel
[roo]: https://docs.roocode.com/features/custom-instructions
[kiro]: https://kiro.dev/docs/steering/
[aider]: https://aider.chat/
[continue]: https://docs.continue.dev/
[gemini]: https://developers.google.com/gemini-code-assist/docs/use-agentic-chat-pair-programmer
[junie]: https://www.jetbrains.com/help/junie/customize-guidelines.html

## License

MIT
