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
| [GitHub Copilot][copilot] | —[[1]](#ref-1) | `.github/copilot-instructions.md` | ✓ |
| [Cursor][cursor] | —[[2]](#ref-2) | `.cursor/rules/*.mdc` | ✓ |
| [Windsurf][windsurf] | `.windsurf/rules` | `AGENTS.md` | ✓ |
| [Amp][amp] | `~/.config/AGENTS.md` | `AGENTS.md` | ✓ |
| [Zed][zed] | —[[3]](#ref-3) | `AGENTS.md` | ✓ |
| [Roo Code][roo] | `~/.roo/rules/` | `.roo/rules/` | ✓ |
| [Kiro][kiro] | `~/.kiro/steering/` | `.kiro/steering/` | ✓ |
| [Aider][aider] | `~/.aider.conf.yml` | `AGENTS.md` | ✓ |
| [Continue][continue] | `~/.continue/config.yaml` | `.continue/` | ✓ |
| [Gemini CLI][gemini] | `~/.gemini/` | `GEMINI.md` | ✓ |
| [JetBrains Junie][junie] | —[[4]](#ref-4) | `.junie/guidelines.md` | — |

### Example

```bash
mkdir -p ~/.claude && echo '**Standards**: $HOME/.smith/AGENTS.md' > ~/.claude/CLAUDE.md
```

Tools supporting `~/.config/`: OpenAI Codex, Amp, GitHub Copilot (JetBrains only)

## References

1. <span id="ref-1"></span>GitHub Copilot: VS Code uses IDE settings; JetBrains has [`~/.config/github-copilot/`][copilot-jb]
2. <span id="ref-2"></span>Cursor: [Global config feature requested][cursor-req], not yet implemented
3. <span id="ref-3"></span>Zed: Project-level only, no global config
4. <span id="ref-4"></span>JetBrains Junie: Uses own format, not AGENTS.md; MCP config at `~/.junie/mcp/mcp.json`
5. [AGENTS.md] — Open standard for AI coding agents
6. [OpenAI Codex AGENTS.md Guide][codex]

[AGENTS.md]: https://agents.md
[claude]: https://docs.anthropic.com/en/docs/claude-code
[codex]: https://developers.openai.com/codex/guides/agents-md/
[copilot]: https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot
[copilot-jb]: https://devblogs.microsoft.com/java/customize-github-copilot-in-jetbrains-with-custom-instructions/
[cursor]: https://docs.cursor.com/context/rules
[cursor-req]: https://forum.cursor.com/t/support-for-cursor-rules-for-global-mdc-rules/144819
[windsurf]: https://docs.windsurf.com/
[amp]: https://ampcode.com/manual
[zed]: https://zed.dev/docs/ai/agent-panel
[roo]: https://docs.roocode.com/features/custom-instructions
[kiro]: https://kiro.dev/docs/steering/
[aider]: https://aider.chat/
[continue]: https://docs.continue.dev/
[gemini]: https://developers.google.com/gemini-code-assist/docs/use-agentic-chat-pair-programmer
[junie]: https://www.jetbrains.com/help/junie/customize-guidelines.html

## License

MIT
