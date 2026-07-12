---
name: smith-dev
description: Development workflow standards and code quality requirements. Use when starting ANY task that will modify repo files (implement, fix, add, refactor, harden), initializing projects, running quality checks, or managing agent tasks. Covers branch-first setup, pre-commit checks, task decomposition, and script organization patterns.
---

# Development Workflow Standards

**Scope:** Development workflow standards and code quality requirements
**Load if:** Initializing a new project
**Prerequisites:** @smith-principles/SKILL.md, @smith-standards/SKILL.md

This document defines development workflow standards and code quality requirements.

## CRITICAL

- **Step 0 of every dev task — before the first edit**: create a dedicated
  branch (+worktree in background sessions) per the `@smith-git/SKILL.md`
  branch-first rule; never start edits on the default branch or an unrelated
  dirty branch.
- Run formatters and linters before committing.
- Run tests before committing.
- Ensure quality checks pass before creating PRs.
- Keep exactly one task in_progress at a time.

## Code Quality (MANDATORY)

- MUST run formatters and linters before commits (ideally after each file edit — use PostToolUse hooks when available, see `@smith-ctx-claude/SKILL.md`)
- MUST run tests before commits
- MUST fix all linting errors

**Language-specific commands:**
- **Python**: See `@smith-python/SKILL.md#before-you-finish` (supports Poetry and uv)
- **TypeScript/Frontend**: See `@smith-typescript/SKILL.md`

## Agent-Assisted Development

**For AI agent workflows**: See @smith-guidance/SKILL.md for comprehensive patterns:
- Exploration workflow (Read → Ask → Propose → Implement)
- Debugging workflow (Reproduce → Analyze → Hypothesize → Test → Verify)
- AGENTS.md optimization for prompt caching
- Constitutional AI principles (HHH framework)

## Agent Task Decomposition

**Sweet spot**: 3-5 high-level milestones, not micro-steps

- Tasks MUST focus on logical phases, be independently verifiable
- Exactly ONE task in_progress at any time
- Mark complete only after tests pass and changes committed
- Use git commits + todos for session bridging

**Task states**: pending → in_progress → completed

**Dependencies**: Note in task description (e.g., "depends on #1")

## Pre-PR Quality Gates

Before creating a pull request:

- MUST run all formatters and linters (see language-specific skills)
- MUST run all tests
- MUST ensure branch is up-to-date with base branch
- MUST review your own changes first (`git diff`)

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
**Naming**: `«purpose»_«id»_«timestamp».json`

## Mechanical Sweeps & Text Transforms

When changing a token across many files, build an EXACT-token allowlist of the
strings to change and edit only those. Never run a blind `sed`/global
find-replace that can hit unintended matches (substrings, comments, unrelated
identifiers). Preview with `grep -n` first, then transform only the vetted set.

## Local Command Footguns (macOS)

Before handing the user a manual/test command, account for these traps:

- GNU make 3.81 (macOS system `make`) silently builds a junk executable via
  the built-in implicit rule `%: %.sh` when `make «target»` has no such target.
  Confirm the target exists (`grep -n '^«target»:' Makefile`) or run the `.sh`.
- The user's macOS package manager is MacPorts, NOT Homebrew. Use `port`,
  never `brew`, in suggested commands.
- A background (non-TTY) Claude Code session's Bash cannot run `sudo` (no
  prompt; iTerm2 won't pop a dialog). Route via a GUI askpass (`SUDO_ASKPASS`
  + `osascript`), or hand the command to the user's terminal with a `!` prefix.
- The user's shell is zsh: unlike bash, zsh does NOT word-split an unquoted
  `$VAR` in `for x in $list` — it iterates ONCE over the whole string. Split
  explicitly with an array (`for x in ${(s: :)list}`) or quote on purpose. Keep
  non-trivial `case`/loop logic in a script file, not a fragile inline one-liner.

## Logging and Observability

**Logging levels:**
- DEBUG: Only when actively debugging
- WARNING: Default for external libraries (httpx, openai, fastapi)
- INFO: Application-level events

**Configuration:**
- Centralized controls in project documentation
- Test logging: Configure via `pytest.ini` and `pyproject.toml`

## Ralph Loop Integration

**Milestones = Ralph iterations**: Each phase boundary triggers quality gates.

See `@smith-ralph/SKILL.md` for full patterns.

## Related

- @smith-principles/SKILL.md - Fundamental coding principles
- @smith-standards/SKILL.md - Universal code standards
- `@smith-python/SKILL.md` - Python-specific patterns
- `@smith-tests/SKILL.md` - Testing standards
- `@smith-git/SKILL.md` - Version control workflow
- `@smith-gh-cli/SKILL.md` - GitHub CLI operations
- `@smith-style/SKILL.md` - Naming conventions

## Before You Finish

**Before committing:**
- Run formatters, linters, and tests (see `@smith-python/SKILL.md` or `@smith-typescript/SKILL.md`)

**Task management:**
- One task in_progress at a time
- Mark complete only after tests pass
- Commit frequently for session recovery
