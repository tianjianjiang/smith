---
name: smith-gh-pr
description: GitHub pull request workflows. Use when creating, updating, reviewing or merging a pull request (PR), replying to review comments, or working on stacked PRs.
---

# GitHub PR Workflows

**Prerequisites:** @smith-principles/SKILL.md, @smith-standards/SKILL.md, `@smith-git/SKILL.md`

## CRITICAL

- Run quality checks before creating a PR
- Ensure the branch is up-to-date before requesting review or merging
- Link to related issues
- Have all CI checks passing before merge
- Create a PR only on an explicit user request
  -- listing is not consent to create
- Attach a committable `suggestion` block to a review finding whose fix is
  mechanical — prose describing an edit the reviewer could have written is a
  defect, not a review (see "Posting Review Findings" for the two exemptions)

## Avoid GitHub MCP

Prefer the `gh pr-review` extension, `gh api`, or GraphQL queries over GitHub
MCP tools (`mcp__github__*`) — they are hard to control pagination on (token
waste), less complete than the CLI, and require a personal token.

Post review comments only with `gh pr-review` (inline comments, thread
replies, review submission) or `gh pr comment`/`gh pr review`; `gh api` stays
for reads. The attribution guard (`smith-ctx-claude/scripts/attribution-guard.mjs`)
allows a pull-request text write only when it matches a signature declared in
`smith-style/scripts/attribution-signatures.json`: a `gh pr` or
`gh issue comment` body goes through `--body-file «absolute path»` and a
literal `--body` is blocked (the close/reopen `--comment` and
`gh pr-review --body` are read as literal text), and every `gh api` write of pull request or comment text
is blocked, pointing at `gh pr-review` or `gh pr create|edit|merge
--body-file`.

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
4. Run the `@smith-style` pre-push branch-name checklist; before pushing, show
   any commit message not yet approved (such as a Ralph loop's local commits,
   `@smith-ralph`) and, if the branch name was not user-specified, the branch
   name, and get an explicit yes to what was shown; then push per step 5
5. Push to remote on the user's instruction (or inside `/smith-ship`)

**AI-generated descriptions**: Analyze full diff, read ALL commits, identify tickets, generate structured summary (What/Why/Dependencies). End the body with the `Assisted-by:` line (see `@smith-style`). Generated or not, a title and description are payload — show them and open on an explicit yes (`@smith-guidance` Safety Rules).

## Working on Existing PRs

- ALWAYS get actual branch name: `gh pr view {PR} --json headRefName`
- ALWAYS check for review comments before making changes
- After pushing changes, draft the updated PR title/body, show it, and edit
  the PR only on an explicit yes (`@smith-guidance` External writes)

## Code Review Cycle

1. Fetch review comments using `gh pr-review` (see "Fetching Review Comments" below)
2. **Get ALL comments including Nitpicks** - don't skip minor issues
3. Categorize: Actionable > Nitpick > Clarification > Discussion
4. **Proactively audit similar issues** in other files not explicitly mentioned
5. Implement fixes with confidence scoring (high: implement, low: ask)
   - **High confidence**: Small surface area change, aligns with existing patterns, covered by tests
   - **Low confidence**: Ambiguous behavior, architectural impact, requires design discussion
