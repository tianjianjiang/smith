# Context Management Principles

<metadata>

- **Scope**: Universal context management strategies for AI coding agents
- **Load if**: Context management OR optimizing context usage OR context window approaching capacity
- **Prerequisites**: @rules-ai_agents.md
- **Requires**: Understanding of context windows, token limits, and prompt engineering
- **Provides**: Universal context optimization strategies, selective retention patterns, progressive disclosure techniques
- **Research**: Anthropic (Claude Code, Prompt Caching), Cursor documentation, Kiro steering files, LLMLingua (Microsoft Research)

</metadata>

<context>

**Foundation**: All AI coding agents (Claude Code, Cursor, Kiro, GitHub Copilot) share common context window constraints. Effective context management requires proactive strategies that work across platforms.

**Context window lifecycle**:
1. **Early phase** (0-50%): Unrestricted exploration, load necessary context
2. **Mid phase** (50-70%): Monitor usage, apply progressive disclosure
3. **Critical phase** (70-90%): Proactive compaction/summarization, selective retention
4. **Emergency phase** (90-100%): Forced truncation/summarization, potential information loss

**Best practice**: Take action in critical phase (70%+) to maintain control over what's retained.

</context>

## Agent Role in Context Management

<context>

**Critical architectural limitation**: Agents cannot programmatically trigger built-in context management commands like `/compact`, `/clear`, or `/summarize`. These are REPL-level controls reserved for user execution only.

**What agents can do**:
- Monitor approximate context usage based on conversation length
- Detect when context approaches critical thresholds (70%+)
- Apply progressive disclosure (load minimal context incrementally)
- Use reference-based communication (file:line, not full content)
- Recommend when user should compact/clear/summarize with specific criteria
- Provide copy-paste ready commands with retention specifications

**What agents cannot do**:
- Directly observe context meter percentage (user must report this)
- Programmatically execute `/compact`, `/clear`, or `/summarize` commands
- Automatically manage context without user action
- Trigger built-in REPL commands via SlashCommand tool

**User-Agent collaboration model**:
1. User monitors context meter in IDE
2. User notifies agent when approaching 70% threshold ("My context is at 75%")
3. Agent provides specific recommendation with retention criteria
4. User executes the recommended command (copy-paste ready format)
5. User confirms compaction completed (optional)

</context>

<required>

### Agent Responsibilities

