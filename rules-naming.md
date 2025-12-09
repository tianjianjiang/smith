# File Naming Conventions and Path Standards

Standardized naming patterns and path reference conventions.

<context>

## Core Naming Principles

### Non-Python Files
- **Hyphen (-)**: Subset/hierarchical relationships (e.g., `rules-core.md`, `2025-09-26`)
- **Underscore (_)**: Multi-word phrases as single concepts (e.g., `semantic_integrity`)

### Python Files
- **snake_case**: Modules, functions, variables
- **PascalCase**: Classes
- **UPPER_SNAKE_CASE**: Constants

</context>

## File Categories

### Test Files
**Pattern**: `test_[module]_[function]_[feature]_[type].py`
- Example: `test_processor_analyze_text_selective_expansion_intg.py`
- MUST include both module AND function name

### JSON Test Data
**Pattern**: `[module]_[function]_[feature]_cases.json`
- Example: `cast_lucene_query_processor_analyze_text_cases.json`
- Use `_cases.json` NOT `_test_cases.json`

### Documentation Rules Files
**Pattern**: `rules-[category].md` (underscore for multi-word categories)
- Examples: `rules-semantic_integrity.md`, `rules-tools-mcp.md`

### Configuration Files
Standard names: `.env`, `.env.sample`, `Dockerfile`, `docker-compose.yml`, `pyproject.toml`, `.gitignore`, `README.md`, `AGENTS.md`

## Naming Examples

<examples>

**Correct naming patterns**:

```text
rules-core.md, rules-semantic_integrity.md
test_processor_analyze_text_intg.py
cast_lucene_query_processor_cases.json
prompt_engineering_session-2025-09-26
```

</examples>

<forbidden>

**Incorrect naming patterns**:

```text
rules_validation.md (underscore in subset)
semantic-integrity (hyphen in phrasal concept)
test_selective_expansion.py (missing module name)
```

</forbidden>

## When to Use Each Separator

### Hyphen (-)
- Date formats: `2025-09-26`
- Subset relationships: `rules-core`, `docs-cli`
- Version numbers: `v2.1.3`

### Underscore (_)
- Multi-word phrases: `semantic_integrity`, `test_metrics`
- Python conventions: `function_name`, `CLASS_CONSTANT`
- Technical compounds: `cast_lucene_query`

### MCP Memory Files
**Pattern**: `topic_concept-YYYY-MM-DD-specific_details`
- Topic: underscore for multi-word (e.g., `prompt_engineering_session`)
- Date: hyphen for hierarchy (e.g., `-2025-09-26-`)
- Details: underscore for specifics (e.g., `failed_experiments`)

## Path Reference Standards

**Path variable definitions**: See project AGENTS.md for "Path Variable Conventions" section

Standard variables: `$REPO_ROOT`, `$WORKSPACE_ROOT`, `$HOME`

### File Reference Pattern

**Use descriptive references with code blocks** (not Markdown links):

```markdown
**Label**: `$WORKSPACE_ROOT/path/to/file.md` - Description
**Label**: `$REPO_ROOT/path/to/file.md` - Description
**Label**: `$HOME/.smith/rules-core.md` - Description
```

**Why**: Coding agents parse file paths from code blocks reliably. Markdown links with path variables don't work (agents treat `$REPO_ROOT` as literal directory name).

**Example**:
```markdown
**Core Rules**: `$WORKSPACE_ROOT/docs/rules-core.md` - NEVER/ALWAYS standards
**Python**: `$HOME/.smith/rules-python.md` - Imports, types, pytest
```

### Usage by Context

**IDE Workspace Configurations:**
```json
{
    "python.testing.pytestArgs": ["tests/"]  // Relative to workspace
}
```

### Path Resolution

**When workspace = Project Root:**
- `$WORKSPACE_ROOT/` → `./`
- `$REPO_ROOT/` → `./` (if workspace is repo root)
- `$HOME/` → `/Users/username/`

**When workspace = Sub-directory:**
- `$WORKSPACE_ROOT/` → `./`
- `$REPO_ROOT/` → `../../../` (relative to workspace)
- `$HOME/` → `/Users/username/`

### Migration from Legacy

