---
name: smith-validation
description: Hypothesis testing, adversarial verification of findings, root cause analysis, and debugging techniques. Use when debugging, investigating any question whose answer you will report as fact, verifying whether a claim or finding is true, red-teaming a conclusion, testing hypotheses, validating solutions, proving correctness, or performing root cause analysis on failures.
---

# Verification Techniques

**Scope:** Hypothesis testing, root cause analysis, and adversarial verification of findings
**Load if:** Bug reported, test failure, proving correctness, root cause
analysis, OR any investigation whose findings will be reported as fact
**Prerequisites:** @smith-guidance/SKILL.md

**Foundation**: Based on PDSA's Study phase (Deming) and Popper's Falsification - understanding WHY something works or doesn't, not just IF it works.

**When to use**: Debugging, testing hypotheses, validating solutions, proving correctness, and verifying findings before reporting them.

## Hypothesis Testing

### Strong Inference

Rapid progress through multiple competing hypotheses:

1. **Devise multiple hypotheses** - Not just one, but several alternatives
2. **Design crucial experiments** - Tests that exclude one or more hypotheses
3. **Execute experiments** - Run tests to eliminate hypotheses
4. **Iterate** - Refine remaining hypotheses, repeat

**Key insight**: Science advances fastest when we actively try to disprove hypotheses, not confirm them.

**For debugging**:

- Bug: "Login fails intermittently"
- H1: Session storage full
- H2: Race condition in token refresh
- H3: Network timeout on auth server
- Crucial test: Check if failures correlate with session count (tests H1)

### Falsification Principle (Popper)

A theory is scientific only if it can be proven false:

- Design tests that could disprove your hypothesis
- Seek evidence that contradicts, not confirms
- One counterexample disproves a universal claim

**Anti-pattern**: Only running tests you expect to pass
**Good practice**: Actively try to break your own code

