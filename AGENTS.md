# Personal Coding Standards (.smith)

<metadata>

- **Scope**: Entry point for personal coding standards
- **Load if**: Starting any development task
- **Prerequisites**: None

</metadata>

<context>

## About This File

This file documents the AI agent's **context-aware capabilities** through dynamic rule loading. Rather than defining separate agent instances, the agent adapts its behavior by loading relevant rule sets based on the current context (file type, operation, task).

**Key Concepts:**
- **Contexts**: Operational modes (e.g., `python_development`, `git_operations`, `testing`)
- **Rules**: Coding standards loaded for each context (e.g., @rules-python.md, @rules-git.md)
- **Dynamic Loading**: Agent loads only relevant rules based on detected context
- **Notifications**: Agent reports which rules are active before proceeding with tasks

See the **Context-Aware Rule Loading** section below for the complete context-to-rules mapping.

</context>

<required>

## Rule Loading Notification

Agent MUST proactively report when rules are dynamically loaded or unloaded. See **Rule Loading Notification Protocol** in the `<instructions>` section below for complete requirements.

</required>

<examples>

**Notification format:**

```text
Rules loaded:
- @rules-python.md (triggered by: python_development context)
- @rules-core.md (triggered by: always_active context)

Rules unloaded:
- @rules-git.md (triggered by: git_operations context no longer active)
```

**Example at session start:**

```text
Rules loaded:
- @AGENTS.md (entry point)
- @rules-core.md (triggered by: always_active context)
- @rules-python.md (triggered by: python_development context)
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

See @rules-ai_agents.md for Helpful, Honest, Harmless principles.

</guiding_principles>

<context>

### Efficiency

- Research with today's date for current information
- Prefer pointers (file:line) over embedded snippets
- Static content first for [prompt caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)

### XML Tag Standards

See @rules-xml_tags.md for approved XML tags with evidence-based references from Anthropic, OpenAI, and Google.

## Context-Aware Rule Loading

<plan_tool_usage>

### Workflow

1. **Detect context** from user request, file type, or current operation
2. **Match context** to applicable rules using mappings below
3. **Report active rules** to user before proceeding with task
4. **Execute task** following those rules

<constraints>

- **MUST** report which rules are loaded before executing any task
- **MUST** match user context to appropriate rule sets
- **MUST** report both loading and unloading when context changes
- **MUST** gracefully skip if referenced rule file does not exist

</constraints>

<rules>

### Context-to-Rules Mapping

**always_active:**
- @rules-core.md (Critical NEVER/ALWAYS rules)

**python_development:**
- Condition: Writing/modifying Python code OR running Python tests
- Load: @rules-python.md

**git_operations:**
- Condition: Performing git commits, merges, or branch management
- Load: @rules-git.md, @rules-naming.md

**pull_request_workflows:**
- Condition: Creating pull requests OR reviewing code OR merging PRs
- Load: @rules-pr-concepts.md (platform-neutral concepts), @rules-github-pr-automation.md (if using GitHub), @rules-github-cli.md, @rules-naming.md

**github_workflows:**
- Condition: Using GitHub CLI OR creating PRs OR managing GitHub features
- Load: @rules-github-cli.md

**modifying_existing_pr:**
- Condition: Working on existing PR OR addressing review comments
- Action: Check for unaddressed review comments BEFORE making changes (see rules-github-pr-automation.md Pre-Work Check)
- Load: @rules-pr-concepts.md (platform-neutral concepts), @rules-github-pr-automation.md (if using GitHub)

**pr_review_response:**
- Condition: Responding to PR review feedback OR resolving review comments
- Load: @rules-pr-concepts.md (platform-neutral concepts), @rules-github-pr-automation.md (review automation)

**pre_commit_hooks:**
- Condition: Pre-commit hooks modify files OR need to amend commits
- Load: @rules-github-utils.md (hook coordination), @rules-git.md

**testing:**
- Condition: Writing or running tests (any language)
- Load: @rules-testing.md

**new_project:**
- Condition: Initializing a new project
- Load: @rules-development.md, @rules-naming.md

**ide_configuration:**
- Condition: Configuring editor/IDE settings
- Load: @rules-tools.md, @rules-ide_mappings.md

**ai_agent_interaction:**
- Condition: Using Claude Code OR GitHub Copilot OR AI pair programming
- Load: @rules-ai_agents.md

**context_management:**
- Condition: Context window approaching capacity (>70%) OR optimizing context usage OR debugging context issues
- Load: @rules-context-principles.md (universal strategies), @rules-context-platforms.md (platform-specific: Claude Code, Cursor, Kiro)
- Action: Monitor context usage, apply selective retention strategies

**prompt_engineering:**
- Condition: Writing or reviewing AI prompts, AGENTS.md files, or rules documentation
- Load: @rules-xml_tags.md

**stacked_pr_parent_merged:**
- Condition: Parent PR in stack just merged OR working on child PR after parent merge
- Load: @rules-pr-stacked.md (stacked PR patterns), @rules-github-pr-automation.md (rebase + post-merge workflows), @rules-git.md, @rules-github-cli.md
- Action: Check if child PRs need rebase, offer to update stack

**pr_maintenance:**
- Condition: Working on existing PR OR updating PR branch OR before requesting review
- Load: @rules-pr-concepts.md (platform-neutral concepts), @rules-github-pr-automation.md (freshness + rebase)
- Action: Check PR freshness relative to base branch, detect conflicts

**pr_review_request:**
- Condition: User asks to request PR review OR agent about to request review
- Load: @rules-pr-concepts.md (platform-neutral concepts), @rules-github-pr-automation.md (pre-review freshness check)
- Action: Verify PR is up-to-date with base, all checks pass, no conflicts

**agent_pr_creation:**
- Condition: Agent about to create PR OR agent analyzing commits for PR
- Load: @rules-pr-concepts.md (platform-neutral concepts), @rules-github-pr-automation.md (PR description generation)

**post_merge_operations:**
- Condition: PR just merged OR immediately after merge operation
- Load: @rules-github-pr-automation.md (post-merge workflows), @rules-github-cli.md
- Action: Check for dependent PRs, offer cascade updates, cleanup branches

### Reporting Format

Rules loaded: @[filename] (triggered by: [context_name] context)

</rules>

</plan_tool_usage>

</context>

<instructions>

## Rule Loading Notification Protocol

Agent MUST proactively report to the user when rules are dynamically loaded or unloaded based on the context-to-rules mapping.

### Notification Requirements

- Report at the start of your response when rules are loaded/unloaded, before proceeding with the task
- Include both the rule files and the context triggers that caused the load/unload
- Format: List each rule file with its triggering context
- If a referenced rule file does not exist, report that it was skipped gracefully

### When to Report

1. **At session start**: Report all initially loaded rules
2. **Before EACH task**: Detect applicable contexts, report which rules are loaded
3. **When context changes**: Report unloading old rules, loading new rules

### Report Format

"Rules loaded: @[filename] (triggered by: [context_name] context)"

### Workflow

1. **Detect context** from user request, file type, or current operation
2. **Match context** to applicable rules using context-to-rules mapping
3. **Report active rules** to user before proceeding with task
4. **Execute task** following those rules

</instructions>

<note>

These standards are **optional**. If a referenced file does not exist, skip it gracefully.

</note>