6. Show the commit message and commit on a yes, push it (inside a ship the
   user invoked or on the user's instruction to push), then reply with the
   pushed SHA — by reviewer type:
   - **Automated reviewer's thread, no human joined**: inside a ship or review
     the user invoked, post "fixed in «SHA»" or a one-line decline directly
     (mechanics); any other reply, or any reply outside such a ship or review,
     is payload: draft, show, post on an explicit yes
   - **Human reviewer, or a human joined the bot thread**: draft, show, post
     only on an explicit yes, one reply per turn (`@smith-guidance` External writes)
7. **Resolve only automated reviewers' threads** after addressing, inside a
   ship or review the user invoked or on the user's explicit instruction to
   resolve them — don't leave
   them open. A human's thread is theirs to resolve; leave it open after replying.
8. Re-check for new comments after CI passes

**Code review response rules:**
- **File-inline comments** (on specific lines): MUST reply in-thread using `gh pr-review comments reply --pr {number} -R {owner}/{repo} --thread-id {PRRT_xxx}`, NOT as PR-level comment. This keeps discussion traceable to the code location.
- **Propose edits as committable suggestions**: a reply proposing a mechanical
  code change MUST embed a committable ` ```suggestion ` block (see "Posting
  Review Findings" below) so the author commits it in one click instead of
  re-typing.
- **PR-level comments** (general discussion, `<details>` blocks): Reply with `gh pr comment` or GitHub's "Quote reply"
- Reply with the commit SHA. In an automated reviewer's thread that no human joined, inside a ship or review the user invoked, reply "fixed in «SHA»" or a one-line decline and then resolve the thread with `gh pr-review threads resolve`; any other reply is payload and needs a yes. In a human reviewer's thread, show the reply and post it on an explicit yes, and leave the thread open for the reviewer to resolve (`@smith-guidance` External writes)
- Proactive audit: search codebase for similar issues before committing
- **CodeRabbit `<details>` comments** (Nitpicks, Duplicated, Outside diff range): These appear in PR thread, not inline on files. Use GitHub's "Quote reply" to include Markdown blockquote of the essential part (e.g., `> The redundant text...`), making response traceable. This creates a new PR-level comment rather than a reply inside the bot's thread, so it is payload — show it and post on a yes (`@smith-guidance` Safety Rules)
- **Attribution**: When Claude Code generates or posts a comment, end it with the `Assisted-by:` line (see `@smith-style`); that line does not turn a "fixed in «SHA»" or one-line-decline reply into payload. No "on behalf of" line — the account it posts under already names that human. A handle in a body names the person the comment addresses, never its poster.
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

## Pre-Draft Verification

Before drafting any PR review comment:

1. Get attribution from script:
   ```bash
   ~/.smith/smith-style/scripts/attribution.sh
   ```

2. Validate format:
   - PASS: The line is exactly what `attribution.sh` printed: `Assisted-by: Claude:«session-model-id»`, the id as the session reports it, provider prefix included (e.g. `claude-opus-4-8`, `us.anthropic.claude-opus-4-8`)
   - FAIL: "on behalf of" anywhere in comment
   - FAIL: hand-typed model IDs

3. Append to comment body:
   - Blank line before attribution
   - Attribution as last line of comment body
   - With `--body-file`, append it with `attribution.sh >> «file»`; with
     `gh pr-review`, which has no `--body-file`, paste the printed line
     unchanged at the end of a single-quoted `--body '…'`

## Review Convergence & Auto-Fix

Follow convergence protocol: fix high-confidence findings (commit message shown for a yes), and merge a user-authored PR on a clean review only inside a ship the user invoked or after the user said to merge. Full protocol in `references/REVIEW-WORKFLOW.md`.

## Rebase Decision Tree

Behind base + no conflicts + explicit "update" → AUTO-REBASE. Full tree in `references/REVIEW-WORKFLOW.md`.

## Merge Strategies

**Merge commit**: Feature branches, **Squash**: Small fixes, **Rebase**: Linear history


## /ultrareview — Cloud Deep-Review

User-invoked, billed multi-agent cloud review of a branch or PR; the agent
never starts one. Invocation, requirements, billing and when to recommend it
in `references/REVIEW-WORKFLOW.md`.

## Automated PR Review Monitoring

Poll for review comments with `/loop` and address them by the auto-address
workflow; full steps in `references/REVIEW-WORKFLOW.md`. `/autofix-pr` is
not recommended: its cloud session pushes commits and posts replies without
showing them first (`@smith-guidance` Safety Rules).

## Claude Code Plugin Integration

Prefer `/code-review` and `pr-review-toolkit:review-pr` (the single entry
point for its own subagents) when available. `/commit-push-pr` is not
recommended: it commits, pushes and opens the PR without showing the commit
message or PR text first; ship with `/smith-ship`. Details in
`references/REVIEW-WORKFLOW.md`.

## Stacked PRs

Critical rules; full workflows (creation, cascade update, squash recovery,
diagrams) in `references/STACKS.md` — load that file when actually operating
on a stack.

- **Prefer the native `gh stack` extension (github/gh-stack) when it is
  installed** — it builds and manages the whole stack (`gh stack init` / `add`
  / `submit` / `push` / `sync` / `rebase` / `checkout` / `link` / `merge`)
  instead of hand-rolling the base-retarget and rebase cascade. Confirm
  availability with `gh extension list`; never assert from memory that it is
  absent (verify from source, `@smith-guidance` Communication Standards). The
  manual git/gh workflows in `references/STACKS.md` are the fallback when the
  extension is unavailable, and remain the reference for WHY each step
  matters (e.g. the child-close race on parent-branch deletion).
- **`gh stack view` saying "not part of a stack" is a per-worktree tracking
  gap, not a licence to hand-roll.** Run `gh stack checkout <stack#|PR#>` to
  restore tracking in this worktree; then, inside a ship the user invoked
  or on their instruction to sync, run `gh stack sync`. Hand-rolled
  `git rebase --onto` cascades, raw-SHA `--force-with-lease` refspec
  pushes, and edits to `.git/gh-stack` are blocked-by-ask
  (`gh-stack-guard`); a worked walkthrough is in `references/STACKS.md`
  "Existing stack from a fresh worktree".
- Inside a ship the user invoked or after the user said to merge, merge
  bottom-up: retarget each child's base onto its grandparent (or the
  default branch) BEFORE merging or deleting the parent — never after.
  `gh pr merge --delete-branch` on a parent whose child still targets it
  CLOSES the child instead of retargeting (a known gh defect, `references/STACKS.md`; the
  web-UI delete auto-retargets). Delete parent branches manually
  (`git push origin --delete`) only after the child is retargeted.
