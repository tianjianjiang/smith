# Development Workflow Standards

This document defines development workflow standards and code quality requirements.

## Code Quality (MANDATORY)

<required>

- MUST run formatters and linters before commits
- MUST run tests before commits
- MUST fix all linting errors

</required>

**Python projects:**
```sh
# Use virtual env runner (poetry run or uv run)
poetry run ruff check --fix && poetry run ruff format
poetry run pytest
```

**Frontend projects:**
```sh
pnpm lint:fix && pnpm test
```

**Note**: Ruff enforces PEP8 automatically - no need for separate PEP8 checks.

**For Python-specific patterns**: See [Python Standards]($HOME/.smith/rules-python.md)

## Agent-Assisted Development

**Context**: Working with Claude Code or AI pair programming tools

### Exploration Workflow

**Pattern**: Read → Ask → Propose → Review → Implement

<required>

- Agent MUST read relevant files before proposing changes
- Agent MUST use Task tool with subagent_type=Explore for codebase discovery
- Agent MUST clarify ambiguities before implementation
- Agent MUST explain trade-offs when multiple approaches exist

</required>

**Example workflow**:
```markdown
User: "Add caching to the API"

Agent exploration:
1. Uses Task(subagent_type=Explore) to find existing caching patterns
2. Reads configuration files and caching implementations
3. Asks: "Found Redis (user-service) and in-memory (session-service) patterns. Which should we use?"
4. Proposes approach with trade-offs
5. Implements after approval
```

### Debugging Workflow

**Pattern**: Reproduce → Analyze → Hypothesize → Test → Verify

<required>

- Agent MUST reproduce the issue before proposing fixes
- Agent MUST analyze logs and error messages
- Agent MUST read relevant code sections (not entire files)
- Agent MUST propose hypothesis with supporting evidence
- Agent MUST verify fix with tests

</required>

**Example workflow**:
```markdown
User: "Fix authentication timeout bug"

Agent debugging:
1. Reads error logs and stack traces
2. Uses Grep to locate timeout configuration
3. Reads auth/middleware.ts focusing on timeout logic
4. Hypothesizes: "Token validation making synchronous DB call (auth.ts:67)"
5. Proposes: "Cache token validation results (5min TTL)"
6. Implements fix + test
7. Verifies timeout no longer occurs
```

### CLAUDE.md Optimization for Prompt Caching

**Location**: Project root `.claude/CLAUDE.md` or `CLAUDE.md`

**Structure** (cache-friendly):
```markdown
<!-- Section 1: Project metadata (STATIC - cached) -->
Project: [name]
Tech stack: [primary technologies]
Standards: See $HOME/.smith/rules-*.md

<!-- Section 2: Architecture overview (STATIC - cached) -->
Architecture: [brief system design]
Key patterns: [established conventions]

<!-- CACHE BREAKPOINT (~1024 tokens) -->

<!-- Section 3: Current work context (DYNAMIC - not cached) -->
Active tasks: [current sprint/focus areas]
Recent changes: [last few commits]
```

**Optimization principle**: Keep first ~1024 tokens static for 90% cache hit rate

**See**: `$HOME/.smith/rules-ai_agents.md` - Complete agent interaction standards

## Pre-PR Quality Gates

<required>

Before creating a pull request:

- MUST run all formatters: `poetry run ruff format .`
- MUST run all linters: `poetry run ruff check --fix .`
- MUST run all tests: `poetry run pytest`
- MUST ensure branch is up-to-date with base branch
- MUST review your own changes first (`git diff`)

</required>

**See**: `$HOME/.smith/rules-pr.md` - Pull request creation workflow
**See**: `$HOME/.smith/rules-github.md` - GitHub-specific PR commands

## Package Management

**Python:**
- Use package manager for dependency management (Poetry or uv)
- Local `.venv` directories (project-local virtual environments)
- Lock files: `poetry.lock` or `uv.lock` (commit to version control)

**Frontend:**
- Use pnpm for dependency management
- Lock files: `pnpm-lock.yaml` (commit to version control)

## Script Organization

### Directory Structure

**Temporary analysis**: `debug_scripts/`
- Quick explorations and debugging
- NOT committed to production
- Output files in `debug_scripts/outputs/`

**Production tools**: `cli/` or `cli/prompt_engineering/`
- Version-controlled utilities
- Team-accessible tools
- Production-ready quality

### Script Migration

**Migrate from debug_scripts/ → cli/ when:**
- Used by multiple team members
- Has general applicability beyond debugging
- Provides reusable functionality
- Requires version control

**Migration process:**
1. Copy to `cli/` with enhanced functionality
2. Update documentation references
3. Remove from `debug_scripts/` after validation
4. Update tool documentation
5. Inform team

### Output Organization

**Directory**: `debug_scripts/outputs/`
**Structure**: Categorized folders
- `document_analysis/`
- `symbol_tests/`
- `query_tests/`
- `performance_analysis/`

**Naming**: `[script_purpose]_[identifier]_[timestamp].json`
**Git**: Add `debug_scripts/outputs/` to `.gitignore`

## Logging and Observability

**Logging levels:**
- DEBUG: Only when actively debugging
- WARNING: Default for external libraries (httpx, openai, fastapi)
- INFO: Application-level events

**Configuration:**
- Centralized controls in project documentation
- Test logging: Configure via `pytest.ini` and `pyproject.toml`

## Related Standards

- **Personal Rules**: [Core Standards]($HOME/.smith/rules-core.md)
- **Python Standards**: [Python Rules]($HOME/.smith/rules-python.md)
- **Testing**: [Testing Standards]($HOME/.smith/rules-testing.md)
- **Git Workflow**: [Git Standards]($HOME/.smith/rules-git.md)
- **GitHub PRs**: [GitHub Workflows]($HOME/.smith/rules-github.md)
- **Naming**: [Naming Conventions]($HOME/.smith/rules-naming.md)
