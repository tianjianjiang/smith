---
name: python
description: Python development with uv, pytest, ruff, and type hints. Use when writing Python code, running tests, managing Python packages, or working with virtual environments. Covers import organization, type hints, pytest patterns, and environment variables.
---

# Python Development Standards

<metadata>

- **Load if**: Python code, pytest, virtual env
- **Prerequisites**: @principles/SKILL.md, @standards/SKILL.md

</metadata>

## CRITICAL (Primacy Zone)

<forbidden>

- NEVER use relative imports (`from .module import`)
- NEVER use inline imports within functions
- NEVER use unittest-style TestCase classes
- NEVER use pytest class-based tests (`class TestFoo:`)
- NEVER execute pytest without virtual env runner (missing .env vars)
- NEVER execute directly: `.venv/bin/python -m pytest`
- NEVER mix package managers in same project

</forbidden>

<required>

- ALWAYS use absolute imports (`from package.module import`)
- ALWAYS use type hints for all function signatures
- ALWAYS use function-based tests: `def test_should_<action>_when_<condition>():`
- ALWAYS use virtual env runner: `poetry run` or `uv run`

</required>

## Import Organization

1. **stdlib**: `import os, sys`
2. **third-party**: `import pytest`
3. **local**: `from package.module import`

## Type Hints

```python
from typing import Optional, List

def process_docs(docs: List[str], max_count: Optional[int] = None) -> bool:
    pass
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

```python
# Error handling
try:
    result = risky_operation()
except SpecificError as e:
    logger.error(f"Operation failed: {e}")
    raise

# Logging
import logging
logger = logging.getLogger(__name__)

# Dataclasses
from dataclasses import dataclass

@dataclass(frozen=True)
class Config:
    api_key: str
    timeout: int = 30
```

<related>

- `@principles/SKILL.md` - Core principles
- `@standards/SKILL.md` - Universal coding standards
- `@tests/SKILL.md` - Testing standards (pytest patterns)
- `@dev/SKILL.md` - Development workflow

</related>

## ACTION (Recency Zone)

**Before commit:**
```sh
# Poetry
poetry run ruff check --fix
poetry run ruff format
poetry run pytest

# uv
uv run ruff check --fix
uv run ruff format
uv run pytest
```

**Package management:**
```sh
# Poetry: poetry install | poetry add <pkg> | poetry remove <pkg>
# uv: uv sync | uv add <pkg> | uv remove <pkg>
```
