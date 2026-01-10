---
name: smith-dev
description: Development workflow standards and code quality requirements. Use when initializing projects, running quality checks, or managing agent tasks. Covers pre-commit checks, task decomposition, and script organization patterns.
---

# Development Workflow Standards

<metadata>

- **Scope**: Development workflow standards and code quality requirements
- **Load if**: Initializing a new project
- **Prerequisites**: @smith-principles/SKILL.md, @smith-standards/SKILL.md

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

**Language-specific commands:**
- **Python**: See `@smith-python/SKILL.md#action-recency-zone` (supports Poetry and uv)
- **TypeScript/Frontend**: See `@smith-typescript/SKILL.md`

## Agent-Assisted Development

**For AI agent workflows**: See @smith-guidance/SKILL.md for comprehensive patterns:
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

- MUST run all formatters and linters (see language-specific skills)
- MUST run all tests
- MUST ensure branch is up-to-date with base branch
- MUST review your own changes first (`git diff`)

</required>

**See**: `@smith-gh-pr/SKILL.md` - Pull request creation workflow
**See**: `@smith-gh-cli/SKILL.md` - GitHub-specific PR commands

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

## Ralph Loop Integration

<context>

**Task decomposition aligns with Ralph iterations:**

- Each milestone (3-5 recommended) = iteration boundary
- Quality gates run between iterations
- Commit frequently for session recovery

**Structure Ralph prompts with milestones:**
```
Phase 1: [milestone] + tests
Phase 2: [milestone] + tests
Phase 3: Integration tests
Output <promise>COMPLETE</promise> after all phases.
```

</context>

<related>

- @smith-principles/SKILL.md - Fundamental coding principles
- @smith-standards/SKILL.md - Universal code standards
- `@smith-python/SKILL.md` - Python-specific patterns
- `@smith-tests/SKILL.md` - Testing standards
- `@smith-git/SKILL.md` - Version control workflow
- `@smith-gh-cli/SKILL.md` - GitHub CLI operations
- `@smith-style/SKILL.md` - Naming conventions

</related>

## ACTION (Recency Zone)

<required>

**Before committing:**
- Run formatters, linters, and tests (see `@smith-python/SKILL.md` or `@smith-typescript/SKILL.md`)

**Task management:**
- One task in_progress at a time
- Mark complete only after tests pass
- Commit frequently for session recovery

</required>
