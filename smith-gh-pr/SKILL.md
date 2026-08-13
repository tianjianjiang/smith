---
name: smith-gh-pr
description: GitHub PR workflows including creation, review cycles, merge strategies, stacked PRs (creation, merge order, rebase after parent merges, squash handling), posting review findings, and confirming a CodeRabbit review actually ran. Use when creating PRs, stacked PRs, or dependent PRs, replying to review comments, running or interpreting a CodeRabbit review (GitHub App or `coderabbit` command line), merging branches, or fetching PR threads. Covers rebase decision trees and AI-generated descriptions. For the stacked shipping pipeline see smith-ship (stacked mode).
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

**AI-generated descriptions**: Analyze full diff, read ALL commits, identify tickets, generate structured summary (What/Why/Testing/Dependencies). End the body with the `Assisted-by:` line (see `@smith-style`). Generated or not, a description is content addressed to a human — show it and open on an explicit yes (`@smith-guidance` Harmless).

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

When Claude Code is the reviewer and an open PR exists (including self-review
before human review), deliver findings as **inline comments anchored to the
line(s)**, carrying a **committable `suggestion` block** whenever the fix is
mechanical — not as one PR-level summary comment. With no open PR, report
in-band (see `@smith-review`).

- **Anchor to the line(s).** A finding that maps to specific line(s) MUST be an
  inline review comment on those lines. Reserve PR-level/summary comments for
  cross-cutting findings with no single anchor (architecture, a missing test
  file, a cross-module concern).
- **A mechanical fix MUST carry a committable suggestion.** GitHub renders a
  "Commit suggestion" button from a fenced block tagged `suggestion`; the author
  applies it in one click. If you can state the replacement text, you can put it
  in the block — describing that edit in prose instead makes the author retype
  what you already wrote, and is the single most common way a review finding
  wastes their time. Omit the block ONLY when the fix needs design discussion or
  cannot be expressed as a line-range replacement — and say which in the
  comment. "I did not bother" is not one of the two exemptions.
- **Replace the whole commented range.** GitHub replaces the commented line(s)
  with the block's contents verbatim — the block may hold more or fewer lines
  than the range (a suggestion can add or drop lines). Comment on the full range
  you intend to replace and put the complete replacement in one block.
- **Lead an author-directed comment with the author's `@«handle»`.** When a
  finding is addressed to the PR author — a blocker, a question, a direct
  request — put their handle on its own first line, then the body, so the
  comment says on sight who it is for. For a purely informational inline note
  it is optional.

**Mechanism (prefer the built-in):**

- `/code-review --comment` — runs the review and posts findings as inline PR
  comments automatically — every finding at once, ungated, each one content
  addressed to a human. Review comments are a conversation, not a list, so they
  stay **one per turn** (`@smith-guidance` Harmless) and `--comment`'s auto-post
  is therefore NOT the default path: post them one at a time. Asking for a
  review is not a yes for words that did not exist when it was asked.
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

**PR ownership gate (whose PRs may we merge?):**
- Merge or `--force-with-lease` push ONLY a PR the user authored (or explicitly
  says is theirs to merge). When unsure, check
  `gh pr view {PR} --json author --jq .author.login` against
  `gh api user --jq .login`; if that lookup errors, returns an empty login, or
  is not an exact match, **fail closed** — treat the PR as not yours and stop.
- A PR authored by someone else is NOT ours to merge: report its status and stop
  — do not merge it, and do not ask whether to merge it, unless the user
  explicitly directs it. This gate scopes every merge default below.
- Approving another author's PR is different — that IS legitimate; see
  "Approving a PR by command".

**Decide-and-proceed defaults (do NOT ask between obvious steps):**
- CodeRabbit finding is Critical/Warning + high-confidence: fix, commit, push
  silently
- CodeRabbit finding is Info/Nitpick: reply-and-resolve or skip with a
  one-line reason
- After pushing a fix: re-run review immediately
- 0 actionable findings on a user-authored PR: merge (`gh pr merge --squash
  --delete-branch`); for a stacked PR with an open child, OMIT `--delete-branch`
  (see "Stacked PRs" below)
- Post-merge: `ExitWorktree action="remove"` → `git pull --ff-only`
  (see `@smith-worktree/SKILL.md` Sync-After-Squash-Merge)

**Must-ask criteria (only interruption triggers):**
- About to post content addressed to a human — a review finding, PR
  description, or approval body (`@smith-guidance` Harmless). Replies to an
  automated reviewer's own thread that no human has joined are mechanics and do
  not trigger this.
