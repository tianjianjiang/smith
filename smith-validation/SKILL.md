---
name: smith-validation
description: Hypothesis testing, root cause analysis, and debugging techniques. Use when debugging, testing hypotheses, validating solutions, proving correctness, or performing root cause analysis on failures.
---

# Verification Techniques

<metadata>

- **Scope**: Hypothesis testing, root cause analysis, and verification
- **Load if**: Bug reported, test failure, proving correctness, root cause analysis
- **Prerequisites**: @smith-guidance/SKILL.md

</metadata>

<context>

**Foundation**: Based on PDSA's Study phase (Deming) and Popper's Falsification - understanding WHY something works or doesn't, not just IF it works.

**When to use**: Debugging, testing hypotheses, validating solutions, proving correctness.

</context>

## Hypothesis Testing

<context>

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

</context>

## Root Cause Analysis

<context>

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

</context>

## Explanation Techniques

<context>

### Rubber Duck Debugging

Explain code line-by-line aloud; when explanation doesn't match code, you've found the bug.

**For AI agents**: When stuck, explain the problem step-by-step before proposing solutions.

### Feynman Technique

Explain simply to reveal gaps: Choose concept → Explain to child → Identify gaps → Review.

If you can't explain it simply, you don't understand it well enough.

</context>

## Systematic Isolation

<context>

### Delta Debugging

Minimize failing input: split in half, test each, recurse on failing half until minimal.

**Use when**: Large input crashes, many files break tests, config changes fail.

### Scientific Debugging (TRAFFIC)

**T**rack → **R**eproduce → **A**utomate → **F**ind origins → **F**ocus → **I**solate → **C**orrect

Work backward: Failure → Propagation → Infection → Defect.

</context>

## Version Control Debugging

<context>

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

</context>

## Coverage-Based Localization

<context>

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

</context>

## ACTION (Recency Zone)

<required>

**When debugging or validating:**
1. Use Strong Inference: devise multiple hypotheses before testing
2. Apply 5 Whys to find root cause, not symptoms
3. Use Git Bisect for regressions (binary search ~7 commits for 100-commit range)
4. Run tests with coverage; inspect code paths common to failures

</required>

## Claude Code Plugin Integration

<context>

**When pr-review-toolkit is available:**

- **silent-failure-hunter agent**: Detects silent failures, inadequate error handling
- Analyzes catch blocks, fallback behavior, missing logging
- Trigger: "Check for silent failures" or use Task tool

</context>

## Ralph Loop Integration

<context>

**Debugging = Ralph iteration**: hypothesis → test → eliminate → iterate until `<promise>ROOT CAUSE FOUND</promise>`.

See `@smith-ralph/SKILL.md` for full patterns.

</context>

<related>

- @smith-guidance/SKILL.md - Anti-sycophancy, HHH framework, exploration workflow
- `@smith-analysis/SKILL.md` - Reasoning patterns, problem decomposition
- `@smith-clarity/SKILL.md` - Cognitive guards, logic fallacies

</related>
