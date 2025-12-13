# Nuxt Development Standards

<metadata>

- **Scope**: Nuxt 3 specific patterns
- **Load if**: Working with Nuxt projects
- **Prerequisites**: @core.md, @typescript.md

</metadata>

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

- @typescript.md (general patterns)
- @testing.md

</related>
