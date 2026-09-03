---
name: smith-gh-pr
description: GitHub PR workflows
---

# GitHub PR Workflows

**Load if:** Creating PRs, replying to review comments, fetching PR threads, merging
**Prerequisites:** @smith-principles/SKILL.md, @smith-standards/SKILL.md, `@smith-git/SKILL.md`

## CRITICAL

- MUST run quality checks before creating PR
- MUST ensure branch is up-to-date before requesting review or merging
- MUST link to related issues
- MUST have all CI checks passing before merge
- MUST have explicit user request before creating PRs
  -- listing is NOT consent to create
- MUST attach a committable `suggestion` block to a review finding whose fix is
  mechanical — prose describing an edit the reviewer could have written is a
  defect, not a review (see "Posting Review Findings" for the two exemptions)

## Avoid GitHub MCP

Prefer the `gh pr-review` extension, `gh api`, or GraphQL queries over GitHub
MCP tools (`mcp__github__*`) — they are hard to control pagination on (token
waste), less complete than the CLI, and require a personal token.

## PR Title Format

Follow conventional commits format. See `@smith-style/SKILL.md` for details.

## PR Body Format

**Structure:**
- Summary of changes (What/Why)
- Dependencies (if any, link to related PRs/issues)
- End with `Assisted-by:` line (see `@smith-style`)

**NO Test plan section** — testing is verified in the pre-PR checklist (linter, formatter, tests). The PR body documents the change, not the verification process.

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

