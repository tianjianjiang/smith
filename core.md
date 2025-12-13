# Core Coding Standards

<metadata>

- **Scope**: Personal coding rules for all languages and outputs
- **Load if**: Starting any development task, file creation, code writing
- **Prerequisites**: None (foundation for all other rules)
- **Requires**: None (foundation document)
- **Referenced by**: All rules*.md files, all AGENTS.md files
- **Optional**: None (personal foundation)

</metadata>

<context>

Fundamental coding rules applying as personal standards across all languages, code, documentation, and outputs.

</context>

## Fundamental Principles

<required>

- **DRY** (Don't Repeat Yourself): Single source of truth; eliminate duplication
- **KISS** (Keep It Simple, Stupid): Simplest solution that works; avoid unnecessary complexity
- **YAGNI** (You Aren't Gonna Need It): Don't implement until actually needed
- **SINE** (Simple Is Not Easy): Simplicity requires deliberate effort; refactor toward simplicity
- **MECE** (Mutually Exclusive, Collectively Exhaustive): Categories don't overlap; coverage is complete
- **Occam's Razor**: Prefer solutions with fewest assumptions

</required>

## Critical Coding Rules

**NEVER violate these rules - STRICTLY ENFORCED across ALL tools and outputs**

### Universal Code Standards

<forbidden>

- **NEVER use decorative emoji** (including ❌, ✅, ⚠️, 📝, 🎉, 👍) in code, logs, print statements, error messages, or documentation. Exception: user-facing UI text if explicitly requested. Unicode symbols for functional purposes (arrows →, math ±×÷) are allowed. Checkmarks (check and cross marks) are redundant when followed by descriptive labels (Good/Bad, Correct/Incorrect).
- NEVER add excessive blank lines between code blocks
- NEVER commit files without exactly one trailing newline

</forbidden>

<required>

**Inline Comments**:
- ONLY add inline comments when code intent is not self-evident from naming and structure
- Prefer self-documenting code (clear variable/function names) over inline comments
- Allowed cases: Config files (.env), TODO markers, complex algorithms, non-obvious business logic

**File Format**:
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

**For AI agent workflows and principles**: See @ai.md for comprehensive coverage:
- Constitutional AI principles (Helpful, Honest, Harmless framework)
- Exploration-before-implementation patterns
- Code quality and security requirements
- Structured output steering

**Core requirement**: Agent output MUST follow the same standards as human-written code (emoji restrictions, formatting, etc.)

<required>

**Rule Loading Notification**: Agent MUST proactively report when rules are dynamically loaded or unloaded, including both the rule files and the context triggers that caused the changes. See @AGENTS.md for detailed specification. This notification is always active.

</required>

### Systematic Thinking

See context-triggered files for critical thinking techniques:
- @design.md - Design principles (DRY, KISS, YAGNI, SOLID)
- @talk.md - Anti-sycophancy, Socratic method (always_active)
- @think.md - Reasoning, problem decomposition, Polya's method
- @verify.md - Hypothesis testing, root cause analysis
- @guard.md - Cognitive guards

## Path Reference Conventions

**Use standardized path variables:**
- `$HOME/` instead of `~/`
- `$WORKSPACE_ROOT/` for workspace-relative paths
- `$REPO_ROOT/` for repository-relative paths

**See:** @naming.md for detailed path standards

<related>

## Language-Specific Standards

For language-specific rules, see:
- **Python**: @python.md
- **TypeScript/JavaScript**: (Create rules-typescript.md as needed)

## Development Workflow

For daily workflow, code quality checks, and tool usage:
- @dev.md
- @testing.md

## Version Control

For Git and GitHub workflows:
- @git.md
- @gh-pr.md
- @gh-cli.md

</related>

### Pull Requests

<forbidden>

- **NEVER** force push to PRs from other authors
- **NEVER** amend commits that are already pushed to shared branches
- **NEVER** amend commits from other authors (check authorship first)
- **NEVER** merge your own PR without review (unless emergency hotfix)
- **NEVER** create PRs with failing tests or linting errors

</forbidden>
