---
name: smith-prompts
description: Prompt engineering standards. Use when writing or revising a prompt, system prompt or agent instruction file, or optimizing token and cache usage.
---

# Prompt Engineering Standards

**Prerequisites:** @smith-principles/SKILL.md

## Prompt Caching

Cache reduces costs 90%, latency 85%

**Structure for caching:**
1. Static content first (methodology, rules)
2. Tool definitions in consistent order
3. Project context (AGENTS.md, docs)
4. Dynamic content last (recent changes)

**Cache breakpoints** (Anthropic): explicit `cache_control` markers; the prefix up to each must be identical for a hit, and short prefixes below a model-specific minimum are not cached.

**Rules:**
- Keep tool definitions in a consistent order between calls
- Keep dynamic content out of static sections
- Keep the cached prefix stable — only change it when the static content
  itself changes
- Use bullet lists instead of Markdown tables (see `@smith-skills/SKILL.md`)

## AGENTS.md Cache-Friendly Structure

```markdown
<!-- STATIC - cached -->
**Metadata**: Scope, Prerequisites

## Critical Rules

Critical rules, written as affirmative statements with their reasons

## Hard Limits

Anti-patterns with no natural positive phrasing

<!-- CACHE BREAKPOINT (at or past the model's minimum cacheable prefix) -->

<!-- DYNAMIC - not cached -->
## Examples

Code examples that evolve
```

## Token Efficiency

### Progressive Disclosure

**Three-level loading:**
1. Metadata only (50 tokens)
2. Core concepts when triggered (200 tokens)
3. Full details when accessed (1000+ tokens)

### Sparse Attention

**Efficient file reading:**
1. Grep to find location
2. Read with offset/limit for large files
3. Read only necessary context (±20 lines)

**Rules:**
- Prefer targeted reads over loading full files
- Check metadata before reading full documentation
- Answer directly instead of restating the user's question

## Structured Output

**Platform mechanisms:**
- **OpenAI**: JSON Schema with `strict: true` (100% compliance)
- **Anthropic**: structured outputs (`output_config.format` with a JSON schema); `strict: true` on tool definitions
- **Gemini**: responseSchema with retry

**Schema design:**
- Match existing project patterns
- Include descriptions for complex fields
- Define required vs optional fields
- Keep nesting ≤3 levels

## Related

- @smith-ctx/SKILL.md - Progressive disclosure, reference-based communication
- `@smith-xml/SKILL.md` - XML tags for runtime prompts (not SKILL.md bodies)

## Before You Finish

**For caching:**
- Place static content before dynamic
- Maintain consistent tool order
- Target >80% cache hit rate

**For efficiency:**
- Use Grep before Read
- Read incrementally (narrow → expand)
- Use file:line references
