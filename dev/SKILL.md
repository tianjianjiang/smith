---
name: dev
description: Development workflow standards and code quality requirements. Use when initializing projects, running quality checks, or managing agent tasks. Covers pre-commit checks, task decomposition, and script organization patterns.
---

# Development Workflow Standards

<metadata>

- **Scope**: Development workflow standards and code quality requirements
- **Load if**: Initializing a new project
- **Prerequisites**: @principles/SKILL.md, @standards/SKILL.md

</metadata>

<context>

This document defines development workflow standards and code quality requirements.

</context>

## CRITICAL (Primacy Zone)

<forbidden>

- Committing without running formatters and linters
- Committing without running tests
- Creating PRs with failing quality checks
- Having more than ONE task in_progress simultaneously

</forbidden>

## Code Quality (MANDATORY)

<required>

- MUST run formatters and linters before commits
- MUST run tests before commits
- MUST fix all linting errors

</required>

**Python projects:**
```sh
poetry run ruff check --fix && poetry run ruff format
poetry run pytest
```

**Frontend projects:**
```sh
pnpm lint:fix && pnpm test
```

**Note**: Ruff enforces PEP8 automatically - no need for separate PEP8 checks.

**For Python-specific patterns**: See @python/SKILL.md

## Agent-Assisted Development

**For AI agent workflows**: See @guidance/SKILL.md for comprehensive patterns:
- Exploration workflow (Read → Ask → Propose → Review → Implement)
- Debugging workflow (Reproduce → Analyze → Hypothesize → Test → Verify)
- AGENTS.md optimization for prompt caching
- Constitutional AI principles (HHH framework)

## Agent Task Decomposition

**Sweet spot**: 3-5 high-level milestones, not micro-steps

<required>

- Tasks MUST focus on logical phases, be independently verifiable
- Exactly ONE task in_progress at any time
- Mark complete only after tests pass and changes committed
- Use git commits + todos for session bridging

</required>

**Task states**: pending → in_progress → completed

**Dependencies**: Note in task description (e.g., "depends on #1")

## Pre-PR Quality Gates

<required>

Before creating a pull request:

- MUST run all formatters: `poetry run ruff format .`
- MUST run all linters: `poetry run ruff check --fix .`
- MUST run all tests: `poetry run pytest`
- MUST ensure branch is up-to-date with base branch
- MUST review your own changes first (`git diff`)

</required>

**See**: @gh-pr/SKILL.md - Pull request creation workflow
**See**: @gh-cli/SKILL.md - GitHub-specific PR commands

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

**Directory**: `debug_scripts/outputs/` (add to `.gitignore`)
**Naming**: `[purpose]_[id]_[timestamp].json`

## Logging and Observability

**Logging levels:**
- DEBUG: Only when actively debugging
- WARNING: Default for external libraries (httpx, openai, fastapi)
- INFO: Application-level events

**Configuration:**
- Centralized controls in project documentation
- Test logging: Configure via `pytest.ini` and `pyproject.toml`

<related>

- `@principles/SKILL.md` - Fundamental coding principles
- `@standards/SKILL.md` - Universal code standards
- `@python/SKILL.md` - Python-specific patterns
- `@tests/SKILL.md` - Testing standards
- `@git/SKILL.md` - Version control workflow
- `@gh-cli/SKILL.md` - GitHub CLI operations
- `@style/SKILL.md` - Naming conventions

</related>

## ACTION (Recency Zone)

<required>

**Before committing:**
```sh
# Python
poetry run ruff check --fix && poetry run ruff format
poetry run pytest

# Frontend
pnpm lint:fix && pnpm test
```

**Task management:**
- One task in_progress at a time
- Mark complete only after tests pass
- Commit frequently for session recovery

</required>
