---
name: smith-python
description: Python development with uv, pytest, ruff, and type hints. Use when writing Python code, running tests, managing Python packages, or working with virtual environments. Covers import organization, type hints, pytest patterns, and environment variables.
---

# Python Development Standards

**Load if:** Python code, pytest, virtual env
**Prerequisites:** @smith-principles/SKILL.md, @smith-standards/SKILL.md

## CRITICAL

- ALWAYS use absolute imports (`from package.module import`) instead of relative imports (`from .module import`)
- ALWAYS use type hints for all function signatures
- ALWAYS use function-based tests: `def test_should_«action»_when_«condition»():` — instead of unittest-style TestCase classes or pytest class-based tests (`class TestFoo:`)
- ALWAYS use virtual env runner: `poetry run` or `uv run` — running `.venv/bin/python -m pytest` directly skips required .env vars
- ALWAYS use structured logging with `extra=` parameter for all log data, instead of %-style formatting in log messages
- ALWAYS prefer moderate defaults for enum parameters
  (e.g., "medium" not "low"/"high" unless spec requires)
- When refactoring, preserve existing parameter values
  and model references unless change is requested
- Keep imports at module level, not inline within functions
- Use a single package manager consistently within a project
- Add `# noqa` to silence ruff/flake8 only when it meets the
  exception criteria in `@smith-validation/SKILL.md`
- Address F841 unused-variable warnings directly, rather than
  renaming to a `_` prefix to suppress them

## Import Organization

1. **stdlib**: `import os, sys`
2. **third-party**: `import pytest`
3. **local**: `from package.module import`

## Type Hints

```python
# Python 3.10+ built-in syntax (preferred)
def process_docs(docs: list[str], max_count: int | None = None) -> bool:
    pass

# Python 3.9 compatibility: use __future__ annotations
from __future__ import annotations
```

## Testing with Pytest

```python
# Function-based tests (required pattern)
def test_should_parse_pdf_when_valid_file_provided():
    result = parse_pdf("valid.pdf")
    assert result.success == True

# OK: Helper classes for test data (not test cases)
class TestDataBuilder:
    @staticmethod
    def create_valid_input() -> dict:
        return {"key": "value"}
```

## Environment Variables

```python
import os
from pydantic_settings import BaseSettings

# Simple access
api_key = os.getenv("API_KEY", "default")

# Pydantic settings (preferred)
class Settings(BaseSettings):
    api_key: str
    timeout: int = 30
    class Config:
        env_file = ".env"

# CRITICAL: Set BEFORE importing library
os.environ["LIBRARY_CONFIG"] = "value"
import library  # Now sees config
```

## Common Patterns

- **Error handling**: Catch specific exceptions, log, re-raise
- **Logging**: `logger = logging.getLogger(__name__)`
- **Dataclasses**: Use `@dataclass(frozen=True)` for immutable config

## Claude Code LSP (Experimental)

**LSP plugins exist but are currently broken** (race condition in initialization):
- `pyright-lsp@claude-plugins-official`

**When fixed**, LSP provides: goToDefinition, findReferences, hover, documentSymbol, getDiagnostics

**Workaround**: Use Serena MCP for language server features (`find_symbol`, `find_referencing_symbols`)

## Related

- @smith-principles/SKILL.md - Core principles
- @smith-standards/SKILL.md - Universal coding standards
- `@smith-tests/SKILL.md` - Testing standards (pytest patterns)
- `@smith-dev/SKILL.md` - Development workflow
- `@smith-serena/SKILL.md` - Serena MCP for language server features

## Before You Finish

**Before commit (Poetry):**
```shell
poetry run ruff check --fix
poetry run ruff format
poetry run pytest
```

**Before commit (uv):**
```shell
uv run ruff check --fix
uv run ruff format
uv run pytest
```

**Package management:**
- Poetry: `poetry install`, `poetry add «pkg»`, `poetry remove «pkg»`
- uv: `uv sync`, `uv add «pkg»`, `uv remove «pkg»`
