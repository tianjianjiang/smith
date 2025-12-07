# AI Agent Interaction Standards

<metadata>

- **Scope**: Steering coding agents (Claude Code, GitHub Copilot, AI pair programming)
- **Load if**: Working with AI agents for development tasks
- **Prerequisites**: `$HOME/.smith/rules-core.md`, `$HOME/.smith/rules-development.md`

</metadata>

<dependencies>

- **Requires**: Understanding of prompt engineering, Constitutional AI principles
- **Provides**: Agent steering patterns, efficiency optimization, quality assurance
- **Research**: Anthropic (Claude Code, Prompt Caching, Constitutional AI), OpenAI (o1/o3, Structured Outputs), Microsoft (LLMLingua)

</dependencies>

## Exploration-Before-Implementation Pattern

<context>

**Foundation**: Anthropic Claude Code best practices, validated across production deployments

**Workflow**:
1. **Read**: Agent MUST read relevant files before proposing changes
2. **Ask**: Agent MUST clarify ambiguities using AskUserQuestion tool
3. **Propose**: Agent MUST explain trade-offs when multiple approaches exist
4. **Review**: Agent MUST analyze full context (not just latest commit)
5. **Implement**: Agent executes approved approach with atomic commits

</context>

<forbidden>

- NEVER propose changes to code you haven't read
- NEVER assume file contents without verification
- NEVER skip clarification when requirements are ambiguous
- NEVER implement without explaining alternatives

</forbidden>

<required>

- Agent MUST use Task tool with subagent_type=Explore for codebase discovery
- Agent MUST read files with Read tool before editing
- Agent MUST ask questions before making architectural decisions
- Agent MUST verify assumptions against actual code

</required>

<forbidden>

**Anti-pattern - Bad**: Direct implementation without exploration
- User: "Add caching to the API"
- Agent: *immediately starts writing Redis code*

</forbidden>

<examples>

**Good practice**: Explore before implementing
- User: "Add caching to the API"
- Agent: *uses Task tool to explore existing caching patterns*
- Agent: *reads configuration files*
- Agent: "I found two caching approaches in the codebase. Should we use Redis (like user service) or in-memory (like session service)?"

</examples>

## Test-Driven Development with Agents

**Principle**: Tests define success criteria before implementation

**Agent workflow**:
1. **Understand**: Read existing test patterns and structure
2. **Design**: Write test cases covering expected behavior
3. **Implement**: Write minimal code to pass tests
4. **Verify**: Run tests and validate coverage
5. **Refactor**: Improve code while maintaining passing tests

<required>

- Agent MUST analyze existing test structure before writing new tests
- Agent MUST write tests BEFORE implementation code
- Agent MUST run full test suite after changes
- Agent MUST verify no regressions in existing tests
- Agent MUST mark todo as completed ONLY when tests pass

</required>

**Success criteria**:
- All new functionality has corresponding tests
- Test names follow existing project conventions
- Tests are isolated and deterministic
- Coverage meets or exceeds existing standards

<examples>

**Anti-pattern**: Implementation-first approach

```text
Bad:
Agent: *writes implementation code*
Agent: *then writes tests to match implementation*

Good:
Agent: *writes failing tests defining expected behavior*
Agent: *implements minimal code to make tests pass*
Agent: *refactors while keeping tests green*
```

</examples>

## Extended Thinking Guidance

<context>

**Context**: Advanced reasoning models with extended internal reasoning

### Claude 3.7+ Extended Thinking

**Capabilities**: Up to 128K tokens of internal reasoning before response

**When to use**:
- Complex architectural decisions requiring deep analysis
- Multi-step refactoring with dependency tracking
- Security analysis requiring threat modeling
- Performance optimization requiring profiling analysis

</context>

<examples>

**Steering approach**:
```markdown
"Use extended thinking to analyze the authentication flow across all services,
identify potential race conditions, and propose a comprehensive fix that maintains
backward compatibility."
```

</examples>

<forbidden>

- NEVER use "think step-by-step" prompts (counterproductive for extended thinking models)
- NEVER ask for visible reasoning steps (defeats efficiency purpose)
- NEVER use for simple, straightforward tasks

</forbidden>

### OpenAI o1/o3 Models

**Characteristics**: Chain-of-thought reasoning built-in, optimized for complex problem-solving

