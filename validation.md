# Verification Techniques

<metadata>

- **Scope**: Hypothesis testing, root cause analysis, and verification
- **Load if**: Bug reported, test failure, proving correctness, root cause analysis
- **Prerequisites**: @steering.md

</metadata>

<context>

**Foundation**: Based on PDSA's Study phase (Deming) and Popper's Falsification - understanding WHY something works or doesn't, not just IF it works.

**When to use**: Debugging, testing hypotheses, validating solutions, proving correctness.

</context>

## Hypothesis Testing

<required>

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

</required>

## Root Cause Analysis

<required>

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

</required>

## Explanation Techniques

<required>

### Rubber Duck Debugging

Explain code line-by-line to reveal errors (from "The Pragmatic Programmer"):

1. Place rubber duck (or equivalent) on desk
2. Explain what code should do, line by line
3. When explanation doesn't match code, you've found the bug

**Why it works**: Forcing verbalization engages different cognitive processes than reading.

**For AI agents**: When stuck, explain the problem step-by-step before proposing solutions.

### Feynman Technique

Explain simply to reveal understanding gaps:

1. **Choose concept** - What are you trying to understand?
2. **Explain to a child** - Use simple words, no jargon
3. **Identify gaps** - Where did explanation break down?
4. **Review and simplify** - Return to source, fill gaps, repeat

**For coding**: If you can't explain your solution simply, you don't understand it well enough.

</required>

## Systematic Isolation

<required>

### Delta Debugging

Systematically minimize failing input to isolate cause:

**Algorithm**:

1. Start with failing input of size n
2. Split into halves, test each half
3. If half fails alone, recurse on that half
4. If neither fails alone, increase granularity
5. Continue until minimal failing input found

**Complexity**: O(n log n) best case, O(n^2) worst case

**For debugging**:

- Large input causes crash: Find minimal reproducer
- Many changed files break tests: Find minimal set
- Config change causes failure: Find minimal diff

**Example**:

- Initial: 1000-line input crashes
- Test lines 1-500: passes
- Test lines 501-1000: fails
- Test lines 501-750: passes
- Test lines 751-1000: fails
- Continue until single line identified

### Scientific Debugging

Apply scientific method systematically:

**TRAFFIC Principle**:

1. **T**rack the problem (reproduce reliably)
2. **R**eproduce automatically (create test case)
3. **A**utomate and simplify (minimize reproducer)
4. **F**ind origins (locate infection chain)
5. **F**ocus on likely causes (domain knowledge)
6. **I**solate the infection chain (delta debugging)
7. **C**orrect the defect (fix root cause)

**Infection Chain Model**:

```text
Defect -> Infection -> Propagation -> Failure
(code)    (bad state)   (spreads)     (visible)
```

Work backward from failure to find defect.

**Hypothesis-Driven Workflow**:

1. Observe failure behavior
2. Hypothesize potential cause
3. Predict what would confirm/refute
4. Experiment to test prediction
5. Conclude and iterate

</required>

## Version Control Debugging

<required>

### Git Bisect

Binary search through commit history:

**Usage**:

```sh
git bisect start
git bisect bad                 # Current commit broken
git bisect good abc1234        # Known good commit
# Git checks out middle, you test
git bisect good  # or bad
# Repeat until culprit found
git bisect reset
```

**Automated**:

```sh
git bisect run ./test.sh
# Exit 0 = good, 1-127 = bad, 125 = skip
```

**Complexity**: O(log n) - tests ~7 commits for 100 commit range

**When to use**:

- Regression appeared, unknown when
- Automated test can detect the bug
- Need to find exact commit that broke something

</required>

## Coverage-Based Localization

<required>

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

</required>

<related>

**Research:**

- Popper, K. (1934). The Logic of Scientific Discovery (Falsification)
- Deming, W.E. PDSA Cycle (Plan-Do-Study-Act)
- Platt, J. R. (1964). Strong inference. Science, 146(3642)
- Zeller, A. (2009). Why Programs Fail: A Guide to Systematic Debugging

**Related files:**

- @steering.md - Questioning techniques
- @reasoning.md - Reasoning patterns, problem decomposition
- @clarity.md - Cognitive guards, logic fallacies

</related>
