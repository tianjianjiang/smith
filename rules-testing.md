# Testing Standards

<metadata>

- **Scope**: Testing requirements and execution patterns
- **Load if**: Writing tests, running test suites, pytest configuration
- **Prerequisites**: [Core Standards](./rules-core.md) → [Python Standards](./rules-python.md)
- **Requires**: [Python Standards](./rules-python.md#testing-with-pytest) (Pytest patterns)
- **Referenced by**: Development workflows
- **Optional**: [Naming](./rules-naming.md#test-files) (Test file naming)

</metadata>


## Test Requirements

<required>

- MUST mirror source structure: `foo/bar/xyz.py` → `tests/unit/foo/bar/test_xyz.py`
- MUST follow test file naming conventions - see [Naming Standards](@rules-naming.md#test-files)
- MUST use pytest functions (not classes) - see @rules-python.md
- MUST separate unit (`tests/unit/`) and integration (`tests/integration/`) tests

</required>

<context>

**Test organization:**
- Unit tests: Mock dependencies, fast execution
- Integration tests: Real services, mark with `@pytest.mark.integration`

</context>

**For naming patterns**: See @rules-naming.md for test file and JSON test data naming

## Test Execution

**Python projects:**
```sh
# Use virtual env runner (poetry run or uv run)
poetry run pytest tests/unit/ -v
poetry run pytest tests/integration/ -v
```

<required>

- MUST use virtual env runner for pytest - see [Python Standards](@rules-python.md#virtual-environment-execution)
- MUST run unit and integration tests separately if mirrored structure exists

</required>

<forbidden>

- NEVER use `pytest -m "not integration"` if folder structure is mirrored (import conflicts)

</forbidden>

**For pytest execution patterns, .env loading**: See @rules-python.md

## Environment Configuration

**Automatic handling:**
- `tests/conftest.py` disables tracking (OPIK, etc.)
- Virtual env runners (poetry run/uv run) load `.env` automatically
- NO manual environment exports needed

**Environment files:**
- Use `.env` for secrets (NEVER commit)
- Use `.env.example` as template

## Related Standards

<related>

- **Python Testing**: @rules-python.md - Pytest patterns
- **Development Workflow**: @rules-development.md - Code quality
- **Naming Conventions**: @rules-naming.md - Test file naming

</related>
