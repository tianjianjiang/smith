# Universal Coding Standards

<metadata>

- **Scope**: Universal coding standards (emoji restrictions, inline comments policy, trailing newlines, datetime standards)
- **Load if**: Starting any development task, code writing
- **Prerequisites**: @principles.md
- **Referenced by**: All rules*.md files, all AGENTS.md files

</metadata>

<context>

Universal standards that apply to all code, logs, documentation, and outputs across all languages and contexts.

</context>

## Universal Code Standards

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

## DateTime Standards

**Timezone**: All timestamps MUST use Asia/Tokyo (UTC+9)
**Format**: ISO 8601 with timezone: `YYYY-MM-DDTHH:MM:SS+09:00`

**Examples:**
- Python: `datetime.now().astimezone().isoformat()`
- JavaScript: `new Date().toISOString()` (convert to JST)

<related>

- @principles.md - Fundamental coding principles
- @quality.md - Code quality standards
- @style.md - Detailed path and naming standards

</related>