Agent MUST:
- Recommend specific retention criteria when user reports high context usage
- Format recommendations as executable commands user can copy-paste
- Explain what will be preserved vs discarded
- Be proactive (don't wait for user to ask for recommendations)

Agent MUST NOT:
- Claim to execute `/compact`, `/clear`, or `/summarize` directly
- Assume automatic context management is possible
- Use language implying agent can trigger these commands
- Wait passively for user to request compaction recommendations

</required>

<required>

## Information Retention Strategy

### Always Preserve

Agent MUST retain during context compaction/summarization:

- **Task goals and requirements**: Original user request, success criteria
- **File locations**: Use `file:line` format (e.g., `auth.ts:123`)
- **Architectural decisions**: Design choices made, trade-offs considered
- **Incomplete work**: Todos, next steps, partially implemented features
- **Root causes**: Bug descriptions, error messages that led to solutions
- **Key findings**: Investigation results, performance metrics, test failures

### Always Discard

Agent MUST remove during context compaction/summarization:

- **Verbose tool outputs**: Long file listings, complete directory trees
- **Failed exploration attempts**: Dead-end investigations, incorrect hypotheses
- **Redundant file readings**: Multiple reads of same file
- **Intermediate debugging**: Print statements, console logs, trace outputs
- **Duplicate information**: Repeated explanations, redundant summaries

### Conditionally Preserve

Agent SHOULD evaluate for retention:

- **Code exploration results**: Keep findings and file:line references, discard full file dumps
- **Test outputs**: Keep failures and root causes, discard passing test logs
- **Documentation**: Keep references and links, discard full text if available externally
- **Configuration**: Keep changed values, discard default/unchanged settings

## Progressive Disclosure Pattern

<context>

**Strategy**: Load information incrementally as needed, not all at once.

**Benefits**:
- Reduced initial context usage (start with metadata only)
- Faster response times (less processing)
- More context available when actually needed

</context>

<required>

Agent MUST follow this loading sequence:

1. **Metadata scanning** (cheapest):
   - Use Glob to find file locations: `**/*.ts`
   - Use Grep to search for keywords: `pattern: "authenticateUser"`
   - Result: File paths only, no content loaded

2. **Targeted reading** (moderate cost):
   - Read specific file sections: `Read file:auth.ts offset:100 limit:50`
   - Read only relevant files based on metadata scan
   - Result: Minimal context for specific task

3. **Full file loading** (expensive):
   - Read complete files only when actively modifying
   - Use offset/limit for large files (>500 lines)
   - Result: Comprehensive understanding for implementation

4. **Broad exploration** (most expensive):
   - Use Task tool with Explore subagent for multi-file discovery
   - Delegate exploration to specialized agents (isolated context)
   - Result: Comprehensive codebase understanding

</required>

<examples>

**Good progressive disclosure**:

```text
User: "Fix authentication bug"

Step 1 (metadata): Grep for "auth" → Find auth/middleware.ts, auth/service.ts
Step 2 (targeted): Read auth/middleware.ts:200-250 (error handling section)
Step 3 (context): Read auth/service.ts:45-80 (called function)
Step 4 (implement): Make fix with minimal context loaded

Total context used: ~100 lines
```

**Bad approach (load everything)**:

```text
User: "Fix authentication bug"

Step 1: Read entire auth/ directory (15 files, 3000 lines)
Step 2: Read all tests (20 files, 2000 lines)
Step 3: Read configuration files (5 files, 500 lines)
Step 4: Implement fix

Total context used: ~5500 lines (context 80% full before starting)
```

</examples>

<forbidden>

- NEVER read entire directories without Grep filtering first
- NEVER load full files when targeted sections would suffice
- NEVER repeat file reads without using context (re-read same file multiple times)
- NEVER explore broadly when user provides specific file paths

</forbidden>

## Reference-Based Communication

<context>

**Strategy**: Use pointers and references instead of embedding full content.

**Benefits**:
- Reduces token usage (reference vs full content)
- Maintains traceability (file:line always accurate)
- Enables quick navigation (user can jump to location)

</context>

<required>

Agent MUST use reference formats:

### File References

```text
Format: file:line or file:start-end

Examples:
- Fixed bug in auth.ts:234
- Modified auth.ts:100-125 and auth.ts:300-315
- See implementation in handlers/webhook.ts:45
```

### Commit References

```text
Format: commit-sha or commit-sha:file

Examples:
- Addresses issue from commit a3b4c5d
- Reverts changes in 7f2e9a1:config.ts
- Based on approach from fe8d3c2
```

### Documentation References

```text
Format: Link with description, not embedded text

Good:
- See API documentation: https://api.example.com/docs#auth
- Follow pattern from docs/architecture.md:Authentication

Bad:
- [Embeds 500 lines of documentation]
```

</required>

<examples>

**Reference-based response**:

```text
I found the authentication bug at auth/middleware.ts:234. The issue is a
missing null check before calling user.permissions. I've added the check
at line 234 and a corresponding test at tests/auth.test.ts:456.

Changes follow the error handling pattern from middleware.ts:100-110.
```

**Inefficient embedded response**:

```text
I found the authentication bug. Here's the full code:

[Pastes 50 lines of middleware.ts]
[Pastes 30 lines of auth.test.ts]
[Pastes 20 lines of error handling example]

The issue is a missing null check. Here's the full fix:

[Pastes another 50 lines]
```

</examples>

## Sparse Attention Pattern

<context>

**Strategy**: Focus context window on actively relevant code, not entire codebase.

**Research**: Based on Anthropic's sparse attention patterns and prompt caching best practices.

</context>

<required>

Agent MUST apply sparse attention:

1. **Locate before loading**:
   - Grep to find where code exists
   - Use file:line references from Grep results
   - Read only the specific locations found

2. **Incremental expansion**:
   - Start with narrowest scope (single function)
   - Expand only if needed (add calling functions)
   - Never load entire call chain speculatively

3. **Delegate broad tasks**:
   - Use Task tool for multi-file exploration
   - Subagents have isolated context windows
   - Parent agent receives summary, not full exploration results

</required>

<examples>

**Sparse attention workflow**:

```text
Task: "Understand how webhooks are processed"

Step 1: Grep "webhook" → Find handlers/webhook.ts, services/webhook.ts, routes.ts
Step 2: Read handlers/webhook.ts:main_function (entry point)
Step 3: See call to services/webhook.ts:process()
Step 4: Read services/webhook.ts:process function only
Result: Understand flow with minimal context

Context used: ~150 lines across 3 specific functions
```

**Dense attention (inefficient)**:

```text
Task: "Understand how webhooks are processed"

Step 1: Read entire handlers/ directory
Step 2: Read entire services/ directory
Step 3: Read routes.ts
Step 4: Read middleware files
Result: Understand flow but context 70% full

Context used: ~3000 lines across 20+ files
```

</examples>

## Semantic Chunking

<context>

**Strategy**: Organize context into logical units that can be loaded/unloaded together.

**Benefits**: When compacting/summarizing, can preserve entire logical units rather than arbitrary line ranges.

</context>

<required>

Agent SHOULD organize context into chunks:

1. **Imports and types** (rarely changes, good for prompt caching):
   - Module imports
   - Type definitions
   - Interfaces and constants

2. **Core logic** (changes frequently, keep focused):
   - Main functions and classes
   - Business logic implementation
   - Error handling

3. **Tests and validation** (load when needed):
   - Test suites
   - Validation functions
   - Mock data

4. **Configuration** (load once, reference often):
   - Environment variables
   - Feature flags
   - Build configuration

</required>

<examples>

**Semantic chunking in practice**:

```text
Working on feature implementation:

Chunk 1 (cached): imports, types, interfaces
Chunk 2 (active): core business logic being modified
Chunk 3 (referenced): related utility functions
Chunk 4 (discarded): unrelated test files, old implementations

When compacting at 70%:
- Preserve Chunk 1 (stable, will be cached)
- Preserve Chunk 2 (actively working)
- Summarize Chunk 3 (keep function signatures, discard implementations)
- Discard Chunk 4 (not relevant to current task)
```

</examples>

## Context Compaction Timing

<context>

**Critical threshold**: Take action at 70% context capacity to maintain control over what's retained.

**Reasoning**:
- Below 70%: Sufficient headroom for continued work
- 70-90%: Proactive compaction prevents forced truncation
- Above 90%: Limited control, may lose critical information

</context>

<required>

Agent SHOULD compact/summarize at these triggers:

1. **Capacity-based** (primary):
   - At 70% capacity: Proactive compaction
   - At 85% capacity: Aggressive compaction
   - At 95% capacity: Emergency measures

2. **Phase-based** (secondary):
   - After exploration phase → Before implementation
   - After implementation → Before testing
   - After code review → Before next task

3. **Task-based** (tertiary):
   - Switching to unrelated task
   - Completing logical unit of work
   - Before requesting review

</required>

<examples>

**Good timing (proactive)**:

```text
Context: 72% full after extensive exploration

Agent: "I'll compact the context before starting implementation.
Preserving: task requirements, file locations found (auth.ts:234,
services/auth.ts:45), architectural decision to use JWT tokens.
Discarding: verbose Grep outputs, failed exploration attempts."

[Uses platform-specific compact command]
```

**Bad timing (reactive)**:

```text
Context: 98% full during implementation

System: *Automatically truncates context*
Agent: "I've lost some context. What were we working on again?"
User: [Has to re-explain task]
```

</examples>

## Platform-Agnostic Strategies

<context>

These strategies work regardless of which coding agent is being used.

</context>

<required>

Universal best practices:

1. **Monitor context usage regularly**:
   - Check context meter/indicator in IDE
   - User should notify agent when approaching 70%
   - Agent should proactively suggest compaction

2. **Commit frequently for session continuity**:
   - Commit after logical units of work
   - Use detailed commit messages (they're persistent memory)
   - Agent can read git log to restore context across sessions

3. **Use project documentation as external memory**:
   - Reference architecture docs instead of embedding
   - Link to API documentation rather than copying
   - Maintain decision log in docs/ directory

4. **Leverage persistent configuration**:
   - Store coding standards in config files (.cursorrules, CLAUDE.md, steering files)
   - Reference standards rather than repeating in each session
   - Update config when patterns change

</required>

</context>

<related>

- **Platform-specific**: See @rules-context-platforms.md (Claude Code, Cursor, Kiro)
- **Parent**: @rules-ai_agents.md (AI agent interaction patterns)
- **Foundation**: @rules-core.md (critical NEVER/ALWAYS rules)
- **Research**: Anthropic Prompt Caching Guide, Microsoft LLMLingua paper

</related>
