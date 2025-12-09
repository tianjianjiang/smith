# GitHub Review Cycle Automation

<metadata>

- **Scope**: Automation for iterative PR review cycles on GitHub
- **Load if**: Responding to PR review feedback, automated review comment handling
- **Prerequisites**: rules-pr-concepts.md, rules-github.md, rules-ai_agents.md
- **Token efficiency**: Use perPage, minimal_output parameters (see rules-github.md)

</metadata>

<context>

## Scope

- **This document**: Automation for the review→fix→re-review cycle
- **Platform-neutral PR concepts**: rules-pr-concepts.md
- **GitHub PR operations**: rules-github-pr.md
- **Other workflows**: rules-github-*.md

**Philosophy**: Automate the iterative review→fix→re-review cycle until all comments are resolved, then proceed to merge when approved.

**Industry Best Practices**:
- **CodeRabbitAI**: Incremental review tracking - only review changed files, not entire PR on each iteration, saving costs and reducing noise
- **Qodo Merge**: `/implement` command directly applies reviewer suggestions with tracking of accepted changes
- **Devin AI**: Confidence scoring (high/medium/low) determines whether to implement directly or ask user first (5-10 min review time)
- **OpenHands**: Label-triggered workflows (e.g., "review-this" label auto-starts review cycle)
- **Real-world impact**: 73.8% of automated review comments marked "Resolved", 30% reduction in review time

</context>

## Review Cycle Automation

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

**Dual-Approach Pattern**:

**GitHub MCP Server** (for fetching review comments):
- Use `mcp__github__pull_request_read` with method="get_review_comments"
- Built-in validation and structured response
- Clearer than parsing JSON manually

**gh CLI + GitHub REST API** (for replying and resolving):
- **Replying to review comments**: Requires `/replies` endpoint (not supported by standard GitHub MCP)
- **Resolving threads**: Requires GraphQL API (not supported by standard GitHub MCP)
- Works without additional MCP extensions
- Standard GitHub REST API and GraphQL

**Decision logic**: Use MCP for fetching, gh CLI/API for replying and resolving.

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

