# GitHub PR Automation Workflows

<metadata>

- **Scope**: Complete PR lifecycle automation - creation, review, rebase, and post-merge operations
- **Load if**: Creating PRs, responding to review feedback, managing PR branches, post-merge operations
- **Prerequisites**: rules-pr-concepts.md, rules-github-cli.md, rules-ai_agents.md
- **Token efficiency**: Use perPage, minimal_output parameters (see rules-github-cli.md)

</metadata>

<context>

## Scope

This document covers the complete GitHub PR automation workflow:
- **PR creation and description generation**
- **Review cycle automation** (review→fix→re-review)
- **Rebase and branch freshness monitoring**
- **Post-merge operations and cleanup**

For platform-neutral PR concepts, see rules-pr-concepts.md.

## Dual-Approach Pattern

**Two approaches for all GitHub PR operations**:

**Preferred: GitHub MCP Server**
- Use MCP tools: `mcp__github__create_pull_request`, `mcp__github__merge_pull_request`, `mcp__github__update_pull_request`, `mcp__github__pull_request_read`, `mcp__github__list_pull_requests`
- Built-in validation and structured response
- Clearer tool names and structured parameters
- Less error-prone than command-line parsing

**Fallback: gh CLI**
- Use commands: `gh pr create`, `gh pr merge`, `gh pr edit`, `gh pr view`, `gh pr list`
- Works without MCP installation
- Widely available and well-documented
- Requires command-line parsing

**Decision logic**: Try MCP tools first. If not available or tool call fails, fall back to gh CLI.

</context>

---

# PR Creation and Description Generation

**Context**: AI automation creating PRs with comprehensive descriptions

## Creating Pull Requests

<required>

- MUST analyze full commit history from base branch divergence
- MUST review ALL changed files (not just latest commit)
- MUST write summary based on actual cumulative changes
- MUST run all checks before PR creation
- MUST verify branch tracks correct remote
- MUST check if branch is current with base before PR creation
- MUST offer to rebase if branch is behind base
- MUST verify no merge conflicts exist with base

**Pre-PR freshness check**:
```sh
git fetch origin
BASE_BRANCH="main"
BEHIND=$(git rev-list HEAD.."origin/$BASE_BRANCH" --count)

if [ "$BEHIND" -gt 0 ]; then
  echo "Branch is $BEHIND commits behind $BASE_BRANCH. Rebase before creating PR?"
fi
```

</required>

## PR Description Auto-Generation

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

## PR Creation Workflow Example

<scenario>

```text
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
Agent: [Creates PR using MCP or gh CLI]
```

</scenario>

## PR Creation Best Practices

<examples>

**Comprehensive analysis**:
"Analyzed 5 commits across 12 files. Generated summary covering auth implementation (auth.py:45-120), rate-limiting middleware (middleware.py:23-45), and API docs (README.md:100-150)."

**Identifies gaps**:
"Generated description but noticed no tests were added in this PR. Should I mention this limitation in the PR description or add tests first?"

**Ticket integration**:
"Found reference to JIRA-1234 in commit messages. Including acceptance criteria from that ticket in PR description for reviewer context."

</examples>

## PR Creation Common Mistakes

<forbidden>

- **NEVER** analyze only the latest commit for PR summary
- **NEVER** skip full diff review (base...HEAD)
- **NEVER** create PR without running checks
- **NEVER** assume file contents without reading
- **NEVER** write generic summaries ("updated files")

**Only analyzed latest commit** (should analyze ALL commits):
"PR adds authentication" - but PR actually includes 5 commits with auth + rate limiting + docs. Only looked at latest commit message instead of full diff.

**Assumed file contents** (should read ALL files):
"PR updates auth.py and docs" - but doesn't describe WHAT changes were made because didn't actually read the files.

**Generic summaries** (should be specific):
"Updated files" - provides no value. Should describe actual changes with file:line references.

</forbidden>

## PR Analysis Checklist

<required>

Before creating PR, MUST:

1. Run `git diff base...HEAD` to see cumulative changes
2. Run `git log base..HEAD` to see all commits
3. Read all modified files (not assume contents)
4. Identify cumulative impact across all commits
5. Verify tests pass for all changes
6. Draft summary reflecting full PR scope

