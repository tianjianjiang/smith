# Core Coding Standards

<metadata>

- **Scope**: Personal coding rules for all languages and outputs
- **Load if**: Starting any development task, file creation, code writing
- **Prerequisites**: None (foundation for all other rules)

</metadata>

<dependencies>

- **Requires**: None (foundation document)
- **Referenced by**: All rules*.md files, all AGENTS.md files
- **Optional**: None (personal foundation)

</dependencies>

<context>

Fundamental coding rules applying as personal standards across all languages, code, documentation, and outputs.

</context>

## Critical Coding Rules

**NEVER violate these rules - STRICTLY ENFORCED across ALL tools and outputs**

### Universal Code Standards

<forbidden>

- NEVER write inline comments except in config files (.env, .env.sample, .env.tmpl) or `# TODO:` comments
- **NEVER use decorative emoji** (including ❌, ✅, ⚠️, 📝, 🎉, 👍) in code, logs, print statements, error messages, or documentation. Exception: user-facing UI text if explicitly requested. Unicode symbols for functional purposes (arrows →, math ±×÷) are allowed. Checkmarks (check and cross marks) are redundant when followed by descriptive labels (Good/Bad, Correct/Incorrect).
- NEVER write excessive blank lines between code blocks
- NEVER commit files without exactly one trailing newline

</forbidden>

<required>

- ALWAYS have exactly one newline at the end of every file
- ALWAYS use language-appropriate formatters before commits
- ALWAYS use descriptive names following language conventions

</required>

### Formatting Standards

**Line Length**: 120 characters maximum (adjust for language if needed)
**Indentation**: Use spaces, not tabs
- Python: 4 spaces
- TypeScript/JavaScript: 2 spaces
- Follow language-specific standards

**String Quotes**: Consistent within language
- Python: Double quotes preferred
- JavaScript/TypeScript: Single quotes or project standard

**Code Blocks in Documentation**:
- Use `sh` for shell commands (portable across bash, zsh, fish)
- Describe code blocks outside the block, not with inline comments
- Use `text` for non-executable examples (commit messages, diagrams)

### DateTime Standards

**Timezone**: All timestamps MUST use Asia/Tokyo (UTC+9)
**Format**: ISO 8601 with timezone: `YYYY-MM-DDTHH:MM:SS+09:00`

**Examples:**
- Python: `datetime.now().astimezone().isoformat()`
- JavaScript: `new Date().toISOString()` (convert to JST)

### Quality Standards

**Documentation:**
- Use precise, technical language
- Maintain consistent terminology
- Follow these standards in ALL text outputs

**Testing:**
- ALWAYS update reports when standards change
- Maintain test documentation accuracy

**Code Reuse:**
- ALWAYS check existing scripts before creating new ones
- Check `debug_scripts/` and language-specific tool directories

## AI Agent Output Standards

**For AI agent workflows and principles**: See `$HOME/.smith/rules-ai_agents.md` for comprehensive coverage:
- Constitutional AI principles (Helpful, Honest, Harmless framework)
- Exploration-before-implementation patterns
- Code quality and security requirements
- Structured output steering

**Core requirement**: Agent output MUST follow the same standards as human-written code (emoji restrictions, formatting, etc.)

## Path Reference Conventions

**Use standardized path variables:**
- `$HOME/` instead of `~/`
- `$WORKSPACE_ROOT/` for workspace-relative paths
- `$REPO_ROOT/` for repository-relative paths

**See:** [Naming Conventions]($HOME/.smith/rules-naming.md) for detailed path standards

<related>

## Language-Specific Standards

For language-specific rules, see:
- **Python**: [Python Standards]($HOME/.smith/rules-python.md)
- **TypeScript/JavaScript**: (Create rules-typescript.md as needed)

## Development Workflow

For daily workflow, code quality checks, and tool usage:
- [Development Standards]($HOME/.smith/rules-development.md)
- [Testing Standards]($HOME/.smith/rules-testing.md)

## Version Control

For Git and GitHub workflows:
- [Git Standards]($HOME/.smith/rules-git.md)
- [PR Workflows]($HOME/.smith/rules-pr-concepts.md) - Platform-neutral concepts
- [GitHub PR Operations]($HOME/.smith/rules-github-pr.md)
- [GitHub Workflows]($HOME/.smith/rules-github.md)

</related>

### Pull Requests

<forbidden>

- **NEVER** force push to PRs from other authors
- **NEVER** amend commits that are already pushed to shared branches
- **NEVER** amend commits from other authors (check authorship first)
- **NEVER** merge your own PR without review (unless emergency hotfix)
- **NEVER** create PRs with failing tests or linting errors

</forbidden>