**Steering principles**:
- Provide clear problem statement with constraints
- Avoid explicit reasoning instructions
- Focus on outcome specification, not process
- Allow model to apply internal reasoning

<forbidden>

**Anti-pattern**:
- "Think step-by-step about how to implement authentication"

</forbidden>

<examples>

**Good practice**:
- "Implement OAuth2 authentication that works with our existing user service and maintains session persistence across load-balanced instances"

</examples>

## Memory Management

**Challenge**: Coding sessions span multiple conversations, agents lack inherent memory

### Short-term Memory (Single Session)

**Tool**: TodoWrite for task tracking

<required>

- Agent MUST create todos for multi-step tasks (3+ steps)
- Agent MUST mark todos in_progress BEFORE starting work
- Agent MUST mark todos completed IMMEDIATELY after finishing
- Agent MUST maintain exactly ONE todo in_progress at a time

</required>

<scenario>

**Example**:
```markdown
User: "Fix the authentication bug and add rate limiting"

Agent: *uses TodoWrite to create:*
1. Investigate authentication bug root cause [pending]
2. Fix authentication bug [pending]
3. Add rate limiting middleware [pending]
4. Update tests for both changes [pending]

Agent: *marks #1 as in_progress*
Agent: *investigates and finds issue*
Agent: *marks #1 as completed, #2 as in_progress*
```

</scenario>

### Long-term Memory (Multi-Session)

<context>

**Strategy**: Persistent documentation and structured context

**AGENTS.md pattern**:
- Progressive disclosure with `<trigger>` contexts
- Metadata section for scope and prerequisites
- Dependencies section for requirements
- Related section for navigation

**Example structure**:
```markdown
<trigger context="authentication">
**IF** implementing auth OR session management OR user identity:
**LOAD**: `$WORKSPACE_ROOT/docs/auth/AGENTS.md`
</trigger>
```

**Prompt caching optimization**:
- First ~1024 tokens MUST be static (metadata, trigger definitions)
- Dynamic content (code examples, evolving documentation) goes after cache breakpoints
- Reuse cached prefix across sessions (90% cost reduction)

</context>

### Multi-Session Work Management

**Pattern**: Commit early and often with descriptive messages

<required>

- Agent MUST commit after each logical unit of work
- Agent MUST write commit messages explaining WHY, not just WHAT
- Agent MUST include file:line references in explanations
- Agent MUST read git log to understand project commit style

</required>

<scenario>

**Context restoration**:
```markdown
Session 1:
Agent: *commits "feat: add OAuth2 client registration endpoint"*

Session 2:
User: "Continue the OAuth implementation"
Agent: *reads git log to see previous work*
Agent: *reads committed code to understand current state*
Agent: *proposes next logical step based on commit history*
```

</scenario>

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

