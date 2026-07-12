---
name: smith-xml
description: XML tag standards for runtime prompts that mix instructions with embedded data (subagent prompts, assembled system messages). Use when constructing such a prompt, NOT when authoring a SKILL.md body — see smith-skills for that. Covers tag conventions for Claude, GPT-5.x, Gemini, and Harmony, with source-credibility notes verified 2026-07-11.
---

# XML Tag Standards

**Load if:** Constructing a runtime prompt that mixes instructions with
embedded data (a subagent prompt, an assembled system message)
**Prerequisites:** None

**Scope note:** this file is about XML tags in *runtime prompts*, not
SKILL.md bodies. SKILL.md bodies use plain Markdown — see
`@smith-skills/SKILL.md`'s "Markdown Structure" section. Verified
2026-07-11: Anthropic's own SKILL.md-authoring examples and OpenAI's
current (GPT-5.5/5.6) model guidance both use plain Markdown for
agent-instruction-file bodies; only Gemini treats XML and Markdown as
equally valid. XML content-tags remain the right tool for the narrower
case this file covers.

## Approved Tags Only

Only use well-established XML tags in a runtime prompt. Don't invent
placeholder-style tags (`<type>`, `<scope>`).

## Universal Tags (All Platforms)

- `<instructions>` - Step-by-step guidance
- `<task>` - Specific user request
- `<context>` - Background information
- `<examples>` - Few-shot examples
- `<constraints>` - Behavioral limitations

## Smith's Custom Tags for Runtime Prompts

These are NOT tags Anthropic's docs prescribe — Anthropic's own XML-tag
guidance only demonstrates content-type tags like `<instructions>`,
`<context>`, `<example>`, `<document>` (verified 2026-07-11: no
prohibition/anti-pattern tag appears anywhere in their prompt-engineering
docs). Smith uses these by analogy, which is still valid per Anthropic's
"use consistent, descriptive tag names" guidance — just don't present them
as an official Anthropic convention:

- `<metadata>` - File/component metadata
- `<required>` - Mandatory requirements
- `<related>` - Cross-references
- `<formatting>` - Output format specs