**Replace:**
- `$PROJECT_ROOT/` → `$WORKSPACE_ROOT/`
- `_REPO_ROOT_/` → `$REPO_ROOT/`
- `~/` → `$HOME/`

## IDE-Specific Mappings

See [IDE Mappings](rules-ide_mappings.md) for VS Code, PyCharm, Kiro variable syntax.

## Consistency Requirements

- Use exact naming patterns in cross-file references
- Follow same conventions for directory names
- Ensure documentation links use correct names
- Reference files with correct names in commit messages

## Git Branch and Commit Naming

### Branch Names

<formatting>

**Pattern**: `type/descriptive_name` (e.g., `feat/user_authentication`, `fix/JIRA-1234-query_processor`)

**Branch Type Prefixes** (MUST match conventional commit type):

| Commit Type | Branch Prefix | Example                         |
| ----------- | ------------- | ------------------------------- |
| `feat`      | `feat/`       | `feat/user_authentication`      |
| `fix`       | `fix/`        | `fix/JIRA-1234-query_processor` |
| `docs`      | `docs/`       | `docs/enhance_agents_md`        |
| `refactor`  | `refactor/`   | `refactor/api-rest`             |
| `test`      | `test/`       | `test/integration_auth`         |
| `chore`     | `chore/`      | `chore/update_dependencies`     |
| `style`     | `style/`      | `style/format_code`             |

<required>

**For conventional commit type `feat`**: Branch prefix MUST be `feat/` (NOT `feature/`)

**Branch type prefix MUST match the conventional commit type used in commits**

</required>

| Separator      | Use Case                    | Example                               |
| -------------- | --------------------------- | ------------------------------------- |
| Underscore (_) | Multi-word phrases/concepts | `feat/user_authentication`            |
| Hyphen (-)     | Parts/subsets of a whole    | `feat/auth-login`                     |
| Hyphen (-)     | Co-existing/differentiation | `feat/api-rest` vs `feat/api-graphql` |
| Hyphen (-)     | ISO dates                   | `2025-01-15`                          |
| Hyphen (-)     | Ticket IDs                  | `JIRA-1234`, `GH-567`                 |
| Slash (/)      | Type delimiter only         | `docs/`, `feat/`, `fix/`              |

**Complex Pattern**: `type/TICKET-number-topic_clause-another_topic-YYYY-MM-DD`

</formatting>

<required>

**Naming Convention Enforcement:**

- Branch names MUST follow the `type/descriptive_name` pattern
- Branch type prefix MUST match the conventional commit type used in commits (see table above)
- Always verify branch naming before creating branches

**Examples of correct branch-to-commit alignment:**
- Branch `feat/user_auth` → Commits: `feat: add user authentication`, `feat(auth): implement login`
- Branch `fix/bug-123` → Commits: `fix: resolve bug 123`, `fix(api): handle null pointer`
- Branch `docs/readme` → Commits: `docs: update README`, `docs(readme): add examples`

**Examples of incorrect branch-to-commit alignment:**
- Branch `feature/user_auth` → WRONG: use `feat/` prefix, not `feature/`
- Branch `feat/user_auth` → Commits: `fix: add user auth` → WRONG: branch type doesn't match commit type
- Branch `feat/user_auth` → Commits: `feature: add user auth` → WRONG: commit type should be `feat`, not `feature`

</required>

### Commit and PR Titles

<formatting>

**Format**: `type: description` or `type(scope): description`

- Type: lowercase (`feat`, `fix`, `docs`)
- Scope: optional, module/component name, underscore for multi-word concepts
- Description: imperative mood, lowercase start

</formatting>

<examples>

```text
feat: add semantic filtering
feat(query_processor): add semantic filtering
docs(agents_md): expand configuration examples
fix(auth-login): resolve token refresh issue
refactor(api-rest): extract validation logic
```

</examples>

<forbidden>

```text
feat(query-processor): add semantic filtering  # hyphen joining words in scope
Docs: Update README  # capitalized type
feat: Add new feature  # capitalized description
```

</forbidden>

## Related Standards

<related>

- **Python Naming**: [Python Standards](rules-python.md) - Python-specific conventions
- **IDE Mappings**: [IDE Mappings](rules-ide_mappings.md) - IDE variable syntax
- **Git Conventions**: [Git Standards](rules-git.md) - Branch and commit naming

</related>
