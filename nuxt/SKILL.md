---
name: nuxt
description: Nuxt 3 development patterns including auto-import stubbing for tests, environment variable conventions, and middleware testing. Use when working with Nuxt projects, testing Nuxt components/middleware, or configuring Nuxt environment variables.
---

# Nuxt Development Standards

<metadata>

- **Scope**: Nuxt 3 specific patterns
- **Load if**: Working with Nuxt projects
- **Prerequisites**: @principles/SKILL.md, @standards/SKILL.md, @typescript/SKILL.md

</metadata>

## CRITICAL: Auto-Import Stubbing (Primacy Zone)

<required>

**Stub Nuxt auto-imports BEFORE importing modules that use them** - module code executes at import time.

</required>

<forbidden>

- Mocking `h3` module expecting auto-imports (they're globals)
- Importing middleware before stubbing globals

</forbidden>

## Auto-Import Stubbing in Tests

<context>

Nuxt auto-imports utilities like `defineEventHandler`, `createError`, `useState`. These are globally available in Nuxt runtime but NOT in test environments.

</context>

<required>

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

</required>

<forbidden>

- NEVER mock `h3` module expecting auto-imports to work (they're globals, not module exports)
- NEVER import middleware before stubbing globals (module executes at import time)

</forbidden>

## Environment Variables

<context>

Nuxt uses `NUXT_` prefix for runtime config environment variables.

- `NUXT_PUBLIC_*` - Exposed to client
- `NUXT_*` - Server-only

</context>

<examples>

```sh
# Server-only
NUXT_DATABASE_URL=postgres://...
NUXT_API_SECRET=secret

# Public (exposed to browser)
NUXT_PUBLIC_API_BASE=https://api.example.com
```

</examples>

<related>

- `@typescript/SKILL.md` - General TypeScript patterns
- `@tests/SKILL.md` - Testing standards

</related>

## ACTION (Recency Zone)

<required>

**Before testing Nuxt code:**
1. Stub auto-imports BEFORE any imports
2. Use `NUXT_PUBLIC_*` for client-exposed env vars
3. Use `NUXT_*` for server-only env vars

</required>
