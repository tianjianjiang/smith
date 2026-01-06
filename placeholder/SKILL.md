---
name: placeholder
description: Placeholder syntax standards for documentation and prompts. Use when writing prompts, documentation, pattern descriptions, or any content with user-substitutable values.
---

# Placeholder Syntax Standards

<metadata>

- **Scope**: Placeholder syntax for documentation and prompts
- **Load if**: Writing prompts, documentation, or pattern descriptions
- **Prerequisites**: @principles/SKILL.md, @standards/SKILL.md

</metadata>

<context>

Placeholders indicate where users substitute values. Syntax must avoid conflicts with Jinja2, Python f-strings, and XML tags.

Code blocks within documents follow their own language conventions.

</context>

## Recommended Syntax

<required>

**Inline Markdown** (primary):

- Backticks: `placeholder_name`, `PLACEHOLDER_NAME`
- Renders as monospace, visually distinct

**Inside code blocks** (when backticks nest):

- Brackets: `[placeholder]`
- Or language-native: `PLACEHOLDER` as literal identifier

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
1. Use backticks for inline markdown: `placeholder_name`
2. Use brackets inside code blocks: `[placeholder]`
3. Avoid Jinja2 `{{}}`, f-string `{}`, and XML `<>` syntax

</required>

<related>

- `@xml/SKILL.md` - XML tag standards
- `@style/SKILL.md` - File/branch naming patterns

</related>
