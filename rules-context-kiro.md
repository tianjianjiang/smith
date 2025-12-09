# Kiro Context Management

<metadata>

- **Scope**: Kiro steering file patterns and context management strategies
- **Load if**: Using Kiro OR creating steering files for AI agent guidance
- **Prerequisites**: @rules-context-principles.md, @rules-ai_agents.md
- **Requires**: Understanding of Kiro steering files, context triggers, MCP integration, VS Code extension system
- **Provides**: Steering file creation patterns, persistent context strategies, custom agent specialization, context-efficient workflows
- **Research**: Kiro documentation (2025-12), MCP protocol specification, VS Code OSS architecture

</metadata>

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

<required>

## Steering File Pattern

<context>

**Purpose**: Define project standards and agent behavior that persist across all sessions.

**Kiro steering file** is equivalent to:
- `.cursorrules` in Cursor (project-specific instructions)
- `CLAUDE.md` in Claude Code (persistent configuration)
- But with advanced features: context triggers, file references, dynamic loading

</context>

<required>

### Steering File Structure

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

### Key Sections Explained

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

## File Reference Syntax

<context>

**Purpose**: Include external file contents in agent context dynamically.

**Syntax**: `#[[file:relative/path/to/file.md]]`

**Benefit**: File contents are loaded when steering file is read, keeping content up-to-date without duplication.

</context>

<required>

### File Reference Pattern

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

## Context Triggers for Dynamic Loading

<context>

**Purpose**: Load additional rules files only when relevant context is detected.

**Benefit**: Prevents context bloat by loading only rules needed for current task.
**Pattern**: IF [condition] → LOAD [file]

**Canonical example**: @AGENTS.md defines 18 context triggers.

</context>

<required>

### Creating Effective Context Triggers

**Trigger structure**:

```xml
<trigger context="descriptive_name">

- **IF** [specific conditions that activate this trigger]:
- **LOAD**: `path/to/rules-file.md`
- **LOAD**: `path/to/another-rules.md` (if multiple files needed)
- **ACTION**: [optional action to take when triggered]

</trigger>
```

**Condition patterns**:

```markdown
# Language/framework detection
IF writing/modifying Python code OR running Python tests

# Workflow detection
IF creating commits OR managing branches OR using git

# Tool detection
IF using GitHub CLI OR working with pull requests

# Phase detection
IF testing OR running test suite OR writing tests

# File pattern detection
IF modifying files in src/database/ OR editing migrations
```

**Loading patterns**:

```markdown
# Load single file
LOAD: `rules-python.md`

# Load multiple related files
LOAD: `rules-pr-concepts.md`
LOAD: `rules-github-pr.md`
LOAD: `rules-github.md`

# Load with action
LOAD: `rules-security.md`
ACTION: Run security checks before committing
```

</required>

<examples>

**Well-designed triggers** (from @AGENTS.md):

```xml
<trigger context="python_development">

- **IF** writing/modifying Python code OR running Python tests:
- **LOAD**: @rules-python.md

</trigger>

<trigger context="pull_request_workflows">

- **IF** creating pull requests OR reviewing code OR working with GitHub PRs:
- **LOAD**: @rules-pr-concepts.md
- **LOAD**: @rules-github-pr.md
- **LOAD**: @rules-github.md
- **LOAD**: @rules-naming.md

</trigger>

<trigger context="always_active">

- **IF** any development task (always active):
- **LOAD**: @rules-core.md

</trigger>
```

**Poorly designed triggers**:

```xml
<!-- Too broad - loads for every file -->
<trigger context="any_file">
- IF modifying any file:
- LOAD: all-rules.md
</trigger>

<!-- Circular dependency -->
<trigger context="python">
- IF Python:
- LOAD: rules-python.md (which has trigger to load rules-testing.md which loads rules-python.md)
</trigger>

<!-- Too many files for one trigger -->
<trigger context="web_dev">
- IF web development:
- LOAD: rules-html.md
- LOAD: rules-css.md
- LOAD: rules-javascript.md
- LOAD: rules-typescript.md
- LOAD: rules-react.md
- LOAD: rules-vue.md
[...20 more files...]
Result: Context bloat, defeats purpose of triggers
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

</examples>

## Location Hierarchy

<context>

**Kiro checks for steering files in this order** (first found wins):

1. **Project-specific**: `.kiro/steering/` in workspace root (highest priority)
2. **User-global**: `~/.kiro/steering/` (applies to all projects)
3. **Fallback**: Check for `AGENTS.md` in workspace root (compatibility)

**Best practice**: Use `AGENTS.md` in workspace root (like smith project does) for maximum compatibility and simplicity.

</context>

<required>

### Steering File Placement Strategy

**For personal projects**:
```
~/personal-project/
└── AGENTS.md                    # Project standards
```

**For team projects**:
```
~/team-project/
├── AGENTS.md                    # Team standards (version controlled)
└── .kiro/
    └── steering/
        └── personal-overrides.md # Personal preferences (gitignored)
