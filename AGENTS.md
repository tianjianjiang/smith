# Personal Coding Standards (.smith)

<metadata>

- **Scope**: Entry point for personal coding standards
- **Load if**: Starting any development task
- **Prerequisites**: None

</metadata>

<required>

## Rule Loading Notification

Agent MUST proactively report to the user when rules are dynamically loaded or unloaded based on context triggers defined in the `<context_triggers>` section below.

**Notification requirements:**
- Report at the start of your response when rules are loaded/unloaded, before proceeding with the task
- Include both the rule files and the context triggers that caused the load/unload
- Format: List each rule file with its triggering context
- If a referenced rule file does not exist, report that it was skipped gracefully

**When to report:**
- At session start: Report all initially loaded rules
- During session: Report when context changes trigger new rule loads
- During session: Report when context changes cause previously loaded rules to no longer apply (i.e., when rules are unloaded due to context changes)

This notification is always active.

</required>

<examples>

**Notification format:**

```text
Rules loaded:
- rules-python.md (triggered by: python_development context)
- rules-core.md (triggered by: always_active context)

Rules unloaded:
- rules-git.md (triggered by: git_operations context no longer active)
```

**Example at session start:**

```text
Rules loaded:
- AGENTS.md (entry point)
- rules-core.md (triggered by: always_active context)
- rules-python.md (triggered by: python_development context)
```

</examples>

<guiding_principles>

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

</guiding_principles>

<context>

### Efficiency

- Research with today's date for current information
- Prefer pointers (file:line) over embedded snippets
- Static content first for [prompt caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)

### XML Tag Standards

See `rules-xml_tags.md` for approved XML tags with evidence-based references from Anthropic, OpenAI, and Google.

</context>

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
- **LOAD**: `$HOME/.smith/rules-pr-concepts.md` (platform-neutral concepts)
- **LOAD**: `$HOME/.smith/rules-github-pr.md` (if using GitHub)
- **LOAD**: `$HOME/.smith/rules-github.md`
- **LOAD**: `$HOME/.smith/rules-naming.md`

</trigger>

<trigger context="github_workflows">

- **IF** using GitHub CLI OR creating PRs OR managing GitHub features:
- **LOAD**: `$HOME/.smith/rules-github.md`

</trigger>

<trigger context="modifying_existing_pr">

- **IF** working on existing PR OR addressing review comments:
- **ACTION**: Check for unaddressed review comments BEFORE making changes (see rules-github-review.md Pre-Work Check)
- **LOAD**: `$HOME/.smith/rules-pr-concepts.md` (platform-neutral concepts)
- **LOAD**: `$HOME/.smith/rules-github-pr.md` (if using GitHub)
- **LOAD**: `$HOME/.smith/rules-github-review.md` (review automation)

</trigger>

<trigger context="pr_review_response">

- **IF** responding to PR review feedback OR resolving review comments:
- **LOAD**: `$HOME/.smith/rules-pr-concepts.md` (platform-neutral concepts)
- **LOAD**: `$HOME/.smith/rules-github-review.md` (review automation)

</trigger>

<trigger context="pre_commit_hooks">

- **IF** pre-commit hooks modify files OR need to amend commits:
- **LOAD**: `$HOME/.smith/rules-github-utils.md` (hook coordination)
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

<trigger context="context_management">

- **IF** context window approaching capacity (>70%) OR optimizing context usage OR debugging context issues:
- **LOAD**: `$HOME/.smith/rules-context-principles.md` (universal strategies)
- **LOAD**: `$HOME/.smith/rules-context-claude_code.md` (if using Claude Code)
- **LOAD**: `$HOME/.smith/rules-context-cursor.md` (if using Cursor)
- **LOAD**: `$HOME/.smith/rules-context-kiro.md` (if using Kiro OR creating steering files)
- **ACTION**: Monitor context usage, apply selective retention strategies

</trigger>

<trigger context="prompt_engineering">

- **IF** writing or reviewing AI prompts, AGENTS.md files, or rules documentation:
- **LOAD**: `$HOME/.smith/rules-xml_tags.md`

</trigger>

<trigger context="always_active">

- **ALWAYS LOAD**: `$HOME/.smith/rules-core.md` (Critical NEVER/ALWAYS rules)

</trigger>

<trigger context="stacked_pr_parent_merged">

- **IF** parent PR in stack just merged OR working on child PR after parent merge:
- **LOAD**: `$HOME/.smith/rules-pr-concepts.md` (stacked PRs)
- **LOAD**: `$HOME/.smith/rules-github-rebase.md` (rebase workflows)
- **LOAD**: `$HOME/.smith/rules-github-merge.md` (post-merge cascade)
- **LOAD**: `$HOME/.smith/rules-git.md`
- **LOAD**: `$HOME/.smith/rules-github.md`
- **ACTION**: Check if child PRs need rebase, offer to update stack

</trigger>

<trigger context="pr_maintenance">

- **IF** working on existing PR OR updating PR branch OR before requesting review:
- **LOAD**: `$HOME/.smith/rules-pr-concepts.md` (platform-neutral concepts)
- **LOAD**: `$HOME/.smith/rules-github-rebase.md` (freshness + rebase)
- **ACTION**: Check PR freshness relative to base branch, detect conflicts

</trigger>

<trigger context="pr_review_request">

- **IF** user asks to request PR review OR agent about to request review:
- **LOAD**: `$HOME/.smith/rules-pr-concepts.md` (platform-neutral concepts)
- **LOAD**: `$HOME/.smith/rules-github-rebase.md` (pre-review freshness check)
- **ACTION**: Verify PR is up-to-date with base, all checks pass, no conflicts

</trigger>

<trigger context="agent_pr_creation">

- **IF** agent about to create PR OR agent analyzing commits for PR:
- **LOAD**: `$HOME/.smith/rules-pr-concepts.md` (platform-neutral concepts)
- **LOAD**: `$HOME/.smith/rules-github-create.md` (PR description generation)

</trigger>

<trigger context="post_merge_operations">

- **IF** PR just merged OR immediately after merge operation:
- **LOAD**: `$HOME/.smith/rules-github-merge.md` (post-merge workflows)
- **LOAD**: `$HOME/.smith/rules-github.md`
- **ACTION**: Check for dependent PRs, offer cascade updates, cleanup branches

</trigger>

</context_triggers>

<note>

These standards are **optional**. If a referenced file does not exist, skip it gracefully.

</note>
