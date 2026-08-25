---
name: smith-style
description: File naming, path standards, and conventional commits. Use when naming files, creating branches, writing commit messages, or setting up new projects. Covers underscore vs hyphen conventions, commit format, and branch naming patterns.
---

# File Naming & Path Standards

**Load if:** Git operations, PR workflows, new project setup
**Prerequisites:** @smith-principles/SKILL.md

## CRITICAL: Naming Separators

**Underscore (_)**: Multi-word phrases as single concept
- `user_authentication`, `query_processor`, `semantic_search`
- Think: "What kind of X?" → underscore

**Hyphen (-)**: Hierarchical/parallel relationships
- `auth-login` (login is part of auth)
- `api-rest` vs `api-graphql` (variants)
- Dates: `2025-01-15`
- Tickets: `JIRA-1234`

## File Patterns

**Test files**: `test_«module»_«function»_«type».py`
**JSON test data**: `«module»_«function»_cases.json`
**Documentation**: `«topic».md` (hyphen for hierarchy, underscore for phrases)
**Config**: `.env`, `pyproject.toml`, `AGENTS.md`

## Path References

**Use code blocks, not Markdown links:**
```markdown
**Core Principles**: @smith-principles/SKILL.md - Description
**Related Skill**: @skill-name/SKILL.md - Description
```

**Variables**: `$WORKSPACE_ROOT`, `$REPO_ROOT`, `$HOME`

## Conventional Commits

**Format**: `type: description` or `type(scope): description`

**Types**: feat, fix, docs, refactor, style, test, chore, perf, build, ci

**Length limits (50/72 rule):**
- Subject: 50 chars target, 72 max
- Body: 72 chars per line

### Examples

```text
feat(auth): add token refresh
fix: resolve CORS issues
docs: update deployment guide
```

**Also keep in mind:**
- Scope each commit to a single logical change — avoid mixing unrelated
  changes ("add X and fix Y")
- Use `docs` only when the commit doesn't also change code

**Special prefixes** (outside conventional commits):
- `#WIP` — Work-in-progress checkpoint, not a conventional commit (used by auto-commit rules)

## Assisted-by attribution

