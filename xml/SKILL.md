---
name: xml
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

## GPT-5/5.1 Tags

- `<plan_tool_usage>` - Planning and task management
- `<context_gathering>` - Search depth strategy
- `<exploration>` - Codebase investigation
- `<verification>` - Testing requirements
- `<code_editing_rules>` - Coding standards
- `<guiding_principles>` - Foundational philosophies
- `<final_instructions>` - Critical closing directives

## Gemini Tags

- `<role>` - Assistant identity
- `<output_format>` - Response structure
- `<rules>` - Behavioral guidelines
- `<planning_process>` - Analysis steps
- `<final_instruction>` - Critical closing directive

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
- **GPT-5**: `<plan_tool_usage>`, `<final_instructions>` - Planning, task management
- **Gemini**: `<rules>`, `<output_format>` - Structured output
- **Harmony**: `<|start|>`, `<|end|>` - Special tokens only
- **agentskills.io**: `<available_skills>`, `<skill>` - Skill discovery

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

- `@prompts/SKILL.md` - Prompt engineering
- @guidance/SKILL.md - Agent behavior

</related>

## ACTION (Recency Zone)

<required>

**Before using XML tags:**
1. Is it a documented tag? → Use it
2. Is it model-specific? → Check compatibility
3. Need markdown inside? → Add blank lines

</required>
