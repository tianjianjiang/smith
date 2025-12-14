# Python Development Standards

<metadata>

- **Scope**: Python-specific coding standards
- **Load if**: Writing Python code, pytest tests, virtual env configuration
- **Prerequisites**: @core.md
- **Requires**: @core.md (Personal formatting, NEVER/ALWAYS)
- **Referenced by**: Testing, Development workflows
- **Optional**: @style.md (File naming patterns)

</metadata>

<context>

For personal rules, see @core.md.

</context>

## Import Rules

<forbidden>

- NEVER use relative imports (from .module import something)
- NEVER use inline imports (import statements within functions)

</forbidden>

<required>

- ALWAYS use absolute imports (from package.module import something)
- ALWAYS organize imports: standard library, third-party, local application

</required>

## Type System

<required>

- MUST use type hints for all function signatures
- MUST use mypy for static type checking
- MUST use proper type annotations for complex types (Dict, List, Optional, Union)

</required>

<examples>

```python
from typing import Optional, List

def process_documents(docs: List[str], max_count: Optional[int] = None) -> bool:
    pass
```

</examples>

## Code Style

**Personal formatting**: See @core.md for line length, indentation, string quotes

**Python-specific (enforced by ruff):**
- Trailing commas: Use in multi-line structures
- PEP8 compliance for all Python code

**Run before commit:**
```sh
poetry run ruff check --fix
poetry run ruff format
```

## Testing with Pytest

<forbidden>

- NEVER use unittest-style test classes (TestCase inheritance)
- NEVER use pytest class-based tests (class TestFoo: def test_bar)
- NEVER execute pytest without virtual env runner (missing .env vars)

</forbidden>

<required>

- MUST use function-based tests: `def test_should_<action>_when_<condition>():`
- MUST use virtual env runner for test execution (poetry run/uv run)
- MUST use type hints in test function signatures
- MUST use pytest.approx() for floating-point comparisons

</required>

<examples>

**Function-based tests:**
```python
def test_should_parse_pdf_when_valid_file_provided():
    result = parse_pdf("valid.pdf")
    assert result.success == True

# OK: Helper classes for test data (not test cases)
class TestDataBuilder:
    @staticmethod
    def create_valid_input() -> dict:
        return {"key": "value"}
```

</examples>

## Virtual Environment Execution

<context>

**Pattern**: Use package manager's virtual environment runner for all Python commands

</context>

<required>

- MUST use virtual env runner for pytest (ensures .env loading, proper paths)
- MUST use virtual env runner for formatters/linters (ruff)
- MUST use package manager for dependency management

</required>

**Implementation by tool**:
```sh
# Poetry
poetry run pytest
poetry run ruff check --fix

# uv
uv run pytest
uv run ruff check --fix
```

<forbidden>

- NEVER execute tests directly: `.venv/bin/python -m pytest` (missing .env vars)
- NEVER mix package managers in same project

</forbidden>

## Environment Variables

<examples>

**Reading environment variables:**
```python
import os
from pydantic_settings import BaseSettings

# Simple access
api_key = os.getenv("API_KEY", "default_value")

# Pydantic settings (preferred for application config)
class Settings(BaseSettings):
    api_key: str
    timeout: int = 30

    class Config:
        env_file = ".env"
```

**Writing environment variables (for library configuration):**
```python
import os
# CRITICAL: Set BEFORE importing library that reads the variable
os.environ["LIBRARY_CONFIG"] = "value"
import library  # Now library sees the config
```

</examples>

<constraints>

**Environment files:**
- Store in `.env` files (NEVER commit to version control)
- Use `.env.example` as template for required variables
- Virtual env runners (poetry run/uv run) load .env automatically

</constraints>

## Package Management

**Dependency management:**
```sh
# Poetry
poetry install
poetry add <package>
poetry remove <package>

# uv
uv sync
uv add <package>
uv remove <package>
```

**Virtual environments:**
- Use local `.venv` directories (project-local isolation)
- Activate shell: `poetry shell` or use `uv run` prefix

## Common Patterns

**Error handling:**
```python
try:
    result = risky_operation()
except SpecificError as e:
    logger.error(f"Operation failed: {e}")
    raise
```

**Logging:**
```python
import logging
logger = logging.getLogger(__name__)

logger.info("Processing started")
logger.error(f"Failed: {error}")
```

**Dataclasses:**
```python
from dataclasses import dataclass

@dataclass(frozen=True)
class Config:
    api_key: str
    timeout: int = 30
```

## Related Standards

<related>

- **Personal Rules**: @core.md - NEVER/ALWAYS for all languages
- **Development Workflow**: @dev.md - Daily practices
- **Testing Standards**: @tests.md - Test execution
- **Naming Conventions**: @style.md - File naming

</related>
