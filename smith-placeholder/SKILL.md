---
name: smith-placeholder
description: Placeholder syntax standard — guillemets «token» in every context. Use when writing prompts, documentation, usage strings, or any content with user-substitutable values.
---

# Placeholder Syntax Standards

<metadata>

- **Scope**: Placeholder syntax for documentation, prompts, and usage strings
- **Load if**: Writing prompts, documentation, or pattern descriptions
- **Prerequisites**: @smith-principles/SKILL.md, @smith-standards/SKILL.md

</metadata>

<context>

A placeholder marks where a reader substitutes a value. The delimiter must not
collide with the grammar of any context it appears in. No ASCII bracket pair is
collision-free: `<x>`=XML/HTML tag, `[x]`=CLI-optional + glob/regex + markdown
link, `{x}`/`{{x}}`=f-string/jinja templating. Guillemets `«»` carry no meaning
in any of those grammars, so smith uses them everywhere — one rule, zero clash.

</context>

## CRITICAL: Standard Form (Primacy Zone)

<required>

**Placeholder = `«token»`** (U+00AB `«` / U+00BB `»`) in EVERY context — prose,
inline-backtick paths, command examples, CLI usage synopses, code identifiers,
injected-prompt strings.

- Prose / inline: use the «project-slug»; `claude mcp remove «name»`
- Path / value: `` `~/.claude/projects/«project-slug»/memory/` ``
- Compound (join sub-tokens with literal separators): `«plugin»@«marketplace»`,
  `«type»/«scope»_«description»`
- Code identifier: `ralph_«task»_state`, `def test_«action»_when_«condition»()`
- CLI usage synopsis: `verify-stack-scope.sh «branch-pattern»`

Keep the token name descriptive (`«project-slug»`, not `«x»`).

**Required vs optional** in a CLI synopsis is stated in words or enforced by the
command itself — NEVER by delimiter shape. `«token»` always means "substitute a
value", never "optional".

</required>

<forbidden>

Never use as a placeholder:

- `<token>` — parses as an XML/HTML tag
- `[token]` — collides with CLI-optional grammar, shell globs, and markdown
  links; `[]` stays reserved for its native uses (links `[text](url)`, task
  checkboxes `- [ ]` / `- [x]`)
- `{token}` / `{{token}}` — f-string / jinja / handlebars templating

</forbidden>

## Typing «»

- macOS: `⌥\` → `«`, `⌥⇧\` → `»`
- Linux (Compose): `Compose < <` → `«`, `Compose > >` → `»`
- Anywhere: copy `«»`, or `«` = U+00AB, `»` = U+00BB

Guillemets are functional Unicode delimiters (permitted by @smith-standards,
which forbids only decorative emoji).

## Code Block Conventions

A literal UPPER_SNAKE value is still fine when the token is an in-place
identifier the reader edits rather than a substituted argument:

```shell
export API_KEY="YOUR_API_KEY"
git checkout -b "feat/«scope»_«description»"
```

## ACTION (Recency Zone)

<required>

**When writing placeholders:**
1. Use `«token»` in all contexts (prose, inline backticks, code, usage strings)
2. Keep the token name descriptive: `«project-slug»`, `«plugin»@«marketplace»`
3. Never use `<>` (XML), `[]` (CLI-optional / links), or `{}`/`{{}}` (templating)
4. Show required/optional in words, not delimiter shape

</required>

<related>

- `@smith-xml/SKILL.md` - XML tag standards
- `@smith-style/SKILL.md` - File/branch naming patterns
- @smith-standards/SKILL.md - Functional Unicode is allowed; decorative emoji is not

</related>
