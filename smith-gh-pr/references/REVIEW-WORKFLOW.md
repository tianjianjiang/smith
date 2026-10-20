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

**Mechanism (post one finding per turn):**

- `/code-review --comment` — runs the review and posts findings as inline PR
  comments automatically — every finding at once, ungated, each one
  payload. Review comments are a conversation, not a list, so they
  stay **one per turn** (`@smith-guidance` Safety Rules). Do not use
  `--comment`: run the review without it and post each finding one at a
  time, after its own explicit yes. Asking for a review is not a yes for
  words that did not exist when it was asked.
- Manual single inline comment with `gh pr-review` (when hand-authoring one
  finding). Run `attribution.sh` first and end the single-quoted body with the
  line it printed; a `gh api` write of a review comment is blocked:

````shell
gh pr-review review --start --pr {pr} -R {owner}/{repo}
gh pr-review review --add-comment --pr {pr} -R {owner}/{repo} --review-id {id} \
  --path {file} --line {n} --body 'Explain the issue briefly.

```suggestion
fixed line(s) here
```

Assisted-by: Claude:«session-model-id»'
# Multi-line range: add --start-line {firstLine}
gh pr-review review --submit --pr {pr} -R {owner}/{repo} --review-id {id} --event COMMENT
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

**Decide-and-proceed defaults (no questions between obvious steps; payload still needs its yes):**
- CodeRabbit finding is Critical/Warning + high-confidence: fix locally;
  show the commit message and commit on a yes; push only inside a ship the
  user invoked or on their instruction
- CodeRabbit finding is Info/Nitpick: in a bot thread no human joined, inside
  a ship or review the user invoked, reply "fixed in «SHA»" or a one-line
  decline, then resolve; any other reply is payload and needs a yes
- After pushing a fix: re-run review immediately
- 0 actionable findings on a user-authored PR, inside a ship the user invoked
  or after the user said to merge: merge (`gh pr merge --squash
  --delete-branch`); for a stacked PR with an open child, OMIT `--delete-branch`
  (see "Stacked PRs" below)
- Post-merge: `ExitWorktree action="remove"` → `git pull --ff-only`
  (see `@smith-worktree/SKILL.md` Sync-After-Squash-Merge)

**Must-ask criteria (only interruption triggers):**
- About to publish payload — a commit message, review finding, PR
  description, or approval body (`@smith-guidance` Safety Rules). For a
  write `external-write-guard` matches (a review finding, an approval
  body), show it, wait for the user's reply, and call the tool only on a
  yes: the guard denies a call made before that reply. Inside a
  ship or review the user invoked, a reply of "fixed in «SHA»" or a one-line
  decline in an automated reviewer's own thread that no human has joined is
  mechanics and does not trigger this.
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
`@smith-validation` "a missing signal is never a passing one":
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
  rolling window frees capacity; a PR comment is payload: show it and post
  on an explicit yes (`@smith-guidance` External writes).
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
- Every word a write publishes — a review finding, a PR description, an
  approval body, a commit message (a Ralph loop's local commits excepted,
  `@smith-ralph`) — is payload: draft it, show it, and wait for an explicit
  yes (one item per turn, or one list whose every draft was shown; review
  findings are never a list). For a write `external-write-guard` matches,
  the guard denies the call until the payload was shown and the user
  replied (`@smith-ctx-claude` External Writes). Inside a ship or review the
  user invoked, a
  reply of "fixed in «SHA»" or a one-line decline in an automated reviewer's
  own thread is mechanics — unless a human has joined that thread, which
  makes it theirs.
  Canonical rule: `@smith-guidance` Safety Rules.
- Merging a PR the user authored once told to and deleting its merged
  branch, `--force-with-lease` to your own branch, and ff-only sync are
  mechanics inside a transaction that performs them, such as a ship the
  user invoked (a review performs none of them); resolving an automated
  reviewer's thread that no human joined, after a "fixed in «SHA»" or
  one-line-decline reply, is a mechanic inside a ship or review the user
  invoked (the PR ownership gate above bounds which PRs qualify). A human
  reviewer's thread stays open for them to resolve.
- Always end the body with the `Assisted-by:` line (`@smith-style`); that
  line does not turn a "fixed in «SHA»" or one-line-decline reply into payload

## Approving a PR by command

- `gh pr review <n> -R <owner/repo> --approve --body-file <f>` — an external
  write under the user's account, and an approval body is payload: draft it,
  show it, and submit only on an explicit yes
  (`@smith-guidance` Safety Rules).
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
3. High-confidence fixes: implement locally, show the commit message and
   commit on a yes, push (inside a ship the user invoked or on the user's
   instruction to push), then reply with the pushed SHA. Inside a ship or
   review the user invoked, a reply in the bot's own thread limited to
   "fixed in «SHA»" or a one-line decline is mechanics (`@smith-guidance`
   Safety Rules); any other reply is payload and needs a yes.
4. Low-confidence: draft the reply, show it, wait for the user's reply,
   and post it only on a yes (`@smith-ctx-claude` External Writes)
5. Re-check after CI passes

**Proactive self-review** — before reviewer sees changes:
- Run CodeRabbit review via configured integration (e.g. `coderabbit:review` skill or GitHub App) after pushing
- Address mechanical feedback (lint, naming, tests)
  before human review begins

**`/autofix-pr` — cloud auto-fix loop**

**Not recommended: `/autofix-pr` cannot show its payload first.** The cloud session outlives the terminal and pushes commits and posts review replies under the user's account without showing them, while `@smith-guidance` Safety Rules require every commit message, and every reply beyond "fixed in «SHA»" or a one-line decline in a bot thread no human joined, to be shown for a yes before the write. Use the monitoring loop pattern above instead: the terminal stays attached and the user approves each commit, push and reply.

`/autofix-pr` (run while on the PR's branch): Claude Code detects the open PR with `gh`, spawns a Claude Code on the web session, and turns on auto-fix for that PR in one step. The web session subscribes to GitHub events (CI checks, review comments) and pushes fixes for high-confidence cases; ambiguous changes prompt instead of pushing.

**Requires** the Claude GitHub App installed on the repo (PR webhooks). Replies to review threads post under the user's GitHub account but are labeled as Claude Code authored. Disable per-PR via the web session's CI status bar.

**Warning:** if the repo uses comment-triggered automation (Atlantis, Terraform Cloud, GitHub Actions on `issue_comment`), auto-fix's review replies can trigger those workflows. Avoid auto-fix where a PR comment can deploy infrastructure or run privileged operations.

Source: https://code.claude.com/docs/en/claude-code-on-the-web#auto-fix-pull-requests

## Claude Code Plugin Integration

**When plugins are available, prefer plugin commands:**

- **`/code-review`**: Launches 4 parallel agents with confidence scoring (threshold 80)
- **`/commit-push-pr`**: Not recommended: it commits, pushes and creates the
  PR in one step without showing the commit message or PR text first
  (`@smith-guidance` Safety Rules). Ship with `/smith-ship` instead
- **`pr-review-toolkit:review-pr`**: the SINGLE entry point for multi-agent
  review — it orchestrates its own 6 subagents. NEVER hand-pick or invoke the
  individual agents (`code-reviewer`, `silent-failure-hunter`,
  `pr-test-analyzer`, etc.) directly via the Task tool. A HIGH finding from one
  agent needs >=2-of-6 corroboration; a solo HIGH downgrades to
  medium-for-user-review.

**Plugin commands complement** (not replace) manual `gh` workflows.
