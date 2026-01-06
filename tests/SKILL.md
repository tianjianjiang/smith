---
name: tests
description: Testing standards and TDD workflow. Use when writing tests, running test suites, implementing TDD, or organizing test files. Covers unit vs integration test separation, pytest patterns, and test-driven development methodology.
---

# Testing Standards

<metadata>

- **Load if**: Writing tests, running test suites, TDD
- **Prerequisites**: `@principles/SKILL.md`, `@standards/SKILL.md`, `@python/SKILL.md`

</metadata>

## CRITICAL (Primacy Zone)

<required>

- MUST mirror source structure: `foo/bar/xyz.py` → `tests/unit/foo/bar/test_xyz.py`
- MUST use pytest functions (not classes) - see `@python/SKILL.md`
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

**Unit**:
- Location: `tests/unit/`
- Characteristics: Mock dependencies, fast

**Integration**:
- Location: `tests/integration/`
- Characteristics: Real services, `@pytest.mark.integration`

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

<related>

- `@python/SKILL.md` - Python testing patterns (pytest functions)
- `@dev/SKILL.md` - Development workflow (quality gates)
- `@principles/SKILL.md` - Core principles

</related>

## ACTION (Recency Zone)

<required>

**Run tests:**
```sh
# Python (use virtual env runner)
poetry run pytest tests/unit/ -v
poetry run pytest tests/integration/ -v

# Or with uv
uv run pytest tests/unit/ -v
```

**Success criteria:**
- All new functionality has tests
- Test names follow project conventions
- Tests are isolated and deterministic
- No regressions in existing tests

</required>