For a prohibited-actions equivalent in a runtime prompt, prefer rewriting
the content as an affirmative statement first (Anthropic: "tell Claude
what to do instead of what not to do"); if a bullet genuinely has no
positive phrasing, group it under a plain `<hard_limits>` tag rather than
`<forbidden>` — no vendor's docs model a dedicated prohibition tag, and
"forbidden" reads as a double negative once the bullet itself also says
"never."

## Tag Selection Criteria

**`<required>` = "DO this"** (imperative, mandatory behavior)
- Agent MUST follow; failure causes incorrect behavior
- Use for: MUST/ALWAYS statements, mandatory behaviors, action directives

**`<context>` = "KNOW this"** (informational, may deprioritize)
- Agent uses to inform decisions; not mandatory
- Use for: Explanations, methodologies, background, reference material

## GPT-5.x Tags

Verified tag-by-tag against OpenAI's official cookbook guides on
2026-07-11. Each guide version has its own vocabulary — they are separate
documents, not one evolving taxonomy:

**GPT-5 guide** (original): `context_gathering`, `persistence`,
`exploration`, `verification`, `code_editing_rules`, `guiding_principles`,
`final_instructions`, `self_reflection`, `tool_preambles`,
`context_understanding`, `frontend_stack_defaults`, `ui_ux_best_practices`

**GPT-5.1 guide**: `plan_tool_usage`, `solution_persistence`,
`output_verbosity_spec`, `user_updates_spec`, `design_system_enforcement`,
`tool_usage_rules`, `final_answer_formatting` — this is where the `_spec`
suffix pattern starts, not GPT-5.2

**GPT-5.2 guide**: `design_and_scope_constraints`,
`design_system_enforcement`, `extraction_spec`, `high_risk_self_check`,
`long_context_handling`, `output_verbosity_spec`, `solution_persistence`,
`tool_usage_rules`, `uncertainty_and_ambiguity`, `user_updates_spec` —
mostly carried over from 5.1, plus a few new `_spec`-suffixed additions

**GPT-5.5 / 5.6 (current, superseding the notebook guides)**: dropped the
XML-tag vocabulary entirely. OpenAI's docs-site "Model Guidance" page for
GPT-5.5 uses a plain Markdown template instead —
`# Personality` / `# Goal` / `# Constraints` / `# Output` / `# Stop rules`.
This is a real format break, not a naming update: verify current guidance
at `developers.openai.com/api/docs/guides/prompt-guidance?model=«model»`
before trusting any tag list here, including this one.

Neither OpenAI's guides nor its docs-site guidance model a dedicated
prohibition tag; OpenAI's own guides still use "never"/"don't" internally
with no stated principle either way.

## Gemini Tags

Verified 2026-07-11 against `ai.google.dev/gemini-api/docs/prompting-strategies`
(Gemini's general, model-family-wide prompting guide — Gemini 3 and 3.5's own
dedicated best-practices pages don't cover tag format at all).

**Officially documented** (found on the Google page above):
`<role>`, `<context>`, `<task>`, `<instructions>`, `<constraints>`,
`<output_format>`, `<final_instruction>`

**NOT officially documented** — traced only to
[philschmid.de/gemini-3-prompt-practices](https://philschmid.de/gemini-3-prompt-practices),
a Google DeepMind engineer's personal blog, not a Google docs property.
Treat these as community convention, not verified official guidance:
`<rules>`, `<planning_process>`, `<error_handling>`

Google's own page states XML tags and Markdown headings are "equally
effective... choose one format and use it consistently" — no preference
either way. Gemini 3.5 (released 2026-05-19) has no dedicated tag guidance
of its own; it defers to the same general page.

## Harmony Format (gpt-oss-120b)

Harmony uses special tokens, NOT XML tags — don't mix formats.

Essential tokens: `<|start|>`, `<|end|>`, `<|message|>`, `<|channel|>`, `<|return|>`

## agentskills.io Tags

- `<available_skills>` - Container for skill index in AGENTS.md
- `<skill name="..." description="...">` - Individual skill entry

## Quick Reference

- **Universal**: `<instructions>`, `<context>`, `<task>`, `<examples>`,
  `<constraints>` — work across platforms
- **Smith runtime-prompt tags**: `<required>`, `<related>`, `<hard_limits>`
  — smith convention, not an official Anthropic taxonomy
- **GPT-5/5.1/5.2 notebook guides**: version-specific vocabularies, see
  above — check which guide is current before reusing a tag name
- **GPT-5.5/5.6 (current)**: plain Markdown, no tags
- **Gemini**: `<role>`, `<output_format>`, `<final_instruction>` officially
  documented; `<rules>`/`<planning_process>`/`<error_handling>` are
  community convention only
- **Harmony**: `<|start|>`, `<|end|>` — special tokens only
- **agentskills.io**: `<available_skills>`, `<skill>` — skill discovery

## Naming Conventions

**Platform-specific patterns:**
- **Claude / smith custom tags**: lowercase concepts (e.g., `<required>`, `<context>`)
- **GPT-5.1/5.2 guides**: snake_case, some with `_spec` suffix (e.g., `<user_updates_spec>`)
- **Gemini (official)**: snake_case (e.g., `<output_format>`, `<final_instruction>`)

**Universal tags** (work across platforms):
- `<context>`, `<instructions>`, `<task>`, `<examples>`, `<constraints>`

## Markdown Rendering

**Blank lines required** after opening and before closing XML tags:

```text
<required>

- List item renders as bullet
- Another item

</required>
```

Without blank lines, markdown renders as literal text.

## Content Organization

- Good examples and bad examples never share one tag or block
- In a runtime prompt: use separate tags/sections per example type
- In a SKILL.md body (plain Markdown, not this file's concern): use
  `### Good` / `### Avoid` subheadings instead — see `@smith-skills/SKILL.md`

## Placeholders

**Use**: Guillemets `«placeholder»` (see `@smith-placeholder/SKILL.md`)
**Avoid**: `<placeholder>` (XML), `[placeholder]` (CLI-optional / links), `{{placeholder}}` (templating)

## Related

- `@smith-prompts/SKILL.md` - Prompt engineering
- `@smith-skills/SKILL.md` - SKILL.md/AGENTS.md authoring (plain Markdown, not this file's tags)
- @smith-guidance/SKILL.md - Agent behavior

## Before Using XML Tags

1. Is this a SKILL.md body? → Don't use tags; see `@smith-skills/SKILL.md` instead
2. Is it a documented tag for the target model/version? → Use it, and note the
   source (official doc vs. community blog)
3. Is it model-specific? → Check compatibility; guide versions change fast
   enough that a tag list can go stale within months (see GPT-5.5/5.6 above)
4. Need markdown inside a tag? → Add blank lines
