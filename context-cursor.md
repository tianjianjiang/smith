# Cursor Context Management

<metadata>

- **Scope**: Cursor-specific context management strategies and commands
- **Load if**: Using Cursor AND (context window approaching capacity >70% OR optimizing context usage)
- **Prerequisites**: @context.md, @steering.md
- **Requires**: Understanding of context windows, token limits, Cursor commands
- **Provides**: Cursor /summarize command, @ mentions, @codebase, .cursorrules configuration
- **Research**: Cursor documentation

</metadata>

<context>

**Foundation**: Cursor provides both manual (/summarize) and automatic summarization when approaching context limits.

**Key capabilities**:
- `/summarize` - Manual context summarization
- Automatic summarization - Triggers at context window limit (uses smaller flash model)
- @ mentions - Force-include specific files in context (@filename)
- @codebase - Search entire codebase for relevant code
- .cursorrules - Persistent project-specific instructions

**For architectural limitations and agent role**: See @context.md - Agent Role in Context Management section

**For universal context management strategies**: See @context.md - Information Retention Strategy, Progressive Disclosure Pattern, Reference-Based Communication

**Limitation**: Automatic summarization uses smaller flash model which can produce vague summaries, losing technical details.

**Best practice**: Use manual `/summarize` proactively before automatic trigger to maintain better control over summary quality.

</context>

## /summarize Command - Manual Summarization

<context>

**How it works**: Creates summary of conversation when you want to free up context window space without starting new chat.

**When to use**: Proactively before automatic trigger, when context approaching 60-70% capacity.

**Benefit over automatic**: You control timing and can review summary quality immediately.

</context>

<required>

Agent SHOULD recommend user execute `/summarize` proactively:

1. **Before automatic trigger** (primary use):
   - Detect when context approaches 60-70%
   - Recommend user execute /summarize
   - Provide guidance on verifying summary quality
   - Suggest @ mentions for files to restore

2. **When switching task phases**:
   - After exploration → Before implementation
   - After implementation → Before testing
   - After testing → Before code review

3. **When summary quality matters**:
   - Complex debugging sessions (need precise technical details preserved)
   - Multi-file refactoring (need file references preserved)
   - Architectural discussions (need design decisions preserved)

**Recommendation format** (copy-paste ready):
```
I recommend running `/summarize` now to free up context space.

After summarizing, please re-add critical files with:
@auth/middleware.ts @auth/tokens.ts

This will preserve our progress while making room for continued implementation.
```

</required>

<examples>

**Proactive manual summarization**:

```text
Context: 65% full after exploring authentication system

Agent: "I recommend running `/summarize` now to free up context space
while preserving our exploration findings.

After summarizing, please re-add the main files we'll be modifying:
@auth/middleware.ts @auth/tokens.ts

Key findings to verify are preserved in summary:
- Auth flow uses JWT tokens
- Token validation at middleware.ts:234
- Refresh token logic at tokens.ts:89"

User: [Executes /summarize, then adds files with @ mentions]

Agent: "Summary looks good. I can see the key findings were preserved.
Ready to continue implementation."
```

**Reactive automatic summarization (suboptimal)**:

```text
Context: 98% full during implementation

System: *Automatic summarization triggers*
Summary: "Discussed authentication implementation"

Agent: "The summary was too vague. I've lost the specific file locations
and design decisions we made. Could you remind me which files we were
modifying?"

Result: Lost productivity, user has to re-explain details
```

</examples>

<forbidden>

