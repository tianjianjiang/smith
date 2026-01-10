---
name: smith-ctx-cursor
description: Cursor context management with /summarize command, @ mentions for file inclusion, and @codebase discovery. Use when operating in Cursor IDE or when context exceeds 60%. Activate for context optimization in Cursor sessions.
---

# Cursor Context Management

<metadata>

- **Load if**: Using Cursor, context >60%
- **Prerequisites**: @smith-ctx/SKILL.md

</metadata>

## CRITICAL: Context Commands (Primacy Zone)

<required>

**Use `/summarize` proactively at 60-70%** - Don't wait for automatic trigger

**Automatic summarization uses smaller flash model** → vague summaries, lost details

**After any summarization:**
1. Re-state critical context (task, files, decisions)
2. Use @ mentions to restore files: `@auth/middleware.ts @auth/tokens.ts`

</required>

## /summarize - Manual Summarization

**When to use**: Before automatic trigger, between task phases

<required>

**Recommendation format:**
```text
/summarize

After summarizing, re-add critical files:
@auth/middleware.ts @auth/tokens.ts
```

**Verify summary preserved:**
- Task goals
- File locations
- Design decisions
- Next steps

</required>

<forbidden>

- Claiming to execute `/summarize` directly
- Relying solely on automatic summarization
- Continuing without verifying summary quality

</forbidden>

## @ Mentions - Force-Include Files

**Syntax**: `@filename` or `@path/to/file.ext`

<required>

**Use @ mentions for:**
- After summarization (restore critical files)
- Before implementation (load files to modify)
- Large files >600 lines (@codebase truncates at 250)

**Patterns:**
```text
@auth/middleware.ts @auth/tokens.ts    # Multiple files
@src/auth.ts @tests/auth.test.ts       # File + tests
```

</required>

<forbidden>

- @codebase for files >600 lines (only loads first 250)
- @ mention entire directories
- @ mention files you won't use

</forbidden>

## @codebase - Discovery Only

**Use for**: Finding files, understanding patterns
**Limitation**: Returns summaries, not complete code

<required>

**Workflow:**
1. `@codebase authentication middleware` → Find files
2. `@auth/middleware.ts` → Load full file
3. Implement with complete context

</required>

## .cursorrules - Persistent Instructions

**Location**: `.cursorrules` in project root

<required>

**Put in .cursorrules** (project-specific):
- Technology stack
- Project structure
- Reference to @AGENTS.md

**Put in skill files** (personal/global):
- Universal principles
- Language style
- Git workflow

**Example:**
```markdown
# Project Rules
Follow standards from @AGENTS.md

## Stack
- Framework: NestJS
- Database: PostgreSQL
- Testing: Jest
```

</required>

<related>

- `@smith-ctx/SKILL.md` - Universal context strategies

</related>

## ACTION (Recency Zone)

<required>

**At 60% context**: Run `/summarize` proactively
**After summarization**: Re-add files with @ mentions
**For large files**: Always use @ mention, not @codebase

**File size strategy:**
- <250 lines: @codebase works
- 250-600 lines: Use @ mention
- >600 lines: Always @ mention

</required>
