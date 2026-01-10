# Agent Smith

> AI agent skills that follow you everywhere, Mr. Anderson.

## Overview

Smith is a collection of **31 skills** for AI-assisted development, following the [agentskills.io](https://agentskills.io)[[29]](#ref-29) specification and [AGENTS.md](https://agents.md)[[28]](#ref-28) standard.

**Features**:
- **Progressive disclosure**: Metadata at startup, full content on activation
- **Semantic activation**: Skills load based on task context
- **Cross-platform**: Works with 25+ AI coding tools

## Quick Start

```shell
git clone https://github.com/tianjianjiang/smith.git $HOME/.smith
```

### Link to your project

Claude Code global config:

```shell
ln -sf $HOME/.smith/AGENTS.md $HOME/.claude/CLAUDE.md
```

Or symlink to project root:

```shell
ln -sf $HOME/.smith/AGENTS.md ./AGENTS.md
```

### Claude Code Skills Directory

Symlink smith as Claude Code skills for automatic discovery:

```shell
ln -sf $HOME/.smith $HOME/.claude/skills
```

Claude Code discovers skills and offers them based on task context. All skills use "smith-" prefix to avoid conflicts with built-in commands (`/context`, `/ide`, `/skills`, etc.).

## Structure

```text
smith/
├── AGENTS.md              # Main entry point (agents.md standard)
├── smith-{skill-name}/
│   └── SKILL.md           # Skill file (agentskills.io standard)
└── ...
```

### Skills (31 total)

| Category | Skills |
|----------|--------|
| **Core** | `smith-principles`, `smith-standards`, `smith-guidance` |
| **Context** | `smith-ctx`, `smith-ctx-claude`, `smith-ctx-kiro`, `smith-ctx-cursor`, `smith-serena` |
| **Reasoning** | `smith-analysis`, `smith-clarity`, `smith-design`, `smith-validation`, `smith-postmortem` |
| **Languages** | `smith-python`, `smith-typescript`, `smith-nuxt` |
| **Testing** | `smith-tests` |
| **Workflow** | `smith-ralph` |
| **Git/GitHub** | `smith-git`, `smith-gh-pr`, `smith-gh-cli`, `smith-style`, `smith-stacks` |
| **Other** | `smith-prompts`, `smith-xml`, `smith-placeholder`, `smith-tools`, `smith-dev`, `smith-ide`, `smith-research`, `smith-skills` |

### SKILL.md Format

Each skill follows [agentskills.io specification](https://agentskills.io/specification)[[29]](#ref-29):

```yaml
---
name: skill-name        # Must match directory name
description: ...        # When to use this skill
---

# Skill Title

<metadata>
- **Load if**: Conditions for activation
- **Prerequisites**: Dependencies
</metadata>

<required>
Instructions...
</required>

<related>
- `@other/SKILL.md` - Description
</related>
```

### Reference Convention

- `@path/SKILL.md` (bare) — Always-loaded skills
- `` `@path/SKILL.md` `` (backticks) — Contextual/on-demand skills

## Platform Compatibility

See [AGENTS.md](AGENTS.md) for the full skill index and loading protocol. Global AGENTS.md support is an ongoing discussion[[27]](#ref-27).

### Native AGENTS.md Support

| Tool | Global Config | Project Config |
|------|---------------|----------------|
| **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)**[[4]](#ref-4) | `~/.claude/CLAUDE.md` | `AGENTS.md` |
| **[OpenAI Codex](https://developers.openai.com/codex/guides/agents-md/)**[[16]](#ref-16) | `~/.codex/AGENTS.md` | `AGENTS.md` |
| **[Amp](https://ampcode.com/manual)**[[2]](#ref-2) | `~/.config/AGENTS.md`[[26]](#ref-26) | `AGENTS.md` |
| **[Devin](https://devin.ai/)**[[8]](#ref-8) | — | `AGENTS.md` |
| **[Kiro](https://kiro.dev/docs/steering/)**[[15]](#ref-15) | `~/.kiro/steering/` | `AGENTS.md` |
| **[VS Code](https://code.visualstudio.com/updates/v1_104)**[[21]](#ref-21) | — | `AGENTS.md` |
| **[Windsurf](https://docs.windsurf.com/)**[[23]](#ref-23) | `.windsurf/rules` | `AGENTS.md` |
| **[Zed](https://zed.dev/docs/ai/agent-panel)**[[24]](#ref-24) | —[[25]](#ref-25) | `AGENTS.md` |
| **[goose](https://github.com/block/goose)**[[12]](#ref-12) | — | `AGENTS.md` |

### Requires Configuration

| Tool | Global Config | Project Config |
|------|---------------|----------------|
| **[Aider](https://aider.chat/)**[[1]](#ref-1) | `~/.aider.conf.yml` | `AGENTS.md` |
| **[Gemini CLI](https://developers.google.com/gemini-code-assist/docs/use-agentic-chat-pair-programmer)**[[9]](#ref-9) | `~/.gemini/` | `GEMINI.md` |
| **[GitHub Copilot](https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot)**[[10]](#ref-10) | —[[11]](#ref-11) | `.github/copilot-instructions.md` |
| **[JetBrains AI](https://www.jetbrains.com/help/ai-assistant/configure-project-rules.html)**[[13]](#ref-13) | `~/.config/JetBrains/*/ai-assistant/rules/` | `.aiassistant/rules/` |
| **[Continue](https://docs.continue.dev/)**[[5]](#ref-5) | `~/.continue/config.yaml` | `.continue/` |

### Different Format

| Tool | Format | Project Config |
|------|--------|----------------|
| **[Cursor](https://docs.cursor.com/context/rules)**[[6]](#ref-6)[[7]](#ref-7) | `.mdc` | `.cursor/rules/*.mdc` |
| **[Antigravity](https://cloud.google.com/products/antigravity)**[[3]](#ref-3) | `GEMINI.md` | `.agent/rules/` |

<details>
<summary>All supported tools</summary>

- **[JetBrains Junie](https://www.jetbrains.com/help/junie/customize-guidelines.html)**[[14]](#ref-14): `.junie/guidelines.md`
- **[OpenHands](https://docs.openhands.dev/)**[[17]](#ref-17): `.openhands/microagents/`
- **[Roo Code](https://docs.roocode.com/features/custom-instructions)**[[18]](#ref-18): `.roo/rules/`
- **[Sourcegraph Cody](https://sourcegraph.com/docs/cody)**[[19]](#ref-19): Enterprise only
- **[Tabnine](https://docs.tabnine.com/main/getting-started/tabnine-agent/guidelines)**[[20]](#ref-20): `.tabnine/guidelines/`
- **[Warp](https://docs.warp.dev/agents/using-agents)**[[22]](#ref-22): `WARP.md`

</details>

## References

1. <span id="ref-1"></span>[Aider](https://aider.chat/)
2. <span id="ref-2"></span>[Amp Manual](https://ampcode.com/manual)
3. <span id="ref-3"></span>[Antigravity Rules](https://atamel.dev/posts/2025/11-25_customize_antigravity_rules_workflows/)
4. <span id="ref-4"></span>[Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
5. <span id="ref-5"></span>[Continue](https://docs.continue.dev/)
6. <span id="ref-6"></span>[Cursor Rules](https://docs.cursor.com/context/rules)
7. <span id="ref-7"></span>[Cursor Global Config Request](https://forum.cursor.com/t/support-for-cursor-rules-for-global-mdc-rules/144819)
8. <span id="ref-8"></span>[Devin by Cognition](https://devin.ai/)
9. <span id="ref-9"></span>[Gemini CLI / Code Assist](https://developers.google.com/gemini-code-assist/docs/use-agentic-chat-pair-programmer)
10. <span id="ref-10"></span>[GitHub Copilot Custom Instructions](https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot)
11. <span id="ref-11"></span>[GitHub Copilot JetBrains Global Config](https://devblogs.microsoft.com/java/customize-github-copilot-in-jetbrains-with-custom-instructions/)
12. <span id="ref-12"></span>[goose by Block](https://github.com/block/goose)
13. <span id="ref-13"></span>[JetBrains AI Assistant Rules](https://www.jetbrains.com/help/ai-assistant/configure-project-rules.html)
14. <span id="ref-14"></span>[JetBrains Junie Guidelines](https://www.jetbrains.com/help/junie/customize-guidelines.html)
15. <span id="ref-15"></span>[Kiro Steering](https://kiro.dev/docs/steering/)
16. <span id="ref-16"></span>[OpenAI Codex AGENTS.md Guide](https://developers.openai.com/codex/guides/agents-md/)
17. <span id="ref-17"></span>[OpenHands Microagents](https://docs.openhands.dev/modules/usage/prompting/microagents-repo)
18. <span id="ref-18"></span>[Roo Code Custom Instructions](https://docs.roocode.com/features/custom-instructions)
19. <span id="ref-19"></span>[Sourcegraph Cody](https://sourcegraph.com/docs/cody)
20. <span id="ref-20"></span>[Tabnine Guidelines](https://docs.tabnine.com/main/getting-started/tabnine-agent/guidelines)
21. <span id="ref-21"></span>[VS Code AGENTS.md Support](https://code.visualstudio.com/updates/v1_104)
22. <span id="ref-22"></span>[Warp Agents](https://docs.warp.dev/agents/using-agents)
23. <span id="ref-23"></span>[Windsurf Documentation](https://docs.windsurf.com/)
24. <span id="ref-24"></span>[Zed Agent Panel](https://zed.dev/docs/ai/agent-panel)
25. <span id="ref-25"></span>[Zed Global Config Discussion](https://github.com/zed-industries/zed/discussions/36560)
26. <span id="ref-26"></span>[XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/)
27. <span id="ref-27"></span>[Global AGENTS.md Proposal](https://github.com/openai/agents.md/issues/91)
28. <span id="ref-28"></span>[AGENTS.md Standard](https://agents.md)
29. <span id="ref-29"></span>[Agent Skills Specification](https://agentskills.io)

## License

MIT
