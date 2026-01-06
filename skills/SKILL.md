---
name: skills
description: Agent skills authoring guide for AGENTS.md and SKILL.md files. Use when creating or editing agent instructions, rules, or documentation. Covers progressive disclosure, rule loading, XML tag usage, and token budget guidelines.
---

# Agent Skills Authoring Guide

<metadata>

- **Scope**: Writing AGENTS.md, SKILL.md, and steering files
- **Load if**: Creating or editing agent instructions, rules, or documentation
- **Prerequisites**: @xml/SKILL.md for approved XML tags

</metadata>

## Progressive Disclosure Philosophy

<context>

Skills and rules follow 3-tier loading to minimize token usage:
- **Layer 1**: AGENTS.md entry point (~500 tokens, always loaded)
- **Layer 2**: Individual standards (<2000 tokens, on-demand by task)
- **Layer 3**: Detailed resources (loaded when explicitly needed)

**Lost-in-the-Middle research**: LLMs have U-shaped attention
- First 20% (primacy zone): CRITICAL rules, `<required>`/`<forbidden>` tags
- Middle 60%: Details, examples (weakest attention)
- Last 10% (recency zone): ACTION items, checklists, `<related>` refs

</context>

## Rule Loading Notification

<required>

**Every AGENTS.md MUST define:**
- Which files are always-active vs on-demand
- Notification format: "Loaded @file.md (reason)"
- Deactivation trigger: "Unload after N turns unused"
- Compaction thresholds: warn at 60%, critical at 70%

**Enforcement**: Reporting proves actual loading, not fake compliance

</required>

## Critical Rules (Primacy Zone)

<required>

- **Bullet lists over tables for ALL content** (instructions AND reference data)
- LLMs parse bullet lists more reliably than tables
- XML tags for semantic boundaries: `<required>`, `<forbidden>`, `<context>`, `<examples>`
- Metadata blocks at file start for early loading
- Lines under 80 characters for better parsing
- No nested lists deeper than 2 levels
- Code blocks with language hints for all code examples

</required>

## File Structure

**AGENTS.md** (entry point, <500 tokens):
- Standards index with descriptions
- Core principles summary
- Context thresholds
- Rule loading protocol

**SKILL.md** (Agent Skills format):
- YAML frontmatter: `name` (kebab-case, max 64 chars), `description` (max 1024 chars)
- Optional: `license`, `compatibility`, `metadata`
- Body: <500 lines recommended

**Steering files** (.md):
- Metadata block at start
- Critical rules in first 20% (primacy zone)
- Action items in last 10% (recency zone)

## Heading Hierarchy

- Use consistent levels (no skipping H2 → H4)
- H1: File title only
- H2: Major sections
- H3: Subsections
- Avoid H4+ (indicates over-nesting)

## XML Tag Usage

**Universal tags** (cross-platform):
- `<instructions>` - Step-by-step guidance
- `<context>` - Background information
- `<examples>` - Correct patterns only
- `<constraints>` - Behavioral limitations

**Claude-specific**:
- `<required>` - Mandatory rules
- `<forbidden>` - Anti-patterns only
- `<metadata>` - File metadata
- `<related>` - Cross-references

<forbidden>

- Mixing good/bad examples in same XML tag
- Inventing placeholder-style tags (`<type>`, `<scope>`)
- **Markdown tables** (use bullet lists for ALL content, even reference data)
- Nested lists deeper than 2 levels
- Skipped heading levels

</forbidden>

## Token Budget Guidelines

- AGENTS.md entry point: <500 tokens
- Individual standard files: <2000 tokens
- SKILL.md files: <500 lines (~5000 tokens max)
- Session total: <5000 tokens (index + 1-2 active skills)

<examples>

**Good**: Bullet list for rules
```markdown
<required>

- Always use `uv` for Python packages
- Type hints on all public functions
- Run tests before committing

</required>
```

**Good**: Reference data (bullet list preferred over table)
```markdown
**Context thresholds:**
- Claude: 60% warning, 70% critical
- Kiro: 70% warning, 80% critical
```

</examples>

<related>

- `@xml/SKILL.md` - Approved XML tags and usage
- `@context/SKILL.md` - Context management strategies
- @principles/SKILL.md - Core coding principles

</related>

## ACTION (Recency Zone)

<required>

**When creating AGENTS.md:**
1. Keep under 500 tokens
2. Declare always-active files
3. Define semantic activation triggers
4. Add compaction thresholds

**When creating skill files:**
1. Add `<metadata>` with Load if condition
2. Put CRITICAL rules in first 20%
3. Put ACTION items in last 10%
4. Add `<related>` cross-references

</required>

<forbidden>

- Tables for instructions (use bullet lists)
- Nested lists deeper than 2 levels
- Custom/invented XML tags

</forbidden>
