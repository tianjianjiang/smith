# AI Platform Context Management

<metadata>

- **Scope**: Context management strategies across AI coding platforms (Claude Code, Cursor, Kiro)
- **Load if**: Context window approaching capacity (>70%) OR optimizing context usage OR debugging context issues
- **Prerequisites**: @rules-context-principles.md, @rules-ai_agents.md
- **Requires**: Understanding of context windows, token limits, platform-specific commands
- **Provides**: Platform-specific context optimization strategies, selective retention patterns, persistent configuration patterns
- **Research**: Anthropic Claude Code documentation, Cursor documentation, Kiro documentation, MCP protocol specification

</metadata>

<context>

**Foundation**: All AI coding platforms share common context window constraints but provide different tools for managing them.

**Covered platforms**:
- **Claude Code** - /compact and /clear commands, Tool Search Tool, CLAUDE.md
- **Cursor** - /summarize command, @ mentions, @codebase, .cursorrules
- **Kiro** - Steering files, context triggers, MCP integration

**Universal principle**: Monitor context usage proactively at 70% capacity to maintain control over what's retained.

</context>

## Architectural Limitation (Universal)

<context>

**Critical**: Agents cannot programmatically trigger built-in context management commands like `/compact`, `/clear`, or `/summarize`.

**Why**: These are built-in REPL commands, not agent tools. Command execution is reserved for users only.

**What agents can do**:
- Detect when context approaches capacity (based on conversation length)
- Recommend specific commands with retention criteria
- Explain what will be preserved vs discarded
- Format commands as copy-paste ready for user execution

**What agents cannot do**:
- Execute `/compact`, `/clear`, or `/summarize` directly
- Automatically manage context without user action
- Trigger built-in commands via tools

**Collaboration model**: User reports context percentage → Agent recommends specific command → User executes command → Agent continues with restored context

</context>

<required>

When context approaches 70%, agent MUST:
1. Inform user that context is at critical threshold
2. Recommend specific command with retention criteria (copy-paste ready)
3. Explain what will be preserved (task goals, file paths, decisions, todos)
4. Explain what will be discarded (verbose outputs, failed attempts)

</required>

---

## Claude Code Context Management

<context>

**Foundation**: Claude Code provides built-in context management commands for maintaining conversation quality while preserving relevant information.

**Key capabilities**:
- `/compact` - Selective summarization with retention criteria
- `/clear` - Complete context reset
- Tool Search Tool - 85% token reduction via on-demand tool loading
- CLAUDE.md - Persistent rules across sessions
- Context meter - Visual indicator in Claude Code interface

**Best practice**: Monitor context meter and recommend `/compact` proactively at 70% capacity to prevent forced truncation.

</context>

### /compact Command - Selective Retention

<context>

**How it works**: Takes entire conversation history and creates a summary while preserving information specified in the message parameter.

**Syntax**: `/compact <optional retention criteria>`

**Critical difference from /clear**: Preserves essential information rather than wiping everything.

</context>

<required>

Agent MUST recommend user execute `/compact` with specific retention criteria.

**Recommendation format** (copy-paste ready):
```
I recommend running:

/compact keep task requirements, modified files (auth.ts:234, tokens.ts:89), OAuth2 design decisions, next steps

This will preserve: [list what's kept]
This will discard: [list what's removed]
```

**Examples of good vs bad recommendations**:

