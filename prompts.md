# Prompt Engineering Standards

<metadata>

- **Scope**: Prompt caching, token efficiency, and optimization techniques
- **Load if**: Writing or reviewing AI prompts, optimizing context usage, prompt engineering
- **Prerequisites**: @core.md
- **Requires**: Understanding of token limits, prompt caching, LLM optimization
- **Provides**: Cache optimization strategies, token efficiency patterns, progressive disclosure
- **Research**: Anthropic (Prompt Caching Guide), Microsoft (LLMLingua)

</metadata>

<context>

**Foundation**: Effective prompt engineering reduces costs by up to 90% and latency by 85% through strategic caching and token optimization.

**Key concepts**:
- **Prompt caching**: Reuse computed context across API calls
- **Token efficiency**: Minimize token usage without sacrificing quality
- **Progressive disclosure**: Load information incrementally as needed

</context>

## Prompt Caching Awareness

<context>

**Context**: Anthropic prompt caching reduces costs by 90% and latency by 85%

**How it works**:
1. Cache breakpoints every ~1024 tokens
2. Prefix (before breakpoint) must be identical for cache hit
3. Cache lifetime: 5 minutes (active use), extended with each hit
4. Applies to system messages, tools, and long contexts

</context>

**Agent behavior implications**:

<required>

- Agent MUST maintain consistent tool order across calls
- Agent MUST avoid unnecessary variations in repeated context
- Agent MUST reuse exact prompt structures when possible
- Agent MUST place dynamic content AFTER static content

</required>

<examples>

**Cache-friendly pattern (good)**:
- Call 1: System message (1500 tokens) + Tools (2000 tokens) + User query
- Call 2: Same system + Same tools + Different user query
- Result: First ~3500 tokens cached, only new query processed

</examples>

<forbidden>

**Cache-unfriendly pattern (bad)**:
- Call 1: System message + Tools in order [A, B, C]
- Call 2: System message + Tools in order [A, C, B]
- Result: No cache hit due to reordering

</forbidden>

**File organization for caching**:
- AGENTS.md metadata section: Static, always cached
- Trigger definitions: Static, always cached
- Code examples: Dynamic, placed after cache breakpoints
- Evolving documentation: Dynamic, placed last

## Prompt Caching Optimization

<context>

**Goal**: Maximize cache hit rate for 90% cost reduction and 85% latency reduction

**Research source**: [Anthropic Prompt Caching Guide](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)

### Four Cache Breakpoint Strategy

**Optimal structure** (each section ≥1024 tokens):
1. **System instructions** (static methodology, core principles)
2. **Tool definitions** (consistent order, complete schemas)
3. **Project context** (AGENTS.md, architecture docs, static references)
4. **Dynamic context** (recent code changes, session-specific data)

</context>

**Implementation**:
```markdown
<system> (1200 tokens - CACHED)
Core agent behavior rules, Constitutional AI principles, task protocols
</system>

<tools> (2500 tokens - CACHED)
Complete tool definitions in stable order: Read, Write, Edit, Bash, Task, etc.
</tools>

<project_context> (1500 tokens - CACHED)
AGENTS.md metadata, architecture overview, dependency graph, testing standards
</project_context>

<dynamic_context> (500 tokens - NOT CACHED)
Recent git commits, current file changes, session-specific todos
</dynamic_context>
```

### AGENTS.md Structure for Caching

**Cache-friendly template** (using only documented XML tags):
```markdown
<!-- Section 1: Metadata (STATIC - cached) -->
<metadata>
**Scope**: ...
**Load if**: ...
**Prerequisites**: ...
**Requires**: ...
**Provides**: ...
</metadata>

<!-- Section 2: Guiding Principles (STATIC - cached) -->
<guiding_principles>
Design principles (DRY, KISS, YAGNI, SOLID)
</guiding_principles>

<!-- Section 3: Context-Aware Rule Loading (STATIC - cached) -->
<context>

<plan_tool_usage>

<constraints>
Requirements for rule loading
</constraints>

<rules>
Context-to-rules mapping
</rules>

</plan_tool_usage>

</context>

<!-- Section 4: Notification Protocol (STATIC - cached) -->
<instructions>
Rule loading notification protocol
</instructions>

<!-- Section 5: Core Concepts (STATIC - cached) -->
<required>
## Validation Rules
Critical NEVER/ALWAYS rules
</required>

<forbidden>
Anti-patterns and prohibited actions
</forbidden>

<!-- CACHE BREAKPOINT (~1024 tokens) -->

<!-- Section 6: Examples (DYNAMIC - not cached) -->
<examples>
## Common Patterns
[Code examples that evolve with codebase]
</examples>

<!-- Section 7: Related (included in examples or metadata) -->
References to related files
```

