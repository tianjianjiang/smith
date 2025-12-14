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
- **Rules**: Coding standards loaded for each context (e.g., @python.md, @git.md)
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
- @python.md (triggered by: python_development context)
- @core.md (triggered by: always_active context)

Rules unloaded:
- @git.md (triggered by: git_operations context no longer active)
```

**Example at session start:**

```text
Rules loaded:
- @core.md (triggered by: always_active context)
- @steering.md (triggered by: always_active context)
- @python.md (triggered by: python_development context)
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

See @steering.md for Helpful, Honest, Harmless principles.

</guiding_principles>

<context>

### Efficiency

- Research with today's date for current information
- Prefer pointers (file:line) over embedded snippets
- Static content first for [prompt caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)

### XML Tag Standards

See @xml.md for approved XML tags with evidence-based references from Anthropic, OpenAI, and Google.

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
- @core.md (Critical NEVER/ALWAYS rules)
- @steering.md (Anti-sycophancy, Socratic questioning, truthfulness, Constitutional AI)

**python_development:**
- Condition: Writing/modifying Python code OR running Python tests
- Load: @python.md

**git_operations:**
- Condition: Performing git commits, merges, or branch management
- Load: @git.md, @style.md

**pull_request_workflows:**
- Condition: Creating pull requests OR reviewing code OR merging PRs
- Load: @gh-pr.md, @gh-cli.md, @style.md

**github_workflows:**
- Condition: Using GitHub CLI OR creating PRs OR managing GitHub features
- Load: @gh-cli.md

**modifying_existing_pr:**
- Condition: Working on existing PR OR addressing review comments
- Action: Check for unaddressed review comments BEFORE making changes (see @gh-pr.md Pre-Work Check)
- Load: @gh-pr.md

**pr_review_response:**
- Condition: Responding to PR review feedback OR resolving review comments
- Load: @gh-pr.md (review automation)

**pre_commit_hooks:**
- Condition: Pre-commit hooks modify files OR need to amend commits
- Load: @gh-pr.md (hook coordination), @git.md (amend safety)

**testing:**
- Condition: Writing or running tests (any language)
- Load: @tests.md

**new_project:**
- Condition: Initializing a new project
- Load: @dev.md, @style.md

**ide_configuration:**
- Condition: Writing/editing IDE config files (.vscode/, .kiro/, .cursor/) OR using IDE path variables ($WORKSPACE_ROOT, ${workspaceFolder}, etc.)
- Load: @tools.md, @ide.md

**platform_context_loading:**
- Condition: Session start OR platform detected (Claude Code, Cursor, or Kiro)
- Load: @context.md (universal strategies, always), @context-claude.md (if Claude Code) OR @context-cursor.md (if Cursor) OR @context-kiro.md (if Kiro)
- Action: Load platform-specific context management strategies proactively at session start

**context_management:**
- Condition: Context window approaching capacity (>70%) OR optimizing context usage OR debugging context issues
- Load: @context.md (universal strategies - already loaded by platform_context_loading)
- Action: Monitor context usage, apply selective retention strategies for active platform

**prompt_engineering:**
- Condition: Writing or reviewing AI prompts, AGENTS.md files, or rules documentation
- Load: @xml.md, @prompts.md

**stacked_pr_parent_merged:**
- Condition: Parent PR in stack just merged OR working on child PR after parent merge
- Load: @stacks.md (stacked PR patterns), @gh-pr.md (rebase + post-merge workflows), @git.md, @gh-cli.md
- Action: Check if child PRs need rebase, offer to update stack

**pr_maintenance:**
- Condition: Working on existing PR OR updating PR branch OR before requesting review
- Load: @gh-pr.md (freshness + rebase)
- Action: Check PR freshness relative to base branch, detect conflicts

**pr_review_request:**
- Condition: User asks to request PR review OR agent about to request review
- Load: @gh-pr.md (pre-review freshness check)
- Action: Verify PR is up-to-date with base, all checks pass, no conflicts

**agent_pr_creation:**
- Condition: Agent about to create PR OR agent analyzing commits for PR
- Load: @gh-pr.md (PR description generation)

**post_merge_operations:**
- Condition: PR just merged OR immediately after merge operation
- Load: @gh-pr.md (post-merge workflows), @gh-cli.md
- Action: Check for dependent PRs, offer cascade updates, cleanup branches

**think:**
- Condition: Planning implementation OR estimating scope OR evaluating arguments OR decomposing tasks
- Load: @reasoning.md

**verify:**
- Condition: Bug reported OR test failure OR root cause analysis OR proving correctness
- Load: @validation.md

**design:**
- Condition: Starting new feature OR refactoring OR architecture decisions
- Load: @design.md

**guard:**
- Condition: Making important decisions OR risk assessment
- Load: @clarity.md

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

**Loading:**
```
Rules loaded:
- @[filename] (triggered by: [context_name] context)
- @[filename] (triggered by: [context_name] context)
```

**Unloading:**
```
Rules unloaded:
- @[filename] (context no longer active: [context_name])
```

**Graceful skip:**
```
Rules skipped (file not found):
- @[filename] (triggered by: [context_name] context)
```

### Workflow

1. **Detect context** from user request, file type, or current operation
2. **Match context** to applicable rules using context-to-rules mapping
3. **Report active rules** to user before proceeding with task (both loading and unloading)
4. **Execute task** following those rules
5. **On context change**: Report which rules are being unloaded and which are being loaded

### Examples

**Session start (Claude Code detected):**
```
Rules loaded:
- @core.md (triggered by: always_active context)
- @steering.md (triggered by: always_active context)
- @context.md (triggered by: platform_context_loading context)
- @context-claude.md (triggered by: platform_context_loading context)
```

**Task: Create PR**
```
Rules loaded:
- @gh-pr.md (triggered by: pull_request_workflows context)
- @gh-cli.md (triggered by: pull_request_workflows context)
- @style.md (triggered by: pull_request_workflows context)
- @git.md (triggered by: git_operations context)
```

**Context change: From Python development to Git operations**
```
Rules unloaded:
- @python.md (context no longer active: python_development)

Rules loaded:
- @git.md (triggered by: git_operations context)
- @style.md (triggered by: git_operations context)
```

</instructions>

<note>

These standards are **optional**. If a referenced file does not exist, skip it gracefully.

</note>
