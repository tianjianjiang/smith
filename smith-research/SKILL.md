---
name: smith-research
description: Proactive research protocol for version queries, APIs, and best practices. Use when answering questions about library versions, API documentation, or technology assessments. Covers research triggers, source citation, and confidence indicators.
---

# Proactive Research Protocol

**Load if:** Queries about versions, APIs, libraries, best practices
**Prerequisites:** @smith-guidance/SKILL.md

## CRITICAL: Mandatory Research Triggers

**Temporal constraint**: ALWAYS get today's real date first as critical context for research queries.

**MUST research when:**
- Version/release queries ("latest version of X")
- API/documentation queries ("how to use X API")
- Best practices queries ("recommended way in «current year»")
- Technology assessment ("should I use X or Y")
- Unfamiliar technology (not in training data)
- **Recommending an integration/config/tooling mechanism that depends on external system behavior** (MCP, OAuth/auth flow, provider API, CLI flag, feature/version support) — MUST load this skill + `@smith-validation/SKILL.md` (falsify-before-present) and verify it actually works via official docs AND the issue tracker BEFORE proposing. A proposed mechanism is a *claim*; claims need evidence — do not present it with confidence until verified. Reframe "set up X" as "is X even possible the way I think" — that reframe is the trigger.

## Research Methods (Priority Order)

1. **Official docs** - Most authoritative
   - `fetch https://docs.python.org/3/library/asyncio.html`

2. **Package registry** - Version info
   - npm: `https://registry.npmjs.org/«package»/latest`
   - PyPI: `https://pypi.org/pypi/«package»/json`
   - GitHub: `https://api.github.com/repos/«owner»/«repo»/releases/latest`

3. **Web search** - Broad queries
   - Include current year: "Next.js 15 best practices «current year»"

4. **GitHub repo** - Source of truth
   - README, CHANGELOG, release notes

## Source Citation

**Always include:**
- Source URL
- Date of retrieval
- Version referenced

**Format:**
```text
"React 19 introduced `feature_name` [1]"

[1] Source Name: URL (retrieved YYYY-MM-DD)
```

**Confidence indicators:**
- High: "Per official documentation..."
- Medium: "Based on recent community discussion..."
- Low: "My training data suggests X, but couldn't verify..."

## Paywall Workarounds

**Medium.com**: Replace domain with `freedium-mirror.cfd`
- Pattern: `https://freedium-mirror.cfd/https://medium.com/@author/article`
- Use when WebFetch returns paywall/403 errors

## When NOT to Research

- Fundamental concepts (won't change)
- Opinion/analysis requests
- User provides current info themselves

## Proactive Behavior

**Research when:**
- Answering would require guessing
- User's code references unfamiliar library
- Error suggests version incompatibility
- User mentions "latest", "current", "2024", "2025"
- Accuracy matters (research rather than skip)
- Docs are accessible (provide current API examples, not outdated ones)
- About to claim certainty about a version (verify first)

**Inform user:**
- "I checked the current documentation..."
- "I couldn't fetch latest info, but based on training..."

## Related

- @smith-guidance/SKILL.md - Honest principle
- `@smith-tools/SKILL.md` - MCP fetch configuration

## Before You Finish

**Before answering version/API questions:**
1. Check if research trigger applies
2. Fetch official docs or registry
3. Cite source with URL and date
4. Flag if info conflicts with training data
