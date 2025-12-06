# Agent Smith

> Personal coding standards that follow you everywhere, Mr. Anderson.

## Quick Start

```bash
git clone https://github.com/tianjianjiang/smith.git $HOME/.smith
```

See [AGENTS.md](AGENTS.md) for context-triggered loading rules and file organization.

Point your AI coding tool to `$HOME/.smith/AGENTS.md`:

| Tool | Global | Project |
|------|--------|---------|
| [Aider](https://aider.chat/)[[1]](#ref-1) | `~/.aider.conf.yml` | `AGENTS.md` |
| [Amp](https://ampcode.com/manual)[[2]](#ref-2) | `~/.config/AGENTS.md` | `AGENTS.md` |
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code)[[3]](#ref-3) | `~/.claude/CLAUDE.md` | `AGENTS.md` |
| [Continue](https://docs.continue.dev/)[[4]](#ref-4) | `~/.continue/config.yaml` | `.continue/` |
| [Cursor](https://docs.cursor.com/context/rules)[[5]](#ref-5) | —[[6]](#ref-6) | `.cursor/rules/*.mdc` |
| [Devin](https://devin.ai/)[[7]](#ref-7) | — | `AGENTS.md` |
| [Gemini CLI](https://developers.google.com/gemini-code-assist/docs/use-agentic-chat-pair-programmer)[[8]](#ref-8) | `~/.gemini/` | `GEMINI.md` |
| [GitHub Copilot](https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot)[[9]](#ref-9) | —[[10]](#ref-10) | `.github/copilot-instructions.md` |
| [goose](https://github.com/block/goose)[[11]](#ref-11) | — | `AGENTS.md` |
| [JetBrains AI](https://www.jetbrains.com/help/ai-assistant/configure-project-rules.html)[[12]](#ref-12) | `~/.config/JetBrains/*/ai-assistant/rules/` | `.aiassistant/rules/` |
| [JetBrains Junie](https://www.jetbrains.com/help/junie/customize-guidelines.html)[[13]](#ref-13) | — | `.junie/guidelines.md` |
| [Kiro](https://kiro.dev/docs/steering/)[[14]](#ref-14) | `~/.kiro/steering/` | `.kiro/steering/` |
| [OpenAI Codex](https://developers.openai.com/codex/guides/agents-md/)[[15]](#ref-15) | `~/.codex/AGENTS.md` | `AGENTS.md` |
| [Roo Code](https://docs.roocode.com/features/custom-instructions)[[16]](#ref-16) | `~/.roo/rules/` | `.roo/rules/` |
| [Sourcegraph Cody](https://sourcegraph.com/docs/cody)[[17]](#ref-17) | Enterprise only | `.idea/cody_settings.json` |
| [Tabnine](https://docs.tabnine.com/main/getting-started/tabnine-agent/guidelines)[[18]](#ref-18) | `~/.config/TabNine/` | `.tabnine/guidelines/` |
| [VS Code](https://code.visualstudio.com/updates/v1_104)[[19]](#ref-19) | — | `AGENTS.md` |
| [Warp](https://docs.warp.dev/agents/using-agents)[[20]](#ref-20) | — | `WARP.md` |
| [Windsurf](https://docs.windsurf.com/)[[21]](#ref-21) | `.windsurf/rules` | `AGENTS.md` |
| [Zed](https://zed.dev/docs/ai/agent-panel)[[22]](#ref-22) | —[[23]](#ref-23) | `AGENTS.md` |

### Example

```bash
mkdir -p ~/.claude && echo '**Standards**: $HOME/.smith/AGENTS.md' > ~/.claude/CLAUDE.md
```

### XDG-Style Global Config

Some tools follow [XDG Base Directory](https://specifications.freedesktop.org/basedir-spec/latest/) conventions under `~/.config/`:
- Amp: `~/.config/AGENTS.md`
- GitHub Copilot (JetBrains only[[10]](#ref-10)): `~/.config/github-copilot/`
- JetBrains AI: `~/.config/JetBrains/*/ai-assistant/rules/`
- Tabnine: `~/.config/TabNine/`

## References

1. <span id="ref-1"></span>[Aider](https://aider.chat/)
2. <span id="ref-2"></span>[Amp Manual](https://ampcode.com/manual)
3. <span id="ref-3"></span>[Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
4. <span id="ref-4"></span>[Continue](https://docs.continue.dev/)
5. <span id="ref-5"></span>[Cursor Rules](https://docs.cursor.com/context/rules)
6. <span id="ref-6"></span>[Cursor Global Config Request](https://forum.cursor.com/t/support-for-cursor-rules-for-global-mdc-rules/144819) — Not yet implemented
7. <span id="ref-7"></span>[Devin by Cognition](https://devin.ai/)
8. <span id="ref-8"></span>[Gemini CLI / Code Assist](https://developers.google.com/gemini-code-assist/docs/use-agentic-chat-pair-programmer)
9. <span id="ref-9"></span>[GitHub Copilot Custom Instructions](https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot)
10. <span id="ref-10"></span>[GitHub Copilot JetBrains Global Config](https://devblogs.microsoft.com/java/customize-github-copilot-in-jetbrains-with-custom-instructions/) — `~/.config/github-copilot/`; VS Code uses IDE settings only
11. <span id="ref-11"></span>[goose by Block](https://github.com/block/goose)
12. <span id="ref-12"></span>[JetBrains AI Assistant Rules](https://www.jetbrains.com/help/ai-assistant/configure-project-rules.html)
13. <span id="ref-13"></span>[JetBrains Junie Guidelines](https://www.jetbrains.com/help/junie/customize-guidelines.html) — Uses `.junie/guidelines.md`, not AGENTS.md
14. <span id="ref-14"></span>[Kiro Steering](https://kiro.dev/docs/steering/)
15. <span id="ref-15"></span>[OpenAI Codex AGENTS.md Guide](https://developers.openai.com/codex/guides/agents-md/)
16. <span id="ref-16"></span>[Roo Code Custom Instructions](https://docs.roocode.com/features/custom-instructions)
17. <span id="ref-17"></span>[Sourcegraph Cody](https://sourcegraph.com/docs/cody) — Enterprise-only global config
18. <span id="ref-18"></span>[Tabnine Guidelines](https://docs.tabnine.com/main/getting-started/tabnine-agent/guidelines)
19. <span id="ref-19"></span>[VS Code AGENTS.md Support](https://code.visualstudio.com/updates/v1_104) — v1.104+, no global config
20. <span id="ref-20"></span>[Warp Agents](https://docs.warp.dev/agents/using-agents) — WARP.md compatible with AGENTS.md
21. <span id="ref-21"></span>[Windsurf Documentation](https://docs.windsurf.com/)
22. <span id="ref-22"></span>[Zed Agent Panel](https://zed.dev/docs/ai/agent-panel)
23. <span id="ref-23"></span>[Zed Global Config Discussion](https://github.com/zed-industries/zed/discussions/36560) — Project-level only
24. [AGENTS.md Standard](https://agents.md) — Open format for AI coding agents

## License

MIT
