---
name: smith-standards
description: Universal coding standards for emoji usage, comments, acronym expansion, datetime formatting, and file conventions. Use when writing code, logs, documentation, or any text output. Always active as universal rules for all development.
---

# Universal Coding Standards

**Scope:** Universal coding standards (emoji, comments, acronyms, datetime)
**Load if:** Always active (universal rules for all development)
**Prerequisites:** @smith-principles/SKILL.md

## Universal Rules

No decorative emoji; exactly one trailing newline; self-documenting code over
comments; every acronym and shorthand expanded on first use; ISO 8601
timestamps with timezone. Full rules in the sections below.

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

## Acronym and Shorthand Expansion

These rules cover every output — anything you write that a human other than
you may read, for example chat, documents, commit and pull-request text,
code comments, diagrams including Mermaid node labels, logs, Slack messages,
and tickets. Assume every file you create or edit is an output; there is no
internal-file exemption.

- Spell out every acronym or abbreviation in full on its first use in each
  output. Write `Retrieval-Augmented Generation (RAG)` first, then `RAG`
  afterward.
- Let identifiers keep their own rules: branch names, commit and
  pull-request titles, their types and scopes, filenames, code symbols, and
  literal code markers such as `TODO`. Identifiers follow
  `@smith-style/SKILL.md`, where domain-standard `gh`, `pr`, `ci`, and `mcp`
  stay abbreviated; in prose those four expand to GitHub, pull request,
  continuous integration, and Model Context Protocol.
- Name any referenced work in full on first use — book, paper, dataset,
  tool, experiment variant, internal document — with a one-line gloss and a
  locator or attribution (URL, file path, issue reference, or author and
  year), so a reader can follow the sentence without looking it up. Write
  `Working Effectively with Legacy Code`, the 2004 book by Michael Feathers,
  rather than a bare title.
- Replace internal index codes (`M1`, `S5`, `C-6`), names coined for this
  work whenever they were coined, and codes borrowed from another
  document's table with a descriptive name — quote the row's content, not
  its index code. A bare code carries no meaning outside the index that
  defines it.
- Exempt an abbreviation in prose in exactly two cases. First, you opened the
  repository's session-start instructions (root `CLAUDE.md` / `AGENTS.md`
  and the files they import) and saw its expansion there; that exemption
  does not travel, so expand it in pull-request text, tickets, Slack, and
  chat. Second, it appears in this list: `AI`, `API`, `CLI`, `CPU`, `CSV`,
  `HTML`, `HTTP`, `ID`, `ISO`, `JSON`, `OS`, `PDF`, `SQL`, `UI`, `URL`,
  `UTC`. Everything absent from the list expands, however obvious it feels —
  your own field's everyday shorthand does not qualify, which is why `RAG`
  above expands. Adding to the list is an edit to this file, not a call you
  make while writing.
- Say you do not know an abbreviation's expansion rather than guessing one.
- Before calling any output done, scan it for abbreviations, shorthand,
  capitalized short forms, and codes, and confirm each has an expansion at
  its first appearance.
- Add a glossary near the top of a long document as well as, never instead
  of, the inline expansion at each term's first appearance.

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

**Before committing or sending:**
1. No decorative emoji in code/logs
2. Exactly one trailing newline
3. Self-documenting names over comments
4. Every acronym and shorthand expanded on first use
5. ISO 8601 timestamps with timezone