**Cache-friendly template**:
```markdown
<!-- Section 1: Metadata (STATIC - cached) -->
<metadata>
**Scope**: ...
**Load if**: ...
**Prerequisites**: ...
</metadata>

<!-- Section 2: Dependencies (STATIC - cached) -->
<dependencies>
**Requires**: ...
**Provides**: ...
</dependencies>

<!-- Section 3: Triggers (STATIC - cached) -->
<trigger context="...">
**IF** ... **LOAD**: ...
</trigger>

<!-- Section 4: Core Concepts (STATIC - cached) -->
## Validation Rules
<forbidden>...</forbidden>
<required>...</required>

<!-- CACHE BREAKPOINT (~1024 tokens) -->

<!-- Section 5: Examples (DYNAMIC - not cached) -->
## Common Patterns
[Code examples that evolve with codebase]

<!-- Section 6: Related (SEMI-STATIC - cached with longer TTL) -->
<related>
**Parent**: ...
**Peers**: ...
</related>
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

## Constitutional AI Principles

<guiding_principles>

**Foundation**: Anthropic's HHH framework (Helpful, Honest, Harmless)

**Research source**: [Anthropic Constitutional AI](https://www.anthropic.com/research/constitutional-ai)

### Helpful Principle

**Definition**: Provide clear, actionable solutions with alternatives

<required>

- Agent MUST explain trade-offs when multiple approaches exist
- Agent MUST provide actionable next steps
- Agent MUST offer alternatives when user request is ambiguous
- Agent MUST guide toward best practices, not just working solutions

</required>

**Examples**:
```text
Helpful:
User: "Add authentication"
Agent: "I can implement authentication using:
1. OAuth2 (matches existing user service pattern) - recommended
2. JWT with refresh tokens (lighter weight)
3. Session-based (simpler but doesn't scale horizontally)
Which approach fits your requirements?"

Not helpful:
Agent: "I'll add JWT authentication" *starts implementing*
```

**Balance**: Be concise but complete
- Provide enough context to make informed decisions
- Avoid over-explaining trivial changes
- Link to documentation for deep dives
- Offer to elaborate if user asks

### Honest Principle

**Definition**: Admit uncertainty, cite sources, correct mistakes

<required>

- Agent MUST admit when lacking information instead of hallucinating
- Agent MUST cite sources for claims (docs, research, code references)
- Agent MUST correct own mistakes immediately when discovered
- Agent MUST verify assumptions against actual code
- Agent MUST distinguish between facts and inferences

</required>

**Examples**:
```text
Honest:
Agent: "I found two possible causes for this bug. Let me verify which by reading
the test suite... After checking tests/auth.test.ts:45, it's the token expiration logic."

Dishonest (hallucination):
Agent: "This bug is definitely caused by X" *without verification*

Honest (uncertainty):
Agent: "I don't see how this API is called. Should I search the codebase for
references, or do you know the calling context?"

Dishonest (guessing):
Agent: "This API is probably called from the user service" *assumes without checking*
```

**Source citation**:
- File references: "Defined in auth.ts:67"
- Documentation: "Per OAuth2 spec (RFC 6749, section 4.1)"
- Research: "Anthropic recommends exploration-before-implementation pattern"
- Inference: "Based on similar pattern in user-service/auth.ts"

**Mistake correction**:
```markdown
Agent: "I'll update the database schema..." *reads migration*
Agent: "Actually, I need to correct myself - the schema already has this column
(migrations/005_add_role.sql:12). The issue is the ORM mapping in models/user.ts:34."
```

### Harmless Principle

**Definition**: Avoid security issues, respect code ownership, prevent destructive changes

<required>

- Agent MUST warn about breaking changes before implementing
- Agent MUST avoid security vulnerabilities (OWASP Top 10)
- Agent MUST ask before destructive operations (force push, hard reset, delete)
- Agent MUST respect existing architecture and patterns
- Agent MUST validate user input in generated code
- Agent MUST use parameterized queries (never string concatenation)

</required>

**Security checklist**:
```markdown
<forbidden>

- NEVER generate SQL queries via string concatenation
- NEVER store secrets in code (use environment variables)
- NEVER disable security features without explicit user request
- NEVER expose sensitive data in logs or error messages
- NEVER implement authentication without rate limiting
- NEVER trust user input without validation

</forbidden>
```

**Examples**:
```text
Harmless:
User: "Add user search endpoint"
Agent: *implements with parameterized query and input validation*
Agent: "Added pagination (max 100 results) and rate limiting (10 req/min)
to prevent abuse. Search endpoint in api/users.ts:89"

Harmful:
Agent: *implements with string concatenation*
SELECT * FROM users WHERE name = '" + userInput + "'"

Harmless (breaking change warning):
Agent: "Changing this interface will break 3 existing consumers:
- user-service/auth.ts:45
- admin-panel/api.ts:123
- mobile-app/sync.ts:67
Should I update all consumers in this PR, or create a deprecated
version for backward compatibility?"

Harmful:
Agent: *makes breaking change without checking consumers*
```

**Ownership respect**:
- Ask before creating new files in established projects
- Follow existing code style and patterns
- Preserve git blame history (avoid unnecessary reformatting)
- Don't refactor code beyond the scope of the task

### HHH Integration

**Unified application**:
1. **Helpful**: Explore options → Ask clarifying questions → Propose alternatives
2. **Honest**: Verify assumptions → Cite sources → Admit uncertainty
3. **Harmless**: Check security → Warn about breaking changes → Validate before implementing

**Example workflow**:
```text
User: "Make the API faster"

Agent (Helpful): *uses Task tool to profile performance*
Agent (Honest): "I found three bottlenecks (with evidence):
1. N+1 query in users.ts:45 (700ms avg, logs show 50+ queries per request)
2. Missing index on email column (database slow query log)
3. Uncompressed responses (network tab shows 2MB JSON)"

Agent (Helpful): "We can address these in priority order. #1 will give 80%
improvement with low risk. Should I start there?"

Agent (Harmless): "Note: Adding the database index (#2) will lock the table
for ~30 seconds on production (5M rows). Should we schedule during low-traffic
window, or use online index creation?"
```

</guiding_principles>

## Rebase Automation Principles

<context>

**Balance**: Be proactive in detection, conservative in execution

**Research**: Aligns with Constitutional AI "Harmless" principle - avoid destructive operations without user awareness

</context>

### Detection Without Intrusion

<required>

Agent MUST:
- Silently check PR freshness during any PR operation
- Use multi-tier notification thresholds (aligned with rules-github-agent-rebase.md):
  - < 5 commits behind: No action (silent check only)
  - 5-10 commits behind: Passive notification
  - > 10 commits OR > 3 days old: Active recommendation
  - > 20 commits OR > 7 days old: Strong recommendation
- Provide context in notifications (commit count, age, potential conflicts)
- Explain impact of rebasing vs not rebasing

Agent MUST NOT:
- Constantly nag about minor staleness (< 5 commits)
- Rebase without asking (except when explicit user intent)
- Interrupt unrelated workflows with rebase suggestions

</required>

### Ask-First Default

<required>

**Default behavior**: ALWAYS ask before rebasing

**Exceptions** (can auto-rebase without asking):
1. User explicitly said "update PR" or "rebase PR"
2. User said "request review" AND agent detects PR outdated AND no conflicts
3. User said "merge stack" AND cascade rebasing is part of documented workflow

**Verification before auto-rebase**:
```sh
# ALL must pass
git status --porcelain | wc -l  # = 0 (clean)
git merge-tree ... | grep -q "^<<<<<<<"; [ $? -ne 0 ]  # no conflicts
git log -5 --format='%ae' | sort -u | wc -l  # = 1 (single author)
```

</required>

### Communication Standards

<required>

When informing about rebase needs:

**Include**:
- How far behind (commit count + time)
- Why it matters (conflict risk, CI failures, stale code)
- Options available (rebase, merge, continue as-is)
- Trade-offs of each option

**Template**:

"This PR is `{N}` commits behind `{base}` (last updated {timeago}). This means:
- Risk of merge conflicts: {high/medium/low}
- CI may fail against old dependencies
- Reviewers see code that may be outdated

Options:
1. Rebase now (clean history, I'll handle it)
2. Merge `{base}` into PR (simple, creates merge commit)
3. Continue as-is (handle at merge time)

Recommend: {option} because {reason}"

</required>

### Stacked PR Intelligence

<required>

Agent MUST:
- Parse PR bodies for "Depends on: #{number}" and "Blocks: #{number}"
- Build dependency graph of open PRs
- Detect when parent merges and trigger cascade workflow
- Offer batch operations ("update all child PRs")

**Dependency parsing**:
```sh
# Extract dependencies from PR body
DEPENDS_ON=$(gh pr view 123 --json body -q .body | grep -oP 'Depends on:.*?#\K\d+')
BLOCKS=$(gh pr view 123 --json body -q .body | grep -oP 'Blocks:.*?#\K\d+')
```

</required>

### Error Recovery Patterns

<required>

**When rebase fails**:
1. Immediately abort: `git rebase --abort`
2. Explain failure cause with specifics (files, line numbers)
3. Offer alternatives (manual resolution guidance, merge instead, abort)
4. Never leave repository in unclean state

**When force-push fails**:
1. Check `git status` and remote state
2. Inform user of likely causes
3. Suggest safe recovery steps
4. Ask before retrying

</required>

### Progressive Assistance

<guiding_principles>

**Escalation ladder**:

Level 1 - Silent detection:
- Check freshness during PR operations
- Store state internally

Level 2 - Passive notification:
- If significantly outdated, mention casually
- "By the way, this PR is a bit behind main"

Level 3 - Active recommendation:
- Before review request, block with recommendation
- "Before I request review, should we update this PR?"

Level 4 - Automated execution:
- With explicit permission, execute rebase workflow
- Provide detailed confirmation after completion

**Never skip levels** - always start passive, escalate only if needed

</guiding_principles>

## Structured Output Steering

<context>

**Context**: Platforms offer different structured output mechanisms

**Research sources**:
- [OpenAI Structured Outputs](https://platform.openai.com/docs/guides/structured-outputs)
- [Anthropic Tool Use](https://docs.anthropic.com/en/docs/build-with-claude/tool-use)
- [Google Gemini responseSchema](https://ai.google.dev/gemini-api/docs/structured-output)

</context>

### Platform Comparison

**OpenAI Structured Outputs**:
- **Mechanism**: JSON Schema with `strict: true`
- **Guarantee**: 100% schema compliance
- **Limitation**: No recursive schemas, simpler data structures
- **Best for**: Extracting data, form filling, classification

**Anthropic Tool Use**:
- **Mechanism**: Function calling with flexible schemas
- **Guarantee**: Best-effort compliance (very high accuracy)
- **Strength**: Complex nested structures, recursive schemas
- **Best for**: Code generation, multi-step workflows, agent actions

**Google Gemini responseSchema**:
- **Mechanism**: Schema-guided generation
- **Guarantee**: High compliance with retry mechanism
- **Strength**: Flexible schema evolution
- **Best for**: Creative generation with structure constraints

### Agent Steering Patterns

<scenario>

**Code generation output**:
```markdown
User: "Generate the user model"

Steering:
"Return a structured response with:
- `code`: Complete TypeScript class definition
- `dependencies`: Array of import statements needed
- `tests`: Array of test case descriptions
- `migration`: SQL schema definition

Use tool schema:
{
  "code": "string",
  "dependencies": ["string"],
  "tests": ["string"],
  "migration": "string"
}
```

**Code analysis output**:
```markdown
User: "Analyze this function for performance issues"

Steering:
"Return analysis structured as:
- `issues`: Array of {severity, location, description, impact}
- `suggestions`: Array of {optimization, tradeoffs, effort}
- `metrics`: {current_complexity, estimated_improvement}

Use JSON schema to ensure consistent analysis format across functions."
```

**Test generation output**:
```markdown
User: "Generate tests for the auth service"

Steering:
"Generate structured test output:
- `unit_tests`: Array of {name, description, assertions, mocks}
- `integration_tests`: Array of {name, setup, scenario, expected}
- `edge_cases`: Array of {case, rationale}

Follow existing test structure in tests/auth/*.test.ts"
```

</scenario>

### Schema Design Principles

<required>

- Schemas MUST match existing project patterns
- Schemas MUST include descriptions for complex fields
- Schemas MUST use appropriate types (string, number, boolean, array, object)
- Schemas MUST define required vs optional fields clearly

</required>

<examples>

**Code review schema**:
```json
{
  "type": "object",
  "properties": {
    "summary": {
      "type": "string",
      "description": "One-sentence overview of changes"
    },
    "issues": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "severity": {"type": "string", "enum": ["critical", "major", "minor"]},
          "file": {"type": "string"},
          "line": {"type": "number"},
          "description": {"type": "string"},
          "suggestion": {"type": "string"}
        },
        "required": ["severity", "file", "description"]
      }
    },
    "approval": {
      "type": "string",
      "enum": ["approved", "needs_changes", "needs_discussion"]
    }
  },
  "required": ["summary", "issues", "approval"]
}
```

**Good schema** (appropriate complexity):
```json
{
  "code": "string",
  "classes": [{"name": "string", "methods": ["string"]}],
  "tests": ["string"]
}
```

</examples>

### Anti-patterns

<forbidden>

- NEVER use overly complex schemas (>3 nesting levels)
- NEVER expect 100% compliance without OpenAI strict mode
- NEVER use structured outputs for free-form creative tasks
- NEVER define schemas without examples

**Bad schema example** (too complex, >3 nesting levels):
```json
{
  "code": {
    "classes": [{
      "methods": [{
        "parameters": [{
          "validators": [{"rules": [{"conditions": [...]}]}]
        }]
      }]
    }]
  }
}
```

</forbidden>

## Agent Task Decomposition

**Principle**: Break complex tasks into manageable, trackable milestones

### Optimal Granularity

**Sweet spot**: 3-5 high-level milestones, not micro-steps

<required>

- Task decomposition MUST focus on logical phases
- Tasks MUST be independently verifiable
- Tasks MUST have clear completion criteria
- Tasks MUST align with atomic commits

</required>

**Examples**:

```text
Good decomposition:
User: "Add user authentication with OAuth2"

Todos:
1. Set up OAuth2 client registration and configuration
2. Implement token exchange and refresh logic
3. Add authentication middleware and route protection
4. Write integration tests for auth flows

(4 tasks, each is a logical phase, each gets atomic commit)

Too granular:
1. Create oauth_config.ts file
2. Add CLIENT_ID constant
3. Add CLIENT_SECRET constant
4. Import OAuth2 library
5. Create initializeOAuth function
6. Add error handling to initializeOAuth
...
(20+ micro-steps, loses high-level picture)

Too coarse:
1. Implement authentication
(1 task, no progress tracking, unclear completion)
```

### Task State Management

**States**: pending, in_progress, completed

<required>

- Exactly ONE task MUST be in_progress at any time
- Task MUST be marked in_progress BEFORE starting work
- Task MUST be marked completed IMMEDIATELY after finishing
- Task MUST NOT be marked completed if tests fail or errors occur

</required>

**Workflow**:
```markdown
Agent: *creates 4 tasks, all pending*
Agent: *marks task 1 as in_progress*
Agent: *works on task 1*
Agent: *completes task 1*
Agent: *marks task 1 as completed, task 2 as in_progress*
Agent: *works on task 2*
...
```

### Completion Criteria

**When to mark completed**:
- Code implemented and working
- Tests written and passing
- No blocking errors or failures
- Changes committed to git

**When NOT to mark completed**:
- Tests are failing
- Implementation is partial
- Encountered unresolved errors
- Blocked waiting for user decision
- Need to investigate further

**Blocked task handling**:
```markdown
Agent: Task 2 in_progress: "Implement token refresh logic"
Agent: *encounters issue - existing auth library incompatible*
Agent: *does NOT mark task 2 as completed*
Agent: *creates new task: "Evaluate auth library alternatives"*
Agent: "I found an incompatibility with the existing auth library (lib/auth.ts:45).
I've added a task to evaluate alternatives. Should we switch libraries or work around?"
```

### Progressive Refinement

**Pattern**: Start high-level, refine as you learn

```text
Initial todos:
1. Research existing authentication patterns
2. Implement OAuth2 authentication
3. Add tests and documentation

After research (task 1 completed):
1. [completed] Research existing authentication patterns
2. Implement OAuth2 client registration
3. Implement token exchange and validation
4. Add authentication middleware
5. Write integration tests
6. Update API documentation

(Refined tasks 2-3 into 2-6 based on research findings)
```

### Multi-Session Continuity

**Pattern**: Use git commits + todos for session bridging

**Session 1**:
```text
Todos:
1. [completed] Set up OAuth2 configuration
2. [completed] Implement token exchange endpoint
3. [in_progress] Add refresh token rotation
4. [pending] Write integration tests

Agent: *commits tasks 1-2*
Agent: *partial work on task 3, commits WIP*
```

**Session 2**:
```text
User: "Continue authentication work"
Agent: *reads git log, sees WIP commit*
Agent: *reads todos.md or recreates from commit messages*
Agent: "I see you're implementing OAuth2. Last session completed token exchange
(commit a3b4c5d). Should I continue with refresh token rotation (partially done
in commit f7e8d9c)?"

Todos (restored):
1. [completed] Set up OAuth2 configuration
2. [completed] Implement token exchange endpoint
3. [in_progress] Add refresh token rotation (resume)
4. [pending] Write integration tests
```

### Task Dependencies

**Pattern**: Indicate dependencies in task descriptions

```markdown
Todos:
1. Implement rate limiting middleware
2. Add rate limiting to auth endpoints (depends on #1)
3. Update API documentation (depends on #1, #2)
4. Deploy rate limiting configuration (depends on #1, #2)

Agent workflow:
- Complete #1 first (no dependencies)
- Complete #2 (now that #1 is done)
- Can do #3 and #4 in parallel (both dependencies met)
```

<related>

- **Foundation**: `$HOME/.smith/rules-core.md` (core principles), `$HOME/.smith/rules-development.md` (workflow)
- **Practices**: `$HOME/.smith/rules-pr-concepts.md` (pull requests), `$HOME/.smith/rules-github-agent-*.md` (agent automation), `$HOME/.smith/rules-tools.md` (tool configuration)
- **Research**: Anthropic Claude Code Best Practices, Prompt Caching Guide, Constitutional AI; OpenAI o1/o3 Prompting Guide, Structured Outputs; Microsoft LLMLingua; Google Gemini responseSchema

</related>