**Falsify a workaround before presenting it as the solution**: when proposing a fix or workaround that depends on external system behavior (MCP/OAuth/API/CLI/feature support), first search the issue tracker for known failures of that exact mechanism. Never present an untested mechanism in a confident voice — say "unverified — let me check" and check. (Triggered 2026-06: proposed two Slack-MCP OAuth setups as if they'd work; both failed; a 30-second search would have found the closed-as-not-planned regression that made the whole route impossible.)

## Adversarial Verification of Findings

The Falsification Principle above, applied to FINDINGS rather than to a
debugging hypothesis — for any investigation whose results will be reported as
fact: code, documents, external systems, history.

Two gates, not one. **Every** finding you report carries a locator. A
**skeptic pass** is only for findings that would cost something to get wrong:
one that contradicts a documented rule, one that drives an irreversible or
externally-visible action (a merge, push, deploy, ticket transition, message
send — reporting the finding itself is not one), or one you would not want to
be wrong about in front of whoever asked.

- **Name the disproof, then hunt it — for every finding you report.** Write
  down the specific observation that would kill the FINDING — the log line,
  file, or command output that, if it existed, would prove it wrong — then go
  looking for exactly that. It stays unproven until a search that should have
  surfaced the disproof comes back empty — not after a fixed number of passes.
- **Red-team what qualifies.** Hand a read-only skeptic subagent
  (`@smith-subagents` SKEPTIC role, contract pasted inline — subagents inherit
  no skills) the claim and the evidence WITHOUT the reasoning that produced
  them, so it cannot grade your argument; ask for a verdict of refuted /
  survived / insufficient evidence, plus the evidence that would have changed
  it. No skeptic available? Record "not run" and why, then conclude — never
  promote it silently.
- **Locator per claim.** Every claim carries a durable locator: a URL,
  `file:line`, commit, ticket, or a command whose output can be re-run —
  format per `@smith-research` Source Citation (external), `@smith-ctx`
  Information Retention (in-repo), `@smith-recon` (multi-source briefs). No
  locator means the claim is labelled unsourced, never asserted, and an
  unsourced claim is a gap to close before concluding (`@smith-guidance` close
  gaps).
- **Scale the machinery, not the floor.** A trivial lookup needs a locator, not
  a skeptic. Bias mechanics: `@smith-clarity` (Confirmation Bias, Premature
  Closure).

Source: Anthropic, "A harness for every task: dynamic workflows in Claude Code"
(https://claude.com/blog/a-harness-for-every-task-dynamic-workflows-in-claude-code,
retrieved 2026-07-28) — "For each spawned agent, run a separate spawned agent
to adversarially verify its output against a rubric or criteria", one of six
workflow patterns it lists. The post separately names self-preferential bias
("Claude's tendency to prefer its own results or findings, especially when
asked to verify or judge them against a rubric") among three failure modes that
isolated subagents combat. Aiming this pattern at that bias, and at your own
findings, is our application — not a claim the post makes.

## Deviation Is Not Discovery

The failure this guards: a recorded decision gets violated unnoticed by a
later session, which then narrates the consequences as a dramatic new finding
("verdict overturned", "assumption disproven") — and the rewrite propagates
through checkpoints. No internal trigger catches this; the read below is
unconditional, not fired by suspicion.

- Before interpreting ANY surprising or anomalous result, read the topic's
  recorded memory/decision set FIRST — especially when your current
  explanation feels coherent.
- If a recorded decision covers the situation and was violated, report
  **"I deviated from the recorded protocol"** — never "we discovered" /
  "the verdict is overturned". Wrong-input or wrong-protocol runs are
  **void measurements**: they support no claim about the system under test.
- Tripwire words in your own draft that MANDATE the read before publishing:
  "overturned", "exonerated", "contrary to what we thought", "it turns out
  the assumption was false", 「翻案」「平反」.
- A later checkpoint QUOTES the earlier recorded decision it builds on; it
  never paraphrases it into a new story.
- **Checkpoint hygiene**: writing a checkpoint triggers an artifact census —
  enumerate EVERY file the session created outside the repo (temp dirs,
  `/tmp`, `~/Downloads`) and record each path or move it somewhere durable;
  no importance judgment (judging "which matter" is the part that fails).
  A checkpoint may claim "persisted to X" only with a same-turn directory
  listing of X quoted; without it the claim is fiction. Known gap: a session
  that ends abruptly without a checkpoint remains exposed — a Stop/PreCompact
  hook that scans the transcript for writes under volatile prefixes and lists
  them before exit would close it; until then, checkpoint early when
  artifacts accumulate.
- **An empty search result is not evidence without a control.** Empty is
  ambiguous between "absent" and "query broken"; the only discriminator is a
  control query known to return hits through the same pipeline. A negative
  reported without one is a claim about your query, not about the world.
- **A queued decision carries its full payload**: the concrete proposal, why
  it was raised, and what "yes" would change — recorded alongside. Can't
  write those down → not ready to queue.
- **Re-derive presented aggregates**: a count or "N open items" is a DERIVED
  value — re-run the enumeration against the primary source in the session
  that presents it; the cached value is only a checksum, and a mismatch is a
  finding, never silently papered over.
- **Re-derive every re-presented option from current state**: an option that
  only made sense under conditions that no longer hold must be withdrawn by
  you, not left for the user to shoot down.
- **Check every conjunct of the requirement AS STATED BY ITS AUTHOR** — not
  as reworded by your progress report. One unmet conjunct → the requirement
  is open. Watch the substitution tell: renaming the requirement after the
  part your last action satisfied. A snapshot is not version control:
  ongoing edit-work needs history, not a one-time copy of its start state.
- **Every proposed action traces to an open requirement.** After a
  correction, re-derive from scratch — "we were in the middle of doing this"
  is not a requirement; if the motivating question is answered, the
  follow-up dissolved with it. Fabricated work manufactures real risks.

## Bugfix Discipline: Trace the Real Path, Reproduce First

**Before writing ANY bugfix:**
1. **Trace the real execution path** — from the failing input, follow the
   source to the EXACT branch that input actually takes. Read the code;
   follow the return/artifact types. A symptom (error string, stack frame)
   names a place, not the branch. Don't pattern-match a fix (often "reuse
   this existing helper") from the symptom alone. Never assume the error
   path — the input may take a *success* branch instead (e.g. a function
   returns an empty *success* artifact, not an error).
2. **Reproduce with the real input** — run the actual failing case and observe
   the failure before touching code. Static reading is a hypothesis, not a
   diagnosis.
3. **Put the fix on the branch the real input hits** — confirm by re-running
   the repro that it now passes.

**The test-masking trap** (2026-06): a fix placed in a branch the real
input never enters, paired with a unit test that *mocks an input* to force that
branch → green test, live bug. The test fit the fix instead of reproducing the
bug. Guard both ends: `@smith-tests/SKILL.md` (never mock the branch/unit under
test; reproduce the bug as a failing test first) and `@smith-subagents/SKILL.md`
(audit the execution path of a delegated diff, not just its style).

## Anti-Workaround Policy

- Only add `# noqa`, `// NOLINT`, or similar inline suppressions when the
  exception criteria below are met
- Only increase timeouts after diagnosing root cause
- Remove the actual dead code rather than merely using a `_` prefix to
  suppress unused-variable warnings
- Only disable warnings with documented justification

**When lint or test failures occur:**
1. Apply 5 Whys to find root cause first
2. Fix the underlying issue, not the symptom
3. Suppressions allowed ONLY when all criteria are met:
   - **Reason** (at least one):
     - External library false positive (document which)
     - Verified false positive (document why)
     - Explicit user approval (cite the approval)
   - **Mechanism**: prefer tool config (ruff.toml, .flake8)
     for repo-wide patterns; inline comments only for
     isolated cases with reason on the same line

**Timeout changes require:**
- Profiling evidence showing actual duration
- Diagnosis of why the operation is slow
- User approval before increasing

## Root Cause Analysis

### 5 Whys (Toyota)

Root cause analysis through iterative questioning:

1. State the problem
2. Ask "Why did this happen?"
3. Repeat for each answer (typically 5 times)
4. Stop when you reach an actionable root cause

**Example**:

- Bug: Users logged out unexpectedly
- Why? Session expired
- Why? Token refresh failed
- Why? Refresh endpoint returned 401
- Why? Clock skew between servers
- Root cause: NTP not configured on auth server

**Caution**: Don't stop at symptoms. "Why?" should reach systemic causes.

## Explanation Techniques

### Rubber Duck Debugging

Explain code line-by-line aloud; when explanation doesn't match code, you've found the bug.

**For AI agents**: When stuck, explain the problem step-by-step before proposing solutions.

### Feynman Technique

Explain simply to reveal gaps: Choose concept → Explain to child → Identify gaps → Review.

If you can't explain it simply, you don't understand it well enough.

## Systematic Isolation

### Delta Debugging

Minimize failing input: split in half, test each, recurse on failing half until minimal.

**Use when**: Large input crashes, many files break tests, config changes fail.

### Scientific Debugging (TRAFFIC)

**T**rack → **R**eproduce → **A**utomate → **F**ind origins → **F**ocus → **I**solate → **C**orrect

Work backward: Failure → Propagation → Infection → Defect.

## Version Control Debugging

### Git Bisect

Binary search through commit history:

**Usage**:

```shell
git bisect start
git bisect bad
git bisect good abc1234
git bisect good
git bisect reset
```

Mark current as bad, known-good commit, then test each checkout (good/bad) until culprit found.

**Automated**:

```shell
git bisect run ./test.sh
```

Exit codes: 0 = good, 1-127 = bad, 125 = skip

**Complexity**: O(log n) - tests ~7 commits for 100 commit range

**When to use**:

- Regression appeared, unknown when
- Automated test can detect the bug
- Need to find exact commit that broke something

## Coverage-Based Localization

### Spectrum-Based Fault Localization (SBFL)

Use test coverage data to locate bugs:

**Concept**: Statements executed by failing tests but not passing tests are more suspicious.

**Ochiai Formula** (most effective):

```text
suspiciousness(s) = failed(s) / sqrt(total_failed * (failed(s) + passed(s)))
```

**Practical application**:

1. Run test suite with coverage
2. Note which tests fail
3. Rank statements by how often they appear in failing vs passing tests
4. Inspect highest-ranked statements first

**For AI agents**: When multiple tests fail, identify code paths common to failures but not successes.

## Before You Finish

**When debugging or validating:**
1. Use Strong Inference: devise multiple hypotheses before testing
2. Apply 5 Whys to find root cause, not symptoms
3. Use Git Bisect for regressions (binary search ~7 commits for 100-commit range)
4. Run tests with coverage; inspect code paths common to failures
5. Bugfix? Trace to the real branch and reproduce real input BEFORE fixing
6. Surprising result? Check the topic's recorded decisions FIRST — deviation
   is reported as deviation, not discovery
7. Checkpoint written? Artifact census done; every "persisted" claim carries
   its same-turn listing

## Claude Code Plugin Integration

**When pr-review-toolkit is available:**

- **silent-failure-hunter agent**: Detects silent failures, inadequate error handling
- Analyzes catch blocks, fallback behavior, missing logging
- Trigger: "Check for silent failures" or use Task tool

## Ralph Loop Integration

**Debugging = Ralph iteration**: hypothesis → test → eliminate → iterate until `<promise>ROOT CAUSE FOUND</promise>`.

See `@smith-ralph/SKILL.md` for full patterns.

## Related

- @smith-guidance/SKILL.md - Anti-sycophancy, HHH framework, exploration workflow
- `@smith-analysis/SKILL.md` - Reasoning patterns, problem decomposition
- `@smith-clarity/SKILL.md` - Cognitive guards, logic fallacies, confirmation bias, premature closure
- `@smith-tests/SKILL.md` - Reproduce-first; never mock the branch under test
- `@smith-subagents/SKILL.md` - Audit a delegated diff's execution path; read-only skeptic role
- `@smith-research/SKILL.md` - Source-citation format for evidence per claim
- `@smith-recon/SKILL.md` - Multi-source briefs, cross-verification
