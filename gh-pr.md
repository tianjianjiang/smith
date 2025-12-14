# GitHub PR Workflows

<metadata>

- **Scope**: Complete GitHub PR lifecycle - creation, review, rebase, merge, and cleanup
- **Load if**: Creating PRs, reviewing code, merging changes, managing PR branches, post-merge operations
- **Prerequisites**: @core.md, @git.md, @gh-cli.md, @steering.md
- **Token efficiency**: Use perPage, minimal_output parameters (see @gh-cli.md)

</metadata>

<context>

## Scope

This document covers the complete GitHub PR workflow:
- **PR creation** (quality checks, title/body format, AI-generated descriptions)
- **Working on existing PRs** (branch checkout, pre-work checks, post-push requirements)
- **Code review** (requesting, responding, giving reviews, automation)
- **Rebase and freshness** (monitoring, decision tree, conflict resolution)
- **Merging** (strategies, pre-merge checks, post-merge cleanup)
- **Best practices** (PR size, communication, documentation, CI integration)

For stacked PR workflows, see stacks.md.

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

# PR Creation

## Prerequisites and Quality Checks

<constraints>

<required>

- MUST run all quality checks before creating PR
- MUST ensure branch is up-to-date with base branch
- MUST have meaningful commit messages
- MUST link to related issues
- MUST verify branch tracks correct remote
- MUST check if branch is current with base before PR creation
- MUST offer to rebase if branch is behind base
- MUST verify no merge conflicts exist with base

</required>

**Pre-PR checklist:**
```sh
poetry run ruff format . && poetry run ruff check --fix .
poetry run pytest
git fetch origin
git rebase origin/main
git push -u origin feat/my_feature
```

**Pre-PR freshness check**:
```sh
git fetch origin
BASE_BRANCH="main"
BEHIND=$(git rev-list HEAD.."origin/$BASE_BRANCH" --count)

if [ "$BEHIND" -gt 0 ]; then
  echo "Branch is $BEHIND commits behind $BASE_BRANCH. Rebase before creating PR?"
fi
```

</constraints>

## PR Title Format

<context>

**Conventional Commits Format**: PR titles follow the same conventional commits format as commit messages.

See @style.md for complete specification, including:
- Format pattern: `type: description` or `type(scope): description`
- Type definitions (feat, fix, docs, etc.)
- 50/72 character rule (PR title becomes merge commit subject)
- Atomicity guidelines

</context>

<required>

**Key requirements for PR titles:**
- MUST follow conventional commits format
- MUST stay within 72 character hard limit (GitLab enforces, GitHub truncates)
- MUST target 50 characters for conciseness
- MUST represent single logical change (use stacked PRs if needed)

</required>

<examples>

- `feat(rag): add semantic search filtering`
- `fix(api): resolve CORS issues`
- `docs: update deployment guide`
- `refactor(auth): extract validation logic`
- `test: add integration tests for search`

</examples>

## PR Body Template

<examples>

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

Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

</examples>

## AI-Generated PR Descriptions

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

<forbidden>

- **NEVER** analyze only the latest commit for PR summary
- **NEVER** skip full diff review (base...HEAD)
- **NEVER** create PR without running checks
- **NEVER** assume file contents without reading
- **NEVER** write generic summaries ("updated files")
- **NEVER** create PR with failing tests
- **NEVER** merge PR with unresolved conflicts
- **NEVER** skip CI checks
- **NEVER** merge without required approvals

</forbidden>

## PR Requirements

<required>

- MUST have descriptive title following conventional commits format
- MUST include summary (1-3 bullet points)
- MUST include test plan with checklist
- MUST link to related issues
- MUST have all CI checks passing
- MUST have minimum 1 approval (if enforced by project)

</required>

## Stacked PRs

<context>

For large features (500+ lines), use stacked PRs to maintain atomic, reviewable changes.

**See**: stacks.md for complete stacked PR workflows, merge strategies, and rebase patterns.

</context>

---

# Working on Existing PRs

## CRITICAL: Always Use Actual Branch Name

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

## Why This Matters

<context>

**Problem**: Creating local branches with assumed names that don't match the PR's actual branch name.

**Impact**:
- Your changes won't push to the PR
- You're working on a disconnected branch
- Risk of losing work or creating merge conflicts

**Solution**: Always verify the PR's actual branch name from GitHub, then checkout from origin.

</context>

## Recovery if You Made This Mistake

If you already made changes to the wrong branch:

```sh
git checkout "<actual-branch-name>"
git cherry-pick <commit-sha-from-wrong-branch>
git branch -D <wrong-branch-name>
```

## Pre-Work Requirements

<required>

Before making changes to an existing PR:

1. **Check for review comments**: Fetch all inline review comments
2. **Verify comment types**: Check for CHANGES_REQUESTED AND COMMENT reviews
3. **Alert on pending feedback**: Inform user of unaddressed comments
4. **Confirm approach**: Ask if user wants to address comments first

</required>

<context>

**Rationale**: Bot reviewers (CodeRabbitAI, Copilot) often post informational COMMENT reviews that don't change PR state. Without proactive checking, these are easily missed.

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

## Pre-Work Review Comment Check

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

## Post-Push Requirements

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

## Pre-Commit Hook Handling

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

For complete amend safety guidelines, see @git.md.

---

# Code Review Process

## Requesting Review

**Best practices:**
- Request reviews from relevant team members
- Provide context in PR description
- Link to design docs or RFCs if applicable
- Highlight areas needing special attention
- Ensure all CI checks are passing before requesting review

## Responding to Reviews

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

## Giving Reviews

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

