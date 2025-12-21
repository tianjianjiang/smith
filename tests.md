# Testing Standards

<metadata>

- **Load if**: Writing tests, running test suites, TDD
- **Prerequisites**: @principles.md, @standards.md, @python.md

</metadata>

## CRITICAL (Primacy Zone)

<required>

- MUST mirror source structure: `foo/bar/xyz.py` → `tests/unit/foo/bar/test_xyz.py`
- MUST use pytest functions (not classes) - see @python.md
- MUST separate unit (`tests/unit/`) and integration (`tests/integration/`) tests
- MUST use virtual env runner for pytest (`poetry run` or `uv run`)
- MUST write tests BEFORE implementation (TDD)
- MUST run full test suite after changes

</required>

<forbidden>

- NEVER use `pytest -m "not integration"` if folder structure is mirrored (import conflicts)
- NEVER write implementation before tests
- NEVER skip running tests after changes

</forbidden>

## Test Organization

| Type        | Location             | Characteristics                           |
| ----------- | -------------------- | ----------------------------------------- |
| Unit        | `tests/unit/`        | Mock dependencies, fast                   |
| Integration | `tests/integration/` | Real services, `@pytest.mark.integration` |

## TDD Workflow

1. **Understand**: Read existing test patterns
2. **Design**: Write failing tests defining expected behavior
3. **Implement**: Write minimal code to pass tests
4. **Verify**: Run tests, validate coverage
5. **Refactor**: Improve code while keeping tests green

## Environment Configuration

- `tests/conftest.py` disables tracking (OPIK, etc.)
- Virtual env runners load `.env` automatically
- Use `.env.example` as template (NEVER commit `.env`)

## ACTION (Recency Zone)

**Run tests:**
```sh
# Python (use virtual env runner)
poetry run pytest tests/unit/ -v
poetry run pytest tests/integration/ -v

# Or with uv
uv run pytest tests/unit/ -v
```

<related>

- @python.md - Python testing patterns (pytest functions)
- @dev.md - Development workflow (quality gates)
- @principles.md - Core principles

</related>

**Success criteria:**
- All new functionality has tests
- Test names follow project conventions
- Tests are isolated and deterministic
- No regressions in existing tests
