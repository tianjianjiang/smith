# GitHub Agent Review Cycle Automation

<metadata>

- **Scope**: Agent automation for iterative PR review cycles on GitHub
- **Load if**: Agent responding to PR review feedback, managing review iterations
- **Prerequisites**: [PR Concepts](./rules-pr-concepts.md), [GitHub PR Operations](./rules-github-pr.md)

</metadata>

<context>

## Scope

- **This document**: Automated review→fix→re-review cycles, inline comment handling, resolution tracking
- **Basic PR operations**: See [GitHub PR Operations](./rules-github-pr.md)
- **Other agent workflows**: See [PR Creation](./rules-github-agent-create.md), [Rebase](./rules-github-agent-rebase.md), [Post-Merge](./rules-github-agent-merge.md)

</context>

## Agent Review Cycle Automation

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

<instructions>

1. **Trigger points** (any of these):
   - User: "address comments on PR #123" or "@agent address comments"
   - Label: "review-this" or "needs-fixes" added to PR (OpenHands pattern)
   - Auto: After reviewer requests changes

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

**Two approaches for handling inline review comments**:

**Preferred: GitHub MCP Server** (when available):
- Clearer tool names: `reply_to_pull_request_comment`, `resolve_pull_request_review_thread`
- Built-in validation and error handling
- Simpler syntax, less error-prone
- Install: [github-mcp-server-review-tools](https://github.com/wjessup/github-mcp-server-review-tools)

**Fallback: gh CLI + GitHub REST API** (when MCP not available):
- Works without MCP installation
- Requires understanding GitHub API nuances
- More verbose commands
- Manual error handling

**Agent decision logic**: Try MCP tools first. If MCP not available or tool call fails, fall back to gh CLI + REST API.

</context>

2. **Fetch inline review thread comments** (not general PR comments):

   **Option A: Using GitHub MCP** (preferred):
   ```
   Use MCP tool: get_pull_request_review_threads
   Parameters:
     - owner: {owner}           # e.g., "tianjianjiang"
     - repo: {repo}             # e.g., "smith"
     - pull_number: {PR}        # e.g., 21

   Returns: List of inline review comment objects with id, path, line, body, user
   ```

   **Option B: Using gh CLI** (fallback):
   ```sh
   PR_NUMBER=123
   OWNER_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

   # CRITICAL: Fetch INLINE review comments (not general PR comments)
   # This fetches comments on specific code lines, not conversation comments
   gh api repos/$OWNER_REPO/pulls/$PR_NUMBER/comments > /tmp/inline_comments.json

   # Parse actionable comments
   cat /tmp/inline_comments.json | jq '.[] | {
     id: .id,
     path: .path,
     line: .line,
     body: .body,
     user: .user.login
   }'
   ```

   **Why this matters**: `gh pr view --json comments` fetches GENERAL PR comments (Type 1), not inline review threads (Type 2). You MUST use the REST API or MCP tool to get inline review comments.

3. **Categorize comments**:

   <planning_process>

   - **Actionable**: Specific code changes requested (can be implemented)
   - **Clarification**: Questions needing answers (respond in comment thread)
   - **Discussion**: Architectural/subjective decisions (needs human input)

   </planning_process>

4. **For each actionable comment** (Qodo Merge pattern):

   <planning_process>

   - **Analyze confidence**: Determine if request is clear and unambiguous
   - **High confidence (>70%)**: Implement directly and explain what was done
   - **Medium confidence (40-70%)**: Implement with explanation, ask for confirmation
   - **Low confidence (<40%)**: Ask user for clarification before implementing

   </planning_process>

   - **Track mapping**: Comment ID → Commit SHA that addresses it

   <final_instruction>

   **Reply to INLINE review thread comment**:

   **Option A: Using GitHub MCP** (preferred):
   ```
   Use MCP tool: reply_to_pull_request_comment
   Parameters:
     - owner: {owner}
     - repo: {repo}
     - pull_number: {PR}
     - comment_id: {comment_id}      # The inline review comment ID (numeric)
     - body: "@{reviewer}\n\n> {quoted_comment}\n\nFixed in commit {sha}"
   ```

   **Option B: Using gh CLI** (fallback):
   ```sh
   COMMENT_ID=2596414027  # The inline review comment ID
   COMMIT_SHA="abc1234"
   REVIEWER="coderabbitai"
   OWNER_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
   PR_NUMBER=21

   # Create reply in the inline review thread
   gh api repos/$OWNER_REPO/pulls/$PR_NUMBER/comments \
     -f body="@${REVIEWER}

> [Quote the original review comment here]

Fixed in commit ${COMMIT_SHA}." \
     -f in_reply_to=$COMMENT_ID
   ```

   **Mark thread as resolved**:

   **Option A: Using GitHub MCP** (preferred):
   ```
   Use MCP tool: resolve_pull_request_review_thread
   Parameters:
     - owner: {owner}
     - repo: {repo}
     - pull_number: {PR}
     - comment_id: {comment_id}      # The root comment ID of the thread
   ```

   **Option B: Using gh CLI** (fallback):
   ```sh
   # Get the review thread ID
   THREAD_ID=$(gh api repos/$OWNER_REPO/pulls/comments/$COMMENT_ID --jq '.pull_request_review_id')

   # Mark thread as resolved via GraphQL API
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

   </final_instruction>

   - **Verify resolution**: Check that thread shows as "Resolved" in GitHub UI

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

   <persistence>

   - Wait for PR checks to complete
   - Check if NEW review comments were posted
   - **If new comments exist**: Return to step 2 (repeat cycle)
   - **If no new comments AND all resolved**: Proceed to step 7

   </persistence>

7. **Auto-merge criteria check**:

   <verification>

   - All review comments addressed OR marked as resolved
   - No new comments in last check (reviewers had chance to re-review)
   - All CI/CD checks passing
   - Required number of approvals met
   - Branch is fresh (not stale - see [Branch Freshness Monitoring](./rules-github-agent-rebase.md))
   - No merge conflicts with base branch

   </verification>

   If ALL criteria met: Proceed to merge (with user confirmation)
   If ANY criteria not met: Inform user what's blocking

8. **Verify all review threads resolved**:

   <verification>

   **Option A: Using GitHub MCP** (preferred):
   ```
   Use MCP tool: check_pull_request_review_resolution
   Parameters:
     - owner: {owner}
     - repo: {repo}
     - pull_number: {PR}

   Returns: {
     all_resolved: true/false,
     unresolved_count: N,
     unresolved_threads: [...]  # List of unresolved comment IDs
   }
   ```

   If `all_resolved: false`, review and address remaining threads before proceeding to merge.

   **Option B: Using gh CLI** (fallback):
   ```sh
   OWNER_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
   PR_NUMBER=21

   # List unresolved threads (threads without replies or not marked resolved)
   # Root comments (in_reply_to_id == null) that haven't been replied to
   UNRESOLVED=$(gh api repos/$OWNER_REPO/pulls/$PR_NUMBER/comments | \
     jq '[.[] | select(.in_reply_to_id == null)] | length')

   if [ "$UNRESOLVED" -gt 0 ]; then
     echo "Warning: $UNRESOLVED review threads not yet addressed"
     echo "Review and reply to all inline comments before merging"
     exit 1
   else
     echo "All review threads have been addressed"
   fi
   ```

   </verification>

</instructions>

<final_instruction>

**CRITICAL: See step 4 above for correct inline review comment reply and resolution procedures.**

Use GitHub MCP tools (preferred) or gh CLI + REST API (fallback) as documented in step 4.

**DO NOT** use `gh pr comment` for inline review threads - it only works for general PR comments.

</final_instruction>

</required>

## Full Iterative Cycle Example

<scenario>

**Full iterative cycle example** (showing both MCP and gh CLI approaches):

```
User: "@agent address review comments on PR #123"

# ITERATION 1: Fetch and address comments
Agent: [Fetches inline review thread comments]

# Using GitHub MCP (preferred):
# get_pull_request_review_threads(owner="tianjianjiang", repo="smith", pull_number=123)

# OR gh CLI fallback:
# gh api repos/tianjianjiang/smith/pulls/123/comments

Agent: "Found 3 actionable inline review thread comments from @reviewer:

1. auth.py:45 - 'Extract timeout value to named constant' [Confidence: 95%]
2. tests/auth_test.py:12 - 'Add test case for expired tokens' [Confidence: 85%]
3. README.md:100 - 'Update docs with new rate limiting behavior' [Confidence: 60%]

Comments #1 and #2 are clear. For #3, should I document both the 10 req/min limit AND the exponential backoff strategy, or just the limit?"

User: "Document both"

Agent: [Implements all 3 changes in separate atomic commits]
Agent: [Commits: feat(auth): extract timeout to named constant (abc1234)]
Agent: [Commits: test(auth): add expired token test case (bcd2345)]
Agent: [Commits: docs: update rate limiting documentation (cde3456)]
Agent: [Pushes to PR branch]
Agent: [Replies to each inline review thread comment]

# Reply to comment #1 (ID: 2596414027):
# Using GitHub MCP (preferred):
# reply_to_pull_request_comment(
#   owner="tianjianjiang",
#   repo="smith",
#   pull_number=123,
#   comment_id=2596414027,
#   body="@reviewer\n\n> Extract timeout value to named constant\n\nDone! Extracted to `DEFAULT_REQUEST_TIMEOUT = 30` in constants.py.\n\nFixed in commit abc1234."
# )

# OR gh CLI fallback:
# gh api repos/tianjianjiang/smith/pulls/123/comments \
#   -f body="@reviewer..." \
#   -f in_reply_to=2596414027

Agent: [Marks comment thread #1 as resolved]

# Using GitHub MCP (preferred):
# resolve_pull_request_review_thread(
#   owner="tianjianjiang",
#   repo="smith",
#   pull_number=123,
#   comment_id=2596414027
# )

# OR gh CLI fallback:
# THREAD_ID=$(gh api repos/tianjianjiang/smith/pulls/comments/2596414027 --jq '.pull_request_review_id')
# gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "'"$THREAD_ID"'"}) { thread { id isResolved } } }'

Agent: [Repeats reply and resolve for comments #2 (2596414028) and #3 (2596414029)]
Agent: "Pushed 3 atomic commits addressing all review comments. Waiting for CI checks and re-review..."

# ITERATION 2: New comment after changes
Agent: [Checks for new comments after CI passes]

# Using GitHub MCP (preferred):
# get_pull_request_review_threads(owner="tianjianjiang", repo="smith", pull_number=123)

Agent: "New inline review comment from @reviewer:

4. auth.py:52 - 'Consider adding error handling for network timeouts' [Confidence: 90%]

Implementing try-except wrapper for network operations..."

Agent: [Makes change, commits: fix(auth): add timeout error handling (def5678)]
Agent: [Pushes to PR branch]
Agent: [Replies to comment thread #4 (ID: 2596414030)]
Agent: [Marks comment thread #4 as resolved]
Agent: "Addressed comment #4. CI passing. Waiting for re-review..."

# ITERATION 3: Verification and merge
Agent: [Checks for new comments after CI passes]
Agent: [Verifies all review threads resolved]

# Using GitHub MCP (preferred):
# check_pull_request_review_resolution(owner="tianjianjiang", repo="smith", pull_number=123)
# Returns: {all_resolved: true, unresolved_count: 0}

# OR gh CLI fallback:
# UNRESOLVED=$(gh api repos/tianjianjiang/smith/pulls/123/comments | jq '[.[] | select(.in_reply_to_id == null)] | length')
# if [ "$UNRESOLVED" -eq 0 ]; then echo "All resolved"; fi

Agent: "No new review comments. All 4 inline review threads addressed and marked resolved. CI checks passing.

Auto-merge readiness:
- All review threads resolved (4/4)
- No new comments from reviewers
- CI checks passing (all 5 checks green)
- 2 approvals received (requirement: 1)
- Branch is fresh (rebased 10 minutes ago)
- No merge conflicts

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

## Examples

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

## Forbidden Practices

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

## Related Standards

- **PR Concepts**: `$HOME/.smith/rules-pr-concepts.md` - Platform-neutral PR workflows
- **GitHub PR Operations**: `$HOME/.smith/rules-github-pr.md` - Basic GitHub operations
- **PR Creation Automation**: `$HOME/.smith/rules-github-agent-create.md` - Agent PR creation
- **Rebase Automation**: `$HOME/.smith/rules-github-agent-rebase.md` - Branch freshness
- **Post-Merge Workflows**: `$HOME/.smith/rules-github-agent-merge.md` - Post-merge automation
- **Agent Utilities**: `$HOME/.smith/rules-github-agent-utils.md` - Workflow coordination
