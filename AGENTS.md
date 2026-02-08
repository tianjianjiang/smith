# Smith AI Agent Skills

AI agent skills for development with progressive disclosure.

<metadata>

- **Always loaded**: @smith-principles/SKILL.md, @smith-standards/SKILL.md, @smith-guidance/SKILL.md, @smith-ctx/SKILL.md
- **Load condition**: Session start (all platforms)
- **Token budget**: This file ~500 tokens, per-skill <2000 tokens

</metadata>

## Platform Context (Load First)

<required>

**Auto-detect platform in order:**
1. **MCP servers**: Check for `cursor-ide-browser` or `cursor-browser-extension` → **Cursor** → Load `@smith-ctx-cursor/SKILL.md`
2. **MCP servers**: Check for `kiro-*` → **Kiro** → Load `@smith-ctx-kiro/SKILL.md`
3. **System prompt**: If mentions "Claude Code" → **Claude Code** → Load `@smith-ctx-claude/SKILL.md`
4. **Default**: Ask user or use Cursor (most common)

</required>

**Manual override** (if auto-detection fails):
- **Cursor**: Load `@smith-ctx-cursor/SKILL.md`
- **Kiro**: Load `@smith-ctx-kiro/SKILL.md`
- **Claude Code**: Load `@smith-ctx-claude/SKILL.md`

## Claude Code Skills Integration

<context>

**Symlink for skill discovery:**
```shell
ln -sf $HOME/.smith $HOME/.claude/skills
```

All skills use "smith-" prefix to avoid conflicts with Claude Code built-in commands (`/context`, `/ide`, `/skills`, etc.).

</context>

## Serena MCP Integration (If Available)

<required>

**If Serena MCP server is available, at session start:**

1. Load memory: `agents_md_loading_protocol` - Contains complete AGENTS.md loading protocol
   - Use: `read_memory("agents_md_loading_protocol")` (Serena MCP tool)
   - This memory documents how to load all workspace AGENTS.md files and skills

2. Follow the protocol in that memory for loading workspace-specific AGENTS.md files

</required>

## Always Load

@smith-principles/SKILL.md @smith-standards/SKILL.md @smith-guidance/SKILL.md @smith-ctx/SKILL.md

## Core Principles

- **DRY**: Don't Repeat Yourself
- **KISS**: Keep It Simple, Stupid
- **YAGNI**: You Aren't Gonna Need It
- **SOLID**: Single Responsibility, Open/Closed, Liskov, Interface Segregation, Dependency Inversion
- **HHH**: Helpful, Honest, Harmless (see @smith-guidance/SKILL.md)

## Skill Loading

<required>

**Before each task**:
1. Identify which skills apply
2. Read the skill files using tools
3. Report using notification format below
4. Unload after 5 turns unused

</required>

## Skill Notification Format

<required>

ALWAYS notify on skill state changes using format: `{Action}: @{skill-name} ({reason})`

Actions: `Skills loaded`, `Activated`, `Loaded`, `Unloaded`

Format: short names (omit `/SKILL.md`), reason in parentheses, group multiple on one line.

</required>

## Proactive Context Management

<required>

- **At warning threshold**: Warn, prepare retention criteria, unload unused skills
- **At critical threshold**: CRITICAL - context reset required (see platform skill for thresholds and command)

</required>

<available_skills>
<!-- Core (always load) -->
<skill name="smith-principles" description="DRY, KISS, YAGNI, SOLID principles">@smith-principles/SKILL.md</skill>
<skill name="smith-standards" description="Universal coding standards">@smith-standards/SKILL.md</skill>
<skill name="smith-guidance" description="AI agent behavior patterns">@smith-guidance/SKILL.md</skill>
<skill name="smith-ctx" description="Context management, proactive recommendations">@smith-ctx/SKILL.md</skill>

<!-- Context (platform-specific) -->
<skill name="smith-ctx-kiro" description="Kiro-specific rules">`@smith-ctx-kiro/SKILL.md`</skill>
<skill name="smith-ctx-claude" description="Claude Code rules">`@smith-ctx-claude/SKILL.md`</skill>
<skill name="smith-ctx-cursor" description="Cursor rules">`@smith-ctx-cursor/SKILL.md`</skill>
<skill name="smith-serena" description="Serena MCP integration">`@smith-serena/SKILL.md`</skill>

<!-- Reasoning -->
<skill name="smith-analysis" description="Problem decomposition, Polya method">`@smith-analysis/SKILL.md`</skill>
<skill name="smith-clarity" description="Cognitive traps, logic fallacies">`@smith-clarity/SKILL.md`</skill>
<skill name="smith-design" description="SOLID principles, architecture">`@smith-design/SKILL.md`</skill>
<skill name="smith-validation" description="Hypothesis testing, debugging">`@smith-validation/SKILL.md`</skill>
<skill name="smith-postmortem" description="Incident postmortem methodology">`@smith-postmortem/SKILL.md`</skill>

