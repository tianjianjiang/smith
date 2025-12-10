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
- Examples: `rules-semantic_integrity.md`, `rules-github-pr-workflows.md`

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
**Label**: @core.md - Description
```

**Why**: Coding agents parse file paths from code blocks reliably. Markdown links with path variables don't work (agents treat `$REPO_ROOT` as literal directory name).

**Example**:
```markdown
**Core Rules**: `$WORKSPACE_ROOT/docs/rules-core.md` - NEVER/ALWAYS standards
**Python**: @python.md - Imports, types, pytest
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

See @ide.md for VS Code, PyCharm, Kiro variable syntax.

## Consistency Requirements

- Use exact naming patterns in cross-file references
- Follow same conventions for directory names
- Ensure documentation links use correct names
- Reference files with correct names in commit messages

## Conventional Commits Format

<context>

This section defines the conventional commits format used for BOTH:
- **Git commit messages** (local commits)
- **PR titles** (pull request titles on GitHub)

Both follow identical formatting rules and the 50/72 character limits.

</context>

<formatting>

**Format**: `type: description` or `type(scope): description`

Scope is optional. Choose type based on PRIMARY change:

- `feat`: New user-facing functionality
- `fix`: Bug fix for existing functionality
- `docs`: Documentation ONLY (no code changes)
- `refactor`: Code restructure without behavior change
- `style`: Formatting ONLY (whitespace, semicolons)
- `test`: Test changes ONLY
- `chore`: Build/tooling (CI, dependencies, scripts)
- `perf`: Performance improvement

</formatting>

<required>

**Length limits** ([50/72 Rule](https://dev.to/noelworden/improving-your-commit-message-with-the-50-72-rule-3g79)):

**Subject line** (first line):
- **Target**: 50 characters (ideal for `git log --oneline`)
- **Hard limit**: 72 characters (80-char terminal - 4-char git indent - 4-char margin)

**Body** (subsequent lines):
- 72 characters per line maximum

**Atomicity indicator**: If subject exceeds 50 chars, consider if combining multiple changes. Split into separate commits/PRs.

**Application**:
- **Commit messages**: Subject line = first line of commit message
- **PR titles**: Entire PR title = subject line (becomes merge commit subject)

</required>

<examples>

**Git commit example:**
```sh
git commit -m "feat(rag): add semantic search filtering

Implement metadata-based filtering for semantic search queries.
Supports multiple filter conditions with AND/OR logic.

Closes #123"
```

**PR title examples:**
- `feat(rag): add semantic search filtering`
- `fix(api): resolve CORS issues`
- `docs: update deployment guide`
- `refactor(auth): extract validation logic`
- `test: add integration tests for search`

</examples>

<forbidden>

- Subject line over 72 characters (commit or PR title)
- Multiple unrelated changes in subject (e.g., "add X and fix Y and update Z")
- Using "and" to join unrelated changes (indicator of non-atomic change)
- Using `docs` when also changing code → use `feat` or `fix`
- Using `refactor` for bug fixes → use `fix`
- Using `chore` for new features → use `feat`

</forbidden>

## Git Branch and Commit Naming

### Branch Names

<formatting>

**Pattern**: `type/descriptive_name`

**Examples:**
- `feat/user_authentication` (underscore: single concept)
- `feat/auth-login` (hyphen: login is part of auth)
- `fix/JIRA-1234-query_processor` (hyphen for ticket ID, underscore for concept)

**Branch Type Prefixes** (MUST match conventional commit type):

**feat**: New features
- Prefix: `feat/`
- Example: `feat/user_authentication`
- Separator: underscore for single concept

**fix**: Bug fixes
- Prefix: `fix/`
- Example: `fix/JIRA-1234-query_processor`
- Separator: hyphen for ticket ID, underscore for concept

**docs**: Documentation changes
- Prefix: `docs/`
- Example: `docs/enhance_agents_md`
- Separator: underscore for single concept

**refactor**: Code restructuring
- Prefix: `refactor/`
- Example: `refactor/api-rest`
- Separator: hyphen for rest as variant of api

**test**: Test changes
- Prefix: `test/`
- Example: `test/integration_auth`
- Separator: underscore for single concept

**chore**: Build/tooling changes
- Prefix: `chore/`
- Example: `chore/update_dependencies`
- Separator: underscore for single concept

**style**: Formatting changes
- Prefix: `style/`
- Example: `style/format_code`
- Separator: underscore for single concept

<required>

Branch type prefix MUST match the conventional commit type used in commits.

</required>

<required>

**Separator Rules** (CRITICAL: Use correct separator based on relationship):

</required>

**Separator Usage Rules**:

**Underscore (_)**: Multi-word phrases/concepts
- Decision Rule: Words form a SINGLE concept/phrase (think: compound noun)
- Example: `feat/user_authentication`

**Hyphen (-) - Hierarchical**: Parts/subsets of a whole
- Decision Rule: Second word is a PART or SUBSET of the first
- Example: `feat/auth-login` (login is part of auth)

**Hyphen (-) - Parallel**: Co-existing/differentiation
- Decision Rule: Different variants/types of the same thing
- Example: `feat/api-rest` vs `feat/api-graphql`

**Hyphen (-) - ISO Dates**: Standard date format
- Decision Rule: Standard date format
- Example: `2025-01-15`

**Hyphen (-) - Ticket IDs**: Standard ticket format
- Decision Rule: Standard ticket format
- Example: `JIRA-1234`, `GH-567`

**Slash (/)**: Type delimiter only
- Decision Rule: Separates branch type from description
- Example: `docs/`, `feat/`, `fix/`

**Complex Pattern**: `type/TICKET-number-topic_clause-another_topic-YYYY-MM-DD`

<required>

**Decision Guide for Underscore vs Hyphen:**

1. **Use Underscore (_)** when words form a single concept:
   - `user_authentication` (authentication is the type of user concept)
   - `query_processor` (processor is the type of query concept)
   - `semantic_search` (search is the type of semantic concept)
   - Think: "What kind of X?" → single concept → underscore

2. **Use Hyphen (-)** when there's a hierarchical or parallel relationship:
   - `auth-login` (login is a subset/part of auth module)
   - `auth-password` (password is a subset/part of auth module)
   - `api-rest` (REST is a variant/type of API, parallel to api-graphql)
   - Think: "X has parts Y and Z" or "X comes in variants Y and Z" → hyphen

</required>

<examples>

**Correct usage:**

- `feat/user_authentication` → underscore: "user authentication" is a single concept
- `feat/auth-login` → hyphen: "login" is a part/subset of "auth"
- `feat/api-rest` → hyphen: "rest" is a variant/type of "api"
- `fix/JIRA-1234-query_processor` → hyphen for ticket, underscore for concept
- `feat/user_profile-settings` → hyphen: "settings" is a subset of "user_profile" (which uses underscore as single concept)

</examples>

<forbidden>

**Incorrect usage:**

- `feat/user-authentication` → WRONG: should be underscore (single concept)
- `feat/auth_login` → WRONG: should be hyphen (login is part of auth)
- `feat/api_rest` → WRONG: should be hyphen (rest is variant of api)

</forbidden>

</formatting>

<required>

**Naming Convention Enforcement:**

- Branch names MUST follow the `type/descriptive_name` pattern
- Branch type prefix MUST match the conventional commit type used in commits

**Examples:**
- Branch `feat/user_auth` → Commits: `feat: add user authentication`
- Branch `fix/bug-123` → Commits: `fix: resolve bug 123`
- Branch `feat/user_auth` → Commits: `fix: add user auth` → WRONG: branch type doesn't match commit type

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