### Optimization Checklist

<required>

- Static content (methodology, rules) MUST come first
- Tool definitions MUST maintain consistent order
- AGENTS.md structure MUST prioritize metadata/triggers before examples
- Dynamic content (code snippets, recent changes) MUST be placed last
- Each cached section SHOULD exceed 1024 tokens for breakpoint efficiency

</required>

<forbidden>

- NEVER reorder tools between calls
- NEVER inject dynamic content into static sections
- NEVER modify cached prefix unnecessarily
- NEVER place evolving examples before stable rules

</forbidden>

**Measurement**:
- Monitor cache hit rates in API responses
- Target: >80% cache hit rate for repeated operations
- Optimize: Move frequently-changing content past breakpoints

## Token Efficiency Techniques

<context>

**Goal**: Reduce token usage without sacrificing quality

**Research sources**:
- [Microsoft LLMLingua](https://github.com/microsoft/LLMLingua) - Token compression
- [Anthropic Prompt Engineering](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering) - Efficiency patterns

</context>

### Progressive Disclosure

<context>

**Principle**: Load information on-demand, not upfront

**Pattern**: Three-level loading hierarchy
```markdown
Level 1: Metadata only (50 tokens)
<metadata>
**Scope**: Authentication module
**Load if**: Working with user identity, sessions, OAuth
</metadata>

Level 2: Core concepts when triggered (200 tokens)
<trigger context="authentication">
**Core patterns**: JWT-based, refresh token rotation, role-based access control
**Key files**: auth/middleware.ts, auth/tokens.ts, auth/roles.ts
</trigger>

Level 3: Full details when accessed (1000+ tokens)
[Complete implementation guide, code examples, edge cases]
```

**Agent behavior**:
- Start with metadata scanning (Glob/Grep for relevant files)
- Load core concepts only when context matches
- Read full documentation only when actively working on feature

</context>

### Sparse Attention Patterns

**Technique**: Focus agent attention on relevant code sections

**File reading strategy**:
```text
Inefficient:
Agent: *reads entire 5000-line file*
Agent: *searches for relevant function*

Efficient:
Agent: *uses Grep to find function location*
Agent: *reads file with offset/limit targeting specific section*
Agent: *reads only necessary context (±20 lines)*
```

<required>

- Use Grep with output_mode="content" to locate code
- Use Read with offset/limit for large files (>500 lines)
- Read incrementally: start narrow, expand only if needed
- Use Task tool for multi-file exploration (delegates efficiently)

</required>

### Semantic Chunking

**Principle**: Break context into meaningful logical units

**Code analysis chunking**:
1. **Imports/Dependencies** (understand external requirements)
2. **Type Definitions** (understand data structures)
3. **Core Logic** (understand implementation)
4. **Tests** (understand expected behavior)

**Example workflow**:
```markdown
User: "Fix the user registration bug"

Agent workflow:
1. Grep for "register" in user-related files → Find auth/register.ts:45
2. Read auth/register.ts (focus on register function + types)
3. Read tests/auth/register.test.ts (understand expected behavior)
4. Read only imported dependencies if needed
5. Implement fix with minimal context loading
```

### Compression Techniques

**Template reuse**:
```text
Verbose:
Agent: "I'm going to read the file to understand its contents, then I'll analyze
the structure, and after that I'll make the necessary changes..."

Concise:
Agent: *reads file* *makes edit* "Updated validation logic in auth/middleware.ts:67"
```

**Reference-based communication**:
```text
Good: Use file:line format: "Fixed in auth.ts:123"
Good: Use commit refs: "Addresses issue from commit a3b4c5d"
Good: Use relative paths: "Updated ../config/database.ts"
Bad: Full path repetition: "/Users/name/project/src/auth/middleware.ts"
```

<forbidden>

- NEVER load full files when targeted reads suffice
- NEVER read documentation when metadata answers the question
- NEVER repeat user's question in responses
- NEVER provide unnecessary explanations for straightforward changes

</forbidden>

<related>

- **Agent behavior**: @steering.md (Constitutional AI, exploration patterns)
- **Context management**: @context.md (platform-specific strategies)
- **XML tags**: @xml.md (approved XML tags for prompts)
- **Research**: Anthropic Prompt Caching Guide, Microsoft LLMLingua

</related>
