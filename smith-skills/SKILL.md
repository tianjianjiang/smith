---
name: smith-skills
description: Agent skills authoring guide for AGENTS.md and SKILL.md files. Use when creating or editing agent instructions, rules, or documentation. Covers progressive disclosure, rule loading, Markdown structure, and token budget guidelines.
---

# Agent Skills Authoring Guide

**Scope:** Writing AGENTS.md, SKILL.md, and steering files
**Load if:** Creating or editing agent instructions, rules, or documentation
**Based on:** [agentskills.io](https://agentskills.io) standards

## Progressive Disclosure Philosophy

Skills and rules follow 3-tier loading to minimize token usage:
- **Layer 1**: AGENTS.md entry point (~500 tokens, always loaded)
- **Layer 2**: Individual standards (<2000 tokens, on-demand by task)
- **Layer 3**: Detailed resources (loaded when explicitly needed)

**Section ordering**: put the rules an agent must never miss near the top of
the file, and checklists/action items near the bottom. Treat this as
practical placement hygiene, not a claim about a specific attention
mechanism — a prior version of this file labeled sections "(Primacy Zone)"
and "(Recency Zone)" as if that maps to a documented Anthropic effect.
Verified 2026-07-11: it doesn't. Anthropic's context-engineering and
prompt-engineering docs never mention primacy/recency, and state that
"exact formatting matters less as models get more capable."

## Rule Loading Notification

**Every AGENTS.md MUST define:**
- Which files are always-active vs on-demand
- Notification format: "Loaded @file.md (reason)"
- Deactivation trigger: "Unload after N turns unused"
- Context thresholds: Claude Code 50%/60%, Cursor/Kiro 70%/80%

**Enforcement**: Reporting proves actual loading, not fake compliance

## Critical Rules

- Use bullet lists over tables for ALL content (instructions AND reference
  data) — LLMs parse bullet lists more reliably than tables
- Put a metadata line (Scope/Load if/Prerequisites) at the file start for
  early loading
- Keep lines under 80 characters for better parsing
- Keep nested lists to 2 levels or fewer
- Use code blocks with language hints for all code examples
- Shell code blocks must be copy-paste ready — no inline comments; move
  descriptions outside as text or subsection titles

## Self-Contained Committed Config

Skills, subagents, and hooks committed into a repo's `.claude/` MUST work in
any operator's session — never depend on the author's machine:

- No references to local Serena/auto-memory slugs (e.g. `read_memory(...)`)
  or dangling memory refs from a committed SKILL.md or `.claude/agents/*.md`
- No hardcoded home paths (e.g. `/Users/«name»/...`) — inline the rule instead
- No hooks reading `$CLAUDE_TOOL_INPUT` / `$CLAUDE_TOOL_INPUT_FILE_PATH`
  (these never existed; input is JSON on stdin, `$CLAUDE_PROJECT_DIR` is the
  only path var) — such hooks exit 0 and silently do nothing
- Verify a committed hook actually fires; a silent exit-0 looks like "passed"

## File Structure

**AGENTS.md** (entry point, <500 tokens):
- Standards index with descriptions
- Core principles summary
- Context thresholds
- Rule loading protocol

**SKILL.md** (Agent Skills format):
- YAML frontmatter (required fields):
  - `name`: kebab-case, max 64 chars, must match directory name (e.g.,
    `smith-guidance`). Use a PRECISE technical term, not a casual one
    (`smith-dialectic`, not `smith-grill`); match the terse body of
    existing names (`ctx`, `git`, `plan`, `validation`).
  - `description`: max 1024 chars, starts with noun phrase,
    ends with trigger conditions ("Use when...")
- YAML frontmatter (optional fields — include only when publishing externally):
  - `version`: semver (for published/shared skills)
  - `license`: SPDX identifier
  - `compatibility`: minimum tool version
- Body structure (plain Markdown — see Markdown Structure below):
  - Metadata line: Scope, Load if, Prerequisites
  - Critical rules near the top
  - Middle: context, examples, reference details
  - Related links, then a final checklist near the bottom
- Size: <500 lines recommended (~5000 tokens max)
- Internal smith skills: omit `version`, `license`, `compatibility`
  (noise without value for project-scoped skills)

**SKILL.md frontmatter dual-spec**: a SKILL.md legitimately carries BOTH the
agentskills.io YAML frontmatter (`name`/`description`, for discovery/registry)
AND a smith metadata line (Scope/Load if/Prerequisites) in the body. They are
complementary — never strip one in favor of the other.

**Steering files** (.md):
- Metadata line at start
- Critical rules near the top
- Action items near the bottom

## Skill Reference Convention

**Backtick usage for skill references:**
- **Always-load skills** (core): No backticks - @smith-principles/SKILL.md
- **Dynamic skills**: With backticks - `@smith-python/SKILL.md`
- **Self-reference**: Bold without @ - **smith-skills**

This distinguishes core skills (always in context) from contextual skills (loaded on demand).

## Skill Loading Mechanics

How Claude Code actually loads skills (non-obvious; governs why smith works):

- Claude Code does NOT auto-execute skill-loading instructions written in
  CLAUDE.md / AGENTS.md — the agent must proactively Read the skill files.
  Discovery works because `~/.smith` is symlinked to `~/.claude/skills`.
- Auto-triggering is description/shape-match in the MAIN thread only.
  Task/Workflow subagents do NOT auto-load skills or AGENTS.md — pass the
  needed rules inline in the subagent prompt.
- Claude Code auto-loads `CLAUDE.md` (including nested CLAUDE.md) but NOT a
  bare `AGENTS.md`. A repo whose root ships only AGENTS.md silently fails to
  load its catalog in CC — keep a root `CLAUDE.md` -> `AGENTS.md` symlink
  (AGENTS.md-native tools load AGENTS.md directly and are unaffected).

## Heading Hierarchy

- Use consistent levels (no skipping H2 → H4)
- H1: File title only
- H2: Major sections
- H3: Subsections
- Avoid H4+ (indicates over-nesting)

## Markdown Structure

SKILL.md bodies use plain Markdown — headers, bold labels, and bullet
lists — not an XML tag skeleton (no `<required>`/`<forbidden>`/`<context>`/
`<metadata>`/`<related>`). This matches Anthropic's own SKILL.md-authoring
examples and OpenAI's current (GPT-5.5/5.6) model-guidance format; only
Gemini's docs treat XML and Markdown as equally valid, so Markdown is the
safer cross-platform default. (Verified 2026-07-11 against
platform.claude.com's Skill authoring best-practices page and OpenAI's
GPT-5.5 model guidance — see `@smith-xml/SKILL.md` for the narrower case
where XML content-tags are still the right tool: runtime prompts that mix
instructions with embedded data, e.g. subagent prompts.)

**Structure:**
- `##` headers name the topic — a header like "## Branch Naming" already
  signals scope; strengthen individual bullets with MUST/ALWAYS/NEVER
  wording instead of relying on a wrapper tag to carry that weight.
- Prefer telling the agent what to do over what not to do. Rewrite
  prohibitions as affirmative statements and fold them into the normal
  bullet list — "Only commit when the user explicitly asks" carries the
  same rule as "Never commit unless asked" without asking the reader to
  parse a negation. This is Anthropic's own documented guidance ("tell
  Claude what to do instead of what not to do"), verified 2026-07-11.
- Reserve a `## Hard Limits` section for the residual with no natural
  affirmative phrasing (secrets, force-push, irreversible deletes). Keep
  it short — if bullets keep accumulating there, some of them probably do
  have a positive rephrasing that hasn't been found yet.
- Good/bad example pairs go in separate `### Good` / `### Avoid`
  subheadings — never mixed in one block.
- Bullet lists over tables for all content, including reference data.
- Don't invent placeholder-style tags (`<type>`, `<scope>`) when writing
  runtime-prompt content per `@smith-xml/SKILL.md` — that guidance is
  scoped to actual runtime prompts, not SKILL.md bodies, which don't use
  tags at all.

## Token Budget Guidelines

- AGENTS.md entry point: <500 tokens
- Individual standard files: <2000 tokens
- SKILL.md files: <500 lines (~5000 tokens max)
- Session total: <5000 tokens (index + 1-2 active skills)

### Good: bullet list for rules

```markdown
- Always use `uv` for Python packages
- Type hints on all public functions
- Run tests before committing
```

### Good: reference data (bullet list preferred over table)

```markdown
**Context thresholds:**
- Claude Code: 50% warning, 60% critical
- Cursor: 70% warning, 80% critical
- Kiro: 70% warning, 80% critical
```

## Related

- `@smith-xml/SKILL.md` - XML tags for runtime prompts (not SKILL.md bodies)
- @smith-ctx/SKILL.md - Context management strategies
- @smith-principles/SKILL.md - Core coding principles

## Before You Finish

**When creating AGENTS.md:**
1. Keep under 500 tokens
2. Declare always-active files
3. Define semantic activation triggers
4. Add context thresholds

**When creating skill files:**
1. Add a metadata line with the Load if condition
2. Put critical rules near the top
3. Put a checklist/action items near the bottom
4. Add a Related section with cross-references
5. Use bullet lists, not tables, for instructions and reference data; keep
   nested lists to 2 levels or fewer
