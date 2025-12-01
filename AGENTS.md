# Personal Coding Standards (.smith)

<metadata>
**Scope**: Entry point for personal coding standards
**Load if**: Starting any development task
**Prerequisites**: None
</metadata>

<context_triggers>
<!-- Load these files ONLY if the specific context applies -->

<trigger context="python_development">
**IF** writing/modifying Python code OR running python tests:
**LOAD**: `$HOME/.smith/rules-python.md`
</trigger>

<trigger context="git_operations">
**IF** performing git commits, merges, or branch management:
**LOAD**: `$HOME/.smith/rules-git.md`
</trigger>

<trigger context="pull_request_workflows">
**IF** creating pull requests OR reviewing code OR merging PRs:
**LOAD**: `$HOME/.smith/rules-pr.md`
</trigger>

<trigger context="github_workflows">
**IF** using GitHub CLI OR managing GitHub-specific features:
**LOAD**: `$HOME/.smith/rules-github.md`
</trigger>

<trigger context="modifying_existing_pr">
**IF** working on existing PR OR addressing review comments:
**LOAD**: `$HOME/.smith/rules-pr.md`
</trigger>

<trigger context="pr_review_response">
**IF** responding to PR review feedback OR resolving review comments:
**LOAD**: `$HOME/.smith/rules-pr.md`
</trigger>

<trigger context="pre_commit_hooks">
**IF** pre-commit hooks modify files OR need to amend commits:
**LOAD**: `$HOME/.smith/rules-pr.md`
**LOAD**: `$HOME/.smith/rules-git.md`
</trigger>

<trigger context="testing">
**IF** writing or running tests (any language):
**LOAD**: `$HOME/.smith/rules-testing.md`
</trigger>

<trigger context="new_project">
**IF** initializing a new project:
**LOAD**: `$HOME/.smith/rules-development.md`
**LOAD**: `$HOME/.smith/rules-naming.md`
</trigger>

<trigger context="ide_configuration">
**IF** configuring editor/IDE settings:
**LOAD**: `$HOME/.smith/rules-tools.md`
**LOAD**: `$HOME/.smith/rules-ide_mappings.md`
</trigger>

<trigger context="always_active">
**ALWAYS LOAD**: `$HOME/.smith/rules-core.md` (Critical NEVER/ALWAYS rules)
</trigger>

</context_triggers>

<note>
These standards are **optional**. If a referenced file does not exist, skip it gracefully.
</note>
