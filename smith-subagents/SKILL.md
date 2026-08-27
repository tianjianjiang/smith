---
name: smith-subagents
description: Subagent spawning and return discipline
---

# Subagent Discipline

**Scope:** Spawning, scoping, and consuming Task/Agent subagents and
workflow orchestration; what tools to grant and how to trust returns
**Load if:** About to spawn a subagent, delegate investigation, orchestrate
parallel agents, OR a subagent will read/modify shared state (PR, issue,
file, remote)
**Prerequisites:** @smith-guidance/SKILL.md (delegation + in-band progress),
@smith-ctx/SKILL.md (context isolation)

## CRITICAL: Spawn Narrow, Trust Nothing

- Spawn READ-ONLY by default. Grant write/side-effecting tools only for a
  bounded edit you have explicitly described in the prompt.
- A subagent RETURNS findings; the main thread decides and acts. Investigators
  report `file:line` facts, not fixes.
- Treat every return as a CLAIM, not ground truth. Reconcile against live
  state before acting on it.
- Subagents do NOT inherit skills, AGENTS.md, or memory. Pass the rules the
  task needs INLINE in the prompt.
- Restate a subagent's key findings in your own message — a reader (and the
  classifier) sees only your text, never the subagent's return.
- Grant investigator/locator roles read-only tools; reserve write, commit,
  push, or external-API tools for a named editor role.
- Keep mutation of shared artifacts (PR title/body, issue, remote branch,
  tracked file) as the main thread's call — a subagent may report on them but
  not apply the change itself.
- Re-read the current state of anything a subagent described before acting on
  its summary.
- Assume a subagent has NOT seen your conventions unless you passed them
  inline — don't assume it follows them because you do.
- For a delegated diff, audit the EXECUTION PATH rather than approving on
  style/quality alone: does the fix run on the real failing input? (the
  test-masking trap: a delegated workflow's clean-looking diff fixed a dead
  branch. See `@smith-validation/SKILL.md` Bugfix Discipline.)

## Spawning: scope and tools

- One concern per subagent. A locator finds; an editor changes one bounded
  thing; a reviewer critiques. Don't fuse roles.
- A SKEPTIC role tries to REFUTE a finding under test — most often your own,
  sometimes another agent's. Read-only tools like any reviewer; its contract
  (what to withhold from it, and the verdict to ask for) is in
  `@smith-validation` Adversarial Verification.
- Parallelize INDEPENDENT subagents in a single message (multiple tool calls).
  Serialize only when one's input depends on another's output.
- Match the tool grant to the role: read-only (Read/Grep/Glob) for
  investigation; add Edit/Write only for an editor with a named target.
- Parallel file-mutating subagents need isolation — see
  `@smith-worktree/SKILL.md`. Read-only fan-out does not.

## Contract template: paste inline when spawning

The rules above are principles; a subagent sees none of them unless you paste
them. Drop this canonical block into an investigative prompt instead of
re-deriving the contract each spawn (re-deriving it is a top cause of subagents
that mutate shared state or return plans instead of findings):

> READ-ONLY investigation. Return FINDINGS ONLY — do NOT edit, write, commit,
> push, or call any mutating / external-write tool. Report `file:line` facts and
> quoted evidence, not fixes or actions taken. If a step seems to need a
> mutation, describe it for the main thread instead of doing it. Restate the
> exact values you observed; do not summarize them away.
> «Inline the specific conventions this task needs — subagents inherit no
> skills, AGENTS.md, or memory»

For a bounded EDITOR role the contract inverts: name the ONE artifact it may
change and the single tool granted, and state that everything else stays
read-only. Open a line of such a prompt with the words `EDITOR ROLE`, in
capitals: that is how the guard below is told this spawn is the inverted case
rather than a missing contract. Leading list, heading or emphasis markup is
fine; the words must begin the line, the match is case-sensitive, and a
`>`-quoted line does not count. It is a DECLARATION, not a content check — any
line beginning with those words claims the exemption, including one that goes
on to disclaim it — so never paste an example of the declaration into an
ordinary investigative prompt. A mid-line mention is safe.

**Enforced deterministically, because documenting it did not hold.**
`smith-ctx-claude/scripts/subagent-contract-guard.mjs` (PreToolUse, matcher
`Agent|Task`) blocks a spawn whose prompt does not carry the block above, and
prints that block in the refusal so pasting it is the cheapest way forward. It
extracts the text from THIS section at run time rather than keeping a copy of
its own, so it always enforces whatever the installed copy of this file says.
Exempt are subagents whose prompt the main thread never writes: plugin-namespaced
types (`plugin:agent`), and the built-in helpers named in
`smith-ctx-claude/subagent-contract-config.json`. Being read-only is NOT the
criterion and never was — `Explore` and `Plan` hold Bash and write-capable
`mcp__` tools, and are not exempt.

