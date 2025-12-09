# XML Tag Standards

<metadata>

- **Scope**: XML tag usage in prompts and documentation
- **Load if**: Writing or reviewing prompts, documentation, or AGENTS.md files
- **Prerequisites**: None

</metadata>

<context>

## Approved XML Tags

**Cross-Model Compatibility**: Many tags work across different models. Common tags like `<instructions>`, `<task>`, `<context>`, `<examples>`, and `<constraints>` are widely supported across Claude, GPT-5/5.1, Codex, and Gemini models. However, model-specific tags (e.g., `<plan_tool_usage>` for GPT-5/5.1, `<thinking>` for Claude) should only be used with their intended models. When in doubt, use generic tags that are documented for your target model.

</context>

<required>

Only use XML tags that are well-established in AI prompt engineering literature.
Do NOT invent placeholder-style tags like `<type>`, `<scope>`, or `<description>`.

</required>

### Anthropic Claude Tags

**Reference**: [Use XML tags to structure your prompts](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/use-xml-tags)

| Tag                        | Purpose                 | Example                       |
| -------------------------- | ----------------------- | ----------------------------- |
| `<metadata>`               | File/component metadata | Load conditions, scope        |
| `<instructions>`           | Direct commands to AI   | Step-by-step guidance         |
| `<background_information>` | Context setting         | Domain knowledge              |
| `<examples>`               | Few-shot examples       | Correct patterns              |
| `<thinking>`               | Chain-of-thought        | Step-by-step reasoning        |
| `<answer>`                 | Final output            | Clean result after thinking   |
| `<context>`                | Contextual information  | Surrounding details           |
| `<formatting>`             | Output format specs     | Patterns, templates           |
| `<forbidden>`              | Prohibited actions      | Anti-patterns, mistakes       |
| `<required>`               | Mandatory requirements  | Must-do rules                 |
| `<related>`                | Cross-references        | Links to other files          |

**Chain-of-Thought Reference**: [Let Claude think](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/chain-of-thought)

### OpenAI GPT-5/5.1 Tags

**References**:

- [GPT-5 Prompting Guide](https://cookbook.openai.com/examples/gpt-5/gpt-5_prompting_guide)
- [GPT-5.1 Prompting Guide](https://cookbook.openai.com/examples/gpt-5/gpt-5-1_prompting_guide)

**Note**: OpenAI Cookbook provides examples of XML tag usage but does not maintain an official comprehensive list. The tags below are documented in cookbook examples and guides. Tags can be nested and customized based on specific use cases.

**Phrasal XML Tag Format**: GPT-5 family models use an implicit phrasal format for XML tags, where multi-word concepts are expressed as single tags with underscores connecting words (e.g., `<plan_tool_usage>`, `<context_gathering>`, `<code_editing_rules>`). This naming convention creates descriptive, self-documenting tag names that clearly indicate their purpose. While simple tags like `<task>` and `<instructions>` are also supported, the phrasal format is preferred for complex, domain-specific instructions in GPT-5/5.1 models.

| Tag                                      | Purpose                        | Example                                                |
| ---------------------------------------- | ------------------------------ | ------------------------------------------------------ |
| `<instructions>`                         | Operational guidelines         | Technical constraints, step-by-step procedures         |
| `<plan_tool_usage>`                      | Planning and task management   | Guidelines for creating and maintaining task plans     |
| `<context_gathering>`                    | Search depth strategy          | Information collection methods and early stop criteria |
| `<exploration>`                          | Codebase investigation         | Strategies before implementation                       |
| `<verification>`                         | Testing requirements           | Quality checks and validation                          |
| `<persistence>`                          | Agent continuation behavior    | Task completion guidelines                             |
| `<self_reflection>`                      | Internal quality evaluation    | Rubrics for self-assessment                            |
| `<code_editing_rules>`                   | Coding standards               | Guidelines with nested subsections                     |
| `<guiding_principles>`                   | Foundational philosophies      | Engineering tenets (often nested in other tags)        |
| `<tool_preambles>`                       | Agent communication patterns   | Patterns before tool calls                             |
| `<efficiency>`                           | Time-conscious execution       | Optimization strategies                                |
| `<apply_patch>`                          | Patch application guidelines   | Code change procedures                                 |
| `<final_instructions>`                   | Critical closing directives    | Final steps before completion                          |
| `<efficient_context_understanding_spec>` | Context gathering optimization | Methods for quick context collection                   |
| `<task>`                                 | Specific user request          | The actual question or objective                       |

**GPT-5.1 Additional Tags**:

| Tag                           | Purpose                | Example                         |
| ----------------------------- | ---------------------- | ------------------------------- |
| `<final_answer_formatting>`   | Output structure rules | Length, format specifications   |
| `<output_verbosity_spec>`     | Response conciseness   | Content priority and verbosity  |
| `<user_updates_spec>`         | Progress update rules  | Frequency, tone for updates     |
| `<solution_persistence>`      | Autonomous completion  | No early termination guidelines |
| `<design_system_enforcement>` | UI component styling   | Design tokens and styling rules |

**Tag Nesting Examples**:

Tags can be nested to create hierarchical structures. Common nesting patterns:

```xml
<code_editing_rules>
<guiding_principles>
- Clarity and Reuse: Every component should be modular
- Consistency: UI must adhere to design system
- Simplicity: Favor small, focused components
</guiding_principles>
<frontend_stack_defaults>
- Framework: Next.js (TypeScript)
- Styling: TailwindCSS
</frontend_stack_defaults>
</code_editing_rules>
```

```xml
<context_gathering>
<goal>Extract key performance metrics</goal>
<method>Focus on quantitative data</method>
<early_stop_criteria>Stop after finding 5 key metrics</early_stop_criteria>
</context_gathering>
```

### OpenAI GPT-5.1-Codex and GPT-5.1-Codex-Max Tags

**References**:

- [GPT-5.1-Codex-Max Prompting Guide](https://cookbook.openai.com/examples/gpt-5/gpt-5-1-codex-max_prompting_guide)

**Note**: GPT-5.1-Codex and GPT-5.1-Codex-Max share the same prompting guide and do not have specific XML tag documentation. The prompting guides focus on general best practices for code formatting, structure, tone, and file references. For structured prompts, you may use XML tags similar to GPT-5/5.1 models, organizing content hierarchically as needed.

**Recommended Approach**: Use XML tags to structure prompts following GPT-5/5.1 patterns, organizing sections such as:
- `<instructions>` for coding guidelines
- `<examples>` for code samples
- `<task>` for specific objectives
- `<constraints>` for limitations and requirements
- `<context_gathering>` with nested tags for structured context collection

**Nested Tag Example for Codex Models**:

```xml
<context_gathering>
<goal>Extract key performance metrics from the report</goal>
<method>Focus on quantitative data and year-over-year comparisons</method>
<early_stop_criteria>Stop after finding 5 key metrics</early_stop_criteria>
</context_gathering>
<task>
Analyze the attached financial report and identify the most important metrics.
</task>
<instructions>
- Use structured code references with file paths and line numbers
- Maintain concise, factual tone
- Avoid nested bullets and ANSI codes
</instructions>
```

### OpenAI gpt-oss-120b Harmony Format

**References**:

- [OpenAI Harmony Response Format](https://cookbook.openai.com/articles/openai-harmony)
- [gpt-oss-120b Model Card](https://cdn.openai.com/pdf/419b6906-9da6-406c-a19d-1bb078ac7637/oai_gpt-oss_model_card.pdf)

<required>

**Important**: The `gpt-oss-120b` model uses the Harmony response format, which employs **special tokens** (NOT XML tags) to structure conversations. These tokens are part of the `o200k_harmony` tokenizer vocabulary and are used in model responses, not in prompts. Do NOT use Harmony tokens as XML tags in prompts for other models.

</required>

**Note**: Harmony format uses special tokens like `<|start|>` and `<|end|>` which appear similar to XML but are actually single tokens in the tokenizer. In Markdown tables, these are shown with escaped pipes (`<\|start\|>`) for display purposes, but in actual usage they appear as `<|start|>` without escaping.

**Special Tokens**:

| Token             | Purpose                                  | Example                           |
| ----------------- | ---------------------------------------- | --------------------------------- |
| `<\|start\|>`     | Marks the beginning of a message         | Message boundary start            |
| `<\|end\|>`       | Indicates the end of a message           | Message boundary end              |
| `<\|message\|>`   | Separates header from content            | Content delimiter                 |
| `<\|channel\|>`   | Specifies channel for assistant messages | `analysis`, `final`, `commentary` |
| `<\|constrain\|>` | Data type specification                  | Tool call parameter types         |
| `<\|call\|>`      | Marks a tool invocation                  | Tool call indicator               |
| `<\|return\|>`    | Indicates completion of response         | Response termination              |

**Roles** (message types):

- `system`: Defines reasoning effort, knowledge cutoff, built-in tools
- `developer`: Provides model instructions and available function tools
- `user`: Represents end-user input
- `assistant`: Model outputs (tool calls or message responses)
- `tool`: Messages representing tool call outputs

**Channels** (for assistant messages):

- `final`: User-facing responses intended for end-users
- `analysis`: Model's chain-of-thought reasoning
- `commentary`: Function tool calls and preambles to multiple function calls

**Example Format**:

```text
<|start|>user<|message|>What is 2 + 2?<|end|>
<|start|>assistant<|channel|>analysis<|message|>User asks: "What is 2 + 2?" Simple arithmetic. Provide answer.<|end|>
<|start|>assistant<|channel|>final<|message|>2 + 2 = 4.<|return|>
```

**Role Hierarchy**: System > Developer > User > Assistant > Tool (used to resolve instruction conflicts)

### Google Gemini 2.5/3 Tags

**References**:

- [Gemini API Prompting Strategies](https://ai.google.dev/gemini-api/docs/prompting-strategies)
- [Gemini 3 Prompting Best Practices](https://www.philschmid.de/gemini-3-prompt-practices)

| Tag                   | Purpose                      | Example                    |
| --------------------- | ---------------------------- | -------------------------- |
| `<role>`              | Assistant identity/expertise | Persona definition         |
| `<instructions>`      | Step-by-step procedures      | Plan, Execute, Validate    |
| `<constraints>`       | Behavioral limitations       | Verbosity, tone            |
| `<context>`           | Background information       | Data, situation            |
| `<task>`              | Specific user request        | The actual question        |
| `<output_format>`     | Response structure           | JSON, markdown, etc         |
| `<rules>`             | Behavioral guidelines        | Cite sources, be objective |
| `<planning_process>`  | Analysis steps               | Decomposition, strategy    |
| `<error_handling>`    | Edge case responses          | Missing data handling      |
| `<final_instruction>` | Critical closing directive   | Before execution           |

## Quick Reference: Commonly Used Tags

<context>

**Cross-Model Tags**: These tags are commonly supported across multiple models and can be used as a starting point for structured prompts.

</context>

| Tag              | Claude | GPT-5/5.1 | Codex | Gemini | Purpose                      |
| ---------------- | ------ | --------- | ----- | ------ | ---------------------------- |
| `<instructions>` | Yes    | Yes       | Yes   | Yes    | Step-by-step guidance        |
| `<task>`         | Yes    | Yes       | Yes   | Yes    | Specific user request        |
| `<context>`      | Yes    | Yes       | Yes   | Yes    | Background information       |
| `<examples>`     | Yes    | Yes       | Yes   | Yes    | Few-shot examples            |
| `<constraints>`  | Yes    | Yes       | Yes   | Yes    | Behavioral limitations       |
| `<role>`         | No     | No        | No    | Yes    | Assistant identity/expertise |
| `<formatting>`   | Yes    | No        | No    | No     | Output format specifications |
| `<thinking>`     | Yes    | No        | No    | No     | Chain-of-thought reasoning   |
| `<answer>`       | Yes    | No        | No    | No     | Final output after thinking  |

**Model-Specific Tags**: Use these only with their intended models:

- **Claude**: `<metadata>`, `<background_information>`, `<forbidden>`, `<required>`, `<related>`
- **GPT-5/5.1**: `<plan_tool_usage>`, `<context_gathering>`, `<exploration>`, `<verification>`, `<persistence>`, `<self_reflection>`, `<code_editing_rules>`, `<guiding_principles>`, `<tool_preambles>`, `<efficiency>`, `<apply_patch>`, `<final_instructions>`
- **Gemini**: `<output_format>`, `<rules>`, `<planning_process>`, `<error_handling>`, `<final_instruction>`

## Markdown Rendering with XML Tags

<context>

**Blank lines are required** for proper markdown rendering inside XML tags.

</context>

<required>

**Blank lines are required** after opening XML tags and before closing XML tags for proper markdown rendering. Without blank lines, markdown inside XML tags renders as literal text.

</required>

<formatting>

**Correct XML tag structure**:

```text
<required>

- List item renders as bullet
- Another item

</required>
```

**Incorrect** (renders as literal text):

```text
<required>
- This won't render as a bullet
- Neither will this
</required>
```

</formatting>

<examples>

**Elements requiring blank lines inside XML**:

1. **Bullet lists** (`-`, `*`, `+`)
2. **Numbered lists** (`1.`, `2.`)
3. **Code blocks** (triple backticks)
4. **Blockquotes** (`>`)
5. **Headers** (`#`, `##`)
6. **Tables** (`|---|---|`)

</examples>

## Content Organization Rules

<required>

**Logical separation of examples**:
- Good examples/correct patterns → ONLY in `<examples>` tags
- Bad examples/anti-patterns → ONLY in `<forbidden>` tags
- NEVER mix good and bad patterns in the same XML tag

**Content format flexibility**:
- Content inside XML tags doesn't have to be code blocks
- Use bullet lists when more concise than code blocks
- Use plain text with inline code (backticks) when appropriate
- Use tables for structured comparisons
- Choose the most readable format for each case

</required>

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

<related>

- **Naming Conventions**: @rules-naming.md - General naming rules
- **Git Standards**: @rules-git.md - Branch and commit naming
- **AI Agent Guidelines**: @rules-ai_agents.md - Agent interaction patterns

</related>