```

**For global standards**:
```
~/.kiro/
└── steering/
    └── global.md                # Applies to all projects
```

**Reference pattern** (project → global):

```markdown
# Project AGENTS.md

Follow global standards: #[[file:~/.kiro/steering/global.md]]

## Project-Specific Additions

- Use NestJS framework
- PostgreSQL database
- Prisma ORM
```

</required>

<examples>

**Good hierarchy usage**:

```
~/.kiro/steering/global.md:
  - Universal rules (DRY, KISS, YAGNI)
  - Language-agnostic best practices
  - Security guidelines

~/project/AGENTS.md:
  - References global.md
  - Adds project tech stack
  - Defines project structure
  - Loads context-triggered rules
```

</examples>

## Custom Agents for Context Specialization

<context>

**Purpose**: Create specialized agents with focused context windows for specific tasks.

**Benefit**:
- Smaller context windows (faster responses, lower cost)
- Task-specific context (no irrelevant information)
- Parallel workflows (different agents for different tasks)

**Configuration**: `.kiro/agents/` directory

</context>

<required>

### Agent Specialization Patterns

**Code Review Agent**:

```markdown
# .kiro/agents/code-review.md

<metadata>
- Role: Code reviewer
- Context window: 50K tokens (focused)
- Excludes: Implementation details, build config
</metadata>

<required>

## Review Focus

- Code quality and maintainability
- Security vulnerabilities
- Performance issues
- Test coverage
- Documentation completeness

## Review Guidelines

- Check for SOLID violations
- Verify error handling
- Ensure proper logging
- Validate input sanitization

</required>

<context>

<plan_tool_usage>

<rules>

**security_review:**
- Condition: Reviewing authentication/authorization code
- Load: rules-security.md

</rules>

</plan_tool_usage>

</context>
```

**Implementation Agent**:

```markdown
# .kiro/agents/implementation.md

<metadata>
- Role: Feature implementation
- Context window: 100K tokens (comprehensive)
- Includes: Architecture docs, related code, tests
</metadata>

<required>

## Implementation Workflow

1. Read architecture documentation
2. Review related existing code
3. Write failing tests (TDD)
4. Implement to pass tests
5. Refactor while keeping tests green
6. Update documentation

</required>

<context>

<plan_tool_usage>

<rules>

**feature_implementation:**
- Load: docs/architecture.md
- Load: rules-testing.md
- Load: rules-development.md

</rules>

</plan_tool_usage>

</context>
```

**Documentation Agent**:

```markdown
# .kiro/agents/documentation.md

<metadata>
- Role: Documentation writer
- Context window: 30K tokens (minimal)
- Excludes: Implementation internals
</metadata>

<required>

## Documentation Standards

- Use Markdown format
- Include code examples
- Provide runnable samples
- Keep examples up-to-date

</required>
```

**Benefits of specialization**:

| Aspect | Generalist Agent | Specialized Agents |
|--------|------------------|-------------------|
| Context window | 200K (all purposes) | 30-100K (focused) |
| Response time | Slower (more context) | Faster (less context) |
| Relevance | Mixed signals | Highly focused |
| Cost | Higher (large context) | Lower (small context) |
| Parallel work | One task at a time | Multiple agents in parallel |

</required>

<examples>

**Using specialized agents**:

```text
Task: Implement feature + review + document

Sequential (one agent):
1. Implement feature (context: 80K)
2. Review own code (context: 120K - includes implementation exploration)
3. Write docs (context: 150K - includes implementation + review)
Total time: 30 minutes
Context usage: High (accumulated)

Parallel (specialized agents):
1. Implementation agent: Implements feature (context: 60K)
2. Review agent: Reviews code (context: 40K, fresh perspective)
3. Documentation agent: Writes docs (context: 25K, clean)
Total time: 12 minutes (agents work concurrently)
Context usage: Low (each agent has minimal focused context)
```

</examples>

## MCP Integration for Context Efficiency

<context>

**MCP (Model Context Protocol)**: Protocol for extending AI agent capabilities with external tools.

**Kiro configuration**: `.kiro/settings/mcp.json` (workspace) or `~/.kiro/settings/mcp.json` (global)

**Relevance to context management**: MCP tools reduce context usage by delegating operations to specialized servers.

</context>

<required>

### MCP Configuration for Context Optimization

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

## Persistent Context Across Sessions

<context>

**Kiro capability**: Maintains context across sessions using steering files and project memory.

**Strategy**: Combine steering files (persistent knowledge) with commit messages (session progress) for seamless session continuity.

</context>

<required>

### Session Continuity Pattern

**Session 1**:
1. Work on feature
2. Update steering file with new decisions/patterns
3. Commit progress with detailed messages
4. Update file references (`#[[file:...]]`) to reflect current state

