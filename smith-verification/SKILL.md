---
name: smith-verification
description: Hypothesis testing and root cause analysis. Use when debugging, when a bug or test failure is reported, or when verifying a claim before reporting it as fact.
---

# Verification

**Scope:** Hypothesis testing, root cause analysis, and adversarial
verification of findings: does the work meet its stated specification, and
are its claims supported
**Prerequisites:** @smith-guidance/SKILL.md

## Where the Techniques Live

This skill is the name every caller uses for verification. Its technique
bodies still live in `@smith-validation/SKILL.md`: invoke `smith-validation`
with the Skill tool and apply the section named below. A reference written
as "`@smith-verification` «section»" means that section there.

- **Hypothesis Testing** - Strong Inference with several competing
  hypotheses; the Falsification Principle, including "falsify a workaround
  before presenting it as the solution"
- **Adversarial Verification of Findings** - name the disproof and hunt
  it, a skeptic subagent for costly findings, a locator per claim
- **Deviation Is Not Discovery** - read the recorded decisions before
  explaining a surprise; checkpoint hygiene; "a missing signal is never a
  passing one"; re-derive aggregates and options; check every conjunct of
  a requirement as its author stated it
- **Bugfix Discipline** - trace the real path, reproduce first, the
  test-masking trap, fix where the bad state is made
- **Anti-Workaround Policy** - suppression and timeout criteria
- **Root Cause Analysis** - 5 Whys
- **Advanced Techniques** - `smith-validation/references/TECHNIQUES.md`:
  Rubber Duck, Feynman, Delta Debugging,
  TRAFFIC (Track, Reproduce, Automate, Find origins, Focus, Isolate, Correct),
  Git Bisect, SBFL (spectrum-based fault localization)
- **Claude Code Plugin Integration** and **Ralph Loop Integration**

## Related

- @smith-guidance/SKILL.md - Close gaps; a missing signal never passes
- `@smith-validation/SKILL.md` - The technique bodies listed above
- `@smith-clarity/SKILL.md` - Confirmation bias, premature closure
- `@smith-subagents/SKILL.md` - Read-only skeptic role, blind evaluator

## Before You Finish

- Invoked `smith-validation` and applied the section the task needs
- Followed its own "Before You Finish" list