<!-- Testing -->
<skill name="smith-tests" description="Testing standards, TDD workflow">`@smith-tests/SKILL.md`</skill>
<skill name="smith-playwright" description="Playwright testing, proactive failure monitoring">`@smith-playwright/SKILL.md`</skill>

<!-- Languages -->
<skill name="smith-python" description="Python patterns and testing">`@smith-python/SKILL.md`</skill>
<skill name="smith-typescript" description="TypeScript patterns">`@smith-typescript/SKILL.md`</skill>
<skill name="smith-nuxt" description="Nuxt.js framework">`@smith-nuxt/SKILL.md`</skill>

<!-- Git/GitHub -->
<skill name="smith-git" description="Git commits, merges, rebases">`@smith-git/SKILL.md`</skill>
<skill name="smith-gh-pr" description="PR creation and review">`@smith-gh-pr/SKILL.md`</skill>
<skill name="smith-gh-cli" description="GitHub CLI usage">`@smith-gh-cli/SKILL.md`</skill>
<skill name="smith-style" description="Commit message conventions">`@smith-style/SKILL.md`</skill>
<skill name="smith-stacks" description="Stacked PR workflows">`@smith-stacks/SKILL.md`</skill>

<!-- Workflow -->
<skill name="smith-ralph" description="Ralph Loop iterative development">`@smith-ralph/SKILL.md`</skill>
<skill name="smith-plan" description="Plan tracking protocol (portable)">`@smith-plan/SKILL.md`</skill>
<skill name="smith-plan-claude" description="Plan automation (Claude Code hooks)">`@smith-plan-claude/SKILL.md`</skill>

<!-- Other -->
<skill name="smith-prompts" description="Prompt engineering">`@smith-prompts/SKILL.md`</skill>
<skill name="smith-xml" description="XML tag patterns for AI">`@smith-xml/SKILL.md`</skill>
<skill name="smith-placeholder" description="Documentation placeholders">`@smith-placeholder/SKILL.md`</skill>
<skill name="smith-tools" description="Development tools">`@smith-tools/SKILL.md`</skill>
<skill name="smith-dev" description="Development workflow">`@smith-dev/SKILL.md`</skill>
<skill name="smith-ide" description="IDE configuration">`@smith-ide/SKILL.md`</skill>
<skill name="smith-research" description="Research methodology">`@smith-research/SKILL.md`</skill>
<skill name="smith-skills" description="Skill authoring">`@smith-skills/SKILL.md`</skill>
</available_skills>

## Semantic Activation

<required>

**Load on task match, unload after 5 turns unused**:

**Languages**: Python → `@smith-python/SKILL.md`, TypeScript → `@smith-typescript/SKILL.md`, Nuxt → `@smith-nuxt/SKILL.md`
**Testing**: Tests/TDD → `@smith-tests/SKILL.md`,
  Playwright → `@smith-playwright/SKILL.md`
**Workflow**: Ralph Loop → `@smith-ralph/SKILL.md`
**Plan**: Plan execution → `@smith-plan/SKILL.md`,
  Claude Code hooks/`!load-plan` → `@smith-plan-claude/SKILL.md`
**Git/GitHub**: Commits → `@smith-git/SKILL.md`,
  PRs/reviews/`gh pr*` → `@smith-gh-pr/SKILL.md`
**Reasoning**: Analysis → `@smith-analysis/SKILL.md`, Design → `@smith-design/SKILL.md`, Debug → `@smith-validation/SKILL.md`
**Other**: Prompts → `@smith-prompts/SKILL.md`, XML → `@smith-xml/SKILL.md`

</required>

## Platform Compatibility

**Native AGENTS.md**: Claude Code, OpenAI Codex, Amp, Jules, Kiro, Cursor
**Config required**: Gemini CLI, Aider
**Note**: Cursor also supports `.mdc` format, but AGENTS.md works via MCP integration

## Kiro Terminal (CRITICAL)

<forbidden>

- echo with double quotes (hangs)
- heredoc syntax (fails)
- Complex zsh themes (hangs)

</forbidden>

<required>

- Use Python scripts for file generation
- Prefer Serena MCP tools over Kiro native file operations
- Use single quotes or write to file instead of echo

</required>

<related>

- @smith-principles/SKILL.md - Core principles (DRY, KISS, YAGNI, SOLID)
- @smith-standards/SKILL.md - Universal coding standards
- @smith-guidance/SKILL.md - AI agent behavior patterns
- @smith-ctx/SKILL.md - Context management, proactive recommendations

</related>
