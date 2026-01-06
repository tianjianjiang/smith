---
name: style
description: File naming, path standards, and conventional commits. Use when naming files, creating branches, writing commit messages, or setting up new projects. Covers underscore vs hyphen conventions, commit format, and branch naming patterns.
---

# File Naming & Path Standards

<metadata>

- **Load if**: Git operations, PR workflows, new project setup
- **Prerequisites**: @principles/SKILL.md

</metadata>

## CRITICAL: Naming Separators (Primacy Zone)

<required>

**Underscore (_)**: Multi-word phrases as single concept
- `user_authentication`, `query_processor`, `semantic_search`
- Think: "What kind of X?" → underscore

**Hyphen (-)**: Hierarchical/parallel relationships
- `auth-login` (login is part of auth)
- `api-rest` vs `api-graphql` (variants)
- Dates: `2025-01-15`
- Tickets: `JIRA-1234`

</required>

## File Patterns

**Test files**: `test_[module]_[function]_[type].py`
**JSON test data**: `[module]_[function]_cases.json`
**Documentation**: `[topic].md` (hyphen for hierarchy, underscore for phrases)
**Config**: `.env`, `pyproject.toml`, `AGENTS.md`

## Path References

<required>

**Use code blocks, not Markdown links:**
```markdown
**Core Principles**: @principles/SKILL.md - Description
**Python**: @python/SKILL.md - Description
```

**Variables**: `$WORKSPACE_ROOT`, `$REPO_ROOT`, `$HOME`

</required>

## Conventional Commits

<required>

**Format**: `type: description` or `type(scope): description`

**Types**: feat, fix, docs, refactor, style, test, chore, perf, build, ci

**Length limits (50/72 rule):**
- Subject: 50 chars target, 72 max
- Body: 72 chars per line

</required>

<examples>

```text
feat(auth): add token refresh
fix: resolve CORS issues
docs: update deployment guide
```

</examples>

<forbidden>

- Subject over 72 characters
- Multiple unrelated changes ("add X and fix Y")
- Using `docs` when also changing code

</forbidden>

## Branch Names

<required>

**Pattern**: `type/descriptive_name`

**Examples:**
- `feat/user_authentication` (underscore: single concept)
- `feat/auth-login` (hyphen: login is part of auth)
- `fix/JIRA-1234-query_processor`

Branch type MUST match commit type

</required>

<forbidden>

- `feat/user-authentication` (should be underscore)
- `feat/auth_login` (should be hyphen)

</forbidden>

<related>

- `@git/SKILL.md` - Branch and commit workflows
- `@python/SKILL.md` - Python naming conventions

</related>

## ACTION (Recency Zone)

<required>

**Before naming:**
1. Is it a single concept? → underscore
2. Is it a part/variant? → hyphen
3. Is it a date/ticket? → hyphen

**Before committing:**
1. Subject ≤72 chars?
2. Single atomic change?
3. Type matches branch?

</required>