- **Good**: "I recommend running: `/compact keep task requirements, modified files (auth.ts:234, tokens.ts:89), OAuth2 design decisions, next steps`"
- **Bad**: Claiming to execute `/compact` directly (agent cannot do this)
- **Bad**: `/compact` without retention criteria (user won't know what to preserve)
- **Bad**: `/compact keep important stuff` (too vague)

#### Retention Criteria Template

```text
/compact keep [what to preserve with specific references]
```

**What to preserve** (from rules-context-principles.md):
- Task goals and requirements
- File paths with line numbers (file:line format)
- Architectural decisions made
- Incomplete todos/next steps
- Root causes of bugs/errors
- Key findings from investigation

**What to discard** (implied - everything not specified):
- Verbose tool outputs
- Failed exploration attempts
- Redundant file readings
- Intermediate debugging output

</required>

<examples>

**Feature implementation context compaction**:

```text
User: "My context is at 75%"

Agent: "Context is at 75%. I recommend running:

/compact keep feature requirements (OAuth2 refresh token rotation),
files modified (auth/middleware.ts:100-150, auth/tokens.ts:45-90),
decision to use JWT with 7-day refresh cycle,
remaining todos (implement token rotation, write integration tests)

This will preserve everything we've discovered (requirements, file locations,
design decisions, next steps) while discarding verbose exploration outputs."

Result: User executes command, context preserved correctly
```

**Bug investigation context compaction**:

```text
User: "Context is at 80% after our debugging session"

Agent: "I recommend running:

/compact keep bug description (users logged out after 1 hour),
root cause (token expiration not handled at auth.ts:234),
fix implemented (added null check and refresh logic),
verification needed (test with 1-hour token expiration)

This preserves the complete debugging trail while discarding failed
hypotheses and verbose log outputs."

Result: User executes, can verify fix without re-investigating
```

**Code review context compaction**:

```text
User: "My context is at 72%"

Agent: "I recommend running:

/compact keep PR objective (add user permissions system),
files reviewed (models/user.ts, middleware/permissions.ts, routes/api.ts),
issues found (P0: missing authorization check at routes/api.ts:456,
P1: inefficient query at models/user.ts:123),
recommended changes (add middleware.checkPermission() call)

This preserves your review findings while discarding the full file contents
(which can be re-read if needed)."

Result: User executes, can provide feedback without re-reading files
```

</examples>

<forbidden>

- NEVER claim to execute `/compact` directly (agent cannot trigger built-in commands)
- NEVER recommend `/compact` without specific retention criteria (user won't know what to preserve)
- NEVER use vague criteria like "important things" or "relevant code" (too ambiguous)
- NEVER recommend compacting away file:line references (breaks traceability)
- NEVER recommend compacting away incomplete work/todos (loses track of progress)
- NEVER wait for user to ask - be proactive when context approaches 70%

</forbidden>

### /clear Command - Full Reset

<context>

**How it works**: Wipes entire conversation history from context window. Next prompt starts with clean slate.

**What's preserved**: Files in project directory, CLAUDE.md configuration
**What's lost**: All conversational history, questions, answers, decisions

**Critical requirement**: Commit work before clearing to enable session recovery.

</context>

<required>

Agent MUST recommend this protocol when suggesting `/clear`:

1. **Before user clears**:
   - Recommend committing current work with detailed message
   - Check for uncommitted changes (warn user if found)
   - Suggest documenting session state in commit message

2. **When to recommend /clear**:
   - Switching to completely unrelated task (after committing)
   - Context filled with failed exploration attempts (dead ends)
   - Starting new feature after completing previous one
   - User explicitly requests fresh start

3. **When to recommend /compact instead**:
   - Mid-feature implementation (preserve progress)
   - Incomplete work that isn't ready to commit
   - Just need more space (selective retention better than full wipe)

**Recommendation format**:
```
I recommend committing your work first, then running /clear to start fresh:

git commit -m "[detailed message]"
/clear

This will give you a clean context for the new task while preserving
your work in git history.
```

</required>

<examples>

**Good /clear recommendation**:

```text
Context: Just completed OAuth2 feature, all tests passing, PR created

Agent: "Feature is complete and committed. Since you're starting the
database migration task (unrelated to OAuth2), I recommend using /clear
for a fresh context:

/clear

This gives you a clean slate for the new task. Your OAuth2 work is
safely preserved in git history and the merged PR."

User: [executes /clear]

Result: Clean separation between unrelated tasks
```

**Bad /clear recommendation**:

```text
Context: Mid-implementation of OAuth2 feature, 60% done

Agent: "Context is getting full. Run /clear to start fresh."

Problem: Work isn't committed, would lose all progress

Better recommendation:
"Context is at 75%. I recommend /compact instead of /clear since we're
mid-implementation:

/compact keep OAuth2 requirements, files modified (auth.ts:100-150),
JWT design decision, remaining todos

This preserves your progress while freeing up context space."
```

</examples>

<forbidden>

- NEVER recommend `/clear` without checking for uncommitted work
- NEVER recommend `/clear` for mid-task context management (recommend /compact instead)
- NEVER recommend `/clear` when context <90% full (premature - use /compact)
- NEVER claim to execute `/clear` directly (agent cannot trigger it)

</forbidden>

### Compact vs Clear Decision Matrix

<required>

Agent SHOULD use this decision tree to make recommendations:

```text
Context approaching capacity?
│
├─ Same task/feature?
│  └─ Recommend /compact with specific retention criteria
│
├─ Unrelated task?
│  ├─ Work committed?
│  │  └─ Recommend /clear for fresh start
│  └─ Work not committed?
│     └─ Recommend: commit first, then /clear
│
├─ Mid-exploration phase?
│  ├─ Found useful info?
│  │  └─ Recommend /compact, keep findings
│  └─ Dead ends only?
│     └─ Recommend /clear, start fresh (after documenting failures)
│
└─ Context <70%?
   └─ No action needed yet (continue normally)
```

**Recommendation templates for each branch**:
- Same task: "I recommend /compact to preserve progress: /compact keep..."
- Unrelated task: "I recommend /clear for a fresh start: /clear"
- Useful findings: "I recommend /compact to keep findings: /compact keep..."
- Dead ends: "I recommend documenting failures, then /clear"

</required>

<examples>

**Scenario recommendation examples**:

```text
Scenario 1: Implementing authentication (70% context)
Agent recommendation: "I recommend /compact to preserve progress:

/compact keep auth requirements, files (middleware.ts:100-150),
JWT design decision, remaining todos"

Reason: Same task continues, preserve progress

Scenario 2: Done with auth, starting email service (50% context)
Agent recommendation: "Auth is complete and committed. For the email
service (unrelated task), I recommend /clear for a fresh start."

Reason: Unrelated tasks, clean separation

Scenario 3: Debugging complex issue (85% context)
Agent recommendation: "I recommend /compact to preserve investigation:

/compact keep bug description (race condition), findings (locks at
order-service.ts:234), hypothesis (deadlock), next step (Redis locking)"

Reason: Continue debugging, preserve findings

Scenario 4: Failed to find bug, tried many approaches (90% context)
Agent recommendation: "After 10 failed approaches, I recommend documenting
what didn't work in a commit, then /clear for a fresh perspective."

Reason: Too many dead ends, need fresh start
```

</examples>

### Tool Search Tool Integration

<context>

**Feature**: Claude Code's Tool Search Tool discovers tools on-demand instead of loading all tool definitions upfront.

**Benefit**: 85% reduction in token usage for tool documentation
**How it works**: Indexes tool documentation, retrieves only relevant tools for current task
**Research**: Introduced in Claude Code 2025 updates

</context>

<required>

Agent SHOULD leverage Tool Search Tool:

- **Do**: Rely on Tool Search Tool for tool documentation lookup
- **Do**: Use specific tool names when querying (improves retrieval accuracy)
- **Don't**: Request full tool documentation dumps
- **Don't**: Embed tool documentation in context (Tool Search handles it)

**Integration with context management**:
- Tool documentation no longer needs to be in context window
- Frees up tokens for actual code and implementation details
- Allows larger codebase exploration within same context window

</required>

### CLAUDE.md for Persistent Rules

<context>

**Pattern**: Use CLAUDE.md files for rules that persist across all sessions without consuming context window on every prompt.

**Location hierarchy** (checked in order):
1. `$WORKSPACE_ROOT/.claude/CLAUDE.md` (project-specific, highest priority)
2. `$HOME/.claude/CLAUDE.md` (user global, applies to all projects)

**Relationship to .smith rules**: CLAUDE.md references rules from `@` for context-triggered detailed guidelines.

</context>

<required>

#### Rule Persistence Strategy

**What goes in CLAUDE.md** (always active):
- Critical guardrails (NEVER/ALWAYS rules)
- Reference to @AGENTS.md for detailed standards
- Project-specific behavioral guidelines
- Workflow preferences (TDD, commit frequency, etc.)

**What goes in .smith rules** (context-triggered):
- Detailed technical guidelines (Python style, git workflows, etc.)
- Platform-specific patterns (GitHub PR automation, testing standards)
- Context-dependent rules (loaded only when relevant)

**Reference pattern in CLAUDE.md**:

```markdown
# Claude Code Global Configuration

**Standards**: @AGENTS.md

## Critical Guardrails (Always Active)

### NEVER
- Propose changes without reading code first
- Commit directly to main/develop
- Force push to shared branches

### ALWAYS
- Load @AGENTS.md at session start
- Read files before proposing changes
- Run tests before commits
```

</required>

<examples>

**Effective CLAUDE.md structure**:

```markdown
# Project: MyApp

**Standards**: @AGENTS.md

## Always Active

- Use TypeScript strict mode
- Run `npm test` before every commit
- Follow conventional commits format

## Project Stack

- Framework: NestJS
- Database: PostgreSQL with Prisma
- Testing: Jest with Supertest

## Context-Triggered Rules

When working on specific tasks, rules from @ are loaded:
- Python code: rules-python.md
- Git operations: rules-git.md
- Testing: rules-testing.md

(These load automatically via AGENTS.md triggers)
```

**Inefficient approach (duplication)**:

```markdown
# Project: MyApp

[Embeds all Python style guidelines - 500 lines]
[Embeds all Git workflows - 300 lines]
[Embeds all testing patterns - 400 lines]

Result: 1200 lines loaded every session, high token usage
```

</examples>

<forbidden>

- NEVER duplicate .smith rules in CLAUDE.md (reference instead)
- NEVER embed detailed guidelines (use references)
- NEVER put context-specific rules in CLAUDE.md (use AGENTS.md triggers)
- NEVER forget to load @AGENTS.md at session start

</forbidden>

### Context Optimization Workflow

<required>

Agent SHOULD follow this optimization workflow:

#### Phase 1: Exploration (0-50% context)
- Use progressive disclosure (Grep → targeted Read)
- Delegate broad exploration to Task tool (isolated context)
- Keep findings in file:line format

#### Phase 2: Implementation (50-70% context)
- Monitor context meter proactively
- Use reference-based communication
- Prepare for compaction (identify what to preserve)

#### Phase 3: Critical (70-90% context)
- Execute /compact with specific retention criteria
- Preserve: task goals, file locations, decisions, todos
- Discard: exploration results, verbose outputs
- Resume implementation with cleaned context

#### Phase 4: Emergency (90%+ context)
- Aggressive compaction (keep only essentials)
- Consider /clear if switching tasks
- Commit work frequently for session recovery

</required>

<examples>

**Optimized full workflow**:

```text
User: "Implement OAuth2 authentication"

Phase 1 (15% context):
- Grep for "auth" → Find auth/ directory
- Read auth/README.md (overview)
- Identify key files: middleware.ts, service.ts

Phase 2 (45% context):
- Implement authentication logic
- Use file:line references in responses
- Write tests incrementally

Phase 3 (72% context - proactive compaction):
- /compact keep OAuth2 requirements, files (middleware.ts:100-150,
  service.ts:45-90), JWT token decision, remaining todos
- Context now at 30%, continue implementation

Phase 4 (Complete):
- Finish implementation
- Commit with detailed message
- Use /clear before starting next unrelated task
```

</examples>

### Monitoring and Metrics

<context>

**Visual indicator**: Claude Code displays context meter in interface (usually bottom right or status bar).

**User responsibility**: User monitors context meter, notifies agent when approaching 70%.
**Agent responsibility**: Agent cannot directly observe context percentage, relies on user notification.

</context>

<required>

#### User-Agent Communication Pattern

**User should notify agent**:
```text
Good: "My context is at 75%, please compact it"
Good: "Context approaching limit, what should we preserve?"
Bad: Waits until 100% and forced truncation occurs
```

**Agent should proactively suggest**:
```text
After extensive exploration:
"I've gathered the necessary information. Should I compact the context
to preserve our findings while discarding verbose exploration outputs?"

After implementing feature:
"Implementation complete. I recommend committing and using /clear before
starting the next unrelated feature."
```

</required>

<examples>

**Proactive collaboration**:

```text
User: "I notice context is at 68%"

Agent: "Good timing to compact proactively. I'll preserve:
- Task: Implement user permissions system
- Files: models/user.ts:123-156, middleware/auth.ts:78-99
- Decision: Role-based access control with enum
- Next: Write integration tests

/compact keep task (user permissions), files (models/user.ts:123-156,
middleware/auth.ts:78-99), RBAC design decision, next step (integration tests)

Context should now be around 30%, plenty of room to continue."
```

</examples>

### Version Information

<metadata>

- **Claude Code Version**: 0.9.x (as of 2025-12)
- **Last Updated**: 2025-12-10
- **Features Documented**: /compact, /clear, Tool Search Tool, CLAUDE.md

</metadata>

<note>

Features documented here are current as of the version noted above. For newer versions, consult Claude Code changelog for updated capabilities or new context management features.

</note>

---

## Cursor Context Management

<context>

**Foundation**: Cursor provides both manual (/summarize) and automatic summarization when approaching context limits.

**Key capabilities**:
- `/summarize` - Manual context summarization
- Automatic summarization - Triggers at context window limit (uses smaller flash model)
- @ mentions - Force-include specific files in context (@filename)
- @codebase - Search entire codebase for relevant code
- .cursorrules - Persistent project-specific instructions

**Limitation**: Automatic summarization uses smaller flash model which can produce vague summaries, losing technical details.

**Best practice**: Use manual `/summarize` proactively before automatic trigger to maintain better control over summary quality.

</context>

### /summarize Command - Manual Summarization

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

**What goes in `@`-prefixed personal standards** (e.g., `@AGENTS.md`, `@rules-*.md`):
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
- @rules-core.md (critical NEVER/ALWAYS rules)

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

## Kiro Context Management

<context>

**Foundation**: Kiro is built on VS Code OSS (Code OSS fork) and uses steering files for project-level and global AI agent configuration.

**Key capabilities**:
- **Steering files** - Project/global configuration for agent behavior
- **Context triggers** - Dynamic rule loading based on task context
- **Custom agents** - Specialized agents with focused context windows
- **Persistent context** - Maintains context across sessions
- **MCP integration** - Model Context Protocol for extended capabilities
- **File references** - `#[[file:path]]` syntax for dynamic file inclusion

**Architecture**: Kiro inherits VS Code's extension system, configuration patterns, and workspace concepts.

**Canonical example**: @AGENTS.md demonstrates production-grade steering file pattern.

</context>

### Steering File Pattern

<context>

**Purpose**: Define project standards and agent behavior that persist across all sessions.

**Kiro steering file** is equivalent to:
- `.cursorrules` in Cursor (project-specific instructions)
- `CLAUDE.md` in Claude Code (persistent configuration)
- But with advanced features: context triggers, file references, dynamic loading

</context>

<required>

#### Steering File Structure

Based on @AGENTS.md canonical example (using only documented XML tags):

```xml
# Project Standards (AGENTS.md)

<metadata>

- **Scope**: Entry point for project coding standards
- **Load if**: Starting any development task
- **Prerequisites**: None

</metadata>

<required>

## Critical Rules

Agent MUST follow these rules at all times:
- Rule 1
- Rule 2
- Rule 3

</required>

<guiding_principles>

## Design Principles

- DRY (Don't Repeat Yourself)
- KISS (Keep It Simple, Stupid)
- YAGNI (You Aren't Gonna Need It)

</guiding_principles>

<context>

## Context-Aware Rule Loading

<plan_tool_usage>

### Workflow

1. Detect context from user request or file type
2. Match context to applicable rules
3. Report active rules to user
4. Execute task following those rules

<constraints>

- MUST report which rules are loaded
- MUST match context to appropriate rule sets
- MUST gracefully skip if rule file not found

</constraints>

<rules>

**python_development:**
- Condition: Writing/modifying Python code OR running Python tests
- Load: `rules-python.md`

**git_operations:**
- Condition: Creating commits OR managing branches
- Load: `rules-git.md`, `rules-naming.md`

**testing:**
- Condition: Writing or running tests
- Load: `rules-testing.md`

</rules>

</plan_tool_usage>

</context>

<instructions>

## Rule Loading Notification

1. At session start: Report baseline rules
2. Before each task: Report applicable rules
3. When context changes: Report rule loading/unloading

</instructions>
```

**Key Sections Explained**:

**`<metadata>`** - File metadata and loading conditions:
- **Scope**: What this file covers
- **Load if**: When agent should load this file
- **Prerequisites**: Other files that should load first

**`<required>`** - Mandatory rules always active:
- Critical NEVER/ALWAYS rules
- Project non-negotiables
- Safety guardrails

**`<guiding_principles>`** - Design philosophy:
- SOLID principles
- DRY, KISS, YAGNI
- Project-specific principles

**`<context>`** with nested tags - Dynamic context-based loading:
- `<plan_tool_usage>`: Workflow for detecting and matching contexts
- `<constraints>`: Requirements for rule loading
- `<rules>`: Context-to-rules mapping
- Enables efficient context management (load only relevant rules)
- Prevents context bloat (don't load Python rules when working on git)

**`<instructions>`** - Rule loading notification protocol:
- Defines when and how to report loaded rules
- Session start, task execution, context changes

</required>

<examples>

**Minimal steering file** (small project):

```markdown
# MyApp Standards

<metadata>
- Scope: MyApp coding standards
- Load if: Working in MyApp project
</metadata>

<required>

- Use TypeScript strict mode
- Run tests before commits
- Follow REST API conventions

</required>

<context>

<plan_tool_usage>

<rules>

**testing:**
- Condition: Running tests
- Load: rules-testing.md

</rules>

</plan_tool_usage>

</context>

<instructions>

Report active rules before executing tasks.

</instructions>
```

**Comprehensive steering file** (large project):

```markdown
# Enterprise App Standards

<metadata>
- Scope: EnterpriseCo coding standards
- Load if: Working in EnterpriseCo repositories
</metadata>

<required>

## Security Requirements

- NEVER commit credentials or API keys
- ALWAYS validate user input
- ALWAYS use parameterized SQL queries

## Code Quality

- Minimum 80% test coverage
- All public APIs must have documentation
- Follow language-specific linters

</required>

<guiding_principles>

- Security first
- Performance matters
- Developer experience
- Backwards compatibility

</guiding_principles>

<context>

<plan_tool_usage>

<constraints>

- MUST report loaded rules before task execution
- MUST gracefully skip non-existent rule files

</constraints>

<rules>

**python_development:**
- Condition: Working with Python
- Load: rules-python.md, rules-testing.md

**javascript_development:**
- Condition: Working with JavaScript/TypeScript
- Load: rules-typescript.md, rules-react.md (if React detected)

**database_operations:**
- Condition: Modifying database schema OR writing migrations
- Load: rules-database.md, rules-migrations.md

**api_development:**
- Condition: Creating/modifying API endpoints
- Load: rules-api.md, rules-security.md

</rules>

</plan_tool_usage>

</context>

<instructions>

Report which rules are loaded for each context before executing tasks.

</instructions>
```

</examples>

<forbidden>

- NEVER hardcode file contents in steering file (use file references or separate rule files)
- NEVER create circular dependencies (fileA loads fileB loads fileA)
- NEVER duplicate rules across multiple files (use references)
- NEVER load all rules by default (defeats purpose of context-aware loading)

</forbidden>

### File Reference Syntax

<context>

**Purpose**: Include external file contents in agent context dynamically.

**Syntax**: `#[[file:relative/path/to/file.md]]`

**Benefit**: File contents are loaded when steering file is read, keeping content up-to-date without duplication.

</context>

<required>

**File Reference Pattern**:

```markdown
# Authentication Module Steering

## Overview

OAuth2 implementation with JWT tokens

## Key Files

- Main logic: #[[file:src/auth/auth.service.ts]]
- Middleware: #[[file:src/auth/auth.middleware.ts]]
- Configuration: #[[file:src/auth/auth.config.ts]]
- Tests: #[[file:tests/auth/auth.integration.test.ts]]

## Documentation

See architecture: #[[file:docs/architecture.md]]
```

**Rules for file references**:

1. **Use relative paths** (relative to steering file location):
   ```markdown
   Good: #[[file:src/auth/service.ts]]
   Bad: #[[file:/Users/username/project/src/auth/service.ts]]
   ```

2. **Reference documentation, not code** (code changes frequently):
   ```markdown
   Good: #[[file:docs/authentication.md]] (stable documentation)
   Acceptable: #[[file:src/auth/README.md]] (module overview)
   Bad: #[[file:src/auth/service.ts]] (implementation details change)
   ```

3. **Use for structure/patterns, not for reading all code**:
   ```markdown
   Good: "See file structure: #[[file:docs/file-structure.md]]"
   Bad: [Lists 50 file references to every source file]
   ```

</required>

<examples>

**Effective file references**:

```markdown
# Project Structure

## Directory Layout

See #[[file:docs/file-structure.md]] for complete directory organization.

## Module Architecture

Each module follows this pattern:

```
module/
├── README.md           # Module overview
├── module.service.ts   # Business logic
├── module.controller.ts # API endpoints
└── module.test.ts      # Tests
```

Example: Authentication module at #[[file:src/auth/README.md]]

## API Conventions

Follow REST API standards documented in #[[file:docs/api-conventions.md]]
```

**Inefficient approach**:

```markdown
# Project Files

Here's every file in the project:

#[[file:src/module1/file1.ts]]
#[[file:src/module1/file2.ts]]
#[[file:src/module2/file1.ts]]
[...100 more file references...]

Result: Entire codebase loaded into context on every session
Better: Use file references for documentation, let agent discover code files as needed
```

</examples>

<forbidden>

- NEVER use absolute paths in file references (breaks portability)
- NEVER reference every source file (defeats progressive disclosure)
- NEVER reference generated files (build outputs, node_modules)
- NEVER reference files outside project (security risk)

</forbidden>

### Context Triggers for Dynamic Loading

<context>

**Purpose**: Load additional rules files only when relevant context is detected.

**Benefit**: Prevents context bloat by loading only rules needed for current task.
**Pattern**: IF [condition] → LOAD [file]

**Canonical example**: @AGENTS.md defines 18 context triggers.

</context>

<required>

**Trigger structure**:

```xml
<trigger context="descriptive_name">

- **IF** [specific conditions that activate this trigger]:
- **LOAD**: `path/to/rules-file.md`
- **LOAD**: `path/to/another-rules.md` (if multiple files needed)
- **ACTION**: [optional action to take when triggered]

</trigger>
```

**@ Reference Resolution**:

When context triggers reference @rules-*.md files:

1. **File Not Found**: Agent should report which file failed to load and continue gracefully without that rule file
2. **Fallback Behavior**: Agent should proceed with available rules, not halt execution
3. **Loading Report**: Agent MUST proactively report which rules were successfully loaded and which failed (see @AGENTS.md Rule Loading Notification)

**Error Handling Example**:

```text
Rules loaded:
- @rules-core.md (triggered by: always_active context)
- @rules-python.md (triggered by: python_development context)

Rules skipped:
- @rules-nonexistent.md (file not found, gracefully skipped)
```

</required>

### Location Hierarchy

<context>

**Kiro checks for steering files in this order** (first found wins):

1. **Project-specific**: `.kiro/steering/` in workspace root (highest priority)
2. **User-global**: `~/.kiro/steering/` (applies to all projects)
3. **Fallback**: Check for `AGENTS.md` in workspace root (compatibility)

**Best practice**: Use `AGENTS.md` in workspace root (like smith project does) for maximum compatibility and simplicity.

</context>

### Custom Agents for Context Specialization

<context>

**Purpose**: Create specialized agents with focused context windows for specific tasks.

**Benefit**:
- Smaller context windows (faster responses, lower cost)
- Task-specific context (no irrelevant information)
- Parallel workflows (different agents for different tasks)

**Configuration**: `.kiro/agents/` directory

</context>

### MCP Integration for Context Efficiency

<context>

**MCP (Model Context Protocol)**: Protocol for extending AI agent capabilities with external tools.

**Kiro configuration**: `.kiro/settings/mcp.json` (workspace) or `~/.kiro/settings/mcp.json` (global)

**Relevance to context management**: MCP tools reduce context usage by delegating operations to specialized servers.

</context>

<required>

**MCP Configuration for Context Optimization**:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "mcp-server-filesystem",
      "args": ["--workspace", "${workspaceFolder}"]
    },
    "git": {
      "command": "mcp-server-git"
    },
    "serena": {
      "command": "mcp-server-serena",
      "args": ["--workspace", "${workspaceFolder}"]
    }
  }
}
```

**Context benefits per MCP server**:

**Filesystem MCP**:
- Efficient file operations without loading full file contents
- Directory listing without reading all files
- File metadata access (size, modified date) without content

**Git MCP**:
- Git operations without loading repository history
- Commit message retrieval without full diff
- Branch information without loading all commits

**Serena MCP**:
- Symbol-level navigation (functions, classes, types)
- Find definitions/references without reading entire files
- Code structure understanding without loading full codebase

</required>

<examples>

**Context-efficient workflow with MCP**:

```text
Without MCP:
Task: "Find and rename authenticateUser function"

