---
name: smith-typescript
description: TypeScript development standards for frontend and backend projects. Use when working with TypeScript, configuring path aliases, setting up test runners (Vitest/Jest), or organizing test files. Covers Vite alias configuration and type checking.
---

# TypeScript Development Standards

**Scope:** TypeScript projects (frontend or backend)
**Load if:** Working with TypeScript
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

## Claude Code LSP (Experimental)

**LSP plugins exist but are currently broken** (race condition in initialization):
- `typescript-lsp@claude-plugins-official`
- `pyright-lsp@claude-plugins-official`

**When fixed**, LSP provides: goToDefinition, findReferences, hover, documentSymbol, getDiagnostics

**Workaround**: Use Serena MCP for language server features (`find_symbol`, `find_referencing_symbols`)

## Related

- `@smith-tests/SKILL.md` - Testing standards
- `@smith-dev/SKILL.md` - Development workflow
- `@smith-serena/SKILL.md` - Serena MCP for language server features

## Before You Finish

**Before running tests:**
1. Configure path aliases in vitest/jest config
2. Match CI type-checking configuration
3. Place tests in `__tests__/` adjacent to source
