---
name: smith-gh-pr
description: GitHub PR workflows including creation, review cycles, merge strategies, and stacked PRs. Use when creating PRs, reviewing code, merging branches, or managing stacked PR workflows. Covers rebase decision trees and AI-generated descriptions.
---

# GitHub PR Workflows

**Load if:** Creating PRs, reviewing code, merging, stacked PRs
**Prerequisites:** @smith-principles/SKILL.md, @smith-standards/SKILL.md, `@smith-git/SKILL.md`

## CRITICAL

- MUST run quality checks before creating PR
- MUST ensure branch is up-to-date before requesting review or merging
- MUST link to related issues
- MUST have all CI checks passing before merge
- MUST have explicit user request before creating PRs
  -- listing is NOT consent to create

## Avoid GitHub MCP

Prefer the `gh pr-review` extension, `gh api`, or GraphQL queries over GitHub
MCP tools (`mcp__github__*`) — they are hard to control pagination on (token
waste), less complete than the CLI, and require a personal token.

## PR Title Format

Follow conventional commits format. See `@smith-style/SKILL.md` for details.

## PR Creation Workflow

**Pre-PR checklist:**
0. **Review to convergence FIRST** — run `/smith-review` (ALL applicable tools,
   per-round receipt, clean final round) BEFORE the first push. Do NOT push a
   code change and then react to one bot afterward — that inverts review-then-push
   and a single-tool pass (one reviewer alone) is NOT convergence.
1. Run linter and formatter
2. Run tests
3. Rebase onto parent branch (not always main - check stacked PRs)
4. Run the `@smith-style` pre-push branch-name checklist; if the branch name was
   not user-specified, confirm it with the user before pushing
5. Push to remote

**AI-generated descriptions**: Analyze full diff, read ALL commits, identify tickets, generate structured summary (What/Why/Testing/Dependencies).

## Working on Existing PRs

- ALWAYS get actual branch name: `gh pr view {PR} --json headRefName`
- ALWAYS check for review comments before making changes
- ALWAYS update PR title/body after pushing changes

## Code Review Cycle

1. Fetch review comments using `gh pr-review` (see "Fetching Review Comments" below)
2. **Get ALL comments including Nitpicks** - don't skip minor issues
3. Categorize: Actionable > Nitpick > Clarification > Discussion
4. **Proactively audit similar issues** in other files not explicitly mentioned
5. Implement fixes with confidence scoring (high: implement, low: ask)
   - **High confidence**: Small surface area change, aligns with existing patterns, covered by tests
   - **Low confidence**: Ambiguous behavior, architectural impact, requires design discussion
6. Reply to comments with commit SHA
7. **Resolve threads after addressing** - don't leave resolved issues open
8. Re-check for new comments after CI passes

