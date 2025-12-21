# Smith Coding Standards

Personal coding standards for AI-assisted development with progressive disclosure.

<metadata>

- **Always loaded**: @principles.md, @standards.md, @guidance.md
- **Load condition**: Session start (all platforms)
- **Token budget**: This file ~500 tokens, per-standard <2000 tokens

</metadata>

## Rule Loading Protocol (CRITICAL)

<required>

**Before each task, agent MUST report loaded files**:
- Format: "Loaded @python.md (Python task detected)"
- Format: "Unloaded @git.md (no Git operations for 5+ turns)"
- Always-active files: Assume loaded, do not report

**Enforcement**: Reporting demonstrates actual file reading, not fake compliance

</required>

## Semantic Activation

<required>

**Load on task match, unload after 5 turns unused**:
- Python code/tests → @python.md
- Git commits/merges → @git.md, @style.md
- PR create/review → @gh-pr.md, @gh-cli.md
- Tests → @tests.md
- Prompts/AI → @xml.md, @prompts.md
- Platform detect → @context-{platform}.md (never unload)

</required>

## Proactive Compaction

<required>

- **At 60% context**: Recommend /compact, unload unused files
- **At 70% context**: CRITICAL - compact before degradation
- **Lost-in-middle**: LLMs weaken in middle 60% of context

</required>

## Core Principles

- **DRY**: Don't Repeat Yourself
- **KISS**: Keep It Simple, Stupid
- **YAGNI**: You Aren't Gonna Need It
- **SOLID**: Single Responsibility, Open/Closed, Liskov, Interface Segregation, Dependency Inversion
- **HHH**: Helpful, Honest, Harmless (see @guidance.md)

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

- @principles.md - Core principles (DRY, KISS, YAGNI, SOLID)
- @standards.md - Universal coding standards
- @guidance.md - AI agent behavior patterns
- @context.md - Context management thresholds

</related>

## Platform Compatibility

**Native AGENTS.md**: Claude Code, OpenAI Codex, Amp, Jules, Kiro
**Config required**: Gemini CLI, Aider
**Not compatible**: Cursor (.mdc format)
