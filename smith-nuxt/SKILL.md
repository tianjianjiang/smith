---
name: smith-nuxt
description: Nuxt 3 development patterns including auto-import stubbing for tests, environment variable conventions, and middleware testing. Use when working with Nuxt projects, testing Nuxt components/middleware, or configuring Nuxt environment variables.
---

# Nuxt Development Standards

**Scope:** Nuxt 3 specific patterns
**Load if:** Working with Nuxt projects
**Prerequisites:** @smith-principles/SKILL.md, @smith-standards/SKILL.md, `@smith-typescript/SKILL.md`

## CRITICAL: Auto-Import Stubbing

**Stub Nuxt auto-imports BEFORE importing modules that use them** - module code executes at import time. Static ES `import`s are hoisted and run before any other code in the file regardless of source position, so source-line order alone does NOT guarantee the stub runs first — use a dynamic `await import(...)` after the stubs instead of a static `import`.

- Treat the `h3` module's auto-imports as globals — stub them directly rather than mocking `h3`
- Stub globals, then dynamically `import()` the middleware — a static `import` would be hoisted above the stubs

## Auto-Import Stubbing in Tests

Nuxt auto-imports utilities like `defineEventHandler`, `createError`, `useState`. These are globally available in Nuxt runtime but NOT in test environments.

Stub auto-imports globally BEFORE importing the module under test:

```typescript
import { describe, it, expect, vi } from 'vitest';
import type { H3Event } from 'h3';

// Stub Nuxt auto-imports BEFORE any imports that use them
(globalThis as Record<string, unknown>).defineEventHandler =
  (handler: (event: H3Event) => unknown) => handler;
(globalThis as Record<string, unknown>).createError =
  (options: { statusCode: number; statusMessage: string }) =>
    Object.assign(new Error(options.statusMessage), { statusCode: options.statusCode });

// Dynamic import runs here, AFTER the stubs above. A static `import` for
// this module would be hoisted and run BEFORE the stubs regardless of
// source position, defeating the stub-before-import order this example
// demonstrates.
const { default: middleware } = await import('../myMiddleware');
```

- Treat the `h3` module's auto-imports as globals, not module exports — stub the globals rather than mocking `h3`
- Stub globals, then dynamically `import()` the middleware — a static `import` would be hoisted above the stubs and run first regardless of where it's written in the file

## Environment Variables

Nuxt uses `NUXT_` prefix for runtime config environment variables.

- `NUXT_PUBLIC_*` - Exposed to client
- `NUXT_*` - Server-only

### Examples

Server-only:
```shell
NUXT_DATABASE_URL=postgres://...
NUXT_API_SECRET=secret
```

Public (exposed to browser):
```shell
NUXT_PUBLIC_API_BASE=https://api.example.com
```

## Related

- `@smith-typescript/SKILL.md` - General TypeScript patterns
- `@smith-tests/SKILL.md` - Testing standards

## Before You Finish

**Before testing Nuxt code:**
1. Stub auto-imports BEFORE any imports
2. Use `NUXT_PUBLIC_*` for client-exposed env vars
3. Use `NUXT_*` for server-only env vars