**Code review response rules:**
- **File-inline comments** (on specific lines): MUST reply in-thread using `gh pr-review comments reply --pr {number} -R {owner}/{repo} --thread-id {PRRT_xxx}`, NOT as PR-level comment. This keeps discussion traceable to the code location.
- **Propose edits as committable suggestions**: when a reply proposes a specific
  code change, embed a committable ` ```suggestion ` block (see "Posting Review
  Findings" below) so the author commits it in one click instead of re-typing.
- **PR-level comments** (general discussion, `<details>` blocks): Reply with `gh pr comment` or GitHub's "Quote reply"
- Reply with commit SHA, then resolve thread with `gh pr-review threads resolve`
- Proactive audit: search codebase for similar issues before committing
- **CodeRabbit `<details>` comments** (Nitpicks, Duplicated, Outside diff range): These appear in PR thread, not inline on files. Use GitHub's "Quote reply" to include Markdown blockquote of the essential part (e.g., `> The redundant text...`), making response traceable
- **Attribution**: When Claude Code generates or posts a comment, state authorship with the user's @ mention per medium (e.g., GitHub: "Posted by Claude Code on behalf of @username", Notion: "Posted by Claude Code on behalf of @Display Name"). Omit when the user manually authors the comment.
- Research questionable suggestions before implementing (see `@smith-research/SKILL.md`)
- Keep `@copilot` out of replies — mentioning it triggers unwanted sub-PRs

**Review reply tone and style:**
- **Concise**: Lead with the action taken or answer; no filler
- **Evidence-based**: Cite commit SHA, file:line, docs URL, or
  test output as proof — strongest evidence available
- **Grateful**: Thank the reviewer for catching the issue
  (e.g., "Good catch — fixed in abc1234")
- **Humble**: If uncertain, say so; don't over-explain or
  defend — ask for guidance instead
- **Gentle**: When disagreeing, present evidence respectfully
  (e.g., "I kept X because «reason» — happy to change if
  you see it differently")

## Posting Review Findings

When Claude Code is the reviewer and an open PR exists (including self-review
before human review), deliver findings as **inline comments anchored to the
line(s)**, carrying a **committable `suggestion` block** whenever the fix is
concrete — not as one PR-level summary comment. With no open PR, report in-band
(see `@smith-review`).

- **Anchor to the line(s).** A finding that maps to specific line(s) MUST be an
  inline review comment on those lines. Reserve PR-level/summary comments for
  cross-cutting findings with no single anchor (architecture, a missing test
  file, a cross-module concern).
- **Carry a committable suggestion when the fix is concrete.** GitHub renders a
  "Commit suggestion" button from a fenced block tagged `suggestion`; the author
  applies it in one click. Include one whenever the fix is a mechanical code
  change. Omit it only when the fix needs design discussion or can't be
  expressed as a line-range replacement — and say why in the comment.
- **Replace the whole commented range.** GitHub replaces the commented line(s)
  with the block's contents verbatim — the block may hold more or fewer lines
  than the range (a suggestion can add or drop lines). Comment on the full range
  you intend to replace and put the complete replacement in one block.

**Mechanism (prefer the built-in):**

- `/code-review --comment` — runs the review and posts findings as inline PR
  comments automatically. Primary path.
- Manual single inline comment via REST (when hand-authoring one finding):

````shell
gh api repos/{owner}/{repo}/pulls/{pr}/comments \
  -f commit_id={headSHA} -f path={file} -F line={n} -f side=RIGHT \
  -f body=$'Explain the issue briefly.\n\n```suggestion\nfixed line(s) here\n```'
# Multi-line range: add -F start_line={firstLine} -f start_side=RIGHT
````

A committable suggestion is just a fenced block inside the comment body:

````text
```suggestion
const timeout = configuredTimeout ?? DEFAULT_TIMEOUT;
```
````

## Review Convergence Protocol

**Decide-and-proceed defaults (do NOT ask between obvious steps):**
- CR finding is Critical/Warning + high-confidence: fix, commit, push silently
- CR finding is Info/Nitpick: reply-and-resolve or skip with one-line reason
- After pushing a fix: re-run review immediately
- 0 actionable findings: merge (`gh pr merge --squash --delete-branch`);
  for a stacked PR with an open child, OMIT `--delete-branch` (see Stacked PRs)
- Post-merge: `ExitWorktree action="remove"` → `git pull --ff-only`
  (see `@smith-worktree/SKILL.md` Sync-After-Squash-Merge)

**Must-ask criteria (only interruption triggers):**
- Finding requires scope change beyond the PR's stated goal
- Finding contradicts an existing smith-skill rule (meta-question)
- Auto-mode classifier denial without a documented escape pattern
- CI fails after a CR-driven fix (regression vs flake ambiguity)
- User explicitly said "pause" or "wait" in recent turns

**Convergence criteria:**
- Clean round (0 Critical/Warning findings): ready to merge
- Diminishing returns (2 consecutive rounds with only Info/Nitpick): merge
- Flip-flop (reviewer alternates contradicting verdicts without
  new evidence): escalate trade-off analysis to user, stop iterating

**CodeRabbit fails OPEN — absence of review is NOT a pass:**
- CodeRabbit silently skips review on exhausted credits / the hourly
  rate-limit (Pro = 1 review/hr): "Review limit reached". It also skips PRs
  whose base is not the default branch (stacked PRs) and a PR closed mid-review.
- Confirm a CR review actually ran before treating "0 findings" as clean.

**External write rule (Notion, Slack, Jira, GitHub comments):**
- Draft content inline in conversation first
- State intent: "posting to «medium»" — user can interrupt
- Post unless user objects within that turn
- Always include attribution line per medium convention

## Approving a PR by command

- `gh pr review <n> -R <owner/repo> --approve --body-file <f>` — an external
  write under the user's account: authorization-gate first (state intent; user
  can interrupt), attribute "on behalf of @user" in the body.
- It **returns silently on success** (no output is normal, not a failure).
  ALWAYS verify: `gh pr view <n> -R <owner/repo> --json reviewDecision,reviews`
  and confirm the user shows `APPROVED` in `reviews`.
- `reviewDecision` is **empty when the repo has no required-review branch
  protection** computing a gate — that is expected, not a missing approval.

## Fetching Review Comments

**Use `gh pr-review`** over `gh api` - structured output with thread IDs.

All commands require `--pr {number} -R {owner}/{repo}` for numeric PR selectors.

**Install**: `gh extension install agynio/gh-pr-review` (consider pinning to vetted SHA)

**On `gh pr-review` errors:**
1. Check if extension installed: `gh extension list | grep pr-review`
2. Verify command syntax (common: missing `--pr`, wrong `-R` format)
3. Verify repo name: `gh repo view --json nameWithOwner`
4. If not installed: `gh extension install agynio/gh-pr-review`

**List unresolved threads**: `gh pr-review threads list --pr {number} -R {owner}/{repo} --unresolved`

### gh-pr-review Commands

**View reviews** (use `--unresolved`, `--reviewer`, `--states` to filter):
`gh pr-review review view --pr {number} -R {owner}/{repo}`

**Reply to thread**:
`gh pr-review comments reply --pr {number} -R {owner}/{repo} --thread-id {PRRT_xxx} --body "..."`

**Resolve/unresolve thread**:
`gh pr-review threads resolve --pr {number} -R {owner}/{repo} --thread-id {PRRT_xxx}`

Output includes `thread_id` (PRRT_xxx format) needed for reply/resolve operations.

### REST API (Single Comments)

URL patterns map to API endpoints:
- `#issuecomment-{id}` → `gh api repos/{owner}/{repo}/issues/comments/{id}`
- `#discussion_r{id}` → `gh api repos/{owner}/{repo}/pulls/comments/{id}`
- `#pullrequestreview-{id}` → `gh api repos/{owner}/{repo}/pulls/{pr}/reviews/{id}`

