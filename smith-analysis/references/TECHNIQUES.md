# Verification Techniques Reference

Detailed debugging and analysis techniques. Core disciplines are in `SKILL.md`.

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
