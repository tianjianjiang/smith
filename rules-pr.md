# DEPRECATED: Pull Request Workflows

<metadata>

- **Status**: DEPRECATED as of 2025-12-08
- **Replacement**: See new modular files below
- **Removal date**: 2026-01-08 (30-day grace period)

</metadata>

## Migration Notice

This file has been split into multiple focused files for better lazy-loading efficiency and reduced token usage (70% reduction: 2000→590 lines average per operation).

## New File Structure

### Platform-Neutral PR Concepts

**File**: `$HOME/.smith/rules-pr-concepts.md` (~425 lines)

**Contains**:
- PR Creation (title format, body template, requirements)
- Stacked PRs (merge workflow, rebasing strategies)
- Working on Existing PRs (branch name handling)
- Code Review Process (requesting, responding, giving reviews)
- Merge Strategies (merge commit vs squash vs rebase)
- Best Practices (PR size, communication, documentation)

### GitHub Operations

**File**: `$HOME/.smith/rules-github-pr.md` (~100 lines)

**Contains**:
- Branch deletion with stacked PRs
- Post-merge cleanup (basic operations)

### Automation Workflows

**File**: `$HOME/.smith/rules-github-review.md` (~470 lines)

**Contains**:
- Review Cycle Automation
- Iterative review→fix→re-review loop
- Comment categorization and confidence scoring
- Inline review thread handling (MCP + gh CLI)
- Auto-merge criteria verification

**File**: `$HOME/.smith/rules-github-create.md` (~220 lines)

**Contains**:
- Creating Pull Requests
- PR Description Auto-Generation
- Full diff analysis and ticket integration
- Common mistakes and PR analysis checklist

**File**: `$HOME/.smith/rules-github-rebase.md` (~410 lines)

**Contains**:
- Proactive Rebase Workflows
- When to detect rebase needs (decision tree)
- 3 workflows: pre-review, post-parent-merge, periodic
- Proactive Branch Freshness Monitoring
- Multi-tier staleness thresholds
- AI conflict resolution

**File**: `$HOME/.smith/rules-github-merge.md` (~60 lines)

**Contains**:
- Post-Merge Workflow
- Child PR detection and cascade updates
- Stacked PR cascade examples

**File**: `$HOME/.smith/rules-github-utils.md` (~215 lines)

**Contains**:
- Pre-Commit Hook Coordination
- CI Check Coordination
- Amend Operations Safety
- Troubleshooting Common Issues
- Recovery Procedures

## Benefits of New Structure

- **70% token reduction**: Average 590 lines loaded vs 2000 lines (saves ~5640 tokens per operation)
- **Granular lazy-loading**: Only load workflows relevant to current task
- **Platform separation**: Clear distinction between platform-neutral concepts and GitHub-specific automation
- **Easier maintenance**: Focused files easier to update and review
- **Future extensibility**: Easy to add GitLab, Bitbucket support without affecting GitHub workflows

## AGENTS.md Trigger Updates

The following trigger contexts have been updated in `$HOME/.smith/AGENTS.md`:

- `pull_request_workflows` → loads `rules-pr-concepts.md` + `rules-github-pr.md`
- `modifying_existing_pr` → loads `rules-pr-concepts.md` + `rules-github-pr.md`
- `pr_review_response` → loads `rules-pr-concepts.md` + `rules-github-review.md`
- `pre_commit_hooks` → loads `rules-github-utils.md`
- `stacked_pr_parent_merged` → loads `rules-pr-concepts.md` + `rules-github-rebase.md` + `rules-github-merge.md`
- `pr_maintenance` → loads `rules-pr-concepts.md` + `rules-github-rebase.md`
- `pr_review_request` → loads `rules-pr-concepts.md` + `rules-github-rebase.md`
- `agent_pr_creation` (NEW) → loads `rules-pr-concepts.md` + `rules-github-create.md`
- `post_merge_operations` → loads `rules-github-merge.md`

## Timeline

- **Deprecated**: 2025-12-08
- **Grace period**: 30 days (references updated, but file kept for backwards compatibility)
- **Removal**: 2026-01-08 (this file will be deleted)

## Action Required

If you have any scripts or tools referencing `rules-pr.md`, update them to use the new modular files listed above.

## Related Standards

- **Git Operations**: [Git Standards](./rules-git.md) - Local git operations
- **GitHub Operations**: [GitHub Standards](./rules-github.md) - GitHub CLI commands
- **Development Workflow**: [Development Standards](./rules-development.md) - Daily practices
- **AI Agent Principles**: [AI Agent Standards](./rules-ai_agents.md) - Constitutional AI principles
