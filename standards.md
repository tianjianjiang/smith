# Universal Coding Standards

<metadata>

- **Scope**: Universal coding standards (emoji, comments, datetime)
- **Load if**: Always active (universal rules for all development)
- **Prerequisites**: @principles.md

</metadata>

## CRITICAL: Universal Rules (Primacy Zone)

<forbidden>

- Decorative emoji in code, logs, or documentation
- Files without exactly one trailing newline

</forbidden>

<required>

- Self-documenting code over inline comments
- ISO 8601 timestamps with timezone

</required>

<context>

Universal standards that apply to all code, logs, documentation, and outputs across all languages and contexts.

</context>

## Universal Code Standards

<forbidden>

- **NEVER use decorative emoji** (for example: x-mark, check mark, warning, memo, celebration, thumbs-up symbols) in code, logs, print statements, error messages, or documentation. Exception: user-facing UI text if explicitly requested. Functional Unicode symbols (→, ±×÷) are allowed. Checkmarks are redundant when followed by descriptive labels.
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

## DateTime Standards

**Timezone**: All timestamps MUST use local timezone dynamically
**Format**: ISO 8601 with timezone: `YYYY-MM-DDTHH:MM:SS±HH:MM`

**Examples:**
- Python: `datetime.now().astimezone().isoformat()` (automatically uses local timezone)
- JavaScript: `new Date().toISOString()` (UTC) or `new Date().toLocaleString('en-CA', {timeZoneName: 'short'})` (local with timezone)

## Quality Standards

**Documentation**: Use precise, technical language; maintain consistent terminology; follow these standards in ALL text outputs

**Testing**: ALWAYS update reports when standards change; maintain test documentation accuracy

**Code Reuse**: ALWAYS check existing scripts before creating new ones; check `debug_scripts/` and language-specific tool directories

<related>

- @principles.md - Fundamental coding principles
- `@style.md` - Path and naming standards
- @guidance.md - AI agent behavior patterns (always active)
- `@dev.md` - Development workflow
- `@tests.md` - Testing standards
- `@git.md` - Version control
- `@gh-pr.md` - Pull request workflows
- `@gh-cli.md` - GitHub CLI operations

</related>


## ACTION (Recency Zone)

<required>

**Before committing:**
1. No decorative emoji in code/logs
2. Exactly one trailing newline
3. Self-documenting names over comments
4. ISO 8601 timestamps with timezone

</required>