Step 1: Grep for "authenticateUser" (loads search results)
Step 2: Read auth.service.ts (5000 lines loaded)
Step 3: Read all files that import auth.service (3000 lines)
Step 4: Rename function
Total context: 8000+ lines

With Serena MCP:
Task: "Find and rename authenticateUser function"

Step 1: Query MCP "find symbol authenticateUser"
Step 2: MCP returns: auth.service.ts:234-267, list of references
Step 3: Read only function definition (33 lines)
Step 4: Use MCP rename operation (handles all references)
Total context: 33 lines (99.6% reduction)
```

</examples>

### Persistent Context Across Sessions

<context>

**Kiro capability**: Maintains context across sessions using steering files and project memory.

**Strategy**: Combine steering files (persistent knowledge) with commit messages (session progress) for seamless session continuity.

</context>

<required>

**Session Continuity Pattern**:

**Session 1**:
1. Work on feature
2. Update steering file with new decisions/patterns
3. Commit progress with detailed messages
4. Update file references (`#[[file:...]]`) to reflect current state

**Session 2** (next day):
1. Agent reads steering file (persistent project knowledge)
2. Agent reviews recent commits (`git log -5`)
3. Agent continues from documented state

</required>

### Steering Files as Context Management Tool

<context>

**Key insight**: Steering files themselves are a context management tool.

