---
name: smith-checkpoint
description: Memory checkpoint
argument-hint: [label] [plan=path]
---

# /smith-checkpoint — persist session state to both memories

Capture what would otherwise be lost across sessions. Arguments:
- `label`: short checkpoint label (required)
- `plan=path`: plan file path (optional, provided by ctx-claude stop hook)

Save the SAME facts to both backends, each in its own format; do not skip one.

## What to capture

Durable only (not transient chatter): goals/decisions, file:line anchors,
PR/commit SHAs, open follow-ups, and any correction the user gave on how to
work. Convert relative dates to absolute. Omit what the repo/git already
records.

## Compression Requirements

**Target**: <400 tokens per checkpoint (current baseline: 800-1200 tokens)

**Format rules**:
1. **Use references, not content duplication**:
   - File locations: `file:line` only (e.g., `plan.md:244-296`)
   - Memory anchors: permalink/name only (e.g., `Serena: memory_name`)
   - NO full content quotes or verbose explanations
2. **Minimal prose**:
   - Decisions: one-line statement + consequence (if non-obvious)
   - Status: checklist format (markdown checkboxes)
   - Next steps: action verb + brief context
3. **Single-source content**:
   - Draft facts ONCE in canonical form
   - Transform to Serena (snake_case) and Basic-Memory (frontmatter + body)
   - Content body IDENTICAL except format-specific metadata

**Example** (compressed format):
```markdown
# Feature Auth Implementation

**Date**: 2026-08-31T14:45+09:00
**Plan**: `~/.claude/plans/auth-plan.md:50-120`
**Session**: bg-job abc123

## Completed
- [x] OAuth flow impl (`auth.ts:234-567`)
- [x] Token refresh logic (`refresh.ts:89-156`)

## Decisions
- Use JWT with 1h TTL (security requirement from `SECURITY.md:45`)
- Store refresh tokens in httpOnly cookies (prevents XSS)

## Next
Implement rate limiting (`auth-plan.md:121-145`)

## Related
- PR #789 (awaiting review)
- Serena: `oauth_implementation_status`
```

## Targets and formats

1. **Serena** (`mcp__serena__write_memory`): a snake_case memory capturing the
   checkpoint; update the matching existing memory if present.
2. **Basic-Memory** (`mcp__basic-memory__write_note`): a note under the project
   folder; type `decision` for material decisions, else `guide`/`note`.

## Naming strategy

**Use semantic names based on checkpoint context, not generic labels:**

- **With plan file**: Use plan basename
  - Serena: `plan_basename` (snake_case, e.g., `priority_2_context_dry`)
  - Basic-Memory: Title Case (e.g., "Priority 2: Context DRY")
- **Without plan**: Use descriptive label from current work context
  - Never use bare "context-limit" or standalone timestamps
  - Example: `feature_auth_implementation`, `bugfix_memory_leak`
- **Label argument**: Passed from enforce-clear.sh, derived from plan basename or session timestamp

**Consistency**: Same semantic name across label, Serena memory, Basic-Memory note (modulo format).

## Procedure

When invoked via `/smith-checkpoint` (no arguments required):

1. **Infer label automatically**:
   - If plan file exists: use plan basename (snake_case)
   - Otherwise: infer from current session's primary work
   - Follow Naming strategy above (semantic, descriptive)
2. **Call write-checkpoint.sh** with inferred label:
   ```bash
   ~/.claude/skills/smith-checkpoint/scripts/write-checkpoint.sh "«label»" "plan=«path»"
   ```
3. The script (exit 0 on success):
   - Generates checkpoint content (<400 tokens)
   - Writes to both backends via CLI (zero Claude tokens)
   - Outputs success confirmation to stderr
   - Outputs Reload block to stdout
4. If script exits non-zero, report which backend failed.
5. On success, output Reload block directly to user.