2. **Fetch inline review thread comments** (not general PR comments):

   **Option A: Using GitHub MCP** (preferred):
   ```
   Use MCP tool: mcp__github__pull_request_read
   Parameters:
     - method: "get_review_comments"
     - owner: {owner}           # e.g., "octocat"
     - repo: {repo}             # e.g., "hello-world"
     - pullNumber: {PR}         # e.g., 21
     - perPage: 10              # ULTRA-conservative: CodeRabbitAI comments have massive HTML/analysis
     - page: 1

   Returns: List of inline review comment objects with id, path, line, body, user
   ```

   **If PR has 10+ review comments** (response shows more pages available):
   ```text
   # Fetch subsequent pages
   Use MCP tool: mcp__github__pull_request_read
   Parameters:
     - method: "get_review_comments"
     - owner: {owner}
     - repo: {repo}
     - pullNumber: {PR}
     - perPage: 10            # ULTRA-conservative: CodeRabbitAI comments have massive HTML/analysis
     - page: 2                # Increment for each additional page
   ```

   **Option B: Using gh CLI** (fallback):
   ```sh
   PR_NUMBER=123
   OWNER_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

   gh api "repos/$OWNER_REPO/pulls/$PR_NUMBER/comments" > /tmp/inline_comments.json

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
   - **High confidence (>70%)**: Implement directly and document changes
   - **Medium confidence (40-70%)**: Implement and request confirmation of approach
   - **Low confidence (<40%)**: Ask user for clarification before implementing

   </planning_process>

   - **Track mapping**: Comment ID → Commit SHA that addresses it

   <final_instruction>

   **Reply to INLINE review thread comment**:

   **Using gh CLI + REST API** (only option - MCP doesn't support this):
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

   **Mark thread as resolved**:

   **Using gh CLI + GraphQL API** (only option - requires two steps):

   **CRITICAL**: Review threads are GraphQL-only. You cannot get the thread ID from REST API.

   **VERIFIED WORKFLOW** (tested 2025-12-07 on PR #23, comments 2596545103 and 2596545104):

   **Step 1: Find the thread ID for your comment** (query all threads, match by comment databaseId):
   ```sh
   OWNER="tianjianjiang"
   REPO="smith"
   PR_NUMBER=23
   COMMENT_ID=2596545103  # The REST API comment databaseId

   # Query all review threads via GraphQL
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

   echo "Thread ID: $THREAD_ID"
   ```

   **Expected output**: `PRRT_kwDOQckce85lDi4k` (GraphQL thread ID format starts with `PRRT_`)

   **Step 2: Resolve the thread** using the thread ID from Step 1:
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

   **Expected output**:
   ```json
   {"data":{"resolveReviewThread":{"thread":{"id":"PRRT_kwDOQckce85lDi4k","isResolved":true}}}}
   ```

   **Permission Required**: Repository Contents write access (not just PR write permissions - counterintuitive!)

   </final_instruction>

   <forbidden>

   **NEVER mention bots when replying to review comments**:

   - `@copilot Thank you for the feedback!` → Triggers unwanted PR creation
   - `@coderabbitai Thanks for the review!` → Unnecessary bot notification
   - `@github-advanced-security[bot] Acknowledged` → Wrong bot entirely

   **CRITICAL: When replying to Copilot's inline review comments, NEVER mention `@copilot`.**

   **Rationale**: Since August 2025, Copilot requires explicit @copilot mentions to respond. **Copilot is designed to open sub-PRs when mentioned, not to receive acknowledgment replies.** Comments on bot reviews are visible to humans but won't trigger bots unless explicitly mentioned. Mentioning `@copilot` in acknowledgment replies triggers unwanted sub-PR creation.

   </forbidden>

   <required>

   **When replying to bot review comments** (especially Copilot):

   ```sh
   # Just acknowledge without bot mention - NEVER mention @copilot
   gh api -X POST \
     -H "Accept: application/vnd.github+json" \
     /repos/{owner}/{repo}/pulls/23/comments/{comment_id}/replies \
     -f body="Thank you for the feedback!"
   ```

   **When to use @copilot** (ONLY when requesting action):
   - `@copilot Please implement this suggestion`
   - `@copilot Fix the issue you identified`

   **Remember**: When replying to Copilot's inline review comments, acknowledge without mentioning `@copilot` to avoid triggering unwanted sub-PR creation.

   </required>

   <final_instruction>

   **Note**: The standard GitHub MCP server doesn't support review thread resolution. Earlier versions of this documentation referenced optional MCP tools (`reply_to_pull_request_comment`, `resolve_pull_request_review_thread`) from third-party extensions like wjessup/github-mcp-server-review-tools. These are not in the standard GitHub MCP server and not widely available, so we use gh CLI + GraphQL as the primary approach.

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
   - Branch is fresh (not stale - see rules-github-agent-rebase.md)
   - No merge conflicts with base branch

   </verification>

   If ALL criteria met: Proceed to merge (with user confirmation)
   If ANY criteria not met: Inform user what's blocking

8. **Verify all review threads resolved**:

   <verification>

   **Using GitHub MCP** (check for unanswered comments):
   ```
   Use MCP tool: mcp__github__pull_request_read
   Parameters:
     - method: "get_review_comments"
     - owner: {owner}
     - repo: {repo}
     - pullNumber: {PR}
     - perPage: 10              # ULTRA-conservative: CodeRabbitAI comments have massive HTML/analysis
     - page: 1

   Filter results for comments with in_reply_to_id == null (root comments without replies)
   If any exist, review and address them before merging.
   ```

   **Alternative: Using gh CLI + GraphQL** (check for unresolved threads):
   ```sh
   OWNER="{owner}"
   REPO="{repo}"
   PR_NUMBER=21

   # Query for unresolved review threads using GraphQL
   gh api graphql -f query='
   query {
     repository(owner: "'"$OWNER"'", name: "'"$REPO"'") {
       pullRequest(number: '"$PR_NUMBER"') {
         reviewThreads(first: 100) {
           nodes {
             isResolved
             comments(first: 1) {
               nodes {
                 id
                 body
               }
             }
           }
         }
       }
     }
   }' | jq '.data.repository.pullRequest.reviewThreads.nodes | map(select(.isResolved == false)) | length'
   ```

   If count > 0, review and resolve remaining threads before proceeding to merge.

   </verification>

</instructions>

<final_instruction>

**CRITICAL: Inline review comment operations**

- **Fetch review comments**: Use GitHub MCP (`mcp__github__pull_request_read` with method="get_review_comments") OR gh CLI REST API
- **Reply to review comments**: Use gh CLI `/replies` endpoint (MCP doesn't support this)
- **Resolve review threads**: Use gh CLI GraphQL API (MCP doesn't support this)

**DO NOT** use `gh pr comment` for inline review threads - it only works for general PR comments.
**DO NOT** use `-f in_reply_to` parameter - it doesn't work. Use the `/replies` endpoint instead.

</final_instruction>

</required>

## Full Cycle Example

<scenario>

**Full iterative cycle example** (showing both MCP and gh CLI approaches):

```
User: "@agent address review comments on PR #123"

Agent: [Fetches inline review thread comments]

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
Agent: [Marks comment threads as resolved]
Agent: "Pushed 3 atomic commits addressing all review comments. Waiting for CI checks and re-review..."

Agent: [Checks for new comments after CI passes]

Agent: "New inline review comment from @reviewer:

4. auth.py:52 - 'Consider adding error handling for network timeouts' [Confidence: 90%]

Implementing try-except wrapper for network operations..."

Agent: [Makes change, commits: fix(auth): add timeout error handling (def5678)]
Agent: [Pushes to PR branch]
Agent: [Replies to comment thread #4]
Agent: [Marks comment thread #4 as resolved]
Agent: "Addressed comment #4. CI passing. Waiting for re-review..."

Agent: [Checks for new comments after CI passes]
Agent: [Verifies all review threads resolved]

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

## Best Practices

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

## Related Standards

- **PR Concepts**: rules-pr-concepts.md - Platform-neutral PR workflows
- **GitHub PR Operations**: rules-github-pr.md - GitHub CLI commands
- **PR Creation**: rules-github-create.md - Automated PR description generation
- **Rebase Workflows**: rules-github-rebase.md - Branch freshness monitoring
- **Workflow Utilities**: rules-github-utils.md - General coordination
- **Principles**: rules-ai_agents.md - Constitutional AI principles
