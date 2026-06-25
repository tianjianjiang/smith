---
name: smith-placeholder
description: Placeholder syntax standards for documentation and prompts. Use when writing prompts, documentation, pattern descriptions, or any content with user-substitutable values.
---

# Placeholder Syntax Standards

<metadata>

- **Scope**: Placeholder syntax for documentation and prompts
- **Load if**: Writing prompts, documentation, or pattern descriptions
- **Prerequisites**: @smith-principles/SKILL.md, @smith-standards/SKILL.md

</metadata>

<context>

Placeholders indicate where users substitute values. Syntax must avoid conflicts with Jinja2, Python f-strings, and XML tags.

Code blocks within documents follow their own language conventions.

</context>

## Recommended Syntax

<required>

**`[placeholder]` brackets are the standard form in EVERY context** — prose,
inline-backtick spans, and fenced code blocks. One rule, no nesting conflicts.

- Prose / inline token: `[placeholder]`, e.g. `claude mcp remove [name]`
- Placeholder as a segment of a backtick path or command:
  `` `~/.claude/projects/[project-slug]/memory/` ``, `` `feat/[name]` ``
- Compound tokens: `[plugin]@[marketplace]`, `type/[scope]_[description]`
- Inside fenced code blocks: `[placeholder]` too (e.g. `claude mcp remove [name]`).
  Reach for a literal UPPER_SNAKE value (`YOUR_API_KEY`) only when the value is
  an in-place identifier the user edits, not a substituted argument.

Keep the token name descriptive (`[project-slug]`, not `[x]`).

</required>

<forbidden>

**Avoid in documentation**:

- `{{placeholder}}` - Jinja2 template conflict
- `{placeholder}` - Python f-string conflict
- `<placeholder>` - XML tag conflict

</forbidden>

## Code Block Conventions

Code blocks follow their language's conventions:

Shell (use literal UPPER_SNAKE or quotes):
```shell
git checkout -b "feat/FEATURE_NAME"
export API_KEY="YOUR_API_KEY"
```

```python
# Python: use descriptive identifiers
user_input = "..."  # Replace with actual input
```

```javascript
// JavaScript: use string literals
const apiKey = "YOUR_API_KEY";
```

## ACTION (Recency Zone)

<required>

**When writing placeholders:**
1. Use `[placeholder]` brackets in all contexts (prose, inline backticks, code blocks)
2. Keep the token name descriptive: `[project-slug]`, `[plugin]@[marketplace]`
3. Avoid Jinja2 `{{}}`, f-string `{}`, and XML `<>` syntax

</required>

<related>

- `@smith-xml/SKILL.md` - XML tag standards
- `@smith-style/SKILL.md` - File/branch naming patterns

</related>
