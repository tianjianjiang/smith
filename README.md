# Agent Smith

> Personal coding standards that follow you everywhere, Mr. Anderson.

## Quick Start

```bash
git clone https://github.com/tianjianjiang/smith.git $HOME/.smith
```

Then point your AI coding tool to `$HOME/.smith/AGENTS.md`:

| Tool | Global | Project | [AGENTS.md] |
|------|--------|---------|:-----------:|
| [Claude Code][claude] | `~/.claude/CLAUDE.md` | `AGENTS.md` | ✓ |
| [OpenAI Codex][codex] | `~/.codex/AGENTS.md` | `AGENTS.md` | ✓ |
| [GitHub Copilot][copilot] | —<sup>1</sup> | `.github/copilot-instructions.md` | ✓ |
| [Cursor][cursor] | —<sup>2</sup> | `.cursor/rules/*.mdc` | ✓ |
| [Windsurf][windsurf] | `.windsurf/rules` | `AGENTS.md` | ✓ |
| [Amp][amp] | `~/.config/AGENTS.md` | `AGENTS.md` | ✓ |
| [Zed][zed] | —<sup>4</sup> | `AGENTS.md` | ✓ |
| [Roo Code][roo] | `~/.roo/rules/` | `.roo/rules/` | ✓ |
| [Kiro][kiro] | `~/.kiro/steering/` | `.kiro/steering/` | ✓ |
| [Aider][aider] | `~/.aider.conf.yml` | `AGENTS.md` | ✓ |
| [Continue][continue] | `~/.continue/config.yaml` | `.continue/` | ✓ |
| [Gemini CLI][gemini] | `~/.gemini/` | `GEMINI.md` | ✓ |
| [JetBrains Junie][junie] | —<sup>3</sup> | `.junie/guidelines.md` | — |

<sup>1</sup> VS Code: IDE settings only. JetBrains: `~/.config/github-copilot/`
<sup>2</sup> [Feature requested][cursor-req], not yet implemented
<sup>3</sup> Uses own format; MCP config at `~/.junie/mcp/mcp.json`
<sup>4</sup> Project-level only; no global config

### Example

```bash
mkdir -p ~/.claude && echo '**Standards**: $HOME/.smith/AGENTS.md' > ~/.claude/CLAUDE.md
```

Tools supporting `~/.config/`: OpenAI Codex, Amp, GitHub Copilot (JetBrains)

## References

- [AGENTS.md] — Open standard for AI coding agents
- [OpenAI Codex AGENTS.md Guide][codex]

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
