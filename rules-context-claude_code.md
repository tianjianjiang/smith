# Claude Code Context Management

<metadata>

- **Scope**: Claude Code-specific context management commands and strategies
- **Load if**: Using Claude Code AND (context window >70% OR optimizing context usage)
- **Prerequisites**: @rules-context-principles.md, @rules-ai_agents.md
- **Requires**: Understanding of Claude Code /compact and /clear commands
- **Provides**: Selective retention patterns, context optimization strategies, persistent configuration patterns
- **Research**: Anthropic Claude Code documentation (accessed 2025-12), Claude Code best practices, Tool Search Tool

</metadata>

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

## Architectural Limitation

<context>

**Critical**: Agents cannot programmatically trigger `/compact` or `/clear` commands.

**Why**: These are built-in REPL commands, not agent tools. The SlashCommand tool only supports custom user-defined commands in `.claude/commands/`, not built-in commands like `/compact` or `/clear`.

**What agents can do**:
- Detect when context approaches capacity (based on conversation length)
- Recommend specific `/compact` command with retention criteria
- Explain what will be preserved vs discarded
- Format commands as copy-paste ready for user execution

**What agents cannot do**:
- Execute `/compact` or `/clear` directly
- Automatically manage context without user action
- Trigger built-in commands via SlashCommand tool

**Collaboration model**: User reports context percentage → Agent recommends specific command → User executes command

</context>

<required>

When context approaches 70%, agent MUST:
1. Inform user that context is at critical threshold
2. Recommend specific `/compact` command with retention criteria (copy-paste ready)
3. Explain what will be preserved (task goals, file paths, decisions, todos)
4. Explain what will be discarded (verbose outputs, failed attempts)

</required>

<required>

## /compact Command - Selective Retention

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

### Retention Criteria Template

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

## /clear Command - Full Reset

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

## Compact vs Clear Decision Matrix

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

## Tool Search Tool Integration

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

## CLAUDE.md for Persistent Rules

<context>

**Pattern**: Use CLAUDE.md files for rules that persist across all sessions without consuming context window on every prompt.

**Location hierarchy** (checked in order):
1. `$WORKSPACE_ROOT/.claude/CLAUDE.md` (project-specific, highest priority)
2. `$HOME/.claude/CLAUDE.md` (user global, applies to all projects)

**Relationship to .smith rules**: CLAUDE.md references rules from `@` for context-triggered detailed guidelines.

</context>

<required>

## Rule Persistence Strategy

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

## Context Optimization Workflow

<required>

Agent SHOULD follow this optimization workflow:

### Phase 1: Exploration (0-50% context)
- Use progressive disclosure (Grep → targeted Read)
- Delegate broad exploration to Task tool (isolated context)
- Keep findings in file:line format

### Phase 2: Implementation (50-70% context)
- Monitor context meter proactively
- Use reference-based communication
- Prepare for compaction (identify what to preserve)

### Phase 3: Critical (70-90% context)
- Execute /compact with specific retention criteria
- Preserve: task goals, file locations, decisions, todos
- Discard: exploration results, verbose outputs
- Resume implementation with cleaned context

### Phase 4: Emergency (90%+ context)
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

## Monitoring and Metrics

<context>

**Visual indicator**: Claude Code displays context meter in interface (usually bottom right or status bar).

**User responsibility**: User monitors context meter, notifies agent when approaching 70%.
**Agent responsibility**: Agent cannot directly observe context percentage, relies on user notification.

</context>

<required>

### User-Agent Communication Pattern

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

## Version Information

<metadata>

- **Claude Code Version**: 0.9.x (as of 2025-12)
- **Last Updated**: 2025-12-10
- **Features Documented**: /compact, /clear, Tool Search Tool, CLAUDE.md

</metadata>

<note>

Features documented here are current as of the version noted above. For newer versions, consult Claude Code changelog for updated capabilities or new context management features.

</note>

</context>

<related>

- **Shared principles**: @rules-context-principles.md (universal strategies)
- **Other platforms**: @rules-context-cursor.md, @rules-context-kiro.md
- **Parent**: @rules-ai_agents.md (AI agent interaction patterns)
- **Foundation**: @rules-core.md (critical NEVER/ALWAYS rules)
- **Research**: Anthropic Claude Code documentation, Prompt Caching Guide

</related>
