---
name: prompts
description: Prompt engineering standards for AI interactions with cache optimization. Use when writing AI prompts, optimizing context usage, or structuring AGENTS.md files. Covers prompt caching, token efficiency, and progressive disclosure patterns.
---

# Prompt Engineering Standards

<metadata>

- **Load if**: Writing AI prompts, optimizing context usage
- **Prerequisites**: @principles/SKILL.md

</metadata>

## CRITICAL: Prompt Caching (Primacy Zone)

<required>

Cache reduces costs 90%, latency 85%

**Structure for caching:**
1. Static content first (methodology, rules)
2. Tool definitions in consistent order
3. Project context (AGENTS.md, docs)
4. Dynamic content last (recent changes)

**Cache breakpoints**: Every ~1024 tokens. Prefix must be identical for cache hit.

</required>

<forbidden>

- Reordering tools between calls
- Injecting dynamic content into static sections
- Modifying cached prefix unnecessarily
- Using markdown tables (see @skills/SKILL.md - use bullet lists instead)

</forbidden>

## AGENTS.md Cache-Friendly Structure

```markdown
<!-- STATIC - cached -->
<metadata>

Scope, Load if, Prerequisites

</metadata>

<required>

Critical NEVER/ALWAYS rules

</required>

<forbidden>

Anti-patterns

</forbidden>

<!-- CACHE BREAKPOINT (~1024 tokens) -->

<!-- DYNAMIC - not cached -->
<examples>

Code examples that evolve

</examples>
```

## Token Efficiency

### Progressive Disclosure

**Three-level loading:**
1. Metadata only (50 tokens)
2. Core concepts when triggered (200 tokens)
3. Full details when accessed (1000+ tokens)

### Sparse Attention

<required>

**Efficient file reading:**
1. Grep to find location
2. Read with offset/limit for large files
3. Read only necessary context (±20 lines)

</required>

<forbidden>

- Loading full files when targeted reads suffice
- Reading documentation when metadata answers the question
- Repeating user's question in responses

</forbidden>

## Structured Output

**Platform mechanisms:**
- **OpenAI**: JSON Schema with `strict: true` (100% compliance)
- **Anthropic**: Tool use with flexible schemas
- **Gemini**: responseSchema with retry

<required>

**Schema design:**
- Match existing project patterns
- Include descriptions for complex fields
- Define required vs optional fields
- Keep nesting ≤3 levels

</required>

<related>

- `@context/SKILL.md` - Progressive disclosure, reference-based communication
- `@xml/SKILL.md` - Approved XML tags

</related>

## ACTION (Recency Zone)

<required>

**For caching:**
- Place static content before dynamic
- Maintain consistent tool order
- Target >80% cache hit rate

**For efficiency:**
- Use Grep before Read
- Read incrementally (narrow → expand)
- Use file:line references

</required>
