# Agent Smith

> AI agent skills that follow you everywhere, Mr. Anderson.

## Overview

Smith is a collection of **47 skills** for AI-assisted development, following the [agentskills.io specification](https://agentskills.io)[[29]](#ref-29) and [AGENTS.md standard](https://agents.md)[[28]](#ref-28).

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

### Hooks (manual registration)

Some scripts in this repo are hooks, NOT self-activating skills — they only
take effect once registered in `$HOME/.claude/settings.json` (see
`@smith-settings/SKILL.md`). With the skills symlink above in place, register
the hooks below. Every hook **fails open** on a parse/tool error unless noted
otherwise — a guard bug never breaks unrelated work — and each ships a
self-check under its owning skill's `scripts/tests/run-all.sh`.

| Hook | Event (matcher) | Script | Blocks / Advisory | Detail |
|---|---|---|---|---|
| `skill-router` | UserPromptSubmit | `smith-ctx-claude/scripts/skill-router.mjs` | Advisory: surfaces candidate skills per prompt | ctx-claude |
| `branch-guard` | PreToolUse (`Edit\|Write\|NotebookEdit`+) | `smith-git/scripts/hooks/branch-guard.mjs` | Blocks edits on the default branch | git |
| `worktree-dirty-guard` | PreToolUse (`EnterWorktree`) | `smith-git/scripts/hooks/worktree-dirty-guard.mjs` | Blocks entering a worktree with uncommitted changes | git |
| `external-write-guard` | PreToolUse (`mcp__.*`, `Bash`) | `smith-ctx-claude/scripts/external-write-guard.mjs` | Escalates human-facing writes to `ask` | ctx-claude |
| `askuserquestion-arity` | PreToolUse (`AskUserQuestion`) | `smith-ctx-claude/scripts/askuserquestion-arity.mjs` | Blocks a multi-question call | ctx-claude |
| `volatile-artifact-guard` | Stop/SubagentStop/SessionEnd | `smith-ctx-claude/scripts/volatile-artifact-guard.mjs` | Advisory: lists files left under volatile paths | ctx-claude |
| `branch-rename-open-pr` | PreToolUse (`Bash`) | `smith-ctx-claude/scripts/branch-rename-open-pr.mjs` | Blocks renaming a branch with an open PR | ctx-claude |
| `branch-name-guard` | PreToolUse (`Bash`, `EnterWorktree`) | `smith-git/scripts/hooks/branch-name-guard.mjs` | Blocks a non-Conventional-Branch-Names create/rename | git |
| `inline-comment-lint` | PreToolUse (`Edit\|Write\|NotebookEdit`) | `smith-standards/scripts/inline-comment-lint.mjs` | Advisory: flags inline comments | standards |
| `coined-shorthand-lint` | PreToolUse (`Edit\|Write\|NotebookEdit`) | `smith-ctx-claude/scripts/coined-shorthand-lint.mjs` | Advisory: flags meaningless coined index codes | ctx-claude |
| `review-orchestration-guard` | PreToolUse (`Agent\|Task`) | `smith-ctx-claude/scripts/review-orchestration-guard.mjs` | Advisory: prefer the toolkit orchestrator | ctx-claude |
| `subagent-contract-guard` | PreToolUse (`Agent\|Task`) | `smith-ctx-claude/scripts/subagent-contract-guard.mjs` | Blocks a subagent spawn missing the read-only contract | ctx-claude |
| `skill-read-substitution-guard` | PreToolUse (`Read`) | `smith-ctx-claude/scripts/skill-read-substitution-guard.mjs` | Advisory: Read a SKILL.md → invoke it via Skill instead | ctx-claude |
| `skill-claim-lint` | Stop | `smith-ctx-claude/scripts/skill-claim-lint.mjs` | Advisory: flags a claimed-but-not-invoked skill | ctx-claude |
| `gh-stack-guard` | PreToolUse (`Bash`) | `smith-ctx-claude/scripts/gh-stack-guard.mjs` | Advisory: prefer `gh stack` over hand-built stacked PRs | ctx-claude |
| `rtk-find-symlink-guard` | PreToolUse (`Bash`) | `smith-ctx-claude/scripts/rtk-find-symlink-guard.mjs` | Advisory: `find -L`/`rtk find -L` bug workaround | ctx-claude |
| `post-merge-pull-reminder` | PostToolUse (`Bash`) | `smith-git/scripts/hooks/post-merge-pull-reminder.mjs` | Advisory: ff-only pull the default branch after merge | git |
| `coderabbit-status-check` | PostToolUse (`Bash`) | `smith-ctx-claude/scripts/coderabbit-status-check.mjs` | Advisory: validate CodeRabbit `--agent` output | ctx-claude |
| `exit-plan-mode-guard` | PreToolUse (`ExitPlanMode`) | `smith-ctx-claude/scripts/exit-plan-mode-guard.mjs` | Blocks `ExitPlanMode` without a prior elaboration turn | ctx-claude |
| `stack-merge-guard` | PreToolUse (`Bash`) | `smith-ctx-claude/scripts/stack-merge-guard.mjs` | Asks before deleting a branch with an open child PR | ctx-claude |
| `amend-shared-commit-guard` | PreToolUse (`Bash`) | `smith-ctx-claude/scripts/amend-shared-commit-guard.mjs` | Asks before amending a commit shared with another branch | ctx-claude |
| `attribution-model-stamp` | PreToolUse (`Bash`) | `smith-ctx-claude/scripts/attribution-model-stamp.sh` | Refreshes the model-id file for `Assisted-by:` trailers | ctx-claude |
| `uv-tool-health-check` | SessionStart (all sources) | `smith-serena/scripts/uv-tool-health-check.sh` | Self-heals a broken `uv tool`-managed venv (e.g. `serena-agent`) | serena |

**Full detail, known limitations, the complete `settings.json` registration
block, and the manual verification checklist** live with each hook's owning
skill, not here:
- `smith-ctx-claude/references/HOOKS.md` — most hooks above, the registration
  JSON, and the verification steps
- `smith-git/references/HOOKS.md` — `branch-guard`, `worktree-dirty-guard`,
  `branch-name-guard`, `post-merge-pull-reminder`
- `smith-standards/references/HOOKS.md` — `inline-comment-lint`
- `smith-serena/references/HOOKS.md` — `uv-tool-health-check`

`/smith-checkpoint`'s runtime prerequisites (Serena/Basic-Memory availability,
the reload-flag hook, the session-restart marker hook, cloud/fresh-clone
reach) are documented in `smith-checkpoint/SKILL.md` "Runtime prerequisites",
not here.