</required>

---

# Review Cycle Automation

**Philosophy**: Automate the iterative review→fix→re-review cycle until all comments are resolved, then proceed to merge when approved.

**Industry Best Practices**:
- **CodeRabbitAI**: Incremental review tracking - only review changed files, not entire PR on each iteration
- **Qodo Merge**: `/implement` command directly applies reviewer suggestions with tracking
- **Devin AI**: Confidence scoring (high/medium/low) determines whether to implement directly or ask user first
- **OpenHands**: Label-triggered workflows (e.g., "review-this" label auto-starts review cycle)
- **Real-world impact**: 73.8% of automated review comments marked "Resolved", 30% reduction in review time

## Review Cycle Workflow

<required>

**Iterative review cycle workflow**:

<instructions>

1. **Trigger points** (any of these):
   - User: "address comments on PR #123" or "@agent address comments"
   - Label: "review-this" or "needs-fixes" added to PR (OpenHands pattern)
   - Auto: After reviewer requests changes
   - **Proactive check**: When starting work on existing PR
     - ALWAYS fetch review comments before making changes
     - Check for both CHANGES_REQUESTED reviews AND COMMENT reviews
     - Alert user if unaddressed comments exist
     - Ask: "Address comments first or proceed with new changes?"

<context>

**CRITICAL: GitHub has TWO types of comments**:

**Type 1: General PR comments** (conversation timeline):
- Posted via `gh pr comment {PR} --body "..."`
- Show up in main PR conversation
- Fetched via `gh pr view {PR} --json comments`
- Cannot be marked "resolved"
- IDs start with IC_ (e.g., IC_kwDOQckce87X60Z1)

**Type 2: Inline review thread comments** (code review):
- Posted on specific code lines during review
- Fetched via REST API: `gh api repos/{owner}/{repo}/pulls/{PR}/comments`
- Can be marked "resolved"
- Numeric IDs (e.g., 2596414027)
- **THIS IS WHAT CodeRabbitAI, GitHub Copilot, and human reviewers post**