**Editing this section is a code change.** The guard finds the block by the
heading `## Contract template`, then takes the section's one and only
blockquote, which must contain the `«placeholder»` line, and every line from
the first placeholder to the end of the block must itself be a placeholder. Add
a new clause BEFORE that line, never after: a clause added after it is printed
in every refusal and enforced against nothing if it happens to contain
guillemets of its own. Renaming the heading, indenting the block, fencing it as
code, splitting it with a blank line, or adding a second blockquote anywhere in
the section all stop the extraction —
and the guard then allows every spawn unchecked, loudly, and fails this
branch's `/smith-preflight`. `smith-ctx-claude/scripts/tests/subagent-contract-guard.test.sh`
asserts the extracted text still contains both clauses, so run it after any
edit here; that assertion is the deliberate second copy, and it exists to make
a mis-edit fail loudly instead of silently narrowing what is enforced.

Every spawn the guard sees is also appended to a per-checkout, per-branch
ledger, so `/smith-preflight` reads what actually happened instead of attesting
it from a session history that `/clear` erases. A spawn allowed WITHOUT being
checked is recorded as such and fails that check rather than passing quietly.

## Returns: findings, not actions

- The deliverable is DATA the main thread can act on: paths, line numbers,
  quoted evidence, a verdict. Not a side effect already taken.
- A subagent that "helpfully" edits a PR, commits, or writes external content
  has exceeded its mandate — even if asked to investigate. Scope the prompt to
  forbid this when the risk exists.
- Verify-from-source applies to returns too: if a subagent asserts a label or
  mechanism, confirm against the actual file/doc before you rely on it (see
  @smith-guidance/SKILL.md Honest).
- For a delegated fix/diff, audit the execution path — trace that the change
  runs on the real failing input — not just its style or quality.
- Reviewers may legitimately DISAGREE, and a vote count ranks severity
  without settling truth: check a dissenting finding's evidence yourself
  before downgrading it. Where a tool sets a corroboration threshold
  (`@smith-gh-pr` sets one for `pr-review-toolkit`), read it as triage, not
  a verdict.

## Delivery: a written report is not a delivered one

- A BACKGROUND subagent's ordinary text output does NOT reach the main
  thread; only a `SendMessage` addressed to `main` does, and the tool scopes
  that address to background subagents alone. An agent that writes its
  findings and stops has delivered nothing. A synchronous subagent is the
  opposite — its final text IS the tool result — so this trap belongs to the
  default spawn mode, not to every spawn.
- Say so IN the spawn prompt — "reply via `SendMessage` to `main`; text
  output alone does not reach me" — rather than chasing a round trip later.
- Treat an idle notification as "ready to be asked", never as "clean".
  Silence is a missing signal, not a passing one (`@smith-guidance` close
  gaps).
- The `summary` on an idle notification goes STALE — it echoes the agent's
  last delivered report, so it can show a verdict already fixed. Re-read the
  message; never trust the summary line.

## Reconcile vs live state

- Between spawn and return, the world can change: a PR gets retitled, a file
  gets edited, a branch moves. The subagent's snapshot is already stale.
- Re-pointing a long-running reviewer at an amended commit is required, not
  optional: it reads the tree from when it started.
- Before mutating a shared artifact a subagent reported on, RE-READ its current
  state and merge — never overwrite from the subagent's snapshot.
- Incident this guards against: a subagent overwrote a PR title from a stale
  read, discarding an intervening change. Reconcile first, then write.

## Related

- @smith-guidance/SKILL.md - Delegation, in-band progress, verify-from-source
- @smith-ctx/SKILL.md - Context isolation: keep findings, discard the noise
- `@smith-ralph/SKILL.md` - Iterative orchestration patterns
- `@smith-skills/SKILL.md` - Subagents don't auto-load skills; pass rules inline
- `@smith-worktree/SKILL.md` - Isolate parallel file-mutating subagents
- `@smith-validation/SKILL.md` - Audit a delegated diff's execution path; adversarial verification of findings

## Before You Finish

**Before spawning:**
1. Pick ONE concern; grant read-only tools unless it is a named bounded edit
2. Inline the rules/conventions the task needs (no skill inheritance)
3. State the expected return shape; forbid side effects if risky

**On return:**
1. Treat it as a claim — re-read live state for anything it will mutate
2. Restate the key findings in your own message
3. Decide and act from the main thread; don't rubber-stamp the summary
4. Delegated fix? Audit the execution path (real input?), not just style
