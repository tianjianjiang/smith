# Smith Coding Standards

Personal coding standards for AI-assisted development with progressive disclosure.

## Platform Context (Load First)

**Kiro**: Load @context-kiro/SKILL.md
**Claude Code**: Load @context-claude/SKILL.md

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
3. Report: "Loaded @principles/SKILL.md, @python/SKILL.md"

**Unload after 5 turns unused**

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

<!-- Other -->
<skill name="prompts" description="Prompt engineering">`@prompts/SKILL.md`</skill>
<skill name="xml" description="XML tag patterns for AI">`@xml/SKILL.md`</skill>
<skill name="placeholder" description="Documentation placeholders">`@placeholder/SKILL.md`</skill>
<skill name="tools" description="Development tools">`@tools/SKILL.md`</skill>
<skill name="stacks" description="Technology stacks">`@stacks/SKILL.md`</skill>
<skill name="dev" description="Development workflow">`@dev/SKILL.md`</skill>
<skill name="ide" description="IDE configuration">`@ide/SKILL.md`</skill>
<skill name="research" description="Research methodology">`@research/SKILL.md`</skill>
<skill name="skills" description="Skill authoring">`@skills/SKILL.md`</skill>
</available_skills>

## Semantic Activation

**Languages**: Python → `@python/SKILL.md`, TypeScript → `@typescript/SKILL.md`, Nuxt → `@nuxt/SKILL.md`
**Testing**: Tests/TDD → `@tests/SKILL.md`
**Git/GitHub**: Commits → `@git/SKILL.md`, PRs → `@gh-pr/SKILL.md`
**Reasoning**: Analysis → `@analysis/SKILL.md`, Design → `@design/SKILL.md`, Debug → `@validation/SKILL.md`
**Other**: Prompts → `@prompts/SKILL.md`, XML → `@xml/SKILL.md`

## Platform Compatibility

**Native AGENTS.md**: Claude Code, OpenAI Codex, Amp, Jules, Kiro
**Config required**: Gemini CLI, Aider
**Not compatible**: Cursor (.mdc format)

<related>

- @principles/SKILL.md - Core principles (DRY, KISS, YAGNI, SOLID)
- @standards/SKILL.md - Universal coding standards
- @guidance/SKILL.md - AI agent behavior patterns
- `@context/SKILL.md` - Context management thresholds

</related>
