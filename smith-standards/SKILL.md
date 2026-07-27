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
comments; shorthand you introduced expanded on first use; ISO 8601
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

- Expand every short form you introduced, on its first use in each output. A
  contraction made to fit a diagram node, a table cell, or a subject line is
  one you introduced: write `ground truth`, not `GT`.
- Leave the field's standing terms as they are — the vocabulary a reader of
  this repository already brings, such as `API`, `JSON`, `MCP`, `RAG`,
  `SQL`, and `URL`. Those are how the field writes; they are not
  compressions you made.
- Expand whatever you cannot place in either group — `LSP` reads as both
  Language Server Protocol and the Liskov Substitution Principle here.
- Let identifiers keep their own rules: branch names, the `type(scope):`
  prefix of commit and pull-request titles, filenames, code symbols, and
  literal code markers such as `TODO`. Identifiers follow
  `@smith-style/SKILL.md`, which owns the length threshold and the list of
  domain-standard terms. The description after the colon is prose.
- Name any referenced work in full on first use — book, paper, dataset, tool,
  experiment variant, internal document — with a one-line gloss and a locator
  (URL, file path, issue reference, or author and year), so a reader can
  follow the sentence without looking it up.
- Replace internal index codes (`M1`, `S5`, `C-6`), names coined for this work
  whenever they were coined, and codes borrowed from another document's table
  with a descriptive name — quote the row's content, not its index code.
- Expand a standing term too when the output leaves this repository. A pull
  request, ticket, or Slack message reaches people who never load these
  instructions.
- Say you do not know an abbreviation's expansion rather than guessing one.
- Before calling any output done, scan it for short forms and codes, and
  confirm each is an identifier, a standing term of the field, or expanded
  at its first appearance.
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
4. Shorthand you introduced expanded on first use
5. ISO 8601 timestamps with timezone
