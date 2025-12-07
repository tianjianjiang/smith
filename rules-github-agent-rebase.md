# GitHub Agent Rebase & Branch Freshness Automation

<metadata>

- **Scope**: Agent automation for proactive rebasing and branch freshness monitoring
- **Load if**: Working on PR, before review request, parent PR merged, periodic maintenance
- **Prerequisites**: [PR Concepts](./rules-pr-concepts.md), [GitHub PR Operations](./rules-github-pr.md)

</metadata>

<context>

## Scope

- **This document**: Proactive rebase detection, branch freshness monitoring, AI conflict resolution
- **Basic PR operations**: See [GitHub PR Operations](./rules-github-pr.md)
- **Other agent workflows**: See [Review Automation](./rules-github-agent-review.md), [PR Creation](./rules-github-agent-create.md), [Post-Merge](./rules-github-agent-merge.md)

</context>

## Agent Proactive Rebase Workflows

**Context**: AI agents detecting and responding to rebase needs

### When Agents Should Detect Rebase Needs

<required>

Agent MUST check for rebase needs in these scenarios:

1. **Before PR review request**: Verify PR is current with base branch
2. **After parent PR merge**: Detect child PRs that need rebasing
3. **When working on existing PR**: Check if base branch has advanced
4. **Before merge operations**: Ensure no conflicts with latest base

**Detection commands**:
```sh
# Check if PR branch is behind base
git fetch origin
git rev-list HEAD..origin/main --count  # > 0 means behind

# Check for merge conflicts without merging
git merge-tree $(git merge-base HEAD origin/main) HEAD origin/main | grep -q "^<<<<<<<" && echo "conflicts" || echo "clean"
```

</required>

### Agent Decision Tree: When to Rebase Automatically vs Ask

<required>

**Decision matrix**:

| Scenario | Agent Action | Rationale |
|----------|-------------|-----------|
| PR behind base, no conflicts, user not explicitly working on it | ASK user | Respectful of user control |
| PR behind base, no conflicts, user just said "update PR" | AUTO-REBASE | Clear intent |
| PR behind base, conflicts detected | INFORM + ASK | Requires manual resolution |
| Parent PR merged, child PR exists | INFORM + OFFER | Helpful but not intrusive |
| User about to request review, PR outdated | BLOCK + INFORM | Prevent bad review request |
| PR current with base | DO NOTHING | No action needed |

**Safe auto-rebase criteria** (ALL must be true):
1. User gave explicit update/rebase command
2. No merge conflicts detected
3. Branch is not shared (only user has commits)
4. Branch tracks correct remote
5. Working directory is clean

</required>

### Workflow 1: Pre-Review Freshness Check

<scenario>

**Trigger**: User says "request review on PR #123" or agent about to run `gh pr edit --add-reviewer`

**Agent workflow**:
```sh
# 1. Get PR branch name
BRANCH=$(gh pr view 123 --json headRefName -q .headRefName)
BASE=$(gh pr view 123 --json baseRefName -q .baseRefName)

# 2. Check if behind
git fetch origin
BEHIND=$(git rev-list "origin/$BRANCH".."origin/$BASE" --count)

# 3. Decision
if [ "$BEHIND" -gt 0 ]; then
  # Agent: "This PR is behind $BASE by $BEHIND commits. Should I rebase it before requesting review?"
  # Wait for user response

  # If user says yes:
  git checkout "$BRANCH"
  git rebase "origin/$BASE"
  git push --force-with-lease

  # Then request review
  gh pr edit 123 --add-reviewer @reviewer
fi
```

**Agent message template**:

"I notice PR #123 is behind `{base}` by `{N}` commits. To ensure reviewers see the latest code:
- Option 1: Rebase now (I'll handle it)
- Option 2: Continue anyway (reviewers will see outdated version)
- Option 3: Cancel review request

Which would you prefer?"

</scenario>

### Workflow 2: Post-Parent-Merge Cascade

<scenario>

**Trigger**: Parent PR in stack just merged (agent performed merge or user informed agent)

**Agent workflow**:
```sh
# 1. After parent PR #123 merges
PARENT_BRANCH=$(gh pr view 123 --json headRefName -q .headRefName)

# 2. Find child PRs (depends on tracking in PR body)
# Agent reads all open PRs, looks for "Depends on: #123"
CHILD_PRS=$(gh pr list --json number,body --jq '.[] | select(.body | contains("Depends on: #123")) | .number')

# 3. For each child PR
for CHILD_PR in $CHILD_PRS; do
  CHILD_BRANCH=$(gh pr view $CHILD_PR --json headRefName -q .headRefName)

  # Agent: "Parent PR #123 merged. Child PR #$CHILD_PR needs rebasing. Shall I update it?"
  # Wait for user response

  # If user approves:
  gh pr edit $CHILD_PR --base main
  git fetch origin
  git checkout "$CHILD_BRANCH"
  git rebase --onto origin/main "$PARENT_BRANCH"
  git push --force-with-lease
done

# 4. Delete parent branch (after all children updated)
git push origin --delete "$PARENT_BRANCH"
```

**Agent message template**:

"Parent PR #{parent} merged successfully. I found `{N}` child PR(s):
- PR #{child1}: {title}
- PR #{child2}: {title}

I can rebase these onto main now. Proceed?"

</scenario>

### Workflow 3: Periodic Freshness Detection

<scenario>

**Trigger**: User asks agent to work on PR, or agent performs any PR operation

**Agent workflow**:
```sh
# 1. When starting work on PR
BRANCH=$(gh pr view 123 --json headRefName -q .headRefName)
BASE=$(gh pr view 123 --json baseRefName -q .baseRefName)

# 2. Silent freshness check
git fetch origin
BEHIND=$(git rev-list "origin/$BRANCH".."origin/$BASE" --count)

# 3. Inform if significantly behind (> 5 commits or > 1 day old)
if [ "$BEHIND" -gt 5 ]; then
  # Agent: "Note: This PR is {N} commits behind {base}. This might cause conflicts.
  # Would you like me to rebase before we continue?"
fi
```

**Agent message template**:

"Note: This PR is `{N}` commits behind `{base}` (last updated {timeago}). Rebasing now would:
- Reduce merge conflict risk
- Make CI failures easier to diagnose
- Ensure changes work with latest code

Rebase now?"

</scenario>

### Safety Checks Before Rebase

<required>

Agent MUST verify ALL of these before rebasing:

```sh
# 1. Check authorship (only rebase if user owns recent commits)
RECENT_AUTHORS=$(git log -5 --format='%ae' | sort -u)
# If multiple authors, ASK before rebasing

# 2. Check branch status
git status --porcelain
# If dirty working tree, ABORT

# 3. Check remote tracking
git branch -vv | grep "$BRANCH"
# If not tracking remote correctly, ABORT

# 4. Check for conflicts (dry-run)
git merge-tree "$(git merge-base HEAD "origin/$BASE")" HEAD "origin/$BASE"
# If conflicts detected, INFORM + ASK

# 5. Check if force-push is safe
git log @{upstream}.. --oneline
# If branch already pushed, warn about force-push
```

</required>

### Error Handling and Recovery

<required>

<error_handling>

**If rebase fails**:

```sh
# Agent workflow:
git rebase --abort  # Always abort first

# Agent: "Rebase failed due to conflicts in:
# - file1.py (lines 45-67)
# - file2.py (lines 123-145)
#
# I can either:
# 1. Show you the conflicts (I'll format them for you)
# 2. Guide you through manual resolution
# 3. Abort and leave PR as-is
#
# What would you like?"
```

**If force-push fails**:

```sh
# Agent: "Force-push failed. This usually means:
# 1. Someone else pushed to this branch (check with team)
# 2. Branch protection prevents force-push
# 3. Authentication issue
#
# Check git status and let me know what you'd like to do."
```

</error_handling>

</required>

### Communication Templates

<examples>

**Good: Informative, offers choice**

"PR #123 is 3 days behind main (12 commits). Rebasing now would catch any breaking changes early. Shall I rebase it?"

**Good: Explains trade-offs**

"This PR has merge conflicts with main. I can't auto-rebase. Options:
1. I'll guide you through manual resolution
2. Merge main into PR (creates merge commit, simpler)
3. Continue as-is (conflicts will appear at merge time)"

</examples>

<forbidden>

**Bad: Too aggressive**

"Rebasing PR #123 now..." (no asking, just doing)

**Bad: Not informative**

"PR needs update. Rebase?" (doesn't explain why or impact)

</forbidden>

## Proactive Branch Freshness Monitoring

<context>

**Philosophy**: Prevention over cure - detect branch staleness early and offer rebase before conflicts occur.

**Industry Standard**: Modern tools like Graphite automate stack rebasing with a single command, keeping all dependent PRs synchronized. AI conflict resolution tools (GitKraken AI, GitHub Copilot, Cursor Agent) auto-resolve simple conflicts with explanations.

**Benefits**: Proactive monitoring prevents conflicts, keeps PRs current, and reduces review friction. AI-assisted resolution handles simple conflicts automatically while escalating complex cases to humans.

</context>

<required>

**Agent monitors PR branch staleness** when:
- User says "work on PR #123" or "check PR status"
- User says "ready to request review"
- User returns to session (background check on session start)

**Staleness check**:
```sh
git fetch origin
BASE_BRANCH="main"  # or detect from branch config
BEHIND=$(git rev-list HEAD.."origin/$BASE_BRANCH" --count)
DAYS_OLD=$(git log -1 --format=%cd --date=relative)

# Optional: Check for potential conflicts (dry-run)
CONFLICTS=$(git merge-tree "$(git merge-base HEAD "origin/$BASE_BRANCH")" HEAD "origin/$BASE_BRANCH" | grep -c "^<<<<<<<" || echo 0)
```

**Thresholds for action**:
- **< 5 commits behind**: No action needed (fresh enough)
- **5-10 commits behind**: Passive notification (inform user)
- **> 10 commits OR > 3 days old**: Active recommendation (suggest rebase)
- **> 20 commits OR > 7 days old**: Strong recommendation (likely conflicts, urgent)

**AI Conflict Resolution**:
When conflicts are detected during rebase:
1. **Auto-resolve simple conflicts**: Whitespace differences, formatting changes, import statement order
2. **Analyze complex conflicts**: Present both sides with context, suggest resolution approach
3. **Request human approval**: Always get user approval before committing AI-proposed resolutions
4. **Learn from patterns**: Track resolution decisions for future reference (optional enhancement)

</required>

## Monitoring Scenarios

<scenario>

**Passive notification** (5-10 commits behind):
```
User: "What's the status of PR #123?"
Agent: "PR #123 is 7 commits behind main (last updated 2 days ago). Consider rebasing to stay current with latest changes."
```

**Active recommendation** (>10 commits behind):
```
User: "Work on PR #123"
Agent: "PR #123 is 15 commits behind main (last updated 4 days ago). Rebasing now would:
- Prevent merge conflicts
- Make CI failures easier to diagnose
- Ensure changes work with latest code

Rebase now?"

User: "Yes"
Agent: [Executes rebase] "Successfully rebased PR #123 on latest main. No conflicts detected."
```

**Strong recommendation** (>20 commits OR >7 days):
```
Agent: "⚠ PR #123 is 25 commits behind main (last updated 1 week ago). High conflict risk. Recommended to rebase before continuing work to avoid difficult merge conflicts later."
```

**AI conflict resolution**:
```
Agent: [During rebase] "Detected 3 conflicts during rebase:

1. auth.py:45 - Whitespace/formatting differences (auto-resolved)
2. config.py:12 - Import statement order (auto-resolved)
3. api.py:78 - Function signature change (needs review)

For api.py conflict:
- Your branch: Added `timeout` parameter to authenticate()
- Main branch: Added `retry_count` parameter to authenticate()
- Suggested resolution: Combine both parameters: authenticate(timeout=30, retry_count=3)

Apply this resolution?"

User: "Yes"
Agent: [Applies resolution, completes rebase] "Rebase completed successfully. Resolved 3 conflicts (2 auto, 1 with approval)."
```

**Stacked PR cascade rebase**:
```
Agent: "PR #123 was just updated in main. Detected stack:
- PR #124: feature/auth_login (child of #123)
- PR #125: feature/auth_session (grandchild of #123)

Auto-rebasing entire stack to stay synchronized?"

User: "Yes"
Agent: [Rebases all dependent PRs in order]
Agent: "✓ PR #124 rebased successfully (no conflicts)
✓ PR #125 rebased successfully (no conflicts)
Stack synchronized with main."
```

</scenario>

## Examples

<examples>

**Proactive prevention**:
"Checked PR #123 freshness. 12 commits behind main. Offering rebase BEFORE user starts work prevents conflicts."

**Context-aware AI resolution**:
"Auto-resolved whitespace conflicts in 3 files. For function signature conflict in auth.py:78, analyzed both changes and suggested combining parameters rather than choosing one side."

**Stacked PR intelligence**:
"Detected 'Depends on: #123' in PR #124 body. When #123 merges, automatically offering to rebase #124 to maintain stack integrity."

</examples>

## Forbidden Practices

<forbidden>

**Force rebase without asking**:
"Rebasing PR #123..." (no user confirmation) - ALWAYS ask before rebasing.

**Vague notifications**:
"PR needs update" - doesn't explain why, how many commits behind, or impact.

**Ignoring stacked dependencies**:
Rebasing parent PR without checking/updating child PRs breaks stack integrity.

**Auto-applying complex resolutions**:
Applying AI-suggested conflict resolutions without human review for non-trivial conflicts.

</forbidden>

## Related Standards

- **PR Concepts**: `$HOME/.smith/rules-pr-concepts.md` - Platform-neutral PR workflows
- **GitHub PR Operations**: `$HOME/.smith/rules-github-pr.md` - Basic GitHub operations
- **Review Automation**: `$HOME/.smith/rules-github-agent-review.md` - Review cycle automation
- **PR Creation Automation**: `$HOME/.smith/rules-github-agent-create.md` - Agent PR creation
- **Post-Merge Workflows**: `$HOME/.smith/rules-github-agent-merge.md` - Post-merge automation
- **Agent Utilities**: `$HOME/.smith/rules-github-agent-utils.md` - Workflow coordination