- Finding requires scope change beyond the PR's stated goal
- Finding contradicts an existing smith-skill rule (meta-question)
- Auto-mode classifier denial without a documented escape pattern
- CI fails after a CodeRabbit-driven fix (regression vs flake ambiguity)
- User explicitly said "pause" or "wait" in recent turns

**Convergence criteria:** owned by `@smith-review` — a clean round or two
consecutive Info-only rounds, with a complete plugin-pass receipt. "Ready to
merge" here means that loop reported converged; a flip-flopping reviewer ends
the loop WITHOUT convergence (escalated to the user, not merged).

**CodeRabbit fails OPEN — absence of review is NOT a pass.** One instance of
`@smith-guidance` "a missing signal is never a passing signal":
- CodeRabbit silently skips review on exhausted credits / the per-plan hourly
  rate-limit: "Review limit reached". The cap is a ROLLING allowance that
  differs per plan and per channel, with its own open-source tier — read the
  current table rather than a number memorised here. It also skips PRs whose
  base is not the default branch (stacked PRs) and a PR closed mid-review.
- Confirm a CodeRabbit review actually ran before treating "0 findings" as
  clean. In `--agent` output that means `"status":"review_completed"` **and** a
  non-empty `reviewedFiles` — `"findings":0` is printed on the skip path too,
  alongside `"status":"review_skipped"`.
- Match the flag to the tree state: `--uncommitted` reviews nothing once the
  work is committed ("No uncommitted changes detected") — including a
  background review that fires after you commit, which reports clean off an
  empty diff. After committing, pass `--committed` with `--base` set to
  «the PR's own base ref»: the default branch for a standalone PR, the
  parent branch for a stacked one. The non-default-base skip above is App
  behaviour; the command line takes `--base` as given.
- Pull-request, editor, and command-line reviews are three SEPARATE hourly
  channels, each counted per developer, so one refusing says nothing about
  another. Re-trigger the App with a `@coderabbitai review` comment as the
  rolling window frees capacity.
- The App's fast reply (currently "Action performed — Review finished") is an
  acknowledgement, not a result: it posts within seconds and reads the same
  whether the review ran, was skipped, or was blocked (a blocked one admits it
  only further down that same comment: "your included review limit is
  currently reached"). The real review arrives minutes later as a SEPARATE
  submitted review, so ANY comment appearing seconds after the trigger proves
  nothing either way — trust only the review-event test below.
- A submitted review event is not sufficient either: replying to a thread
  makes the App post a review event with an EMPTY body. Check
  `gh pr view «number» --json reviews` for an event that (a) has a non-empty
  body and (b) is timestamped after the head commit — an older event read an
  older tree, so zero open threads under it says nothing about the newest
  commit. Do not test for the "Actionable comments posted: «count»" opener:
  nitpick-only and outside-diff reviews omit it, and an outside-diff review
  can carry a Major. If that command errors or returns empty, record "not
  reviewed" — a failed lookup must never read as "no findings".

Source: https://docs.coderabbit.ai/management/plans and the `--agent` output
of `coderabbit review` (both retrieved 2026-07-27). The quotas and the App's
comment wording are point-in-time; the review-event test is not.

**External write rule (Notion, Slack, Jira, GitHub comments):**
- A comment addressed to a **human** — a review finding, a PR description, an
  approval body — is content: draft it, show it, wait for an explicit yes, one
  per turn. A reply to an automated reviewer's own thread is mechanics and needs
  no yes — unless a human has joined that thread, which makes it theirs.
  Canonical split: `@smith-guidance` Harmless.
- Merging, `--force-with-lease`, ff-sync, and resolving threads are mechanics —
  decide-and-proceed inside an authorized ship (the PR ownership gate above
  bounds which PRs qualify).
- Always end the body with the `Assisted-by:` line (`@smith-style`)

## Approving a PR by command

- `gh pr review <n> -R <owner/repo> --approve --body-file <f>` — an external
  write under the user's account, and an approval body is content: draft it,
  show it, and submit only on an explicit yes (`@smith-guidance` Harmless).
  End the body with the `Assisted-by:` line (`@smith-style`).
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
git branch -d feat/my_feature
```
`--ff-only` is mandatory: it refuses to create a stray merge commit if local has
diverged (e.g. after a squash-merge), surfacing the problem instead of hiding it.

**Check freshness** (`@{u}` = current branch's upstream, branch-name-agnostic):
```shell
git fetch  # fetches the current branch's configured remote, matching @{u}
BEHIND=$(git rev-list HEAD..@{u} --count)
```