- Update child branches by merging their immediate parent (never the default
  branch directly) — cascade through each level in order, pushing only
  inside a ship the user invoked or on their instruction.
- Keep stacks to 3-4 levels deep; one worktree per unit.
- Every stacked PR body carries `Depends on:` / `Blocks:` and ends with the
  `Assisted-by:` line; the stack's titles and bodies are shown together and
  opened on one explicit yes (one list whose every draft was shown,
  `@smith-guidance` Safety Rules).
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
gh pr create --title "feat: add feature" --body-file «draft file» --assignee @me
```

**Merge PR:**
```shell
gh pr merge {PR} --squash
```

Options: `--squash`, `--merge`, or `--rebase`

**Post-merge cleanup** (use the repo's DEFAULT branch — `main`, `develop`, etc., never assume `main`), run from the PRIMARY checkout:
```shell
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git checkout "$DEFAULT_BRANCH" && git fetch --prune origin && git pull --ff-only
git branch -d feat/my-feature
```
`--ff-only` is mandatory: it refuses to create a stray merge commit if local has
diverged (e.g. after a squash-merge), surfacing the problem instead of hiding it.

Inside a worktree session this block cannot run as written: the default branch
is checked out in the primary checkout, so `git checkout` fails, `git fetch
origin «default»:«default»` is refused, and `git -C «primary-checkout»` is
blocked by Claude Code's worktree isolation guard. `ExitWorktree` first, then
run the block (`@smith-worktree/SKILL.md` Sync-After-Squash-Merge Protocol and
Built-in Isolation Guard).

**Check freshness** (`@{u}` = current branch's upstream, branch-name-agnostic):
```shell
git fetch  # fetches the current branch's configured remote, matching @{u}
BEHIND=$(git rev-list HEAD..@{u} --count)
```
