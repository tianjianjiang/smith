# Personal Coding Standards (.smith)

<metadata>

- **Scope**: Entry point for personal coding standards
- **Load if**: Starting any development task
- **Prerequisites**: None

</metadata>

## Design Principles

- [**DRY**](https://en.wikipedia.org/wiki/Don%27t_repeat_yourself): Don't Repeat Yourself
- [**KISS**](https://en.wikipedia.org/wiki/KISS_principle): Keep It Simple, Stupid
- [**YAGNI**](https://en.wikipedia.org/wiki/You_aren%27t_gonna_need_it): You Aren't Gonna Need It
- [**MECE**](https://en.wikipedia.org/wiki/MECE_principle): Mutually Exclusive, Collectively Exhaustive

### [SOLID](https://en.wikipedia.org/wiki/SOLID)

- **S**ingle Responsibility: One reason to change per class/module
- **O**pen/Closed: Open for extension, closed for modification
- **L**iskov Substitution: Subtypes must be substitutable for base types
- **I**nterface Segregation: Many specific interfaces over one general
- **D**ependency Inversion: Depend on abstractions, not concretions

### [Constitutional AI](https://www.anthropic.com/research/constitutional-ai-harmlessness-from-ai-feedback) (HHH)

See `rules-ai_agents.md` for Helpful, Honest, Harmless principles.

### Efficiency

- Research with today's date for current information
- Prefer pointers (file:line) over embedded snippets
- Static content first for [prompt caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)

### XML Tag Standards

See `rules-xml_tags.md` for approved XML tags with evidence-based references from Anthropic, OpenAI, and Google.

<context_triggers>

<!-- Load these files ONLY if the specific context applies -->

<trigger context="python_development">

- **IF** writing/modifying Python code OR running python tests:
- **LOAD**: `$HOME/.smith/rules-python.md`

</trigger>

<trigger context="git_operations">

- **IF** performing git commits, merges, or branch management:
- **LOAD**: `$HOME/.smith/rules-git.md`
- **LOAD**: `$HOME/.smith/rules-naming.md`

</trigger>

<trigger context="pull_request_workflows">

- **IF** creating pull requests OR reviewing code OR merging PRs:
- **LOAD**: `$HOME/.smith/rules-pr.md`
- **LOAD**: `$HOME/.smith/rules-github.md`
- **LOAD**: `$HOME/.smith/rules-naming.md`

</trigger>

<trigger context="github_workflows">

- **IF** using GitHub CLI OR creating PRs OR managing GitHub features:
- **LOAD**: `$HOME/.smith/rules-github.md`

</trigger>

<trigger context="modifying_existing_pr">

- **IF** working on existing PR OR addressing review comments:
- **LOAD**: `$HOME/.smith/rules-pr.md`

</trigger>

<trigger context="pr_review_response">

- **IF** responding to PR review feedback OR resolving review comments:
- **LOAD**: `$HOME/.smith/rules-pr.md`

</trigger>

<trigger context="pre_commit_hooks">

- **IF** pre-commit hooks modify files OR need to amend commits:
- **LOAD**: `$HOME/.smith/rules-pr.md`
- **LOAD**: `$HOME/.smith/rules-git.md`

</trigger>

<trigger context="testing">

- **IF** writing or running tests (any language):
- **LOAD**: `$HOME/.smith/rules-testing.md`

</trigger>

<trigger context="new_project">

- **IF** initializing a new project:
- **LOAD**: `$HOME/.smith/rules-development.md`
- **LOAD**: `$HOME/.smith/rules-naming.md`

</trigger>

<trigger context="ide_configuration">

- **IF** configuring editor/IDE settings:
- **LOAD**: `$HOME/.smith/rules-tools.md`
- **LOAD**: `$HOME/.smith/rules-ide_mappings.md`

</trigger>

<trigger context="ai_agent_interaction">

- **IF** using Claude Code OR GitHub Copilot OR AI pair programming:
- **LOAD**: `$HOME/.smith/rules-ai_agents.md`

</trigger>

<trigger context="prompt_engineering">

- **IF** writing or reviewing AI prompts, AGENTS.md files, or rules documentation:
- **LOAD**: `$HOME/.smith/rules-xml_tags.md`

</trigger>

<trigger context="always_active">

- **ALWAYS LOAD**: `$HOME/.smith/rules-core.md` (Critical NEVER/ALWAYS rules)

</trigger>

</context_triggers>

<note>

These standards are **optional**. If a referenced file does not exist, skip it gracefully.

</note>
