---
name: smith-xml
description: XML tag standards for AI prompts and documentation. Use when writing prompts, documentation, or AGENTS.md files. Covers approved tags for Claude, GPT-5, Gemini, and Harmony formats with markdown rendering rules.
---

# XML Tag Standards

<metadata>

- **Load if**: Writing prompts, documentation, AGENTS.md files
- **Prerequisites**: None

</metadata>

## CRITICAL: Approved Tags Only (Primacy Zone)

<required>

Only use well-established XML tags. Do NOT invent placeholder-style tags.

</required>

## Universal Tags (All Platforms)

- `<instructions>` - Step-by-step guidance
- `<task>` - Specific user request
- `<context>` - Background information
- `<examples>` - Few-shot examples
- `<constraints>` - Behavioral limitations

## Claude-Specific Tags

- `<metadata>` - File/component metadata
- `<forbidden>` - Prohibited actions
- `<required>` - Mandatory requirements
- `<related>` - Cross-references
- `<formatting>` - Output format specs
- `<thinking>` - Chain-of-thought reasoning
- `<answer>` - Final output

## Tag Selection Criteria

<required>

**`<required>` = "DO this"** (imperative, mandatory behavior)
- Agent MUST follow; failure causes incorrect behavior
- Use for: MUST/ALWAYS/NEVER statements, mandatory behaviors, action directives

**`<context>` = "KNOW this"** (informational, may deprioritize)
- Agent uses to inform decisions; not mandatory
- Use for: Explanations, methodologies, background, reference material

</required>

## GPT-5.x Tags (Updated Dec 2025)

**GPT-5/5.1 Tags:**
- `<plan_tool_usage>` - Planning and task management
- `<context_gathering>` - Search depth strategy
- `<exploration>` - Codebase investigation
- `<verification>` - Testing requirements
- `<code_editing_rules>` - Coding standards
- `<guiding_principles>` - Foundational philosophies
- `<final_instructions>` - Critical closing directives

**GPT-5.2 Tags (Dec 2025):**
- `<planning>` - Scaffolds reasoning before execution
- `<response>` - Contains output after planning phase
- `<solution_persistence>` - Maintains global context across agent turns
- `<user_updates_spec>` - Defines scope boundaries
- `<tool_preambles>` - Tool usage instructions
- `<output_verbosity_spec>` - Output length/format constraints

**Pattern**: GPT-5.2 favors `_spec` suffix for instruction categories

## Gemini 3 Tags (Updated Nov 2025)

- `<role>` - Assistant identity
- `<rules>` - Behavioral guidelines
- `<planning_process>` - Analysis workflow
- `<error_handling>` - Error management
- `<context>` - Background info (universal)
- `<instructions>` - Step-by-step guidance (universal)
- `<constraints>` - Parameters (universal)
- `<output_format>` - Response structure
- `<task>` - User request (universal)
- `<final_instruction>` - Closing directive (recency zone)

**Pattern**: Gemini 3 uses snake_case, prefers direct/concise prompts

## Harmony Format (gpt-oss-120b)

<forbidden>

Harmony uses special tokens, NOT XML tags. Do not mix formats.

</forbidden>

<required>

Essential tokens: `<|start|>`, `<|end|>`, `<|message|>`, `<|channel|>`, `<|return|>`

</required>

## agentskills.io Tags

- `<available_skills>` - Container for skill index in AGENTS.md
- `<skill name="..." description="...">` - Individual skill entry

## Quick Reference

- **Claude**: `<required>`, `<forbidden>`, `<context>` - Instructions, constraints
- **GPT-5.2**: `<planning>`, `<response>`, `*_spec` tags - Agentic workflows
- **Gemini 3**: `<rules>`, `<planning_process>`, `<output_format>` - Structured output
- **Harmony**: `<|start|>`, `<|end|>` - Special tokens only
- **agentskills.io**: `<available_skills>`, `<skill>` - Skill discovery

## Naming Conventions

<context>

**Platform-specific patterns:**
- **Claude**: lowercase concepts (e.g., `<required>`, `<forbidden>`, `<context>`)
- **GPT-5.2**: snake_case with `_spec` suffix (e.g., `<user_updates_spec>`, `<output_verbosity_spec>`)
- **Gemini 3**: snake_case (e.g., `<planning_process>`, `<error_handling>`)

**Universal tags** (work across platforms):
- `<context>`, `<instructions>`, `<task>`, `<examples>`, `<constraints>`

</context>

## Markdown Rendering

<required>

**Blank lines required** after opening and before closing XML tags:

```text
<required>

- List item renders as bullet
- Another item

</required>
```

Without blank lines, markdown renders as literal text.

</required>

## Content Organization

<required>

- Good examples → `<examples>` only
- Bad examples → `<forbidden>` only
- NEVER mix good and bad in same tag

</required>

## Placeholders

<required>

**Use**: Backticks `` `placeholder` `` or brackets `[placeholder]`
**Avoid**: `<placeholder>`, `{{placeholder}}`

</required>

<related>

- `@smith-prompts/SKILL.md` - Prompt engineering
- @smith-guidance/SKILL.md - Agent behavior

</related>

## ACTION (Recency Zone)

<required>

**Before using XML tags:**
1. Is it a documented tag? → Use it
2. Is it model-specific? → Check compatibility
3. Need markdown inside? → Add blank lines

</required>