**How they manage context**:
- **Static content** (metadata, principles) → Cached, low cost
- **Context triggers** → Load only relevant rules
- **File references** → Dynamic, always current
- **Persistent across sessions** → Don't need to reload each time

</context>

<required>

**Structure for prompt caching** (from `rules-ai_agents.md:Prompt Caching`):

```markdown
# AGENTS.md (optimized for caching)

<!-- STATIC CONTENT (cached) -->

<metadata>
- Scope
- Load if
- Prerequisites
</metadata>

<guiding_principles>
[Static design principles]
</guiding_principles>

<required>
[Mandatory rules that rarely change]
</required>

<context>

<plan_tool_usage>

<rules>
[Context-to-rules mapping - structure is static]
</rules>

</plan_tool_usage>

</context>

<!-- DYNAMIC CONTENT (not cached) -->

<context>

## Recent Decisions

[Updates frequently - new decisions added]

</context>

<examples>

[Code examples - may update as patterns evolve]

</examples>
```

**Benefits of this structure**:
- First ~1024 tokens cached (metadata, principles, triggers)
- 90% cost reduction on cached sections
- 85% latency reduction
- Dynamic content (recent decisions, examples) can update without breaking cache

</required>

### Version Information

<metadata>

- **Kiro Version**: 1.x (as of 2025-12)
- **Last Updated**: 2025-12-10
- **Features Documented**: Steering files, context triggers, file references, custom agents, MCP integration

</metadata>

<note>

Features documented here are current as of the version noted above. Kiro is built on VS Code OSS and may inherit new features from VS Code releases. Consult Kiro changelog for platform updates.

</note>

---

<related>

- **Shared principles**: @rules-context-principles.md (universal strategies)
- **Parent**: @rules-ai_agents.md (AI agent interaction patterns, prompt caching)
- **Foundation**: @rules-core.md (critical NEVER/ALWAYS rules)
- **MCP integration**: @rules-tools.md (MCP server configuration)
- **Research**: Anthropic Claude Code documentation, Cursor documentation, Kiro documentation, MCP protocol specification

</related>