**For fetching review comments**: Use MCP (`mcp__github__pull_request_read` with method="get_review_comments") or gh CLI REST API
**For replying and resolving**: Use gh CLI `/replies` endpoint and GraphQL API (MCP doesn't support these)

</context>

### Pre-Work Review Comment Check

<required>

**When starting work on ANY existing PR** (before making changes):

1. **Fetch review comments**:
   ```sh
   gh api /repos/{owner}/{repo}/pulls/{PR}/comments | jq -r '.[] |
     select(.user.type == "Bot" and .in_reply_to_id == null) |
     "\(.id): \(.user.login) - \(.body[:100])"'
   ```

2. **Check comment threads**:
   - Look for unresolved threads from CodeRabbitAI, Copilot, human reviewers
   - Filter for top-level comments (in_reply_to_id == null)
   - Identify nitpick, suggestion, and issue comments

3. **Alert user**:
   - "Found X unaddressed review comments from [bots/reviewers]"
   - Show comment IDs and first 100 chars of each
   - Ask: "Address these comments first or proceed with planned changes?"

4. **Only if user chooses to address**: Enter review cycle automation workflow

</required>

<context>

**Why This Matters**:
- CodeRabbitAI posts COMMENT reviews (not CHANGES_REQUESTED)
- COMMENT reviews don't change PR state
- Without proactive checking, informational feedback is missed

</context>

2. **Fetch inline review thread comments**:

   **Using GitHub MCP** (preferred):
   ```text
   Use MCP tool: mcp__github__pull_request_read
   Parameters:
     - method: "get_review_comments"
     - owner: {owner}
     - repo: {repo}
     - pullNumber: {PR}
     - perPage: 10              # ULTRA-conservative: CodeRabbitAI comments have massive HTML/analysis
     - page: 1

   Returns: List of inline review comment objects with id, path, line, body, user
   ```

   **If PR has 10+ review comments**, fetch subsequent pages by incrementing `page` parameter.

   **Using gh CLI** (fallback):
   ```sh
   gh api "repos/{owner}/{repo}/pulls/{PR}/comments" | jq '.[] | {id, path, line, body, user: .user.login}'
   ```

3. **Categorize comments**:
   - **Actionable**: Specific code changes requested (can be implemented)
   - **Clarification**: Questions needing answers (respond in comment thread)
   - **Discussion**: Architectural/subjective decisions (needs human input)

4. **For each actionable comment**:
   - **Analyze confidence**: Determine if request is clear and unambiguous
   - **High confidence (>70%)**: Implement directly and document changes
   - **Medium confidence (40-70%)**: Implement and request confirmation of approach
   - **Low confidence (<40%)**: Ask user for clarification before implementing
   - **Track mapping**: Comment ID → Commit SHA that addresses it

   **Reply to inline review thread comment** (gh CLI + REST API):
   ```sh
   COMMENT_ID=2596414027
   COMMIT_SHA="abc1234"
   REVIEWER="coderabbitai"
   OWNER="{owner}"
   REPO="{repo}"
   PR_NUMBER=21

   gh api \
     -X POST \
     -H "Accept: application/vnd.github+json" \
     -H "X-GitHub-Api-Version: 2022-11-28" \
     "/repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments/$COMMENT_ID/replies" \
     -f body="@${REVIEWER}

> [Quote the original review comment here]

Fixed in commit ${COMMIT_SHA}."
   ```

   **IMPORTANT**: Use the `/replies` endpoint, NOT the base `/comments` endpoint. The `in_reply_to` parameter does NOT work.

   **Mark thread as resolved** (gh CLI + GraphQL API - requires two steps):

   **Step 1: Find the thread ID for your comment**:
   ```sh
   THREAD_ID=$(gh api graphql -f query='
   query {
     repository(owner: "'"$OWNER"'", name: "'"$REPO"'") {
       pullRequest(number: '"$PR_NUMBER"') {
         reviewThreads(first: 100) {
           nodes {
             id
             isResolved
             comments(first: 10) {
               nodes {
                 databaseId
               }
             }
           }
         }
       }
     }
   }' | jq -r '.data.repository.pullRequest.reviewThreads.nodes[] |
     select(.comments.nodes[] | .databaseId == '"$COMMENT_ID"') | .id')
   ```

   **Step 2: Resolve the thread**:
   ```sh
   gh api graphql -f query='
   mutation {
     resolveReviewThread(input: {threadId: "'"$THREAD_ID"'"}) {
       thread {
         id
         isResolved
       }
     }
   }'
   ```

   <forbidden>

   **NEVER mention bots when replying to review comments**:

   - `@copilot Thank you for the feedback!` → Triggers unwanted PR creation
   - `@coderabbitai Thanks for the review!` → Unnecessary bot notification

   **CRITICAL: When replying to Copilot's inline review comments, NEVER mention `@copilot`.**

   **Rationale**: Copilot is designed to open sub-PRs when mentioned. Mentioning `@copilot` in acknowledgment replies triggers unwanted sub-PR creation.

   </forbidden>

   <required>

   **When to use @copilot** (ONLY when requesting action):
   - `@copilot Please implement this suggestion`
   - `@copilot Fix the issue you identified`

   </required>

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
   - Branch is fresh (not stale - see Rebase section below)
   - No merge conflicts with base branch

   If ALL criteria met: Proceed to merge (with user confirmation)
   If ANY criteria not met: Inform user what's blocking

8. **Verify all review threads resolved**:

   **Using GitHub MCP**:
   ```text
   Use MCP tool: mcp__github__pull_request_read
   Parameters:
     - method: "get_review_comments"
     - owner: {owner}
     - repo: {repo}
     - pullNumber: {PR}
     - perPage: 10
     - page: 1

   Filter results for comments with in_reply_to_id == null (root comments without replies)
   If any exist, review and address them before merging.
   ```

   **Using gh CLI + GraphQL**:
   ```sh
   gh api graphql -f query='query {
     repository(owner: "'"$OWNER"'", name: "'"$REPO"'") {
       pullRequest(number: '"$PR_NUMBER"') {
         reviewThreads(first: 100) {
           nodes {
             isResolved
           }
         }
       }
     }
   }' | jq '.data.repository.pullRequest.reviewThreads.nodes | map(select(.isResolved == false)) | length'
   ```

   If count > 0, review and resolve remaining threads before proceeding to merge.

</instructions>

</required>

## Review Cycle Example

<scenario>

```text
User: "@agent address review comments on PR #123"

Agent: [Fetches inline review thread comments]

Agent: "Found 3 actionable inline review thread comments from @reviewer:

1. auth.py:45 - 'Extract timeout value to named constant' [Confidence: 95%]
2. tests/auth_test.py:12 - 'Add test case for expired tokens' [Confidence: 85%]
3. README.md:100 - 'Update docs with new rate limiting behavior' [Confidence: 60%]

Comments #1 and #2 are clear. For #3, should I document both the 10 req/min limit AND the exponential backoff strategy, or just the limit?"

User: "Document both"

Agent: [Implements all 3 changes in separate atomic commits]
Agent: [Pushes to PR branch]
Agent: [Replies to each inline review thread comment]
Agent: [Marks comment threads as resolved]
Agent: "Pushed 3 atomic commits addressing all review comments. Waiting for CI checks and re-review..."

Agent: [Checks for new comments after CI passes]
Agent: [Verifies all review threads resolved]

Agent: "No new review comments. All 3 inline review threads addressed and marked resolved. CI checks passing.

Auto-merge readiness:
- All review threads resolved (3/3)
- No new comments from reviewers
- CI checks passing (all 5 checks green)
- 2 approvals received (requirement: 1)
- Branch is fresh (rebased 10 minutes ago)
- No merge conflicts

Ready to merge. Proceed with squash and merge?"

User: "Yes"
Agent: [Executes merge]
```

</scenario>

---

# Rebase and Branch Freshness Monitoring

**Philosophy**: Prevention over cure - detect branch staleness early and offer rebase before conflicts occur.

**Industry Standard**: Modern tools like Graphite automate stack rebasing. AI conflict resolution tools (GitKraken AI, GitHub Copilot, Cursor Agent) auto-resolve simple conflicts while escalating complex cases to humans.

## When to Detect Rebase Needs

<required>

MUST check for rebase needs in these scenarios:

1. **Before PR review request**: Verify PR is current with base branch
2. **After parent PR merge**: Detect child PRs that need rebasing
3. **When working on existing PR**: Check if base branch has advanced
4. **Before merge operations**: Ensure no conflicts with latest base

**Detection commands**:
```sh
git fetch origin
git rev-list HEAD..origin/main --count

git merge-tree "$(git merge-base HEAD origin/main)" HEAD origin/main | grep -q "^<<<<<<< " && echo "conflicts" || echo "clean"
```

</required>

## Decision Tree: When to Rebase Automatically vs Ask

<required>

**Decision matrix**:

| Scenario | Action | Rationale |
|----------|-------------|-----------|
| PR behind base, no conflicts, user not explicitly working on it | ASK user | Respectful of user control |
| PR behind base, no conflicts, user just said "update PR" | AUTO-REBASE | Clear intent |
| PR behind base, conflicts detected | INFORM + ASK | Requires manual resolution |
| Parent PR merged, child PR exists | INFORM + OFFER | Helpful but not intrusive |
| About to request review, PR outdated | BLOCK + INFORM | Prevent bad review request |
| PR current with base | DO NOTHING | No action needed |

**Safe auto-rebase criteria** (ALL must be true):
1. User gave explicit update/rebase command
2. No merge conflicts detected
3. Branch is not shared (only user has commits)
4. Branch tracks correct remote
5. Working directory is clean

</required>

## Rebase Workflows

### Workflow 1: Pre-Review Freshness Check

<scenario>

**Trigger**: User says "request review on PR #123" or about to request review

**Using GitHub MCP** (preferred):
```text
Use MCP tool: mcp__github__pull_request_read
Parameters:
  - owner: {owner}
  - repo: {repo}
  - pullNumber: 123
  - method: "get"

git fetch origin
BEHIND=$(git rev-list HEAD.."origin/{baseRefName}" --count)

if [ "$BEHIND" -gt 0 ]; then
  git rebase "origin/{baseRefName}"
  git push --force-with-lease

  Use MCP tool: mcp__github__update_pull_request
  Parameters:
    - owner: {owner}
    - repo: {repo}
    - pullNumber: 123
    - reviewers: ["reviewer-username"]
fi
```

**Using gh CLI** (fallback):
```sh
BRANCH=$(gh pr view 123 --json headRefName -q .headRefName)
BASE=$(gh pr view 123 --json baseRefName -q .baseRefName)

git fetch origin
BEHIND=$(git rev-list "origin/$BRANCH".."origin/$BASE" --count)

if [ "$BEHIND" -gt 0 ]; then
  git checkout "$BRANCH"
  git rebase "origin/$BASE"
  git push --force-with-lease
  gh pr edit 123 --add-reviewer @reviewer
fi
```

</scenario>

### Workflow 2: Post-Parent-Merge Cascade

<scenario>

**Trigger**: Parent PR in stack just merged

**Using GitHub MCP** (preferred):
```text
Use MCP tool: mcp__github__pull_request_read to get parent PR details
Use MCP tool: mcp__github__list_pull_requests to find children (filter for "Depends on: #123" in body)

For each CHILD_PR:
  Use MCP tool: mcp__github__update_pull_request to update base to "main"
  git rebase --onto origin/main "$PARENT_BRANCH"
  git push --force-with-lease

git push origin --delete "$PARENT_BRANCH"
```

**Using gh CLI** (fallback):
```sh
PARENT_BRANCH=$(gh pr view 123 --json headRefName -q .headRefName)
CHILD_PRS=$(gh pr list --json number,body --jq '.[] | select(.body | contains("Depends on: #123")) | .number')

for CHILD_PR in $CHILD_PRS; do
  gh pr edit "$CHILD_PR" --base main
  git checkout "$(gh pr view "$CHILD_PR" --json headRefName -q .headRefName)"
  git rebase --onto origin/main "$PARENT_BRANCH"
  git push --force-with-lease
done

git push origin --delete "$PARENT_BRANCH"
```

</scenario>

### Workflow 3: Periodic Freshness Detection

<scenario>

**Trigger**: User asks to work on PR, or performing any PR operation

```sh
BRANCH=$(gh pr view 123 --json headRefName -q .headRefName)
BASE=$(gh pr view 123 --json baseRefName -q .baseRefName)

git fetch origin
BEHIND=$(git rev-list "origin/$BRANCH".."origin/$BASE" --count)

if [ "$BEHIND" -gt 5 ]; then
  echo "Note: This PR is $BEHIND commits behind $BASE. Rebase?"
fi
```

</scenario>

## Proactive Branch Freshness Monitoring

<required>

**Monitor PR branch staleness** when:
- User says "work on PR #123" or "check PR status"
- User says "ready to request review"
- User returns to session (background check on session start)

**Staleness check**:
```sh
git fetch origin
BASE_BRANCH="main"
BEHIND=$(git rev-list HEAD.."origin/$BASE_BRANCH" --count)
DAYS_OLD=$(git log -1 --format=%cd --date=relative)

CONFLICTS=$(git merge-tree "$(git merge-base HEAD "origin/$BASE_BRANCH")" HEAD "origin/$BASE_BRANCH" | grep -c "^<<<<<<< " || echo 0)
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

## Rebase Safety Checks

<required>

MUST verify ALL of these before rebasing:

```sh
RECENT_AUTHORS=$(git log -5 --format='%ae' | sort -u)
git status --porcelain
git branch -vv | grep "$BRANCH"
git merge-tree "$(git merge-base HEAD "origin/$BASE")" HEAD "origin/$BASE"
git log @{upstream}.. --oneline
```

</required>

## Rebase Error Handling

<required>

**If rebase fails**:
```sh
git rebase --abort
```

**If force-push fails**: Check git status and resolve authentication or branch protection issues.

</required>

---

# Post-Merge Operations and Cleanup

**Context**: Operations to perform after PR is merged

## Branch Deletion with Stacked PRs

<forbidden>

**NEVER use `--delete-branch` when merging a PR that has dependent child PRs.**

The GitHub API immediately deletes the branch, closing all child PRs before their base can be updated. This is a known GitHub API limitation ([cli/cli#1168](https://github.com/cli/cli/issues/1168)).

</forbidden>

<required>

**Process for stacked PRs:**

1. Merge parent PR WITHOUT deleting branch:

   **Using GitHub MCP** (preferred):
   ```text
   Use MCP tool: mcp__github__merge_pull_request
   Parameters:
     - owner: {owner}
     - repo: {repo}
     - pullNumber: 123
     - merge_method: "squash"
   ```

   **Using gh CLI** (fallback):
   ```sh
   gh pr merge 123 --squash
   ```

2. Update child PR base and rebase:

   **Using GitHub MCP** (preferred):
   ```text
   Use MCP tool: mcp__github__update_pull_request
   Parameters:
     - owner: {owner}
     - repo: {repo}
     - pullNumber: 124
     - base: "main"

   git fetch origin
   git checkout feat/child_branch
   git rebase --onto origin/main feat/parent_branch
   git push --force-with-lease
   ```

   **Using gh CLI** (fallback):
   ```sh
   gh pr edit 124 --base main
   git fetch origin
   git checkout feat/child_branch
   git rebase --onto origin/main feat/parent_branch
   git push --force-with-lease
   ```

3. Delete parent branch AFTER child is updated:
   ```sh
   git push origin --delete feat/parent_branch
   ```

</required>

## Post-Merge Workflow

<scenario>

**Context**: Just merged PR or user informs of merge

**Workflow**:
1. Check if merged PR has child PRs (parse "Blocks: #{number}" in PR body)
2. If children exist, trigger cascade update workflow (see Workflow 2 above)
3. If no children, perform standard cleanup
4. Sync local repository

**Using GitHub MCP** (preferred):
```text
Use MCP tool: mcp__github__pull_request_read to get merged PR details
Use MCP tool: mcp__github__list_pull_requests to find children

if CHILD_PRS exist:
  [Trigger cascade update workflow]
else:
  git checkout main
  git fetch --prune origin
  git pull origin main
  git branch -d "$MERGED_BRANCH"
  git push origin --delete "$MERGED_BRANCH"
```

**Using gh CLI** (fallback):
```sh
MERGED_BRANCH=$(gh pr view 123 --json headRefName -q .headRefName)
CHILD_PRS=$(gh pr list --json number,body --jq '.[] | select(.body | contains("Depends on: #123")) | .number')

if [ -n "$CHILD_PRS" ]; then
  echo "Found child PRs. Triggering cascade update workflow."
else
  git checkout main
  git fetch --prune origin
  git pull origin main
  git branch -d "$MERGED_BRANCH"
  git ls-remote --exit-code --heads origin "$MERGED_BRANCH" >/dev/null 2>&1 && \
    git push origin --delete "$MERGED_BRANCH"
fi
```

</scenario>

## Post-Merge Cleanup

**For stacked PRs** (parent with children):
Use the cascade update workflow described above.

**For non-stacked PRs** (simple feature branch):
See rules-pr-concepts.md for standard cleanup workflow:
```sh
git checkout main
git fetch --prune origin
git pull origin main
git branch -d feat/my_feature
git ls-remote --exit-code --heads origin feat/my_feature >/dev/null 2>&1 && \
  git push origin --delete feat/my_feature
```

<forbidden>

- NEVER use `git branch -D` (force delete) unless you are certain the branch should be abandoned
- NEVER delete local branch before PR is merged
- NEVER skip `git fetch --prune` (leaves stale remote-tracking refs)
- NEVER use `--delete-branch` flag when merging stacked PRs

</forbidden>

---

# Related Standards

- **PR Concepts**: rules-pr-concepts.md - Platform-neutral PR workflows, stacked PRs, code review process
- **GitHub CLI**: rules-github-cli.md - GitHub CLI commands and token efficiency
- **Git Operations**: rules-git.md - Local git operations, commits, branches
- **Workflow Utilities**: rules-github-utils.md - Troubleshooting and recovery procedures
- **AI Principles**: rules-ai_agents.md - Constitutional AI principles, exploration-before-implementation