Smith policy: every commit, PR body, PR review comment, and Slack message
produced with AI assistance ends with an `Assisted-by:` trailer naming the agent
and model. The trailer format follows the Linux kernel coding-assistants policy
(https://docs.kernel.org/process/coding-assistants.html, retrieved 2026-07-16),
which mandates it for commits; extending it to PR bodies, review comments, and
Slack is a Smith convention.

**Format**: `Assisted-by: «AGENT_NAME»:«MODEL_VERSION» [«tool»]…`
- Smith value: `Assisted-by: Claude:claude-opus-4-8` — `«MODEL_VERSION»` is the
  actual running session model id, not a frozen string.
- Optional bracketed `[«tool»]` entries name specialized analysis tools only
  (e.g. coccinelle, sparse, semgrep); never basic dev tools (git, editors).

**Deterministic source — do not hand-type the trailer.** The model id has no
environment variable, and hand-typing is where the format drifts (a parenthetical
instead of the colon form). `smith-ctx-claude/scripts/attribution.sh` is the single
source: it prints the correct `Assisted-by: Claude:«MODEL_VERSION»` from the live
session model, kept current by the `attribution-model-stamp` PreToolUse hook. Pull
it, never type it — for a commit add it as a `--trailer` only when non-empty (the
empty-safe array recipe is in README "Hooks"; a bare `--trailer "$(…)"` aborts the
commit when the model is unknown), embed `$(…/attribution.sh)` in a gh PR body or a
`gh pr review --comment --body …` body, or run it and paste its output into an MCP
message (Slack/Jira). Details and registration in README "Hooks".

**Never add a `Signed-off-by:` trailer yourself** — only a human can certify the
DCO, so the agent must not add one (a human may still add their own), and
`Assisted-by:` does not replace human authorship/sign-off. It names the AI that
assisted, not the human who directed the work — the commit's author field, or
the account it posts under, already carries that name, so do not pair it
with an "on behalf of" line (`@smith-gh-pr`).

## Branch Names

**Pattern**: `type/description` — the Conventional Branch specification
(https://conventionalbranch.org/, retrieved 2026-08-24), adopted verbatim
instead of a smith-invented hyphen/underscore split.

- `description` is one or more lowercase-and-digit segments joined by a
  **single hyphen** (`-`) — never an underscore, space, or uppercase letter.
  No consecutive, leading, or trailing hyphens. A segment MAY contain dots
  (`.`) — the spec allows this for version-like text, e.g.
  `chore/deps-node18.20-bump`.
- `type` matches the Conventional Commits type of the work (feat, fix, docs,
  refactor, style, test, chore, perf, build, ci) — branch type MUST match
  commit type.
- Prefer full words over abbreviations (`cmd`, `cfg`, `auth`) unless the full
  word exceeds 15 chars OR the abbreviation is a domain-standard term in this
  repo (`gh` = GitHub, `pr` = pull request, `ci` = continuous integration,
  `mcp` = Model Context Protocol). `command`, `configuration`,
  `authentication` all fit — spell them out.
- Never put `post-review`/`after-review` in a branch or commit — that names
  the change's ORIGIN (a review round), not what the change does. Name the
  effect instead: `fix/auth-token-expiry`, not `fix/auth-post-review`.

**Examples**: `feat/user-authentication`, `fix/plan-claude-model-detection`,
`docs/gh-pr-attribution-wording`.

**Why not encode scope hierarchy in the branch name.** The previous
two-separator convention (hyphen = hierarchy, underscore = single concept)
was retired after two real, independent misapplications of its own
documented examples — the examples themselves didn't follow one derivable
rule (`gh-pr-attribution_wording`'s `attribution` sits on the hyphen side
despite its own annotation calling it part of the description), because
branch names in this repo's history were chosen by feel and rationalized
afterward, not generated from an algorithm. Checking why that scope
information seemed to matter surfaced the real answer: it doesn't, to any
tooling that exists. release-please (https://github.com/googleapis/
release-please, retrieved 2026-08-24) — the standard tool for automating
versions/changelogs from Conventional Commits, should this repo ever adopt
it — parses only commit messages on the default branch; it never reads
branch names. Scope belongs in the commit's `type(scope): description`
header, where release-please-class tooling actually looks; the branch name
only needs to be unambiguous and human-readable, which a single separator
already guarantees.

**Enforced deterministically for Bash-driven git.**
`smith-ctx-claude/scripts/branch-name-guard.mjs` (PreToolUse, matcher `Bash`)
blocks the branch-creating/renaming `git` invocations run via Bash when the
target name doesn't match the pattern above, or contains
`post-review`/`after-review` — no manual pre-push checklist or blacklist
needed, the character-set rule and the type list are the only things a name
has to satisfy. It does not see a branch created outside Bash
(`EnterWorktree`, an IDE git panel, an external terminal) or pushed under a
different name (`git push -u origin HEAD:name`) — see the hook's README
entry for the full known-limitation note. If the name was not explicitly
given by the user, still confirm it with them before the first push — the
hook checks *format*, not *what the user actually wanted named*.

Pre-2026-08-24 branch names used the retired two-separator convention
(visible in old PR history) — this section governs branches created from
now on; do not rename already-merged branches to match retroactively.

## External Communication Standards

**Language matching:**
- Match the language of the source context
  (English PR → English reply; zh-Hant Notion → zh-Hant reply)
- Code artifacts always English: variable names, commits, branch names, inline code comments
- Default for user-facing explanations when context is ambiguous: zh-Hant (user preference)
- Never switch language unprompted — if unsure, ask once

**Wiki-link leakage prevention:**
- `[[Page Title]]` renders as broken literal text outside Notion
- When copying to Slack/GitHub/Jira: convert to plain name or full URL

**Issue format (Job Story):**
- "When «situation», I want to «motivation», so I can «expected outcome»"
- Describe the problem and outcome, not the implementation approach

## Related

- `@smith-git/SKILL.md` - Branch and commit workflows
- @smith-principles/SKILL.md - Core principles (DRY, KISS, YAGNI)
- `@smith-slack/SKILL.md` - Slack message formatting and pre-send gate (owns all Slack rules)

## Before You Finish

**Before naming:**
1. Is it a single concept? → underscore
2. Is it a part/variant? → hyphen
3. Is it a date/ticket? → hyphen

**Before committing:**
1. Subject ≤72 chars?
2. Single atomic change?
3. Type matches branch?
4. `Assisted-by:` trailer present, and no AI-added `Signed-off-by:`?