## Review Cycle Automation

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
   - **Proactive check**: When starting work on existing PR (see Pre-Work Review Comment Check above)

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
   - **Actionable (must fix)**: Specific code changes requested (bugs, security, breaking changes)
   - **Nitpick/Minor**: Style suggestions, minor improvements (CodeRabbitAI often labels these "nitpick" or "suggestion")
   - **Inline code comments**: Specific to particular lines of code (require code changes)
   - **General PR comments**: Overall feedback on PR (may not require code changes)
   - **Clarification**: Questions needing answers (respond in comment thread)
   - **Discussion**: Architectural/subjective decisions (needs human input)

   **Priority order**: Actionable (must fix) > Nitpick/Minor > Clarification > Discussion

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

   **When to resolve**:
   - ✅ After implementing actionable change and committing
   - ✅ After answering clarification question
   - ✅ For nitpick/minor suggestions you've addressed
   - ❌ NOT before changes are committed and pushed
   - ❌ NOT for discussion threads (let reviewer resolve after consensus)

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

**Rebase Decision Logic**:

**Scenario 1: PR behind base, no conflicts, user not explicitly working on it**
- Action: ASK user
- Rationale: Respectful of user control

**Scenario 2: PR behind base, no conflicts, user just said "update PR"**
- Action: AUTO-REBASE
- Rationale: Clear intent

**Scenario 3: PR behind base, conflicts detected**
- Action: INFORM + ASK
- Rationale: Requires manual resolution

**Scenario 4: Parent PR merged, child PR exists**
- Action: INFORM + OFFER
- Rationale: Helpful but not intrusive

**Scenario 5: About to request review, PR outdated**
- Action: BLOCK + INFORM
- Rationale: Prevent bad review request

**Scenario 6: PR current with base**
- Action: DO NOTHING
- Rationale: No action needed

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

# Merging Pull Requests

## Pre-Merge Checklist

<required>

- MUST have all CI checks passing
- MUST have required approvals
- MUST be up-to-date with base branch
- MUST have no merge conflicts
- MUST have related issues linked

</required>

## Merge Strategies

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

## Post-Merge Operations and Cleanup

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
```sh
git checkout main
git fetch --prune origin
git pull origin main
git branch -d feat/my_feature
git ls-remote --exit-code --heads origin feat/my_feature >/dev/null 2>&1 && \
  git push origin --delete feat/my_feature
```

<context>

**Command explanation:**

- `git fetch --prune`: Update remote refs and remove stale tracking branches
- `git pull origin main`: Update local main with merged commits (required for branch -d check)
- `git branch -d`: Safe delete (fails if branch not merged to main)
- `git ls-remote --exit-code`: Check if remote branch exists before attempting deletion
- Works whether GitHub auto-delete is enabled or disabled

</context>

<forbidden>

- NEVER use `git branch -D` (force delete) unless you are certain the branch should be abandoned
- NEVER delete local branch before PR is merged
- NEVER skip `git fetch --prune` (leaves stale remote-tracking refs)
- NEVER use `--delete-branch` flag when merging stacked PRs

</forbidden>

---

# Best Practices

## PR Size

<constraints>

- Keep PRs focused and small (< 400 lines changed ideal)
- Split large features into multiple PRs
- Use draft PRs for work in progress
- One logical change per PR

</constraints>

## Communication

- Use PR comments for technical discussions
- Use issue comments for requirements and planning
- Tag relevant team members with @mentions
- Be respectful and constructive in reviews
- Explain your reasoning in review responses

## Documentation

- Update README if public API changes
- Update CHANGELOG for notable changes
- Add inline code comments for complex logic
- Include examples in PR description for new features

## CI Integration

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
- Ensure all tests run in CI
- Set up automatic deployment previews when possible
- Configure status checks as required
- Wait for all checks to pass before requesting review
- If checks fail, fix immediately before other work
- Monitor checks continuously to catch failures early

---

# Troubleshooting PR Issues

## Changes Not Appearing in PR

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

## Merge Conflicts After Base Branch Update

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

## CI Checks Fail After Pre-Commit Hook

**Symptoms**: Pre-commit passes locally but CI fails

**Solution:**
```sh
poetry run ruff check . --config=<same-as-ci>
poetry run pytest --cov=<same-as-ci>
```

## Recovery Procedures

### Wrong Branch Checkout

**Problem**: Made changes to wrong branch

**Solution**: See "Recovery if You Made This Mistake" section above in "Working on Existing PRs"

### Accidentally Pushed to Wrong Remote

**Problem**: Pushed PR branch to wrong repository

**Solution:**
```sh
git remote -v
git remote remove wrong-remote
git remote add origin <correct-repo-url>
git push -u origin <branch-name>
```

### Undo Last Commit but Keep Changes

**Problem**: Made commit but want to redo it differently

**Solution:**
```sh
git reset --soft HEAD~1
git reset HEAD~1
git add .
git commit -m "better commit message"
```

### Syncing with Updated Base Branch

**Problem**: Base branch (main/develop) has new commits

**Solution:**
```sh
git fetch origin
git rebase origin/main
git push --force-with-lease
git merge origin/main
git push
```

---

# Related Standards

- **Git Operations**: @git.md - Commits, branches, merges
- **Stacked PRs**: @stacks.md - Advanced stacked PR patterns and workflows
- **GitHub CLI**: @gh-cli.md - GitHub CLI commands and token efficiency
- **Development Workflow**: @dev.md - Daily practices, quality gates
- **Testing**: @tests.md - Test requirements
- **AI Principles**: @steering.md - Constitutional AI principles, exploration-before-implementation
