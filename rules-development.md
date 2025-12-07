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

**For AI agent workflows**: See `$HOME/.smith/rules-ai_agents.md` for comprehensive patterns:
- Exploration workflow (Read → Ask → Propose → Review → Implement)
- Debugging workflow (Reproduce → Analyze → Hypothesize → Test → Verify)
- AGENTS.md optimization for prompt caching
- Constitutional AI principles (HHH framework)

## Pre-PR Quality Gates

<required>

Before creating a pull request:

- MUST run all formatters: `poetry run ruff format .`
- MUST run all linters: `poetry run ruff check --fix .`
- MUST run all tests: `poetry run pytest`
- MUST ensure branch is up-to-date with base branch
- MUST review your own changes first (`git diff`)

</required>

**See**: `$HOME/.smith/rules-pr-concepts.md` - Pull request creation workflow
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
