---
name: smith-analysis
description: Reasoning frameworks, problem decomposition and cause finding. Use when planning an implementation, estimating scope, breaking down a complex task, assessing risk, debugging, or when a bug or test failure is reported.
metadata:
  smith-question: analysis
---

# Reasoning Frameworks

**Scope:** Reasoning, problem decomposition, cause finding, and analysis techniques
**Prerequisites:** @smith-guidance/SKILL.md

**Foundation**: Based on OODA Loop's Orient phase (Boyd) - the "cognitive engine" that drives decision-making through mental models, prior experience, and analysis/synthesis.

**When to use**: Problem framing, solution design, risk assessment, logical validation.

**MECE relationship**:
- **smith-analysis** (this file) - Constructive thinking (how to reason)
- `@smith-clarity/SKILL.md` - Defensive thinking (what to avoid)
- `@smith-verification/SKILL.md` - Proving/testing (verifying correctness)

<a name="reasoning-patterns-v1"></a>
## Reasoning Patterns

### Deductive Reasoning

General principles to specific conclusions (logically certain):

**Pattern**: If all A are B, and C is A, then C is B.

1. Start with general premise (known to be true)
2. Apply to specific case
3. Derive guaranteed conclusion

### Inductive Reasoning

Specific observations to general patterns (probabilistic):

**Pattern**: Observed A1, A2, A3... all have property B. Therefore all A probably have B.

1. Gather specific observations
2. Identify patterns
3. Form general hypothesis (may be wrong)

**Caution**: Inductive conclusions can be wrong.

### Abductive Reasoning

Best explanation from incomplete observations (inference to best explanation):

**Pattern**: B is observed. A would explain B. Therefore A is probably true.

1. Observe surprising/unexpected result
2. Generate candidate explanations
3. Select most plausible explanation
4. Test to confirm or falsify

<a name="hypothesis-testing-v1"></a>
## Hypothesis Testing

**Foundation**: Based on the Study phase of Deming's Plan-Do-Study-Act (PDSA) cycle and Popper's Falsification - understanding WHY something works or doesn't, not just IF it works.

### Strong Inference

Rapid progress through multiple competing hypotheses:

1. **Devise multiple hypotheses** - Not just one, but several alternatives
2. **Design crucial experiments** - Tests that exclude one or more hypotheses
3. **Execute experiments** - Run tests to eliminate hypotheses
4. **Iterate** - Refine remaining hypotheses, repeat

**Key insight**: Science advances fastest by actively trying to disprove hypotheses, not confirm them.

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

**Falsify a workaround before presenting it as the solution**: when proposing a fix or workaround that depends on external system behavior (MCP/OAuth/API/CLI/feature support), first search the issue tracker for known failures of that exact mechanism. Never present an untested mechanism in a confident voice — say "unverified — checking now" and check.

<a name="root-cause-analysis-v1"></a>
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

### Current Reality Tree (CRT)

Trace symptoms to root cause:

1. List Undesirable Effects (UDEs) - symptoms observed
2. Connect with "if...then" cause-effect logic
3. Trace backward to find common root cause
4. Validate: Does root cause explain ALL symptoms?

<a name="bugfix-discipline-v1"></a>
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

**The test-masking trap**: a fix placed in a branch the real
input never enters, paired with a unit test that *mocks an input* to force that
branch → green test, live bug. The test fit the fix instead of reproducing the
bug. Guard both ends: `@smith-tests/SKILL.md` (never mock the branch/unit under
test; reproduce the bug as a failing test first) and `@smith-subagents/SKILL.md`
(audit the execution path of a delegated diff, not just its style).

**Fix where the bad state is made, not where it is read.** When a
consumer receives bad, duplicated or inconsistent input, carry the step 1
trace back to the producer that created it, ask why it did, and put the
step 3 fix there. Teaching the consumer to tolerate the input gives it
decisions it never had to make, and each one is a new way to fail.
Tolerate in the consumer only when the producer is outside your control,
and say so. A sign you are at the wrong end: every review round finds a
new edge case in your fix.

<a name="anti-workaround-policy-v1"></a>
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

<a name="advanced-techniques-v1"></a>
## Advanced Techniques

See `references/TECHNIQUES.md` for:
- Explanation techniques (Rubber Duck, Feynman)
- Systematic isolation: Delta Debugging and
  TRAFFIC (Track, Reproduce, Automate, Find origins, Focus, Isolate, Correct)
- Version control debugging (Git Bisect)
- Coverage-based localization (SBFL, spectrum-based fault localization)

