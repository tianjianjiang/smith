# TypeScript Development Standards

<metadata>

- **Scope**: TypeScript projects (frontend or backend)
- **Load if**: Working with TypeScript
- **Prerequisites**: @core.md

</metadata>

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

- @testing.md
- @dev.md (workflow)

</related>
