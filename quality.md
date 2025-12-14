# Code Quality Standards

<metadata>

- **Scope**: Quality assurance, testing, documentation, code reuse, AI agent outputs
- **Load if**: Starting any development task, code review
- **Prerequisites**: @principles.md
- **Referenced by**: All rules*.md files, all AGENTS.md files

</metadata>

<context>

Quality standards for documentation, testing, code reuse, and AI agent outputs.

</context>

## Quality Standards

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

<required>

Agent output MUST follow the same standards as human-written code (emoji restrictions, formatting, etc.)

**For agent behavior patterns**: See @guidance.md for comprehensive coverage:
- Constitutional AI principles (Helpful, Honest, Harmless framework)
- Exploration-before-implementation patterns
- Anti-sycophancy and questioning techniques
- Code quality and security requirements

**Rule Loading Notification**: Agent MUST proactively report when rules are dynamically loaded or unloaded, including both the rule files and the context triggers that caused the changes. See @AGENTS.md for detailed specification.

</required>

## Path Reference Conventions

**Use standardized path variables:**
- `$HOME/` instead of `~/`
- `$WORKSPACE_ROOT/` for workspace-relative paths
- `$REPO_ROOT/` for repository-relative paths

**See:** @style.md for detailed path standards

<related>

- @principles.md - Fundamental coding principles
- @standards.md - Code formatting standards
- @guidance.md - AI agent behavior patterns
- @dev.md - Development workflow
- @tests.md - Testing standards
- @git.md - Version control standards
- @gh-pr.md - Pull request workflows
- @gh-cli.md - GitHub CLI operations

</related>