**Session 2** (next day):
1. Agent reads steering file (persistent project knowledge)
2. Agent reviews recent commits (`git log -5`)
3. Agent continues from documented state

**Steering file updates during session**:

```markdown
# Project AGENTS.md

<context>

## Recent Decisions

- 2025-12-10: Adopted JWT with 7-day refresh for auth (see commit a3b4c5d)
- 2025-12-09: Migrated to Prisma ORM (see migration guide at docs/prisma-migration.md)

</context>

<context>

<plan_tool_usage>

<rules>

**authentication:**
- Condition: Working with authentication
- Load: rules-auth.md
- NOTE: Using JWT pattern from auth.service.ts:100-150

</rules>

</plan_tool_usage>

</context>
```

**Commit messages as persistent memory**:

```bash
git commit -m "feat(auth): implement JWT refresh token rotation

Implemented 7-day refresh token rotation per OAuth2 RFC 6749.

Technical decisions:
- Store refresh tokens in database (tokens table)
- Automatic rotation on use (one-time refresh tokens)
- Sliding window: extends by 7 days on each refresh
- Invalidation: mark old token as used in database

Implementation:
- Token service: src/auth/tokens.service.ts:89-156
- Database schema: prisma/schema.prisma:45-60
- Tests: tests/auth/tokens.integration.test.ts:234-290

Next steps:
- Add token cleanup job (delete expired tokens)
- Implement rate limiting for refresh endpoint
- Add monitoring for token rotation failures"
```

**Session restoration**:

```text
User: (Next session) "Continue working on authentication"

Agent:
1. Reads AGENTS.md → Sees JWT auth decision
2. Reads git log → Sees refresh token implementation (commit a3b4c5d)
3. Reads commit message → Understands next steps
4. Responds: "I see we implemented JWT refresh tokens. The next steps are:
   - Add token cleanup job
   - Implement rate limiting
   - Add monitoring
   Which would you like me to work on first?"

Result: Seamless continuation without user re-explaining
```

</required>

<examples>

**Good session continuity**:

```text
Session 1 end:
- Updated AGENTS.md with auth decisions
- Committed work with detailed message
- Noted next steps in commit

Session 2 start:
- Agent reads AGENTS.md
- Agent reads recent commits
- Agent proposes continuing from last checkpoint
- No context re-explanation needed
```

**Bad session continuity**:

```text
Session 1 end:
- Didn't update AGENTS.md
- Vague commit message: "wip"
- No documentation of decisions

Session 2 start:
- Agent has no persistent context
- User must re-explain entire feature
- Lost architectural decisions
- Wasted time reconstructing state
```

</examples>

## Steering Files as Context Management Tool

<context>

**Key insight**: Steering files themselves are a context management tool.

**How they manage context**:
- **Static content** (metadata, principles) → Cached, low cost
- **Context triggers** → Load only relevant rules
- **File references** → Dynamic, always current
- **Persistent across sessions** → Don't need to reload each time

</context>

<required>

### Optimizing Steering Files for Context Efficiency

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

## Version Information

<metadata>

- **Kiro Version**: 1.x (as of 2025-12)
- **Last Updated**: 2025-12-10
- **Features Documented**: Steering files, context triggers, file references, custom agents, MCP integration

</metadata>

<note>

Features documented here are current as of the version noted above. Kiro is built on VS Code OSS and may inherit new features from VS Code releases. Consult Kiro changelog for platform updates.

</note>

</context>

<related>

- **Shared principles**: @rules-context-principles.md (universal strategies)
- **Other platforms**: @rules-context-claude_code.md, @rules-context-cursor.md
- **Canonical example**: @AGENTS.md (production steering file demonstrating all patterns)
- **Parent**: @rules-ai_agents.md (AI agent interaction patterns, prompt caching)
- **Foundation**: @rules-core.md (critical NEVER/ALWAYS rules)
- **MCP integration**: @rules-tools-mcp.md (MCP server configuration)
- **Research**: Kiro documentation, VS Code extension API, MCP protocol specification

</related>
