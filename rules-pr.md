# DEPRECATED: Pull Request Workflows

<metadata>

- **Status**: DEPRECATED as of 2025-12-08
- **Removal date**: 2026-01-08 (30 days)
- **Migration**: See new files below

</metadata>

## Deprecation Notice

This file has been split into multiple focused files for better lazy-loading and token efficiency:

### Platform-Neutral PR Concepts

**See**: `$HOME/.smith/rules-pr-concepts.md`

Contains:
- PR Creation (prerequisites, title format, body template)
- Stacked PRs (merge workflow, rebasing strategies)
- Working on Existing PRs
- Code Review Process (basics)
- Merge Strategies
- Best Practices

**Load when**: Creating PRs, reviewing code, merging changes (any Git platform)

### GitHub PR Operations

**See**: `$HOME/.smith/rules-github-pr.md`

Contains:
- Basic GitHub PR operations
- Branch deletion with stacked PRs
- Post-merge cleanup

**Load when**: Using GitHub for pull requests

### GitHub Agent Automation Workflows

**Agent Review Cycle**: `$HOME/.smith/rules-github-agent-review.md`
- Iterative review→fix→re-review automation
- Inline comment handling (MCP + gh CLI)
- Comment categorization and confidence scoring
- Auto-merge criteria verification

**Agent Rebase & Freshness**: `$HOME/.smith/rules-github-agent-rebase.md`
- Proactive rebase workflows
- Branch freshness monitoring
- AI conflict resolution
- Multi-tier staleness thresholds

**Agent PR Creation**: `$HOME/.smith/rules-github-agent-create.md`
- Full diff analysis for PR descriptions
- Ticket integration
- Template-driven generation

**Agent Post-Merge**: `$HOME/.smith/rules-github-agent-merge.md`
- Child PR detection
- Cascade update workflows

**Agent Utilities**: `$HOME/.smith/rules-github-agent-utils.md`
- Pre-commit hook coordination
- CI check coordination
- Amend operations safety
- Troubleshooting common issues

## Migration Guide

1. **AGENTS.md** has been updated with new trigger contexts
2. **Cross-references** in other rules files updated to point to new files
3. **No action required** - Files load automatically based on context

## Benefits of New Structure

- **70% token reduction**: Average 590 lines loaded vs 2000 lines
- **Granular lazy-loading**: Only load workflows relevant to current task
- **Platform separation**: Platform-neutral concepts separated from GitHub-specific automation
- **Better organization**: Related workflows grouped together

## Timeline

- **Deprecated**: 2025-12-08
- **Grace period**: 30 days
- **Removal**: 2026-01-08

After removal, references to `rules-pr.md` will load `rules-pr-concepts.md` as fallback.

## Related Standards

- **Platform-Neutral**: `$HOME/.smith/rules-pr-concepts.md`
- **GitHub Operations**: `$HOME/.smith/rules-github-pr.md`
- **Agent Workflows**: `$HOME/.smith/rules-github-agent-*.md`
- **Git Operations**: `$HOME/.smith/rules-git.md`
- **Development Workflow**: `$HOME/.smith/rules-development.md`