## Structure

```text
smith/
├── AGENTS.md              # Main entry point (agents.md standard)
├── smith-{skill-name}/
│   └── SKILL.md           # Skill file (agentskills.io standard)
└── ...
```

### Skills (47 total)

| Category | Skills |
|----------|--------|
| **Core** | `smith-principles`, `smith-standards`, `smith-guidance` |
| **Commands** (`/smith-X`) | `smith-ship`, `smith-review`, `smith-preflight`, `smith-checkpoint`, `smith-recon`, `smith-tickets` |
| **Context** | `smith-ctx`, `smith-ctx-claude`, `smith-ctx-kiro`, `smith-ctx-cursor`, `smith-serena` |
| **Reasoning** | `smith-analysis`, `smith-clarity`, `smith-design`, `smith-validation`, `smith-postmortem`, `smith-dialectic` |
| **Languages** | `smith-python`, `smith-typescript`, `smith-nuxt` |
| **Testing** | `smith-tests`, `smith-playwright`, `smith-mcp-browser` |
| **Workflow** | `smith-ralph`, `smith-plan`, `smith-plan-claude`, `smith-subagents`, `smith-automation` |
| **Git/GitHub** | `smith-git`, `smith-gh-pr`, `smith-gh-cli`, `smith-style`, `smith-worktree` |
| **Communication** | `smith-slack` |
| **Other** | `smith-prompts`, `smith-xml`, `smith-placeholder`, `smith-tools`, `smith-dev`, `smith-ide`, `smith-research`, `smith-skills`, `smith-settings`, `smith-ctx-claude-mode-auto` |

### SKILL.md Format

Each skill follows [agentskills.io specification](https://agentskills.io/specification)[[29]](#ref-29).
Bodies use plain Markdown (headers, bold labels, bullet lists) — not an XML
tag skeleton — matching Anthropic's own SKILL.md-authoring examples and
OpenAI's current model guidance; see `smith-xml/SKILL.md` for the narrower
case where XML tags still apply (runtime prompts, not SKILL.md bodies):

```yaml
---
name: skill-name        # Must match directory name
description: ...        # When to use this skill
---

# Skill Title

**Load if:** Conditions for activation
**Prerequisites:** Dependencies

## Section Title

Instructions...

## Related

- `@other/SKILL.md` - Description
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
