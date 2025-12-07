# Pull Request Workflows

<metadata>

- **Scope**: Platform-neutral pull request and workflow concepts
- **Load if**: Creating PRs, reviewing code, merging changes, working with any Git platform
- **Prerequisites**: [Core Standards](./rules-core.md), [Git Standards](./rules-git.md)

</metadata>

<context>

## Scope

- **This document**: PR concepts, code review workflows, merge strategies, agent guidelines
- **Platform-specific operations**: See platform-specific files (e.g., rules-github.md for GitHub CLI)
- **Local git operations**: See [Git Standards]($HOME/.smith/rules-git.md) for commits, branches, merges

</context>

## Pull Request Creation

### Prerequisites

<constraints>

<required>

- MUST run all quality checks before creating PR
- MUST ensure branch is up-to-date with base branch
- MUST have meaningful commit messages
- MUST link to related issues

</required>

**Pre-PR checklist:**
```sh
poetry run ruff format . && poetry run ruff check --fix .
poetry run pytest
git fetch origin
git rebase origin/main
git push -u origin feature/my_feature
```

</constraints>

### PR Title Format

<formatting>

**Format**: `type: description` or `type(scope): description`

Scope is optional. Choose type based on PRIMARY change:

- `feat`: New user-facing functionality
- `fix`: Bug fix for existing functionality
- `docs`: Documentation ONLY (no code changes)
- `refactor`: Code restructure without behavior change
- `style`: Formatting ONLY (whitespace, semicolons)
- `test`: Test changes ONLY
- `chore`: Build/tooling (CI, dependencies, scripts)
- `perf`: Performance improvement

</formatting>

<required>

**Length limits** (PR title becomes merge commit subject):
- **Target**: 50 characters (forces conciseness)
- **Hard limit**: 72 characters (GitLab enforces, GitHub truncates)

**Atomicity indicator**: If title exceeds 50 chars, consider if PR combines multiple changes. Split into stacked PRs if needed.

</required>

<examples>

- `feat(rag): add semantic search filtering`
- `fix(api): resolve CORS issues`
- `docs: update deployment guide`
- `refactor(auth): extract validation logic`
- `test: add integration tests for search`

</examples>

<forbidden>

- PR title over 72 characters
- Multiple unrelated changes in title (e.g., "add X and fix Y and update Z")
- Using "and" to join unrelated changes (indicator of non-atomic PR)
- Using `docs` when also changing code → use `feat` or `fix`
- Using `refactor` for bug fixes → use `fix`
- Using `chore` for new features → use `feat`

</forbidden>

### PR Body Template

<examples>

