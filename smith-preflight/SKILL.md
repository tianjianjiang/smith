---
name: smith-preflight
description: Pre-ship gate
allowed-tools: Bash(git *), Bash(gh *), Bash(command -v *), Bash(node *), Read, Grep
---

# /smith-preflight — gate the current change against the invariants

Read-only: no fix, no commit, no push — it reports whether shipping is
allowed. That is a contract you keep, not a fence the allowlist builds;
the grant follows the command skills that declare one and does admit
writes, so honour it regardless and never let this gate change the state
it measures. `/smith-review` judges review quality, a different question.

This command gates rules, it does not state them: each check names its
owning skill, and the owner's wording wins over this file's.

## Live state

- Branch: !`git branch --show-current`
- Default branch: !`git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo unset`
- Changes: !`git status --porcelain -uall`
- Hooks path: !`git config --get core.hooksPath || echo unset`
- GitHub CLI on PATH: !`command -v gh 2>&1`
- GitHub CLI auth (gh's own `--json`/`--jq` machine fields, not its
  prose — see pr-ownership below):
  !`gh auth status --json hosts --active --jq '[.hosts[][].state] | unique | join(",")' 2>&1`
- PR author: !`gh pr view --json author --jq .author.login 2>&1 | head -1`
- Authenticated login: !`gh api user --jq .login 2>/dev/null | head -1`
- Subagent spawn ledger (written by `subagent-contract-guard`; see
  subagent-contract below):
  !`node "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/smith-ctx-claude/scripts/spawn-ledger-report.mjs" 2>/dev/null || echo "subagent-contract PROBE-UNAVAILABLE — the guard is not installed at this profile's skills path"`

## Checks

**Machine** checks are decided by the probes above. **Attested** checks
are answered from evidence, never a bare yes — this session's history
(which turn, which quote) or durable artifacts that outlive it (a PR
comment, a commit, a ticket). If the check's subject occurred and you
cannot evidence it either way, that is a `FAIL`; if it never occurred,
`N/A` (not applicable) plus the reason. Never let `N/A` stand in for
evidence you lack.

A resumed session is the exception, and context resets are routine here.
When a `/clear` hides history the durable artifacts cannot recover,
record `SKIP:resumed-session` naming the check and what you did search,
and say so rather than burying it. That is a disclosed gap, not a pass,
and never a substitute for evidence you could still go and find.

- **branch-first** — machine. See below.
- **secret-scan** — machine when you can point at scan output covering
  the change, whether you produced it here or a commit's hook did;
  attested otherwise. See below.
- **pr-ownership** — machine. See below.
- **external-write** — attested. Every human-facing external write this
  task made carried its own explicit yes. Owner @smith-guidance
  Harmless, External writes.
- **verify-before-assert** — attested. Every convention or rule
  asserted was quoted from its source. Owner @smith-guidance Honest.
- **suggestions** — attested. Every mechanical review finding posted
  carried a committable `suggestion` block. Owner `@smith-gh-pr`
  Posting Review Findings.
- **subagent-contract** — machine when the ledger probe answers. See below.

**branch-first.** Owner @smith-git CRITICAL, enforced by
`smith-ctx-claude/scripts/branch-guard.mjs`. Protected: `main`,
`master`, `develop`, plus the default branch when one resolves — and
that default counts in BOTH its full name and its last path segment.
The hook compares only the segment (`origin/release/v2` becomes `v2`)
while the probe prints `origin/release/v2`, so honouring one form alone
lets a branch through that the hook blocks. Strip the `origin/` prefix
and treat either form as protected. An `unset` default is not a failure
— fall back to the static set, as the hook does. A detached HEAD (empty
branch) is a `FAIL` even though the hook permits it: there is no branch
to commit onto.

**secret-scan.** The scanner is a local, gitignored install, so no
committed file here names its path — resolve it from `core.hooksPath`.
It is a pre-commit hook, so it has not fired at this gate; and one
resolving its patterns from `git rev-parse --show-toplevel` finds none
inside a worktree and exits 0 having scanned nothing. A silent exit 0 is
evidence of no scan, never of a clean one (@smith-guidance close gaps).

This gate never runs it — the grant would permit that (`git hook run`
and `git commit` both sit inside `Bash(git *)`), so it is the contract
holding, not the allowlist. Produce the evidence yourself: `git` for the
diff, Read for the pattern list, Grep to match them; or point at output
a commit's hook already produced.

`PASS` requires scan evidence you can point at, covering everything a
push would carry:

- Uncommitted work: the working tree — staged, unstaged AND untracked
  (the Changes probe uses `-uall` for that reason). Never substitute
  `git diff --cached`; it sees staged content only.
- Commits already on the branch: diff against the base branch, not
  `git show`, which covers one commit while the push carries all of
  them.
- Both at once, the usual state at a fix-and-amend: scan both.

A scanner that is configured but whose patterns are unreachable is a
`FAIL`, not the `SKIP` that absent tooling earns elsewhere: the setup is
broken, a `SKIP` does not block, and a scan that cannot run is exactly
when shipping must stop. A repository with no scanner configured at all
is a different state — most repositories, since the install here is
local and gitignored. Do not `FAIL` it: scan the same scope yourself for
credential-shaped content and answer from what you found.

**pr-ownership.** Owner `@smith-gh-pr` PR ownership gate, which fails
closed. Its probes run independently of each other, so evaluate the
bullets below as an ordered if/elif chain — stop at the first one whose
condition matches, never check a later bullet once an earlier one has:

- GitHub CLI on PATH probe empty (no `gh` binary found) → `SKIP`.
- An author line reporting no GitHub remote, or no remotes at all →
  `SKIP`. The repository is not on GitHub, so the question does not
  arise; failing it would block every push outside GitHub.
- GitHub CLI auth probe reading anything other than `success` (gh's own
  "not logged into any GitHub hosts" text on a never-authenticated
  machine, an auth error state, or an `unknown flag` error from a
  pre-2.81.0 gh) → `FAIL`. A failed lookup is never a `SKIP`; this
  bullet is reached only once the on-PATH bullet above has already
  ruled out a missing `gh` binary, so a missing binary never reaches it.
  The probe (`--json hosts --active --jq '[.hosts[][].state] | unique |
  join(",")'`) reads gh's own documented `state` field rather than its
  free-form prose, which a future gh release could reword; `--active`
  scopes it to each host's active account, so a stale secondary account
  doesn't fail this check; and it reports only that field, never the
  token/scope detail plain `gh auth status` would print into the Live
  State block. Requires gh ≥ 2.81.0 for `--json` support (cli/cli#11544,
  first shipped in the v2.81.0 release notes) — an older gh's `unknown
  flag` error also reads as `FAIL` here.
- An author line reading `no pull requests found for branch ...` →
  `SKIP`. `gh pr view` writes it to stderr and exits non-zero, so it
  arrives looking like an error; reading it as one would fail every
  branch that has no pull request yet.
- Any other author line that is not a plain login, or a login probe
  that is not a plain login → `FAIL`.
- Both values non-empty and identical → `PASS`. Anything else → `FAIL`.

The owner's gate runs again at merge time and still fails closed there.

A `SKIP` authorizes nothing anywhere in this gate. It says the question
could not be asked, not that the answer was yes.

**subagent-contract.** Owner `@smith-subagents` Contract template, enforced
by `smith-ctx-claude/scripts/subagent-contract-guard.mjs`, which appends
every in-scope spawn to a per-checkout ledger tagged with the branch it ran
on. The Live state probe above prints that ledger's verdict; take it
verbatim rather than deciding again:

- `PASS` — no spawn reached the tool unaccounted for. Report `PASS` and
  state the counts the probe printed. Read it for exactly that: the counts
  include spawns the guard EXCUSED (`exempt`, `editor-role`) and spawns it
  REFUSED (`blocked`), not only spawns that carried the contract. It is not
  a claim that every subagent honoured it, which no hook can verify.
- `FAIL:unchecked-spawn(«reasons»)` — something on this branch cannot be
  shown to have been checked. Report `FAIL` and quote the reasons the probe
  printed; do not paraphrase them or list causes from memory, because the
  set grows with the code.
- `N/A:no-spawns` — the ledger exists and records no spawn on this branch.
  Report `N/A` with that reason.
- `SKIP:no-ledger`, or `PROBE-UNAVAILABLE` — the machine check could not
  run: no ledger for this checkout, or no reporter installed at this
  profile's skills path. Neither is a pass, and a hook that is merged is
  not thereby registered. Fall back to the attested answer — every spawn
  either pasted the contract inline, declared a bounded editor role, was a
  type the contract does not reach, or was refused — and report `SKIP`
  naming which of the two you saw, so a reader can tell the machine check
  did not run.

Two limits to state rather than paper over. The ledger sees the
`Agent`/`Task` tool channel only, so a skill the harness runs in its own
subagent, or a cloud review agent, never appears in it. And a `FAIL` here
does not clear: the ledger is append-only and an unchecked spawn really did
run, so no later correct spawn erases it. Where the cause was file damage
rather than a real unchecked spawn, pruning that record is a legitimate
repair — but deleting the ledger outright yields `SKIP:no-ledger`, a softer
verdict than the truth, so do it deliberately and say what you did.

`/clear` cannot erase this check the way it erases an attested one, because
the ledger outlives the session that wrote it. Never answer it
`SKIP:resumed-session` while the probe is giving an answer.

## Verdict

Report every check as `«name» «PASS|FAIL|SKIP|N/A»` in the order listed
above, separated by ` · `, wrapping as needed; `FAIL`, `SKIP` and `N/A`
append their reason as `:«reason»`. Put the verdict on the next line:

```text
branch-first PASS · secret-scan PASS · pr-ownership SKIP:no-pr ·
external-write N/A:no-writes · verify-before-assert PASS ·
suggestions N/A:no-findings · subagent-contract N/A:no-spawns
GO
```

Any `FAIL` → `NO-GO`, `branch-first` included: print the `NO-GO`. One
exception governs what `/smith-ship` does with that verdict, never what
you print — a `branch-first FAIL` from sitting on a protected branch is
resolved at ship's Isolate step, and a detached HEAD is not that case.
A check missing from the line counts as a `FAIL`. State the line in your
own message; do not point at tool output.

## Related

- `@smith-ship/SKILL.md` - the pipeline this gates
- `@smith-review/SKILL.md` - review convergence
- @smith-git/SKILL.md - branch-first rule
- `@smith-gh-pr/SKILL.md` - PR ownership gate, Posting Review Findings
- @smith-guidance/SKILL.md - external-write gate, verify-before-assert
- `@smith-subagents/SKILL.md` - contract template