**AI-generated descriptions**: Analyze full diff, read ALL commits, identify tickets, generate structured summary (What/Why/Dependencies). End the body with the `Assisted-by:` line (see `@smith-style`). Generated or not, a description is content addressed to a human — show it and open on an explicit yes (`@smith-guidance` Harmless).

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
- **Propose edits as committable suggestions**: a reply proposing a mechanical
  code change MUST embed a committable ` ```suggestion ` block (see "Posting
  Review Findings" below) so the author commits it in one click instead of
  re-typing.
- **PR-level comments** (general discussion, `<details>` blocks): Reply with `gh pr comment` or GitHub's "Quote reply"
- Reply with commit SHA, then resolve thread with `gh pr-review threads resolve`
- Proactive audit: search codebase for similar issues before committing
- **CodeRabbit `<details>` comments** (Nitpicks, Duplicated, Outside diff range): These appear in PR thread, not inline on files. Use GitHub's "Quote reply" to include Markdown blockquote of the essential part (e.g., `> The redundant text...`), making response traceable. This creates a new PR-level comment rather than a reply inside the bot's thread, so it is content — show it and post on a yes (`@smith-guidance` Harmless)
- **Attribution**: When Claude Code generates or posts a comment, end it with the `Assisted-by:` line (see `@smith-style`). No "on behalf of" line — the account it posts under already names that human. A handle in a body names the person the comment addresses, never its poster.
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

Inline comments anchored to line(s) with committable `suggestion` blocks. See `references/REVIEW-WORKFLOW.md` for full guidelines and examples.

## Review Convergence & Auto-Fix

Follow convergence protocol: fix high-confidence findings, merge on clean review. Full protocol in `references/REVIEW-WORKFLOW.md`.

## Rebase Decision Tree

Behind base + no conflicts + explicit "update" → AUTO-REBASE. Full tree in `references/REVIEW-WORKFLOW.md`.

## Merge Strategies

**Merge commit**: Feature branches, **Squash**: Small fixes, **Rebase**: Linear history


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
3. High-confidence fixes: implement, commit, reply with SHA — a reply to the
   bot's own thread is mechanics, so it needs no yes (`@smith-guidance`
   Harmless). A comment addressed to a human reviewer does.
4. Low-confidence: draft reply, ask user before posting
5. Re-check after CI passes

**Proactive self-review** — before reviewer sees changes:
- Run CodeRabbit review via configured integration (e.g. `coderabbit:review` skill or GitHub App) after pushing
- Address mechanical feedback (lint, naming, tests)
  before human review begins

**`/autofix-pr` — cloud auto-fix loop**

Run `/autofix-pr` while on the PR's branch. Claude Code detects the open PR with `gh`, spawns a Claude Code on the web session, and turns on auto-fix for that PR in one step. The web session subscribes to GitHub events (CI checks, review comments) and pushes fixes for high-confidence cases; ambiguous changes prompt instead of pushing.

**Requires** the Claude GitHub App installed on the repo (PR webhooks). Replies to review threads post under the user's GitHub account but are labeled as Claude Code authored. Disable per-PR via the web session's CI status bar.

Running `/autofix-pr` is itself the up-front authorization for that PR's loop — the one case where the per-item yes (`@smith-guidance` Harmless) cannot apply, since the session outlives the terminal. It authorizes exactly two things on that one PR: pushing fixes, and replying to its review threads. It does NOT authorize merging, `--force-with-lease`, or any action on a linked or downstream PR — those still run through `/smith-ship` and the PR ownership gate. Its replies post under the user's account, so they carry the same attribution as any other reply: the `Assisted-by:` line (`@smith-style`). Authorization is what the loop grants; attribution is not waived by it.

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

## Stacked PRs

Critical rules; full workflows (creation, cascade update, squash recovery,
diagrams) in `references/STACKS.md` — load that file when actually operating
on a stack.

- **Prefer the native `gh stack` extension (github/gh-stack) when it is
  installed** — it builds and manages the whole stack (`gh stack init` / `add`
  / `submit` / `push` / `sync` / `rebase` / `merge`) instead of hand-rolling
  the base-retarget and rebase cascade. Confirm availability with `gh
  extension list`; never assert from memory that it is absent (recurring
  miss — verify from source, `@smith-guidance` Honest). The manual git/gh
  workflows in `references/STACKS.md` are the fallback when the extension is
  unavailable, and remain the reference for WHY each step matters (e.g. the
  cli/cli#1168 child-close race).
- Merge bottom-up: retarget each child's base onto its grandparent (or the
  default branch) BEFORE merging or deleting the parent — never after.
  `gh pr merge --delete-branch` on a parent whose child still targets it
  CLOSES the child instead of retargeting (cli/cli#1168, still open; the
  web-UI delete auto-retargets). Delete parent branches manually
  (`git push origin --delete`) only after the child is retargeted.
- Update child branches by merging their immediate parent (never the default
  branch directly) — cascade through each level in order.
- Keep stacks to 3-4 levels deep; one worktree per unit.
- Every stacked PR body carries `Depends on:` / `Blocks:` and ends with the
  `Assisted-by:` line; the stack's titles and bodies are shown together and
  opened on one explicit yes (batched consent, `@smith-guidance` Harmless).
- Before stack-wide operations on EXISTING branches, verify scope:
  `./smith-gh-pr/scripts/verify-stack-scope.sh '«branch-glob»'` — enumerate
  all branches, present the summary, get approval. The pre-branch
  decomposition approval is a distinct earlier gate owned by `@smith-ship`
  stacked mode. If a rebase produces 0 new commits, STOP and investigate.

## Related

- `@smith-gh-cli/SKILL.md` - GitHub CLI commands, pagination limits
- `@smith-review/SKILL.md` - Local review loop, convergence criteria
- `@smith-git/SKILL.md` - Git operations, rebase
- `@smith-style/SKILL.md` - Conventional commits, branch naming
- `@smith-tests/SKILL.md` - Testing standards (pre-PR checklist)
- `@smith-research/SKILL.md` - Research best practices before implementing review feedback
- `@smith-validation/SKILL.md` - Debugging, root cause analysis for review issues

## Before You Finish

**Before posting any review finding:** is the fix mechanical? Then the comment
carries the replacement text in a fenced `suggestion` block (see "Posting
Review Findings").

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
git branch -d feat/my-feature
```
`--ff-only` is mandatory: it refuses to create a stray merge commit if local has
diverged (e.g. after a squash-merge), surfacing the problem instead of hiding it.

**Check freshness** (`@{u}` = current branch's upstream, branch-name-agnostic):
```shell
git fetch  # fetches the current branch's configured remote, matching @{u}
BEHIND=$(git rev-list HEAD..@{u} --count)
```
