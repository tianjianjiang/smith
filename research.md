# Proactive Research Protocol

<metadata>

- **Load if**: Queries about versions, APIs, libraries, best practices
- **Prerequisites**: @guidance.md

</metadata>

## CRITICAL: Mandatory Research Triggers (Primacy Zone)

<required>

**MUST research when:**
- Version/release queries ("latest version of X")
- API/documentation queries ("how to use X API")
- Best practices queries ("recommended way in 2025")
- Technology assessment ("should I use X or Y")
- Unfamiliar technology (not in training data)

</required>

## Research Methods (Priority Order)

<required>

1. **Official docs** - Most authoritative
   - `fetch https://docs.python.org/3/library/asyncio.html`

2. **Package registry** - Version info
   - npm: `https://registry.npmjs.org/[package]/latest`
   - PyPI: `https://pypi.org/pypi/[package]/json`
   - GitHub: `https://api.github.com/repos/[owner]/[repo]/releases/latest`

3. **Web search** - Broad queries
   - Include current year: "Next.js 15 best practices 2025"

4. **GitHub repo** - Source of truth
   - README, CHANGELOG, release notes

</required>

## Source Citation

<required>

**Always include:**
- Source URL
- Date of retrieval
- Version referenced

**Format:**
```text
"React 19 introduced [feature] (source: [URL])"

Sources:
- [Description]: [URL] (retrieved [date])
```

**Confidence indicators:**
- High: "Per official documentation..."
- Medium: "Based on recent community discussion..."
- Low: "My training data suggests X, but couldn't verify..."

</required>

## When NOT to Research

- Fundamental concepts (won't change)
- Opinion/analysis requests
- User provides current info themselves

## Proactive Behavior

<required>

**Research when:**
- Answering would require guessing
- User's code references unfamiliar library
- Error suggests version incompatibility
- User mentions "latest", "current", "2024", "2025"

**Inform user:**
- "I checked the current documentation..."
- "I couldn't fetch latest info, but based on training..."

</required>

<forbidden>

- Claiming certainty about versions without verification
- Providing outdated API examples when docs accessible
- Skipping research when accuracy matters

</forbidden>

<related>

- @guidance.md - Honest principle
- @tools.md - MCP fetch configuration

</related>

## ACTION (Recency Zone)

<required>

**Before answering version/API questions:**
1. Check if research trigger applies
2. Fetch official docs or registry
3. Cite source with URL and date
4. Flag if info conflicts with training data

</required>