<a name="problem-decomposition-v1"></a>
## Problem Decomposition

### First Principles Thinking

Break down to fundamentals, reason up:

1. **Identify assumptions** - What is taken for granted?
2. **Decompose** - What are the fundamental truths?
3. **Reconstruct** - Build solution from first principles only

### Polya's 4-Step Method

Universally applicable problem-solving:

1. **Understand the problem**
   - What is the unknown? What are the data? What is the condition?
   - Can you restate in your own words?

2. **Devise a plan**
   - Have you seen this before? Know a related problem?
   - Can you solve a simpler problem first?

3. **Carry out the plan**
   - Execute each step, check as you go
   - Can you prove each step correct?

4. **Look back**
   - Can you check the result differently?
   - Can you use this for other problems?

<a name="estimation-v1"></a>
## Estimation

### Fermi Estimation

Order-of-magnitude approximation with limited data:

1. Break complex question into simpler sub-questions
2. Make reasonable assumptions for each part
3. Combine estimates (multiply/add as appropriate)
4. Sanity check: Is result reasonable?

<a name="constraint-thinking-v1"></a>
## Constraint Thinking

### TOC Five Focusing Steps

Systematic bottleneck elimination (Goldratt):

1. **Identify** - Find the constraint limiting throughput
2. **Exploit** - Maximize constraint output without additional investment
3. **Subordinate** - Align everything else to support the constraint
4. **Elevate** - Increase constraint capacity if still limiting
5. **Repeat** - Find the new constraint (it will shift)

### Three-Point Estimation (PERT)

Handle uncertainty with optimistic, likely, pessimistic:

- **O**: Best case (everything goes right)
- **M**: Most likely (typical scenario)
- **P**: Pessimistic (realistic worst case)
- **Expected**: (O + 4M + P) / 6

<a name="risk-assessment-v1"></a>
## Risk Assessment

### Pre-Mortem Analysis

Before implementation, imagine failure has occurred:

1. **Assume failure** - "The project failed. Why?"
2. **Generate causes** - List reasons independently
3. **Categorize** - Group failure modes
4. **Mitigate** - Address highest-risk items in plan

Increases problem identification by 30%.

### Inversion Thinking

Think backward to avoid failure:

- Instead of "How can this succeed?" ask "How could this fail?"
- Instead of "How to make this fast?" ask "What would make this slow?"
- Avoid stupidity rather than seeking brilliance

Inversion and pre-mortem stress-test a PLAN. To adversarially verify FINDINGS
already in hand, see `@smith-verification/SKILL.md#adversarial-verification-v1`.

<a name="comprehensive-review-v1"></a>
## Comprehensive Review

### Six Thinking Hats

Ensure coverage by examining from 6 perspectives:

- **White** (Facts): What data/evidence is available?
- **Red** (Intuition): What do unmeasured signals suggest? Any concerns?
- **Black** (Caution): What could go wrong? What are the risks?
- **Yellow** (Optimism): What are the benefits? Best case?
- **Green** (Creativity): What alternatives exist? New approaches?
- **Blue** (Process): Is the work on track? What's the next step?

<a name="ralph-loop-v1"></a>
## Ralph Loop Integration

**Debugging = Ralph iteration**: hypothesis → test → eliminate → iterate until `<promise>ROOT CAUSE FOUND</promise>`.

See `@smith-ralph/SKILL.md` for full patterns.

<a name="before-you-finish-v1"></a>
## Before You Finish

**When reasoning or planning:**
1. Use First Principles to break down complex problems
2. Apply Polya's 4-Step Method for systematic problem-solving
3. Use Pre-Mortem Analysis before implementation
4. Apply Six Thinking Hats for comprehensive review

**When debugging:**
1. Use Strong Inference: devise multiple hypotheses before testing
2. Apply 5 Whys to find root cause, not symptoms
3. Use Git Bisect for regressions (binary search ~7 commits for 100-commit range)
4. Run tests with coverage; inspect code paths common to failures
5. Bugfix? Trace to the real branch and reproduce real input BEFORE fixing

<a name="related-v1"></a>
## Related

- @smith-guidance/SKILL.md - Anti-sycophancy, safety rules, making changes
- `@smith-clarity/SKILL.md` - Cognitive guards, logic fallacies
- `@smith-verification/SKILL.md#adversarial-verification-v1` - Adversarial verification of findings
- `@smith-tests/SKILL.md` - Reproduce-first; never mock the branch under test
- `@smith-subagents/SKILL.md` - Audit a delegated diff's execution path
