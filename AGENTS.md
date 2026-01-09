# Smith Coding Standards

Personal coding standards for AI-assisted development with progressive disclosure.

<metadata>

- **Always loaded**: @principles/SKILL.md, @standards/SKILL.md, @guidance/SKILL.md
- **Load condition**: Session start (all platforms)
- **Token budget**: This file ~500 tokens, per-skill <2000 tokens

</metadata>

## Platform Context (Load First)

<required>

**Auto-detect platform in order:**
1. **MCP servers**: Check for `cursor-ide-browser` or `cursor-browser-extension` → **Cursor** → Load @context-cursor/SKILL.md
2. **MCP servers**: Check for `kiro-*` → **Kiro** → Load @context-kiro/SKILL.md
3. **System prompt**: If mentions "Claude Code" → **Claude Code** → Load @context-claude/SKILL.md
4. **Default**: Ask user or use Cursor (most common)

</required>

**Manual override** (if auto-detection fails):
- **Cursor**: Load @context-cursor/SKILL.md
- **Kiro**: Load @context-kiro/SKILL.md
- **Claude Code**: Load @context-claude/SKILL.md

## Serena MCP Integration (If Available)

<required>

**If Serena MCP server is available, at session start:**

1. Load memory: `agents_md_loading_protocol` - Contains complete AGENTS.md loading protocol
   - Use: `mcp_oraiosserena_read_memory("agents_md_loading_protocol")`
   - This memory documents how to load all workspace AGENTS.md files and skills

2. Follow the protocol in that memory for loading workspace-specific AGENTS.md files

</required>

## Always Load

@principles/SKILL.md @standards/SKILL.md @guidance/SKILL.md

## Core Principles

- **DRY**: Don't Repeat Yourself
- **KISS**: Keep It Simple, Stupid
- **YAGNI**: You Aren't Gonna Need It
- **SOLID**: Single Responsibility, Open/Closed, Liskov, Interface Segregation, Dependency Inversion
- **HHH**: Helpful, Honest, Harmless (see @guidance/SKILL.md)

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

**Always notify when skills change state:**

- **Session start**: `Skills loaded: @principles, @standards, @guidance, @context-{platform}`
- **Task activation**: `Activated: @python (task match: Python code detected)`
- **Explicit load**: `Loaded: @git (user requested)`
- **Unload**: `Unloaded: @python (5 turns unused)`

**Format rules:**
- Use short names (omit `/SKILL.md` suffix)
- Include reason in parentheses
- Group multiple loads on one line when possible
- Always notify on state change (load/unload)

</required>

## Proactive Compaction

<required>

- **At 60% context**: Recommend /compact, unload unused
- **At 70% context**: CRITICAL - compact before degradation

</required>

<available_skills>
<!-- Core (always load) -->
<skill name="principles" description="DRY, KISS, YAGNI, SOLID principles">@principles/SKILL.md</skill>
<skill name="standards" description="Universal coding standards">@standards/SKILL.md</skill>
<skill name="guidance" description="AI agent behavior patterns">@guidance/SKILL.md</skill>

<!-- Context -->
<skill name="context" description="Context management thresholds">`@context/SKILL.md`</skill>
<skill name="context-kiro" description="Kiro-specific rules">`@context-kiro/SKILL.md`</skill>
<skill name="context-claude" description="Claude Code rules">`@context-claude/SKILL.md`</skill>
<skill name="context-cursor" description="Cursor rules">`@context-cursor/SKILL.md`</skill>
<skill name="serena" description="Serena MCP integration">`@serena/SKILL.md`</skill>

<!-- Reasoning -->
<skill name="analysis" description="Problem decomposition, Polya method">`@analysis/SKILL.md`</skill>
<skill name="clarity" description="Cognitive traps, logic fallacies">`@clarity/SKILL.md`</skill>
<skill name="design" description="SOLID principles, architecture">`@design/SKILL.md`</skill>
<skill name="validation" description="Hypothesis testing, debugging">`@validation/SKILL.md`</skill>
<skill name="postmortem" description="Incident postmortem methodology">`@postmortem/SKILL.md`</skill>

<!-- Testing -->
<skill name="tests" description="Testing standards, TDD workflow">`@tests/SKILL.md`</skill>

<!-- Languages -->
<skill name="python" description="Python patterns and testing">`@python/SKILL.md`</skill>
<skill name="typescript" description="TypeScript patterns">`@typescript/SKILL.md`</skill>
<skill name="nuxt" description="Nuxt.js framework">`@nuxt/SKILL.md`</skill>

<!-- Git/GitHub -->
<skill name="git" description="Git commits, merges, rebases">`@git/SKILL.md`</skill>
<skill name="gh-pr" description="PR creation and review">`@gh-pr/SKILL.md`</skill>
<skill name="gh-cli" description="GitHub CLI usage">`@gh-cli/SKILL.md`</skill>
<skill name="style" description="Commit message conventions">`@style/SKILL.md`</skill>
<skill name="stacks" description="Stacked PR workflows">`@stacks/SKILL.md`</skill>

<!-- Other -->
<skill name="prompts" description="Prompt engineering">`@prompts/SKILL.md`</skill>
<skill name="xml" description="XML tag patterns for AI">`@xml/SKILL.md`</skill>
<skill name="placeholder" description="Documentation placeholders">`@placeholder/SKILL.md`</skill>
<skill name="tools" description="Development tools">`@tools/SKILL.md`</skill>
<skill name="dev" description="Development workflow">`@dev/SKILL.md`</skill>
<skill name="ide" description="IDE configuration">`@ide/SKILL.md`</skill>
<skill name="research" description="Research methodology">`@research/SKILL.md`</skill>
<skill name="skills" description="Skill authoring">`@skills/SKILL.md`</skill>
</available_skills>

## Semantic Activation

<required>

**Load on task match, unload after 5 turns unused**:

**Languages**: Python → `@python/SKILL.md`, TypeScript → `@typescript/SKILL.md`, Nuxt → `@nuxt/SKILL.md`
**Testing**: Tests/TDD → `@tests/SKILL.md`
**Git/GitHub**: Commits → `@git/SKILL.md`, PRs → `@gh-pr/SKILL.md`
**Reasoning**: Analysis → `@analysis/SKILL.md`, Design → `@design/SKILL.md`, Debug → `@validation/SKILL.md`
**Other**: Prompts → `@prompts/SKILL.md`, XML → `@xml/SKILL.md`

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

- @principles/SKILL.md - Core principles (DRY, KISS, YAGNI, SOLID)
- @standards/SKILL.md - Universal coding standards
- @guidance/SKILL.md - AI agent behavior patterns
- `@context/SKILL.md` - Context management thresholds

</related>
