# GitHub Workflow Utilities and Troubleshooting

<metadata>

- **Scope**: GitHub workflow coordination, troubleshooting, and recovery procedures
- **Load if**: Pre-commit hooks, CI checks, amend operations, troubleshooting PR issues
- **Prerequisites**: rules-pr-concepts.md, rules-git.md, rules-ai_agents.md

</metadata>

<context>

## Scope

- **This document**: Shared utilities and troubleshooting across all PR workflows
- **Platform-neutral PR concepts**: rules-pr-concepts.md
- **GitHub PR operations**: rules-github-pr-automation.md
- **Other workflows**: rules-github-*.md

</context>

## Pre-Commit Hook Coordination

<scenario>

**When hooks modify files during commit:**

1. Pre-commit hook runs automatically
2. Hook modifies files (formatting, linting fixes)
3. Commit fails with "files were modified by hook"

</scenario>

<required>

**Workflow for hook modifications:**

```sh
git add .
git commit -m "feat: add feature"
git diff --cached
git log -1 --format='%an %ae'
git status
git commit --amend --no-edit
git commit -m "style: apply pre-commit hook fixes"
```

</required>

<forbidden>

- **NEVER** amend without checking commit authorship
- **NEVER** amend commits already pushed to remote
- **NEVER** amend commits from other authors

</forbidden>

**Decision tree:**
- Amend IF: You authored last commit AND commit not pushed yet
- New commit IF: Last commit from someone else OR already pushed

## CI Check Coordination

<scenario>

<required>

**Monitor CI status before and after changes:**

```sh
git push
git add .
git commit -m "fix: resolve CI check failures"
git push
```

</required>

<forbidden>

- **NEVER** request review while CI checks are failing
- **NEVER** ignore CI check failures
- **NEVER** merge with failing checks

</forbidden>

**Best practices:**
- Wait for all checks to pass before requesting review
- If checks fail, fix immediately before other work
- Monitor checks continuously to catch failures early

</scenario>

## Amend Operations Safety

<forbidden>

**NEVER amend in these scenarios:**

- Commit authored by someone else
- Commit already pushed to remote (unless you force push intentionally)
- Working on protected branches (main, develop)
- Commit is part of a PR under active review by others

</forbidden>

<required>

**Verification checklist before amending:**

```sh
AUTHOR=$(git log -1 --format='%ae')
CURRENT_USER=$(git config user.email)
if [ "$AUTHOR" != "$CURRENT_USER" ]; then
  echo "Not your commit - create new commit instead"
  exit 1
fi
# Check if HEAD exists in unpushed commits list
# git log @{upstream}.. lists commits that exist locally but not on remote
# If grep finds HEAD in that list, commit is not pushed yet (safe to amend)
# If grep fails, HEAD is not in unpushed list, meaning it was pushed (avoid amending)
if git log @{upstream}.. | grep -q "$(git rev-parse HEAD)"; then
  echo "Commit not pushed yet - safe to amend"
else
  echo "Commit already pushed - avoid amending"
fi
BRANCH=$(git branch --show-current)
if [[ "$BRANCH" == "main" || "$BRANCH" == "develop" ]]; then
  echo "Protected branch - DO NOT AMEND"
  exit 1
fi
```

</required>

**Safe amend scenarios:**
- Pre-commit hook modified files (see Pre-Commit Hook Coordination)
- Fixing typo in commit message you just made
- Adding forgotten file to your last commit (before push)

**When to create new commit instead:**
- Addressing review feedback (keep review history)
- Fixing bugs found after push
- Any change to commits from other authors


## Troubleshooting Common Issues

### Issue 1: Changes Not Appearing in PR

**Symptoms**: You made changes and committed but PR doesn't show them

**Diagnosis:**
```sh
git branch --show-current
git branch -vv
```

**Solution:**
```sh
git branch --set-upstream-to=origin/<branch-name>
git push
```

### Issue 2: Merge Conflicts After Base Branch Update

**Symptoms**: PR shows merge conflicts with base branch

**Diagnosis:**
```sh
git fetch origin
git log HEAD..origin/main
```

**Solution:**
```sh
git fetch origin main:main
git rebase main
git status
git add .
git rebase --continue
git push --force-with-lease
```

### Issue 3: CI Checks Fail After Pre-Commit Hook

**Symptoms**: Pre-commit passes locally but CI fails

**Solution:**
```sh
poetry run ruff check . --config=<same-as-ci>
poetry run pytest --cov=<same-as-ci>
```

## Recovery Procedures

### Scenario 1: Wrong Branch Checkout

**Problem**: Made changes to wrong branch

**Solution**: See rules-pr-concepts.md for recovery procedure

### Scenario 2: Accidentally Pushed to Wrong Remote

**Problem**: Pushed PR branch to wrong repository

**Solution:**
```sh
git remote -v
git remote remove wrong-remote
git remote add origin <correct-repo-url>
git push -u origin <branch-name>
```

### Scenario 3: Need to Undo Last Commit but Keep Changes

**Problem**: Made commit but want to redo it differently

**Solution:**
```sh
git reset --soft HEAD~1
git reset HEAD~1
git add .
git commit -m "better commit message"
```

### Scenario 4: Syncing with Updated Base Branch

**Problem**: Base branch (main/develop) has new commits

**Solution:**
```sh
git fetch origin
git rebase origin/main
git push --force-with-lease
git merge origin/main
git push
```

## Related Standards

- **PR Concepts**: rules-pr-concepts.md - Platform-neutral PR workflows
- **GitHub PR Automation**: rules-github-pr-automation.md - PR creation, review, rebase, merge workflows
- **Git Standards**: rules-git.md - Commit amending, conflict resolution
- **Core Standards**: rules-core.md - PR restrictions, amend safety
