# GitHub Agent PR Creation Automation

<metadata>

- **Scope**: Agent automation for creating pull requests with comprehensive descriptions
- **Load if**: Agent about to create PR, analyzing commits for PR description
- **Prerequisites**: [PR Concepts](./rules-pr-concepts.md), [GitHub PR Operations](./rules-github-pr.md)

</metadata>

<context>

## Scope

- **This document**: Agent-created PRs, full diff analysis, PR description auto-generation
- **Basic PR operations**: See [GitHub PR Operations](./rules-github-pr.md)
- **Other agent workflows**: See [Review Automation](./rules-github-agent-review.md), [Rebase](./rules-github-agent-rebase.md), [Post-Merge](./rules-github-agent-merge.md)

</context>

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
BEHIND=$(git rev-list HEAD.."origin/$BASE_BRANCH" --count)

if [ "$BEHIND" -gt 0 ]; then
  # Agent: "Your branch is {N} commits behind {base}. Rebase before creating PR?"
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

## Agent Workflow Example

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

## Examples

<examples>

**Comprehensive analysis**:
"Analyzed 5 commits across 12 files. Generated summary covering auth implementation (auth.py:45-120), rate limiting middleware (middleware.py:23-45), and API docs (README.md:100-150)."

**Identifies gaps**:
"Generated description but noticed no tests were added in this PR. Should I mention this limitation in the PR description or add tests first?"

**Ticket integration**:
"Found reference to JIRA-1234 in commit messages. Including acceptance criteria from that ticket in PR description for reviewer context."

</examples>

## Common Agent Mistakes

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

## PR Analysis Checklist

<required>

Before creating PR, agent MUST:

1. Run `git diff base...HEAD` to see cumulative changes
2. Run `git log base..HEAD` to see all commits
3. Read all modified files (not assume contents)
4. Identify cumulative impact across all commits
5. Verify tests pass for all changes
6. Draft summary reflecting full PR scope

</required>

**Workflow**:
```sh
git diff base...HEAD
git log base..HEAD
poetry run ruff format . && poetry run ruff check --fix .
poetry run pytest
```

## Forbidden Practices

<forbidden>

**Only analyzed latest commit** (should analyze ALL commits):
"PR adds authentication" - but PR actually includes 5 commits with auth + rate limiting + docs. Agent only looked at latest commit message instead of full diff.

**Assumed file contents** (should read ALL files):
"PR updates auth.py and docs" - but doesn't describe WHAT changes were made because agent didn't actually read the files.

**Generic summaries** (should be specific):
"Updated files" - provides no value. Should describe actual changes with file:line references.

</forbidden>

## Related Standards

- **PR Concepts**: `$HOME/.smith/rules-pr-concepts.md` - Platform-neutral PR workflows
- **GitHub PR Operations**: `$HOME/.smith/rules-github-pr.md` - Basic GitHub operations
- **Review Automation**: `$HOME/.smith/rules-github-agent-review.md` - Review cycle automation
- **Rebase Automation**: `$HOME/.smith/rules-github-agent-rebase.md` - Branch freshness
- **Post-Merge Workflows**: `$HOME/.smith/rules-github-agent-merge.md` - Post-merge automation
- **Agent Utilities**: `$HOME/.smith/rules-github-agent-utils.md` - Workflow coordination
- **AI Agent Standards**: `$HOME/.smith/rules-ai_agents.md` - Complete agent interaction standards
