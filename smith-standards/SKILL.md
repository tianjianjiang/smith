---
name: smith-standards
description: Universal coding standards for emoji usage, comments, datetime formatting, and file conventions. Use when writing code, logs, documentation, or any text output. Always active as universal rules for all development.
---

# Universal Coding Standards

**Scope:** Universal coding standards (emoji, comments, datetime)
**Load if:** Always active (universal rules for all development)
**Prerequisites:** @smith-principles/SKILL.md

## Universal Rules

No decorative emoji; exactly one trailing newline; self-documenting code over
comments; ISO 8601 timestamps with timezone. Full rules below in "Universal
Code Standards" and "DateTime Standards".

Universal standards that apply to all code, logs, documentation, and outputs across all languages and contexts.

## Universal Code Standards

- Keep code, logs, print statements, error messages, and documentation free
  of decorative emoji (x-mark, check mark, warning, memo, celebration,
  thumbs-up) — except user-facing UI text if explicitly requested.
  Functional Unicode symbols (→, ±×÷) are fine; checkmarks are redundant
  next to descriptive labels.
- Keep blank lines between code blocks minimal

**Inline Comments**:
- ONLY add inline comments when code intent is not self-evident from naming and structure
- Prefer self-documenting code (clear variable/function names) over inline comments
- Allowed cases: Config files (.env), TODO markers, complex algorithms, non-obvious business logic

**File Format**:
- ALWAYS have exactly one newline at the end of every file
- ALWAYS use language-appropriate formatters before commits
- ALWAYS use descriptive names following language conventions

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

## Related

- @smith-principles/SKILL.md - Fundamental coding principles
- `@smith-style/SKILL.md` - Path and naming standards
- @smith-guidance/SKILL.md - AI agent behavior patterns (always active)
- `@smith-dev/SKILL.md` - Development workflow
- `@smith-tests/SKILL.md` - Testing standards
- `@smith-git/SKILL.md` - Version control
- `@smith-gh-pr/SKILL.md` - Pull request workflows
- `@smith-gh-cli/SKILL.md` - GitHub CLI operations

## Before You Finish

**Before committing:**
1. No decorative emoji in code/logs
2. Exactly one trailing newline
3. Self-documenting names over comments
4. ISO 8601 timestamps with timezone