```markdown
## Summary
- Bullet point 1: Main change
- Bullet point 2: Additional change
- Bullet point 3: Impact or benefit

## Test Plan
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing completed
- [ ] Documentation updated

## Related Issues
Closes #123
Fixes #456

Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

</examples>

### PR Requirements

<required>

- MUST have descriptive title following conventional commits format
- MUST include summary (1-3 bullet points)
- MUST include test plan with checklist
- MUST link to related issues
- MUST have all CI checks passing
- MUST have minimum 1 approval (if enforced by project)

</required>

<forbidden>

- NEVER create PR with failing tests
- NEVER merge PR with unresolved conflicts
- NEVER skip CI checks
- NEVER merge without required approvals

</forbidden>

### Stacked PRs

<context>

For large features, use stacked PRs to maintain atomic, reviewable changes.

**When to stack**:
- Feature requires 500+ lines of changes
- Multiple logical components that can be reviewed independently
- Need to unblock dependent work before full feature is ready

</context>

<required>

**How to stack**:
1. Create base PR with foundation (e.g., `feature/auth-base`)
2. Create child PR branching from base (e.g., `feature/auth-login` from `feature/auth-base`)
3. Each PR should be independently reviewable and mergeable
4. Merge bottom-up: base first, then children

</required>

<examples>

**Stack structure**:
```text
main
 └── feature/auth-base (PR #1: models, migrations)
      └── feature/auth-login (PR #2: login endpoint)
           └── feature/auth-oauth (PR #3: OAuth integration)
```

**PR description for stacked PRs**:
```markdown
## Stack
- **Depends on**: #123 (feature/auth-base) ← This PR requires #123 to be merged first
- **Blocks**: #125 (feature/auth-oauth) ← PR #125 depends on this PR
```

**Field meanings**:
- `Depends on`: PRs that must merge before this one (upstream dependencies)
- `Blocks`: PRs waiting for this one to merge (downstream dependents)

</examples>

### Stacked PR Merge Workflow

<required>

**Sequential merge order** (bottom-up):
1. Wait for parent PR approval
2. Merge parent PR into `main`
3. Rebase child PR onto updated `main`
4. Get child PR approved
5. Repeat for each level in stack

</required>

<forbidden>

- NEVER merge child PR before parent (merges into parent branch, not main)
- NEVER merge main directly into child branch (corrupts history)
- NEVER use squash merge for non-final PRs in a stack

</forbidden>

<examples>

**Correct merge sequence**:
```text
1. Merge PR #1 (feature/auth-base) → main
2. Rebase PR #2 (feature/auth-login) onto main
3. Merge PR #2 → main
4. Rebase PR #3 (feature/auth-oauth) onto main
5. Merge PR #3 → main (can squash this one)
```

</examples>

### Rebasing After Parent Merges

<required>

When a parent PR merges, child PRs must be rebased:

1. Fetch latest changes
2. Checkout child branch
3. Rebase onto updated main
4. Force push (safe for your PR branch)

```sh
git fetch origin
git checkout feature/auth-login
git rebase --onto origin/main feature/auth-base
git push --force-with-lease
```

**Why `--onto`**: Only transplants commits unique to child branch (commits between parent and child), avoiding duplicate commits.

</required>

<examples>

**Before rebase** (after parent merged):
```text
main ──●──●──●──M (parent merged as M)
                 \
feature/auth-login ──A──B──C (still based on old parent)
```

**After `git rebase --onto origin/main feature/auth-base`**:
```text
main ──●──●──●──M
                 \
                  └──A'──B'──C' (feature/auth-login rebased)
```

</examples>

### Agent-Assisted Stack Management

<context>

When working with stacked PRs, agents can proactively detect when rebasing is needed.

**Agent responsibilities**:
1. Detect when parent PR merges
2. Identify child PRs from "Depends on" links in PR body
3. Offer to update child PR base and rebase
4. Handle branch deletion timing correctly

</context>

<required>

Agent MUST:
- Parse PR bodies for "Depends on: #{number}" to build dependency graph
- Offer cascade updates immediately after parent merge
- Verify child PR base update before rebasing
- Ask before force-pushing to child PR branches

</required>

**See**: "Agent Proactive Rebase Workflows" section for detailed automation workflows

### Squash Merge with Stacked PRs

<required>

**Squash merge IS allowed** if you follow the branch deletion process for stacked PRs (see "Branch Deletion with Stacked PRs").

**Merge strategy by position**:

| PR Position | Squash Merge | Branch Deletion Timing |
|-------------|--------------|-----------------|
| Parent (has children) | OK with process | After child base updated |
| Middle | OK with process | After child base updated |
| Final (leaf) | OK | Immediate OK |

</required>

**Why squash merge requires extra steps**:

Squash merge creates a single commit, destroying commit ancestry. Child branches still contain parent's original commits, causing:
- Duplicate commits in child PR
- Merge conflicts when rebasing
- Git unable to recognize commits already in main

<examples>

**Fixing child PR after parent was squash merged**:

Option 1 - Rebase with `--fork-point`:
```sh
git fetch origin
git checkout feature/auth-login
git rebase --onto origin/main --fork-point origin/feature/auth-base
git push --force-with-lease
```

Option 2 - Interactive rebase to drop parent's commits:
```sh
git checkout main && git pull
git checkout feature/auth-login
git rebase -i main
```
In the interactive editor, mark all commits from the parent branch as `drop`.

</examples>

### Keeping Stack Updated

<required>

When pulling changes from main into a stack, cascade updates through the stack sequentially:

```sh
git checkout feature/auth-base
git merge main
git push

git checkout feature/auth-login
git merge feature/auth-base
git push
```

</required>

<forbidden>

Merging main directly into a child branch corrupts history:

```sh
git checkout feature/auth-login
git merge main
```

</forbidden>

### Stacked PR References

- [How to handle stacked PRs on GitHub](https://www.nutrient.io/blog/how-to-handle-stacked-pull-requests-on-github/)
- [Stacked pull requests with squash merge](https://echobind.com/post/stacked-pull-requests-with-squash-merge/)
- [How to merge stacked PRs in GitHub](https://graphite.com/guides/how-to-merge-stack-pull-requests-github)
- [Dave Pacheco's Stacked PR Workflow](https://www.davepacheco.net/blog/2025/stacked-prs-on-github/)

### Branch Deletion with Stacked PRs

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

## Working on Existing PRs

### CRITICAL: Always Use Actual Branch Name

<forbidden>

**NEVER create arbitrary local branch names when working on PRs:**

- Do NOT create local branches with assumed names like `pr-123`
- Do NOT assume branch name follows a pattern
- Do NOT make changes without verifying current branch

</forbidden>

<required>

**ALWAYS get and use the actual PR branch name:**

```sh
git fetch origin
git checkout -b "<actual-branch-name>" "origin/<actual-branch-name>"
git branch --show-current
git status
```

</required>

### Why This Matters

<context>

**Problem**: Creating local branches with assumed names that don't match the PR's actual branch name.

**Impact**:
- Your changes won't push to the PR
- You're working on a disconnected branch
- Risk of losing work or creating merge conflicts

**Solution**: Always verify the PR's actual branch name from your platform, then checkout from origin.

</context>

### Recovery if You Made This Mistake

If you already made changes to the wrong branch:

```sh
git checkout "<actual-branch-name>"
git cherry-pick <commit-sha-from-wrong-branch>
git branch -D <wrong-branch-name>
```

### Post-Push Requirements

<required>

After pushing changes to a PR:

1. **Address review comments**: Read and respond to all new review comments
2. **Revise PR title**: Update if changes have shifted the PR's focus
3. **Revise PR body**: Update summary to reflect current cumulative changes
4. **Verify atomicity**: Confirm PR still represents a single logical change

</required>

<forbidden>

- Leaving review comments unaddressed after push
- PR title/body that doesn't reflect actual changes
- Pushing without checking for new review comments

</forbidden>

## Code Review Process

### Requesting Review

**Best practices:**
- Request reviews from relevant team members
- Provide context in PR description
- Link to design docs or RFCs if applicable
- Highlight areas needing special attention
- Ensure all CI checks are passing before requesting review

### Responding to Reviews

**Address all comments:**
1. Read all review comments carefully
2. Respond to each comment thread
3. Make requested changes
4. Test your changes thoroughly
5. Mark conversations as resolved
6. Re-request review after changes

**Workflow:**
```sh
git add .
git commit -m "refactor: address review comments"
git push
```

### Giving Reviews

**Review checklist:**
- [ ] Code follows project standards
- [ ] Tests are adequate and passing
- [ ] Documentation is updated
- [ ] No security vulnerabilities
- [ ] Performance considerations addressed
- [ ] Error handling is appropriate
- [ ] Changes are focused and don't include unrelated modifications

**Review types:**
- **Approve**: Code is ready to merge
- **Request changes**: Issues must be addressed before merging
- **Comment**: Suggestions or questions, but not blocking

### Agent Review Cycle Automation

<context>

**Philosophy**: Automate the iterative review→fix→re-review cycle until all comments are resolved, then proceed to merge when approved.

**Industry Best Practices**:
- **CodeRabbitAI**: Incremental review tracking - only review changed files, not entire PR on each iteration, saving costs and reducing noise
- **Qodo Merge**: `/implement` command directly applies reviewer suggestions with tracking of accepted changes
- **Devin AI**: Confidence scoring (high/medium/low) determines whether to implement directly or ask user first (5-10 min review time)
- **OpenHands**: Label-triggered workflows (e.g., "review-this" label auto-starts review cycle)
- **Real-world impact**: 73.8% of automated review comments marked "Resolved", 30% reduction in review time

</context>

<required>

**Iterative review cycle workflow**:

1. **Trigger points** (any of these):
   - User: "address comments on PR #123" or "@agent address comments"
   - Label: "review-this" or "needs-fixes" added to PR (OpenHands pattern)
   - Auto: After reviewer requests changes

2. **Fetch all review comments**:
```sh
# Get review comments with requested changes
gh api repos/{owner}/{repo}/pulls/{PR}/reviews --jq '.[] | select(.state == "CHANGES_REQUESTED")'

# Get inline comment threads
gh api repos/{owner}/{repo}/pulls/{PR}/comments
```

3. **Categorize comments**:
   - **Actionable**: Specific code changes requested (can be implemented)
   - **Clarification**: Questions needing answers (respond in comment thread)
   - **Discussion**: Architectural/subjective decisions (needs human input)

4. **For each actionable comment** (Qodo Merge pattern):
   - **Analyze confidence**: Determine if request is clear and unambiguous
   - **High confidence (>70%)**: Implement directly and explain what was done
   - **Medium confidence (40-70%)**: Implement with explanation, ask for confirmation
   - **Low confidence (<40%)**: Ask user for clarification before implementing
   - **Track mapping**: Comment ID → Commit SHA that addresses it
   - **Reply to comment**: Use quote reply format with reviewer mention
   - **Mark resolved**: Hide comment as resolved after addressing

5. **Commit and push changes**:
```sh
git add .
git commit -m "fix: address review comments from @reviewer

- Extract timeout value to constant (comment #123)
- Add test for token expiration (comment #124)
- Update docs with rate limit info (comment #125)

Addresses review feedback from PR review."
git push
```

6. **Incremental re-review check** (CodeRabbitAI pattern):
   - Wait for PR checks to complete
   - Check if NEW review comments were posted
   - **If new comments exist**: Return to step 2 (repeat cycle)
   - **If no new comments AND all resolved**: Proceed to step 7

7. **Auto-merge criteria check**:
   - All review comments addressed OR marked as resolved
   - No new comments in last check (reviewers had chance to re-review)
   - All CI/CD checks passing
   - Required number of approvals met
   - Branch is fresh (not stale - see Proactive Branch Freshness Monitoring)
   - No merge conflicts with base branch

   If ALL criteria met: Proceed to merge (with user confirmation)
   If ANY criteria not met: Inform user what's blocking

**Comment reply format**:

When replying to review comments, use GitHub quote reply with reviewer mention:

```markdown
@reviewer-username

> Original comment text here

Response explaining what was done or asking for clarification.

Fixed in commit abc1234.
```

**Marking resolved**:
- Use `gh pr comment {PR} --body "..."` to reply to comments
- Use `gh api` to mark threads as resolved after addressing:
```sh
# Mark review thread as resolved
gh api -X PUT repos/{owner}/{repo}/pulls/comments/{comment_id}/replies/{reply_id} \
  -f state=resolved
```

Or if using GitHub web UI automation, hide the conversation after confirming fix is implemented.

</required>

<scenario>

**Full iterative cycle example**:

```
User: "@agent address review comments on PR #123"

# ITERATION 1
Agent: [Fetches review comments via gh API]
Agent: "Found 3 actionable review comments from @reviewer:

1. auth.py:45 - 'Extract timeout value to named constant' [Confidence: 95%]
2. tests/auth_test.py:12 - 'Add test case for expired tokens' [Confidence: 85%]
3. README.md:100 - 'Update docs with new rate limiting behavior' [Confidence: 60%]

Comments #1 and #2 are clear. For #3, should I document both the 10 req/min limit AND the exponential backoff strategy, or just the limit?"

User: "Document both"

Agent: [Implements all 3 changes]
Agent: [Commits with message listing all addressed comments]
Agent: [Pushes to PR branch]
Agent: [Replies to each comment with quote format]

# Reply to comment #1:
"@reviewer

> Extract timeout value to named constant

Done! Extracted to `DEFAULT_REQUEST_TIMEOUT = 30` in constants.py.

Fixed in commit abc1234."

Agent: [Marks comment #1 as resolved]
Agent: [Repeats for comments #2 and #3]
Agent: "Pushed fixes addressing all 3 comments. Waiting for CI checks and re-review..."

# ITERATION 2 (reviewer adds new comment after seeing changes)
Agent: [Checks for new comments after CI passes]
Agent: "New comment from @reviewer:

4. auth.py:52 - 'Consider adding error handling for network timeouts' [Confidence: 90%]

Implementing try-except wrapper for network operations..."

Agent: [Makes change, commits, pushes]
Agent: [Replies to comment #4]

# Reply to comment #4:
"@reviewer

> Consider adding error handling for network timeouts

Good catch! Added try-except wrapper with `requests.exceptions.Timeout` handling and exponential backoff retry logic.

Fixed in commit def5678."

Agent: [Marks comment #4 as resolved]
Agent: "Addressed comment #4. CI passing. Waiting for re-review..."

# ITERATION 3 (no new comments)
Agent: [Checks again after CI passes]
Agent: "No new review comments. All 4 comments addressed and marked resolved. CI checks passing.

Auto-merge readiness:
✓ All comments addressed
✓ No new comments from reviewers
✓ CI checks passing (all 5 checks green)
✓ 2 approvals received (requirement: 1)
✓ Branch is fresh (rebased 10 minutes ago)
✓ No merge conflicts

Ready to merge. Proceed with squash and merge?"

User: "Yes"
Agent: [Executes: gh pr merge 123 --squash --delete-branch]
Agent: "PR #123 merged successfully. Branch deleted."
```

**Confidence scoring example** (Devin pattern):

```
Agent: "Review comment: 'Refactor for better performance' [Confidence: 35%]

This request is ambiguous. Multiple approaches possible:
1. Add caching (if called frequently)
2. Optimize algorithm complexity (if computationally expensive)
3. Implement async/parallel execution (if I/O bound)
4. Use memoization (if same inputs repeated)

Which approach aligns with the performance issue you're seeing?"

User: "The function is called in a tight loop, go with caching"

Agent: "Understood. Implementing LRU cache with TTL..."
```

</scenario>

<examples>

**Incremental tracking** (CodeRabbitAI pattern):
"Detected changes in auth.py and README.md since last review. Only analyzing those 2 files for new comments, not re-reviewing entire PR (10 other files unchanged)."

**Accepted suggestion tracking** (Qodo Merge pattern):
"Tracked 5 accepted review suggestions to wiki page. Pattern analysis shows reviewer frequently requests error handling additions - proactively including in future PRs."

**Progressive escalation**:
"Comments #1-3 implemented directly (high confidence). Comment #4 needs clarification (low confidence) - asking user before proceeding."

**Comment reply with quote and mention** (proper format):
```markdown
@reviewer-name

> Extract timeout to constant

Done! Extracted to `DEFAULT_TIMEOUT = 30` in constants.py.

Fixed in commit abc1234.
```

Then mark as resolved after confirming fix is correct.

</examples>

<forbidden>

**Bad comment reply** (missing quote or mention):
```markdown
Fixed the timeout issue.
```

This doesn't quote the original comment, mention the reviewer, or reference the commit. Makes it hard for reviewers to track what was addressed.

**Not marking resolved**:
Addressing a comment but leaving the thread open/unresolved. Reviewers have to manually check all comments to see what's done.

**Merging with unresolved comments**:
Proceeding to merge when review comments still show "unresolved" status or reviewer explicitly requested changes.

**Ignoring new comments**:
Merging after addressing initial comments without checking if reviewer added new comments after seeing your changes.

**Force-pushing during active review**:
Using `git push --force` while review is ongoing, which can lose review comment context and confuse reviewers.

**Bypassing CI or approval requirements**:
Attempting to merge when CI checks are failing or required approvals not met.

**Auto-implementing low-confidence requests**:
Implementing ambiguous review comments without asking for clarification first.

</forbidden>

## Merging Pull Requests

### Pre-Merge Checklist

<required>

- MUST have all CI checks passing
- MUST have required approvals
- MUST be up-to-date with base branch
- MUST have no merge conflicts
- MUST have related issues linked

</required>

### Merge Strategies

<context>

**Merge commit:**
- Creates a merge commit preserving all individual commits
- **Use for**: Feature branches with multiple logical commits
- Maintains complete history of branch development

**Squash and merge:**
- Combines all commits into a single commit
- **Use for**: Small fixes, documentation updates, single logical change
- Clean main branch history, but loses individual commit history

**Rebase and merge:**
- Replays commits on top of base branch
- **Use for**: When linear history is required and commits are clean
- No merge commits, but rewrites history

**When to use each:**
- **Merge commit**: Feature branches with meaningful commit history
- **Squash**: Tiny fixes, doc updates, experimental branches with messy commits
- **Rebase**: Projects requiring linear history with clean commits

</context>

### Post-Merge Cleanup

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

See "Branch Deletion with Stacked PRs" section and "Agent-Assisted Stack Management" for automated workflows.

### Agent Post-Merge Workflow

<scenario>

**Context**: Agent just merged PR or user informs agent of merge

**Agent workflow**:
1. Check if merged PR has child PRs (parse "Blocks: #{number}" in PR body)
2. If children exist, trigger cascade update workflow
3. If no children, perform standard cleanup
4. Sync local repository

```sh
# After merging PR #123
MERGED_BRANCH=$(gh pr view 123 --json headRefName -q .headRefName)

# Check for child PRs
CHILD_PRS=$(gh pr list --json number,body --jq '.[] | select(.body | contains("Depends on: #123")) | .number')

if [ -n "$CHILD_PRS" ]; then
  # Agent: "I found {N} child PR(s). Shall I update them now?"
  # Trigger cascade update workflow (see Proactive Branch Freshness Monitoring)
else
  # Standard cleanup
  git checkout main
  git fetch --prune origin
  git pull origin main
  git branch -d "$MERGED_BRANCH"
  git ls-remote --exit-code --heads origin "$MERGED_BRANCH" >/dev/null 2>&1 && \
    git push origin --delete "$MERGED_BRANCH"
fi
```

**Stacked PR cascade example**:
```
User: "PR #123 merged"
Agent: "PR #123 (feature/auth_base) merged. Found stack:
  main
   └─ PR #123 (merged) ← feature/auth_base
       ├─ PR #124 ← feature/auth_login (child, 245 lines)
       └─ PR #125 ← feature/auth_session (grandchild, 180 lines)

Auto-updating stack..."
Agent: [Updates #124 base to main, rebases onto origin/main]
Agent: "✓ PR #124 rebased successfully. No conflicts."
Agent: [Updates #125 base, rebases]
Agent: "✓ PR #125 rebased successfully. No conflicts."
Agent: [Deletes local and remote feature/auth_base]
Agent: "Stack updated. All PRs ready for continued review."
```

</scenario>

<forbidden>

- NEVER use `git branch -D` (force delete) unless you are certain the branch should be abandoned
- NEVER delete local branch before PR is merged
- NEVER skip `git fetch --prune` (leaves stale remote-tracking refs)

</forbidden>

## Agent-Created Pull Requests

**Context**: AI agents (Claude Code, GitHub Copilot) creating PRs

<required>

- Agent MUST analyze full commit history from base branch divergence
- Agent MUST review ALL changed files (not just latest commit)
- Agent MUST write summary based on actual cumulative changes
- Agent MUST run all checks before PR creation
- Agent MUST verify branch tracks correct remote
- Agent MUST check if branch is current with base before PR creation
- Agent MUST offer to rebase if branch is behind base
- Agent MUST verify no merge conflicts exist with base

**Pre-PR freshness check**:
```sh
# Before creating PR
git fetch origin
BASE_BRANCH="main"  # or detect from git config
BEHIND=$(git rev-list HEAD..origin/$BASE_BRANCH --count)

if [ "$BEHIND" -gt 0 ]; then
  # Agent: "Your branch is {N} commits behind {base}. Rebase before creating PR?"
fi
```

</required>

### PR Description Auto-Generation

<context>

**Industry Standard**: AI assistants can generate comprehensive PR descriptions achieving 80% user satisfaction by analyzing code changes and commit history (GitHub Copilot research).

**Philosophy**: Generate context-aware PR descriptions that save time while maintaining quality. Include ticket integration and compliance analysis for complete context.

</context>

<required>

**Before creating PR**, agent MUST:

1. Analyze full diff: `git diff origin/main...HEAD`
2. Read ALL commit messages: `git log origin/main..HEAD --format='%s%n%b'`
3. Read ALL changed files (verify contents, don't assume)
4. Identify associated tickets from GitHub Issues, commit messages, or branch names
5. Generate structured summary:
   - **What**: 2-3 bullets describing changes
   - **Why**: Purpose/motivation (from commits + tickets)
   - **Testing**: How to verify (from test files or commit descriptions)
   - **Dependencies**: Links to related PRs/issues (stacked PRs, blocking issues)
   - **Compliance**: How changes fulfill ticket requirements (if applicable)

**PR Description Template**:
```markdown
## Summary
- [Main change - what was added/fixed/changed]
- [Secondary change or impact]
- [Additional context if needed]

## Context
[Why this change is needed - from commit messages and associated tickets]

## Testing
- [How to verify the changes work - from test files or manual steps]
- [Specific test commands or scenarios]

## Dependencies
- Depends on: #[PR number] (if this is a stacked PR)
- Fixes: #[issue number] (if fixing a reported bug)
- Blocks: #[PR number] (if other PRs depend on this)

## Related Tickets
- Closes: #[issue number] or JIRA-[ticket-id]
- Relates to: #[issue number] (if related but doesn't close)
```

**Customization**: Include project-specific code conventions in generated descriptions (Devin AI best practice).

</required>

<scenario>

**Agent workflow example**:
```
User: "Create PR for this work"

Agent: [Analyzes full diff from base branch]
Agent: [Reads ALL commits: git log origin/main..HEAD]
Agent: [Reads ALL changed files to verify contents]
Agent: [Identifies ticket references in commits/branch name]

Agent: "I'll create PR with this description:

## Summary
- Add OAuth2 authentication with automatic token refresh
- Implement rate limiting (10 requests/min per user)
- Update API documentation with authentication examples

## Context
Users need secure API access without exposing credentials (closes #42).
OAuth2 provides industry-standard token-based authentication with automatic
token refresh for improved security.

## Testing
- Unit tests: `pytest tests/test_auth.py`
- Integration tests: `pytest tests/integration/test_oauth_flow.py`
- Manual verification: POST /oauth/token with client credentials

## Dependencies
- Fixes: #42 (API authentication requirement)

## Related Tickets
- Closes: #42 (Add OAuth2 authentication)

Looks good?"

User: "Yes"
Agent: [Creates PR with generated description using gh or platform API]
```

</scenario>

<examples>

**Comprehensive analysis**:
"Analyzed 5 commits across 12 files. Generated summary covering auth implementation (auth.py:45-120), rate limiting middleware (middleware.py:23-45), and API docs (README.md:100-150)."

**Identifies gaps**:
"Generated description but noticed no tests were added in this PR. Should I mention this limitation in the PR description or add tests first?"

**Ticket integration**:
"Found reference to JIRA-1234 in commit messages. Including acceptance criteria from that ticket in PR description for reviewer context."

</examples>

<forbidden>

**Only analyzed latest commit** (should analyze ALL commits):
"PR adds authentication" - but PR actually includes 5 commits with auth + rate limiting + docs. Agent only looked at latest commit message instead of full diff.

**Assumed file contents** (should read ALL files):
"PR updates auth.py and docs" - but doesn't describe WHAT changes were made because agent didn't actually read the files.

**Generic summaries** (should be specific):
"Updated files" - provides no value. Should describe actual changes with file:line references.

</forbidden>

<examples>

**Workflow**:
```sh
git diff base...HEAD
git log base..HEAD
poetry run ruff format . && poetry run ruff check --fix .
poetry run pytest
```

</examples>

### Common Agent Mistakes

<forbidden>

- **NEVER** analyze only the latest commit for PR summary
- **NEVER** skip full diff review (base...HEAD)
- **NEVER** create PR without running checks
- **NEVER** assume file contents without reading
- **NEVER** write generic summaries ("updated files")

</forbidden>

**Example - Bad vs Good**:
```markdown
Bad (only looked at latest commit):
Summary:
- Fixed typo in README

(But PR actually includes 5 commits adding entire auth system!)

Good (analyzed full diff):
Summary:
- Implement OAuth2 authentication with token refresh
- Add rate limiting to prevent abuse (10 req/min)
- Update API documentation with auth examples

(Accurately reflects all 5 commits in the PR)
```

### PR Analysis Checklist

<required>

Before creating PR, agent MUST:

1. Run `git diff base...HEAD` to see cumulative changes
2. Run `git log base..HEAD` to see all commits
3. Read all modified files (not assume contents)
4. Identify cumulative impact across all commits
5. Verify tests pass for all changes
6. Draft summary reflecting full PR scope

</required>

**See**: `$HOME/.smith/rules-ai_agents.md` - Complete agent interaction standards

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
git merge-tree $(git merge-base HEAD origin/main) HEAD origin/main | grep -q "^+<<<<<<<" && echo "conflicts" || echo "clean"
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
BEHIND=$(git rev-list origin/$BRANCH..origin/$BASE --count)

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
BEHIND=$(git rev-list origin/$BRANCH..origin/$BASE --count)

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
git merge-tree $(git merge-base HEAD origin/$BASE) HEAD origin/$BASE
# If conflicts detected, INFORM + ASK

# 5. Check if force-push is safe
git log @{upstream}.. --oneline
# If branch already pushed, warn about force-push
```

</required>

### Error Handling and Recovery

<required>

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
BEHIND=$(git rev-list HEAD..origin/$BASE_BRANCH --count)
DAYS_OLD=$(git log -1 --format=%cd --date=relative)

# Optional: Check for potential conflicts (dry-run)
CONFLICTS=$(git merge-tree $(git merge-base HEAD origin/$BASE_BRANCH) HEAD origin/$BASE_BRANCH | grep -c "^@@" || echo 0)
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

<examples>

**Proactive prevention**:
"Checked PR #123 freshness. 12 commits behind main. Offering rebase BEFORE user starts work prevents conflicts."

**Context-aware AI resolution**:
"Auto-resolved whitespace conflicts in 3 files. For function signature conflict in auth.py:78, analyzed both changes and suggested combining parameters rather than choosing one side."

**Stacked PR intelligence**:
"Detected 'Depends on: #123' in PR #124 body. When #123 merges, automatically offering to rebase #124 to maintain stack integrity."

</examples>

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

## Agent Workflow Guidelines

### Pre-Commit Hook Coordination

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

### CI Check Coordination

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

### Amend Operations Safety

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
if [ "$AUTHOR" != "your-email@example.com" ]; then
  echo "Not your commit - create new commit instead"
  exit 1
fi
if git log @{upstream}.. | grep -q $(git rev-parse HEAD); then
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


### Troubleshooting Common Issues

#### Issue 1: Changes Not Appearing in PR

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

#### Issue 2: Merge Conflicts After Base Branch Update

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

#### Issue 3: CI Checks Fail After Pre-Commit Hook

**Symptoms**: Pre-commit passes locally but CI fails

**Solution:**
```sh
poetry run ruff check . --config=<same-as-ci>
poetry run pytest --cov=<same-as-ci>
```

### Recovery Procedures

#### Scenario 1: Wrong Branch Checkout

**Problem**: Made changes to wrong branch

**Solution**: See "Recovery if You Made This Mistake" section above

#### Scenario 2: Accidentally Pushed to Wrong Remote

**Problem**: Pushed PR branch to wrong repository

**Solution:**
```sh
git remote -v
git remote remove wrong-remote
git remote add origin <correct-repo-url>
git push -u origin <branch-name>
```

#### Scenario 3: Need to Undo Last Commit but Keep Changes

**Problem**: Made commit but want to redo it differently

**Solution:**
```sh
git reset --soft HEAD~1
git reset HEAD~1
git add .
git commit -m "better commit message"
```

#### Scenario 4: Syncing with Updated Base Branch

**Problem**: Base branch (main/develop) has new commits

**Solution:**
```sh
git fetch origin
git rebase origin/main
git push --force-with-lease
git merge origin/main
git push
```

## Best Practices

### PR Size

<constraints>

- Keep PRs focused and small (< 400 lines changed ideal)
- Split large features into multiple PRs
- Use draft PRs for work in progress
- One logical change per PR

</constraints>

### Communication

- Use PR comments for technical discussions
- Use issue comments for requirements and planning
- Tag relevant team members with @mentions
- Be respectful and constructive in reviews
- Explain your reasoning in review responses

### Documentation

- Update README if public API changes
- Update CHANGELOG for notable changes
- Add inline code comments for complex logic
- Include examples in PR description for new features

### CI Integration

- Ensure all tests run in CI
- Set up automatic deployment previews when possible
- Configure status checks as required
- Monitor CI failures and fix promptly

## Related Standards

- **Git Operations**: `$HOME/.smith/rules-git.md` - Commits, branches, merges
- **Development Workflow**: `$HOME/.smith/rules-development.md` - Daily practices, quality gates
- **Testing**: `$HOME/.smith/rules-testing.md` - Test requirements
- **Platform-Specific**: See your platform's rules file (e.g., rules-github.md for GitHub CLI)
