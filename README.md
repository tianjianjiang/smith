# Agent Smith

> Personal coding standards that follow you everywhere, Mr. Anderson.

## Quick Start

```bash
git clone https://github.com/tianjianjiang/smith.git $HOME/.smith
```

Then point your AI coding tool to `$HOME/.smith/AGENTS.md`:

| Tool | Global | Project | AGENTS.md |
|------|--------|---------|:---------:|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | `~/.claude/CLAUDE.md` | `AGENTS.md` | ✓ |
| [OpenAI Codex](https://developers.openai.com/codex/guides/agents-md/) | `~/.codex/AGENTS.md` | `AGENTS.md` | ✓ |
| [GitHub Copilot](https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot) | —[[5]](#ref-5) | `.github/copilot-instructions.md` | ✓ |
| [Cursor](https://docs.cursor.com/context/rules) | —[[7]](#ref-7) | `.cursor/rules/*.mdc` | ✓ |
| [Windsurf](https://docs.windsurf.com/) | `.windsurf/rules` | `AGENTS.md` | ✓ |
| [Amp](https://ampcode.com/manual) | `~/.config/AGENTS.md` | `AGENTS.md` | ✓ |
| [Zed](https://zed.dev/docs/ai/agent-panel) | —[[11]](#ref-11) | `AGENTS.md` | ✓ |
| [Roo Code](https://docs.roocode.com/features/custom-instructions) | `~/.roo/rules/` | `.roo/rules/` | ✓ |
| [Kiro](https://kiro.dev/docs/steering/) | `~/.kiro/steering/` | `.kiro/steering/` | ✓ |
| [Aider](https://aider.chat/) | `~/.aider.conf.yml` | `AGENTS.md` | ✓ |
| [Continue](https://docs.continue.dev/) | `~/.continue/config.yaml` | `.continue/` | ✓ |
| [Gemini CLI](https://developers.google.com/gemini-code-assist/docs/use-agentic-chat-pair-programmer) | `~/.gemini/` | `GEMINI.md` | ✓ |
| [Warp](https://docs.warp.dev/agents/using-agents) | — | `WARP.md` | ✓ |
| [goose](https://github.com/block/goose) | — | `AGENTS.md` | ✓ |
| [VS Code](https://code.visualstudio.com/updates/v1_104) | —[[20]](#ref-20) | `AGENTS.md` | ✓ |
| [Devin](https://devin.ai/) | — | `AGENTS.md` | ✓ |
| [JetBrains Junie](https://www.jetbrains.com/help/junie/customize-guidelines.html) | —[[17]](#ref-17) | `.junie/guidelines.md` | — |

### Example

```bash
mkdir -p ~/.claude && echo '**Standards**: $HOME/.smith/AGENTS.md' > ~/.claude/CLAUDE.md
```

Tools supporting `~/.config/`: OpenAI Codex, Amp, GitHub Copilot (JetBrains only[[5]](#ref-5))

## References

1. [AGENTS.md](https://agents.md) — Open standard for AI coding agents
2. [OpenAI Codex AGENTS.md Guide](https://developers.openai.com/codex/guides/agents-md/)
3. [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
4. [GitHub Copilot Custom Instructions](https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot)
5. <span id="ref-5"></span>[GitHub Copilot JetBrains Global Config](https://devblogs.microsoft.com/java/customize-github-copilot-in-jetbrains-with-custom-instructions/) — `~/.config/github-copilot/`; VS Code uses IDE settings only
6. [Cursor Rules](https://docs.cursor.com/context/rules)
7. <span id="ref-7"></span>[Cursor Global Config Request](https://forum.cursor.com/t/support-for-cursor-rules-for-global-mdc-rules/144819) — Feature requested, not yet implemented
8. [Windsurf Documentation](https://docs.windsurf.com/)
9. [Amp Manual](https://ampcode.com/manual)
10. [Zed Agent Panel](https://zed.dev/docs/ai/agent-panel)
11. <span id="ref-11"></span>[Zed Global Config Discussion](https://github.com/zed-industries/zed/discussions/36560) — Project-level only, no global config
12. [Roo Code Custom Instructions](https://docs.roocode.com/features/custom-instructions)
13. [Kiro Steering](https://kiro.dev/docs/steering/)
14. [Aider](https://aider.chat/)
15. [Continue](https://docs.continue.dev/)
16. [Gemini CLI / Code Assist](https://developers.google.com/gemini-code-assist/docs/use-agentic-chat-pair-programmer)
17. <span id="ref-17"></span>[JetBrains Junie Guidelines](https://www.jetbrains.com/help/junie/customize-guidelines.html) — Uses own format `.junie/guidelines.md`, not AGENTS.md
18. [Warp Agents](https://docs.warp.dev/agents/using-agents) — WARP.md compatible with AGENTS.md
19. [goose by Block](https://github.com/block/goose) — Open source AI agent
20. <span id="ref-20"></span>[VS Code AGENTS.md Support](https://code.visualstudio.com/updates/v1_104) — Native support since v1.104 (Aug 2025), no global config
21. [Devin by Cognition](https://devin.ai/) — AI software engineer

## License

MIT
