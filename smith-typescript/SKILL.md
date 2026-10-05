---
name: smith-typescript
description: TypeScript development standards. Use when working with TypeScript, or configuring path aliases or a test runner.
---

# TypeScript Development Standards

**Scope:** TypeScript projects (frontend or backend)
**Prerequisites:** @smith-principles/SKILL.md, @smith-standards/SKILL.md

## CRITICAL: Path Aliases

**Configure path aliases in test config** - Vite's `~` and `@` aliases need explicit test runner setup.

## Path Aliases in Test Config

Vite-based projects use `~` and `@` as path aliases. Test runners need explicit configuration.

### Examples

```typescript
// vitest.config.ts or jest.config.ts
resolve: {
  alias: {
    '~': projectRoot,
    '@': projectRoot,
  },
}
```

## Test File Organization

- Place tests adjacent to source in `__tests__/` directories
- Use consistent extension (`.spec.ts` or `.test.ts`)

## Type Checking

Framework CLIs may provide enhanced type checking. Match CI configuration for consistency.

## Claude Code LSP

Use Serena MCP (`find_symbol`, `find_referencing_symbols`) for language-server features, per `@smith-serena/SKILL.md`; the harness LSP tool is the fallback when Serena is unavailable.

## Related

- `@smith-tests/SKILL.md` - Testing standards
- `@smith-dev/SKILL.md` - Development workflow
- `@smith-serena/SKILL.md` - Serena MCP for language server features

## Before You Finish

**Before running tests:**
1. Configure path aliases in vitest/jest config
2. Match CI type-checking configuration
3. Place tests in `__tests__/` adjacent to source
