# GitHub Pull Request Operations

<metadata>

- **Scope**: Basic GitHub PR operations using gh CLI (non-agent workflows)
- **Load if**: Using GitHub for pull requests, basic PR operations
- **Prerequisites**: [PR Concepts](./rules-pr-concepts.md), [GitHub Standards](./rules-github.md)

</metadata>

<context>

## Scope

- **This document**: Basic GitHub PR operations (`gh pr` commands)
- **Agent automation**: See [GitHub Agent Workflows](./rules-github-agent-*.md) for automation
- **Platform-neutral concepts**: See [PR Concepts](./rules-pr-concepts.md)

</context>

## Branch Deletion with Stacked PRs

<forbidden>

**NEVER use `--delete-branch` when merging a PR that has dependent child PRs.**

The GitHub API immediately deletes the branch, closing all child PRs before their base can be updated. This is a known GitHub API limitation ([cli/cli#1168](https://github.com/cli/cli/issues/1168)).

</forbidden>

<required>

**Process for stacked PRs:**

1. Merge parent PR WITHOUT deleting branch:
   ```sh
   gh pr merge 123 --squash  # No --delete-branch
   ```

2. Update child PR base and rebase:
   ```sh
   gh pr edit 124 --base main
   git fetch origin
   git checkout feature/child_branch
   git rebase --onto origin/main feature/parent_branch
   git push --force-with-lease
   ```

3. Delete parent branch AFTER child is updated:
   ```sh
   git push origin --delete feature/parent_branch
   ```

</required>

## Post-Merge Cleanup

**For non-stacked PRs** (simple feature branch):

```sh
git checkout main
git fetch --prune origin
git pull origin main
git branch -d feature/my_feature
git ls-remote --exit-code --heads origin feature/my_feature >/dev/null 2>&1 && git push origin --delete feature/my_feature
```

<context>

**Command explanation:**

- `git fetch --prune`: Update remote refs and remove stale tracking branches
- `git pull origin main`: Update local main with merged commits (required for branch -d check)
- `git branch -d`: Safe delete (fails if branch not merged to main)
- `git ls-remote --exit-code`: Check if remote branch exists before attempting deletion
- Works whether GitHub auto-delete is enabled or disabled

</context>

**For stacked PRs** (parent with children):

See "Branch Deletion with Stacked PRs" section above and [Agent Post-Merge Workflow](./rules-github-agent-merge.md) for automated workflows.

<forbidden>

- NEVER use `git branch -D` (force delete) unless you are certain the branch should be abandoned
- NEVER delete local branch before PR is merged
- NEVER skip `git fetch --prune` (leaves stale remote-tracking refs)

</forbidden>

## Related Standards

- **PR Concepts**: `$HOME/.smith/rules-pr-concepts.md` - Platform-neutral PR workflows
- **GitHub Operations**: `$HOME/.smith/rules-github.md` - GitHub CLI operations
- **Git Operations**: `$HOME/.smith/rules-git.md` - Local git commands
- **GitHub Agent Workflows**: See `$HOME/.smith/rules-github-agent-*.md` for automation