- NEVER claim to execute `/summarize` directly (agent cannot trigger built-in commands)
- NEVER rely solely on automatic summarization for complex tasks
- NEVER assume summaries preserve file:line references (they often don't)
- NEVER continue implementation without verifying summary quality after user executes /summarize
- NEVER ignore context indicator until automatic summarization triggers
- NEVER recommend `/summarize` without suggesting @ mentions for file restoration

</forbidden>

### Automatic Summarization

<context>

**Trigger**: Activates when context window reaches limit (e.g., 200K tokens with Sonnet 4).

**Model used**: Smaller flash model (faster but less nuanced than main model).
**Not charged**: Uses different model, doesn't count against your main model usage.

**Risk**: Vague summaries that lose technical details, especially for complex debugging or multi-file work.

</context>

<required>

#### Mitigation Strategies for Vague Summaries

When automatic summarization occurs, agent MUST:

1. **Immediately re-state critical information**:
   ```text
   After automatic summarization:
   "Let me re-state the key context:
   - Task: Implement OAuth2 refresh token rotation
   - Files: auth/middleware.ts, auth/tokens.ts, services/auth.ts
   - Decision: 7-day refresh cycle with automatic rotation
   - Next: Implement rotation logic at tokens.ts:89"
   ```

2. **Use @ mentions to re-add critical files**:
   ```text
   After summary, restore file context:
   @auth/middleware.ts @auth/tokens.ts
   "Now I have the files loaded, continuing implementation..."
   ```

3. **Document key decisions in code comments**:
   ```text
   Before summarization occurs, add comments:
   // Decision: Use JWT with 7-day refresh cycle (discussed 2025-12-10)
   // Token rotation implemented per OAuth2 RFC 6749 Section 10.4

   Result: Decisions preserved in file context even after summarization
   ```

4. **Use commit messages as memory anchors**:
   ```text
   After completing phase:
   git commit -m "feat(auth): implement JWT token validation

   - Added token validation middleware at middleware.ts:234
   - Implemented refresh token rotation at tokens.ts:89
   - Decision: 7-day refresh cycle for security/UX balance"

   Result: Can read git log to restore context even after summarization
   ```

</required>

<examples>

**Handling automatic summarization well**:

```text
Context: Working on complex refactoring

System: *Automatic summarization triggers*

Agent: "I see summarization occurred. Let me restore critical context:

Task: Refactor authentication to use dependency injection
Files being modified: @auth/service.ts @auth/middleware.ts @di/container.ts

Key decisions preserved:
- Use InversifyJS for DI container
- Keep existing JWT logic (don't change)
- Add AuthService interface at service.ts:10

Let me review the latest commit to ensure I have full context:
[Reads git log -1]

Ready to continue refactoring."

Result: Seamless continuation despite summarization
```

</examples>

### @ Mention Patterns for Context Control

<context>

**Purpose**: Force-include specific files in context, preventing them from being removed during summarization.

**Syntax**: `@filename` or `@path/to/file.ext`

**Use case**: Keep critical files loaded when context is tight or after summarization.

</context>

<required>

Agent SHOULD use @ mentions strategically:

#### When to @ Mention Files

1. **After summarization** (restore critical files):
   ```text
   @auth/middleware.ts @auth/tokens.ts
   ```

2. **Before implementation** (load files you'll modify):
   ```text
   @models/user.ts implement new permissions field
   ```

3. **For large files** (>600 lines - @codebase doesn't load completely):
   ```text
   @src/large-service.ts find the authentication function

   (Better than @codebase which only loads first 250 lines)
   ```

4. **To preserve configuration**:
   ```text
   @config/database.ts review connection pooling settings
   ```

#### @ Mention Patterns

**Single file**:
```text
@auth/middleware.ts add rate limiting
```

**Multiple related files**:
```text
@auth/middleware.ts @auth/tokens.ts @services/auth.ts
implement OAuth2 refresh token rotation
```

**File + tests**:
```text
@src/auth.ts @tests/auth.test.ts
add test for token expiration edge case
```

**Configuration + implementation**:
```text
@config/auth.ts @src/middleware/auth.ts
update token expiration from 1h to 7d
```

</required>

<examples>

**Effective @ mention usage**:

```text
User: "Add email validation to user registration"

Agent: "I'll load the relevant files:
@models/user.ts @validators/email.ts @routes/auth.ts

Now I can see the current user model, existing email validation patterns,
and the registration endpoint. I'll add email validation using the
existing validator pattern at validators/email.ts:45."

Result: Loaded exactly what's needed, minimal context usage
```

**Inefficient @ mention usage**:

```text
User: "Add email validation to user registration"

Agent: "@codebase find user registration"

Result: Loads summaries of many files, not complete code. User model might
be >600 lines, so @codebase only sees first 250 lines, misses the fields
defined later.

Better: Grep for "user registration" → get file paths → @ mention specific files
```

</examples>

<forbidden>

- NEVER use @codebase for files >600 lines (Cursor only loads first 250 lines, then extends by 250 if needed)
- NEVER @ mention entire directories (too much context)
- NEVER @ mention files you won't actually use (wastes context)
- NEVER forget to @ mention files after summarization (loses implementation context)

</forbidden>

### @codebase for Discovery

<context>

**Purpose**: Search entire codebase for relevant code patterns.
**Benefit**: Fast discovery without loading full files.
**Limitation**: Returns summaries, not complete code. For files >600 lines, only first 250 lines analyzed.

</context>

<required>

Agent SHOULD use @codebase for:

1. **Initial discovery** (find files, then @ mention them):
   ```text
   @codebase authentication middleware

   Result: "Found auth middleware in: auth/middleware.ts, auth/service.ts"

   Then: @auth/middleware.ts to load full file
   ```

2. **Pattern finding** (understand existing conventions):
   ```text
   @codebase error handling patterns

   Result: Shows common error handling approach

   Then: Apply same pattern in new code
   ```

3. **Related code search** (find dependencies):
   ```text
   @codebase uses AuthService

   Result: Shows all files that import AuthService

   Then: @ mention specific files that need updating
   ```

Agent SHOULD NOT use @codebase for:

1. **Files you already know** (use @ mention directly)
2. **Large files you need complete** (@codebase truncates at 250 lines)
3. **Detailed code reading** (summaries miss details)

</required>

<examples>

**Good @codebase workflow**:

```text
Step 1: Discovery
@codebase how are API endpoints defined

Result: "API endpoints use Express router in routes/ directory,
following REST conventions"

Step 2: Load specific files
@routes/api.ts @routes/auth.ts

Step 3: Implement new endpoint following existing pattern
```

**Bad @codebase workflow**:

```text
User: "Fix bug in authentication"

Agent: "@codebase authentication"

Problem: Returns summaries of many auth-related files, not the specific
bug location or complete code needed for fixing.

Better: Grep for "authentication" → get file:line → Read specific section
```

</examples>

### .cursorrules for Persistent Instructions

<context>

**Purpose**: Project-specific instructions that persist across all chat sessions.

**Location**: `.cursorrules` file in project root
**Format**: Plain text or Markdown
**Benefit**: Doesn't consume context window (loaded automatically but efficiently)

**Relationship to .smith rules**: .cursorrules is project-specific, while .smith rules are personal/global cross-project standards.

</context>

<required>

#### Rule Organization Strategy

**What goes in .cursorrules** (project-specific):
- Technology stack (frameworks, libraries, databases)
- Project structure and file organization
- Project-specific coding patterns
- External API conventions
- Reference to personal standards

**What goes in `@`-prefixed personal standards** (e.g., `@AGENTS.md`, `@*.md`):
- Universal coding principles (DRY, KISS, YAGNI)
- Language-specific style (Python, TypeScript, etc.)
- Git workflow preferences
- Testing standards
- AI agent interaction patterns

**Reference pattern in .cursorrules**:

```text
# Project: MyApp Cursor Rules

Follow personal coding standards from:
- @AGENTS.md (entry point for all personal standards)
- @core.md (critical NEVER/ALWAYS rules)

## Project Stack

- Framework: NestJS (TypeScript)
- Database: PostgreSQL with Prisma ORM
- Testing: Jest with Supertest

## Project Patterns

- Use dependency injection for services
- Follow repository pattern for data access
- Place business logic in service layer, not controllers
```

</required>

<examples>

**Effective .cursorrules structure**:

```text
# Project Coding Standards

## Personal Standards (via .smith)

Follow standards defined in @AGENTS.md

This loads context-triggered rules:
- TypeScript: rules-development.md (coding style, formatting)
- Git: rules-git.md (commit conventions, branching)
- Testing: rules-testing.md (test structure, coverage)

## Project-Specific Stack

### Backend
- Framework: NestJS with TypeScript
- Database: PostgreSQL 15
- ORM: Prisma
- Auth: JWT with passport-jwt

### Frontend
- Framework: Next.js 14
- State: Zustand
- Styling: Tailwind CSS

## Project File Structure

```
src/
├── modules/     # Feature modules (NestJS)
│   ├── auth/
│   ├── users/
│   └── posts/
├── common/      # Shared utilities
├── config/      # Configuration
└── main.ts      # Entry point
```

## Project Patterns

### Dependency Injection
Always use constructor injection for services:

```typescript
export class AuthService {
  constructor(
    private readonly userService: UserService,
    private readonly jwtService: JwtService,
  ) {}
}
```

### Error Handling
Use NestJS exception filters, not try/catch:

```typescript
// Good
@Post('login')
async login(@Body() dto: LoginDto) {
  return this.authService.login(dto); // Service throws HttpException
}

// Bad
@Post('login')
async login(@Body() dto: LoginDto) {
  try {
    return this.authService.login(dto);
  } catch (error) {
    throw new HttpException('Login failed', 400);
  }
}
```
```

**Inefficient approach (duplication)**:

```text
# Project: MyApp

[Embeds all TypeScript style guidelines - 500 lines]
[Embeds all testing patterns - 400 lines]
[Embeds git workflow - 300 lines]

Result: High token usage every session, duplicates personal standards
Better: Reference @AGENTS.md, add only project-specific patterns
```

</examples>

<forbidden>

- NEVER duplicate .smith rules in .cursorrules (reference instead)
- NEVER put personal preferences in .cursorrules (use .smith)
- NEVER forget to reference @AGENTS.md as entry point
- NEVER put sensitive data in .cursorrules (it's version controlled)

</forbidden>

### Cursor Agent Mode Context Gathering

<context>

**Feature**: Cursor's Agent Mode (Cmd/Ctrl+I) autonomously gathers context using specialized search tools.

**How it works**:
- codebase_search - Finds relevant files and patterns
- read_file - Loads specific files
- grep_search - Searches for specific patterns
- file_search - Finds files by name
- web_search - External research

**Limitation**: Agent mode defaults to reading first 250 lines of files, occasionally extending by another 250 lines.

**Cursor 2.0 improvement**: Agents can now read full files when needed without size constraints.

</context>

<required>

Agent SHOULD leverage Agent Mode efficiently:

1. **Let Agent Mode discover files** (don't load everything manually):
   ```text
   In Agent Mode:
   Task: "Implement user permissions"

   Agent automatically:
   - Searches codebase for existing auth patterns
   - Reads relevant files (models/user.ts, middleware/auth.ts)
   - Proposes implementation following existing patterns
   ```

2. **Explicitly @ mention for files >500 lines**:
   ```text
   For large service files:
   "Review @services/large-service.ts and refactor the authentication method"

   (Ensures full file is loaded, not just first 250-500 lines)
   ```

3. **Use Agent Mode for discovery, @ mentions for implementation**:
   ```text
   Discovery phase:
   "Find all places where User model is used" (Agent Mode searches)

   Implementation phase:
   "@models/user.ts @services/user.ts add email field" (Explicit @ mentions)
   ```

</required>

<examples>

**Good Agent Mode workflow**:

```text
User: (In Agent Mode) "Add rate limiting to API"

Cursor Agent:
1. Searches codebase for existing middleware patterns
2. Reads middleware/ directory structure
3. Finds rate limiting is handled at middleware/security.ts:100-150
4. Reads that section
5. Proposes adding rate limiting following existing pattern

Result: Efficient discovery and implementation
```

**Bad workflow (over-loading)**:

```text
User: "Add rate limiting to API"

Manual approach:
@middleware/security.ts @middleware/auth.ts @middleware/logger.ts
@middleware/cors.ts @routes/api.ts @routes/auth.ts @config/app.ts

Result: Loaded 7 files manually, context 60% full, most files not needed

Better: Let Agent Mode discover which files are actually relevant
```

</examples>

### Context-Efficient File Reading

<context>

**Best practice**: Keep code files under 500 lines where possible for optimal Agent Mode comprehension.

**Research**: Files exceeding 600 lines are more effectively handled with explicit @ mentions rather than relying on @codebase.

</context>

<required>

Agent SHOULD adapt reading strategy based on file size:

**Small files (<250 lines)**:
- @codebase works well
- Agent Mode reads fully
- No special handling needed

**Medium files (250-600 lines)**:
- Use @ mention for complete loading
- Agent Mode may read incrementally (250 lines, then +250)
- Verify full context is loaded

**Large files (>600 lines)**:
- Always use @ mention (never rely on @codebase)
- Consider asking user about specific sections
- Use Read tool with offset/limit for targeted loading

</required>

<examples>

**Handling large file efficiently**:

```text
User: "Fix the bug in AuthService"

Agent: "@services/auth.ts is 800 lines. Can you point me to the specific
method or line number where the bug occurs?"

User: "The validateToken method around line 450"

Agent: [Uses Read tool to load auth.ts:430-480]
"I see the issue at line 456 - missing null check before accessing
user.permissions. I'll fix it."

Result: Loaded 50 lines instead of 800, fix implemented efficiently
```

</examples>

### Version Information

<metadata>

- **Cursor Version**: 1.6.x / 2.0.x (as of 2025-12)
- **Last Updated**: 2025-12-10
- **Features Documented**: /summarize, @ mentions, @codebase, .cursorrules, Agent Mode

</metadata>

<note>

Features documented here are current as of the version noted above. Cursor 2.0 introduced improved agent file reading (full files without size constraints). For newer versions, consult Cursor changelog for updated capabilities.

</note>

---


<related>

- **Universal principles**: @context.md (shared context management strategies, agent role)
- **Parent**: @steering.md (AI agent interaction patterns, prompt caching)
- **Foundation**: @core.md (critical NEVER/ALWAYS rules)
- **Research**: Cursor documentation

</related>
