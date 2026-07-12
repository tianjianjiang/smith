---
name: smith-nuxt
description: Nuxt 3 development patterns including auto-import stubbing for tests, environment variable conventions, and middleware testing. Use when working with Nuxt projects, testing Nuxt components/middleware, or configuring Nuxt environment variables.
---

# Nuxt Development Standards

**Scope:** Nuxt 3 specific patterns
**Load if:** Working with Nuxt projects
**Prerequisites:** @smith-principles/SKILL.md, @smith-standards/SKILL.md, `@smith-typescript/SKILL.md`

## CRITICAL: Auto-Import Stubbing

**Stub Nuxt auto-imports BEFORE importing modules that use them** - module code executes at import time.

- Treat the `h3` module's auto-imports as globals — stub them directly rather than mocking `h3`
- Stub globals before importing middleware, since the module executes at import time

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

// Now import the module that uses auto-imports
import middleware from '../myMiddleware';
```

- Treat the `h3` module's auto-imports as globals, not module exports — stub the globals rather than mocking `h3`
- Stub globals before importing middleware, since the module executes at import time

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
