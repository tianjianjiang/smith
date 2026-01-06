---
name: typescript
description: TypeScript development standards for frontend and backend projects. Use when working with TypeScript, configuring path aliases, setting up test runners (Vitest/Jest), or organizing test files. Covers Vite alias configuration and type checking.
---

# TypeScript Development Standards

<metadata>

- **Scope**: TypeScript projects (frontend or backend)
- **Load if**: Working with TypeScript
- **Prerequisites**: @principles/SKILL.md, @standards/SKILL.md

</metadata>

## CRITICAL: Path Aliases (Primacy Zone)

<required>

**Configure path aliases in test config** - Vite's `~` and `@` aliases need explicit test runner setup.

</required>

## Path Aliases in Test Config

<context>

Vite-based projects use `~` and `@` as path aliases. Test runners need explicit configuration.

</context>

<examples>

```typescript
// vitest.config.ts or jest.config.ts
resolve: {
  alias: {
    '~': projectRoot,
    '@': projectRoot,
  },
}
```

</examples>

## Test File Organization

<required>

- Place tests adjacent to source in `__tests__/` directories
- Use consistent extension (`.spec.ts` or `.test.ts`)

</required>

## Type Checking

<context>

Framework CLIs may provide enhanced type checking. Match CI configuration for consistency.

</context>

<related>

- `@tests/SKILL.md` - Testing standards
- `@dev/SKILL.md` - Development workflow

</related>

## ACTION (Recency Zone)

<required>

**Before running tests:**
1. Configure path aliases in vitest/jest config
2. Match CI type-checking configuration
3. Place tests in `__tests__/` adjacent to source

</required>
