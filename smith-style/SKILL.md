---
name: smith-style
description: File naming, path standards, and conventional commits. Use when naming files, creating branches, writing commit messages, or setting up new projects. Covers underscore vs hyphen conventions, commit format, and branch naming patterns.
---

# File Naming & Path Standards

<metadata>

- **Load if**: Git operations, PR workflows, new project setup
- **Prerequisites**: @smith-principles/SKILL.md

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

**Test files**: `test_«module»_«function»_«type».py`
**JSON test data**: `«module»_«function»_cases.json`
**Documentation**: `«topic».md` (hyphen for hierarchy, underscore for phrases)
**Config**: `.env`, `pyproject.toml`, `AGENTS.md`

## Path References

<required>

**Use code blocks, not Markdown links:**
```markdown
**Core Principles**: @smith-principles/SKILL.md - Description
**Related Skill**: @skill-name/SKILL.md - Description
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

<context>

**Special prefixes** (outside conventional commits):
- `#WIP` — Work-in-progress checkpoint, not a conventional commit (used by auto-commit rules)

</context>

## Branch Names

<required>

**Patterns** (in order of frequency in this repo):

1. **Compound** (most common): `type/«hierarchical-scope»_«single-concept-description»`
   - Hyphens preserve the hierarchical scope (matches the commit scope).
   - A single `_` separates scope from description.
   - Underscores inside the description treat the whole phrase as one concept.

2. **Description-only**: `type/«single-concept-description»` — when there's no
   meaningful hierarchical scope, just underscored words.

3. **Scope-only-hierarchy**: `type/«hierarchical-scope»-«sub-hierarchy»` — when
   the whole name is hierarchy (e.g. `smith-tools-ext`).

**Real examples from merged PRs:**
- `fix/plan-claude_model_detection_improvements` (scope: plan→claude; desc: "model detection improvements" → all underscores)
- `fix/plan-claude-review_polish` (scope: plan→claude→review; desc: "polish")
- `docs/gh-pr-attribution_wording` (scope: gh→pr; desc: "attribution wording")
- `fix/smith_convention_renames` (no hierarchy; desc only: "smith convention renames")
- `feat/smith-ctx-claude-ext` (all hierarchy: smith→ctx→claude→ext, no description)
- `feat/smith-automation_skill` (scope: smith→automation; desc: "skill")

Branch type MUST match commit type. Prefer full words over abbreviations
(`cmd`, `cfg`, `auth`) unless the full word exceeds 15 chars OR the
abbreviation is a domain-standard term in this repo (`gh` = GitHub,
`pr` = pull request, `ci` = continuous integration, `mcp` = Model Context
Protocol). `command`, `configuration`, `authentication` all fit — spell
them out.

</required>

<forbidden>

- `feat/user-authentication` — multi-word single concept; should be `feat/user_authentication`
- `feat/auth_login` — hierarchy (login is part of auth); should be `feat/auth-login`
- `feat/ctx-claude-slash-cmd-rule` — three errors in one: (a) `slash-cmd` should be `slash_command` (multi-word single concept); (b) `cmd` is an unnecessary abbreviation; (c) the separator between scope `ctx-claude` and description should be `_`, not `-`. Correct: `feat/ctx-claude_slash_command_rule`.
- `fix/auth_post_review` / `fix/auth_after_review` — names the change's ORIGIN (a review round), not the change. Name what it does: `fix/auth_token_expiry`. Never put `post_review`/`post-review`/`after_review` in a branch or commit.

</forbidden>

<context>

**Pre-push checklist (use this before every `git push`):**

1. Read the branch name out loud.
2. For each `-` and `_` in the name, justify it:
   - `-` ← "this is hierarchy or a parallel variant"
   - `_` ← "this is a multi-word single concept" OR "this separates the scope from the description"
3. If any separator can't be justified — the name is wrong; rename before push.
4. If the branch name contains an abbreviation, ask: "is the full word ≤15 chars AND not a domain-standard term (`gh`, `pr`, `ci`, `mcp`)? If yes, use the full word."

This checklist exists because the same underscore-vs-hyphen mistake has recurred
across multiple PRs (#71/#72 skill names, #80 branch name) — both rounds
required follow-up fixes. The rule itself was always documented; the failure
mode was not pausing to apply it before pushing.

</context>

## External Communication Standards

<required>

**Language matching:**
- Match the language of the source context
  (English PR → English reply; zh-Hant Notion → zh-Hant reply)
- Code artifacts always English: variable names, commits, branch names, inline code comments
- Default for user-facing explanations when context is ambiguous: zh-Hant (user preference)
- Never switch language unprompted — if unsure, ask once

**Slack formatting (mrkdwn, not Markdown):**
- Links: `<https://url|display text>` (not `[text](url)`)
- Emphasis: `*bold*`, `_italic_`, `` `code` ``
- Mentions: `<@USERID>` format, never display names
- Thread replies for follow-ups; avoid walls of text in channels

**Wiki-link leakage prevention:**
- `[[Page Title]]` renders as broken literal text outside Notion
- When copying to Slack/GitHub/Jira: convert to plain name or full URL

**Issue format (Job Story):**
- "When «situation», I want to «motivation», so I can «expected outcome»"
- Describe the problem and outcome, not the implementation approach

</required>

<related>

- `@smith-git/SKILL.md` - Branch and commit workflows
- @smith-principles/SKILL.md - Core principles (DRY, KISS, YAGNI)

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
