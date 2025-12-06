# XML Tag Standards

<metadata>

- **Scope**: XML tag usage in prompts and documentation
- **Load if**: Writing or reviewing prompts, documentation, or AGENTS.md files
- **Prerequisites**: None

</metadata>

## Approved XML Tags

<required>

Only use XML tags that are well-established in AI prompt engineering literature.
Do NOT invent placeholder-style tags like `<type>`, `<scope>`, or `<description>`.

</required>

### Anthropic Claude Tags

**Reference**: [Use XML tags to structure your prompts](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/use-xml-tags)

| Tag | Purpose | Example |
|-----|---------|---------|
| `<metadata>` | File/component metadata | Load conditions, scope |
| `<dependencies>` | Dependency information | Required files, prerequisites |
| `<instructions>` | Direct commands to AI | Step-by-step guidance |
| `<background_information>` | Context setting | Domain knowledge |
| `<examples>` | Few-shot examples | Correct patterns |
| `<thinking>` | Chain-of-thought | Step-by-step reasoning |
| `<answer>` | Final output | Clean result after thinking |
| `<context>` | Contextual information | Surrounding details |
| `<formatting>` | Output format specs | Patterns, templates |
| `<trigger>` | Conditional loading | Context-based file loading |
| `<forbidden>` | Prohibited actions | Anti-patterns, mistakes |
| `<required>` | Mandatory requirements | Must-do rules |
| `<related>` | Cross-references | Links to other files |

**Chain-of-Thought Reference**: [Let Claude think](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/chain-of-thought)

### OpenAI GPT-5/5.1 Tags

**References**:

- [GPT-5 Prompting Guide](https://cookbook.openai.com/examples/gpt-5/gpt-5_prompting_guide)
- [GPT-5.1 Prompting Guide](https://cookbook.openai.com/examples/gpt-5/gpt-5-1_prompting_guide)

| Tag | Purpose | Example |
|-----|---------|---------|
| `<plan_tool_usage>` | Planning and task management | Before function calls |
| `<context_gathering>` | Search depth strategy | Information collection |
| `<exploration>` | Codebase investigation | Before implementation |
| `<verification>` | Testing requirements | Quality checks |
| `<persistence>` | Agent continuation behavior | Until task completion |
| `<self_reflection>` | Internal quality evaluation | Rubrics |
| `<code_editing_rules>` | Coding standards | Subsections |
| `<guiding_principles>` | Foundational philosophies | Engineering tenets |
| `<tool_preambles>` | Agent communication patterns | Before tool calls |
| `<efficiency>` | Time-conscious execution | Optimization |
| `<instructions>` | Operational guidelines | Technical constraints |

**GPT-5.1 Additional Tags**:

| Tag | Purpose | Example |
|-----|---------|---------|
| `<final_answer_formatting>` | Output structure rules | Length, format |
| `<output_verbosity_spec>` | Response conciseness | Content priority |
| `<user_updates_spec>` | Progress update rules | Frequency, tone |
| `<solution_persistence>` | Autonomous completion | No early termination |
| `<design_system_enforcement>` | UI component styling | Design tokens |

### Google Gemini 2.5/3 Tags

**References**:

- [Gemini API Prompting Strategies](https://ai.google.dev/gemini-api/docs/prompting-strategies)
- [Gemini 3 Prompting Best Practices](https://www.philschmid.de/gemini-3-prompt-practices)

| Tag | Purpose | Example |
|-----|---------|---------|
| `<role>` | Assistant identity/expertise | Persona definition |
| `<instructions>` | Step-by-step procedures | Plan, Execute, Validate |
| `<constraints>` | Behavioral limitations | Verbosity, tone |
| `<context>` | Background information | Data, situation |
| `<task>` | Specific user request | The actual question |
| `<output_format>` | Response structure | JSON, markdown, etc. |
| `<rules>` | Behavioral guidelines | Cite sources, be objective |
| `<planning_process>` | Analysis steps | Decomposition, strategy |
| `<error_handling>` | Edge case responses | Missing data handling |
| `<final_instruction>` | Critical closing directive | Before execution |

## Placeholder Alternatives

<forbidden>

Do NOT use XML-like placeholders:

- `<type>` → Use backticks: `type`
- `<scope>` → Use backticks: `scope`
- `<description>` → Use backticks: `description`

</forbidden>

<formatting>

**For patterns/templates**, use one of:

1. **Backtick literals**: `type/descriptive_name`
2. **Jinja2 variables**: `{{ variable_name }}`
3. **Shell-style**: `${VARIABLE_NAME}`
4. **Bracket placeholders**: `[placeholder]`

</formatting>

<examples>

**Approved placeholder styles**:

```text
**Pattern**: `type: description` or `type(scope): description`
**Template**: {{ branch_type }}/{{ feature_name }}
```

</examples>

<forbidden>

**XML-like placeholders** (do not use):

```text
**Pattern**: <type>: <description>
**Template**: <branch_type>/<feature_name>
```

</forbidden>

## Related Standards

- **Naming Conventions**: `$HOME/.smith/rules-naming.md` - General naming rules
- **Git Standards**: `$HOME/.smith/rules-git.md` - Branch and commit naming
- **AI Agent Guidelines**: `$HOME/.smith/rules-ai_agents.md` - Agent interaction patterns