## Rebase Decision Tree

**Behind base, no conflicts, explicit "update"**: AUTO-REBASE
**Behind base, no conflicts, not explicit**: ASK user
**Behind base, conflicts detected**: INFORM + ASK
**Parent PR merged**: INFORM + OFFER cascade
**About to request review, outdated**: BLOCK + INFORM

**Staleness thresholds**: <5 commits (fresh), 5-10 (notify), >10 (recommend), >20 (urgent)

**Note**: The above decision tree provides guidance during active development. The MUST requirement for up-to-date branches is enforced when requesting review or merging.

## Merge Strategies

**Merge commit**: Feature branches with meaningful history
**Squash**: Small fixes, docs, single logical change
**Rebase**: Linear history required, clean commits

## Stacked PRs

For stacked PRs, merge parent WITHOUT `--delete-branch` — via the gh CLI it
closes the open child instead of retargeting it (cli/cli#1168). Then:
```shell
gh pr edit {CHILD} --base main
git rebase --onto origin/main feat/parent_branch
git push --force-with-lease
git push origin --delete feat/parent_branch
```

## /ultrareview — Cloud Deep-Review

`/ultrareview` (research preview, v2.1.86+) runs a multi-agent reviewer fleet in a remote Claude Code on the web sandbox. Higher signal than the built-in single-pass `/review` slash command: every finding is independently reproduced and verified before it's reported. Takes 5–10 min; runs in background so the terminal stays free.

**Invocation:**

- `/ultrareview` — review diff between current branch and default branch (includes uncommitted/staged)
- `/ultrareview «PR»` — review a GitHub PR (PR mode; clones from GitHub directly, requires `github.com` remote)
- `claude ultrareview «PR»` (or `«base»`) — non-interactive variant; prints findings to stdout; flags `--json`, `--timeout «minutes»`

**Requires:** authenticated with claude.ai (run `/login`), not available on Bedrock/Vertex/Foundry or for Zero Data Retention organizations.

**Billing:** Pro/Max get 3 one-time free runs; after that, billed as usage credits (~$5–$20/run by change size). Team/Enterprise has no free runs. Account must have usage credits enabled (`/usage-credits` to check). User-invoked only — agent does not start one on its own.

**Track:** `/tasks` shows running reviews. Stopping a review archives the cloud session and doesn't return partial findings; a stopped/failed run still consumes a free run.

**When to recommend over the built-in `/review`:** before merging a substantial change where pre-merge confidence matters; not for quick iterative feedback. Source: https://code.claude.com/docs/en/ultrareview

## Automated PR Review Monitoring

**`/loop` for review cycles** — periodically poll for
new review comments and auto-address them:

```shell
/loop 5m /smith-gh-pr:check-reviews
```

Note: `check-reviews` is a conceptual pattern, not a
built-in sub-command. Implement the workflow below manually
or as a custom skill. For `/loop` semantics see `@smith-automation/SKILL.md`.

**Auto-address workflow** (see "Review Convergence Protocol"
above for decide-vs-ask criteria and convergence rules):
1. Fetch unresolved comments:
   `gh pr-review threads list --pr {number} -R {owner}/{repo} --unresolved`
2. Classify each: code change vs clarification vs resolved
3. High-confidence fixes: implement, commit, reply with SHA
4. Low-confidence: draft reply, ask user before posting
5. Re-check after CI passes

**Proactive self-review** — before reviewer sees changes:
- Run CodeRabbit review via configured integration (e.g. `coderabbit:review` skill or GitHub App) after pushing
- Address mechanical feedback (lint, naming, tests)
  before human review begins

**`/autofix-pr` — cloud auto-fix loop**

Run `/autofix-pr` while on the PR's branch. Claude Code detects the open PR with `gh`, spawns a Claude Code on the web session, and turns on auto-fix for that PR in one step. The web session subscribes to GitHub events (CI checks, review comments) and pushes fixes for high-confidence cases; ambiguous changes prompt instead of pushing.

**Requires** the Claude GitHub App installed on the repo (PR webhooks). Replies to review threads post under the user's GitHub account but are labeled as Claude Code authored. Disable per-PR via the web session's CI status bar.

**Warning:** if the repo uses comment-triggered automation (Atlantis, Terraform Cloud, GitHub Actions on `issue_comment`), auto-fix's review replies can trigger those workflows. Avoid auto-fix where a PR comment can deploy infrastructure or run privileged operations.

Source: https://code.claude.com/docs/en/claude-code-on-the-web#auto-fix-pull-requests

**When to use the monitoring loop pattern (above) vs `/autofix-pr`:**

- Loop pattern: terminal stays attached; agent under the user's direct supervision; user controls each push
- `/autofix-pr`: terminal can close; runs autonomously in cloud; for PRs where you're confident in unattended fixing

## Claude Code Plugin Integration

**When plugins are available, prefer plugin commands:**

- **`/code-review`**: Launches 4 parallel agents with confidence scoring (threshold 80)
- **`/commit-push-pr`**: Commits, pushes, and creates PR in one step
- **`pr-review-toolkit:review-pr`**: the SINGLE entry point for multi-agent
  review — it orchestrates its own 6 subagents. NEVER hand-pick or invoke the
  individual agents (`code-reviewer`, `silent-failure-hunter`,
  `pr-test-analyzer`, etc.) directly via the Task tool. A HIGH finding from one
  agent needs >=2-of-6 corroboration; a solo HIGH downgrades to
  medium-for-user-review.

**Plugin commands complement** (not replace) manual `gh` workflows.

## Related

- `@smith-gh-cli/SKILL.md` - GitHub CLI commands, pagination limits
- `@smith-stacks/SKILL.md` - Stacked PR workflows
- `@smith-git/SKILL.md` - Git operations, rebase
- `@smith-style/SKILL.md` - Conventional commits, branch naming
- `@smith-tests/SKILL.md` - Testing standards (pre-PR checklist)
- `@smith-research/SKILL.md` - Research best practices before implementing review feedback
- `@smith-validation/SKILL.md` - Debugging, root cause analysis for review issues

## Before You Finish

**Create PR:**
```shell
gh pr create --title "feat: add feature" --body "..." --assignee @me
```

**Merge PR:**
```shell
gh pr merge {PR} --squash
```

Options: `--squash`, `--merge`, or `--rebase`

**Post-merge cleanup** (use the repo's DEFAULT branch — `main`, `develop`, etc., never assume `main`):
```shell
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git checkout "$DEFAULT_BRANCH" && git fetch --prune origin && git pull --ff-only
git branch -d feat/my_feature
```
`--ff-only` is mandatory: it refuses to create a stray merge commit if local has
diverged (e.g. after a squash-merge), surfacing the problem instead of hiding it.

**Check freshness** (`@{u}` = current branch's upstream, branch-name-agnostic):
```shell
git fetch  # fetches the current branch's configured remote, matching @{u}
BEHIND=$(git rev-list HEAD..@{u} --count)
```
