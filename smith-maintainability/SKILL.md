---
name: smith-maintainability
description: Shared rules for deterministic maintainability signals; its members so far measure rework. Use when choosing, placing or reading a code-quality signal, or when setting a repository's quality bar.
---

# Maintainability Signals

**Scope:** What every `smith-maintainability-*` member shares: evidence
levels, size, blocking versus warning, placement and baselines
**Prerequisites:** @smith-principles/SKILL.md

## Critical Rules

- Treat every signal as a heuristic that orders attention, never as a
  quality grade; a team made to keep a number under a limit finds the
  cheapest way to do it
- Read every signal next to the size of what it measures: size confounds
  code metrics, and in one comparative case study size was among the few
  measures tied to maintenance effort
- Block only on a stable per-function threshold the agent can meet by
  changing its own code; a signal that depends on history or on other
  files warns
- Hold today's level instead of inventing a target: record existing
  violations as a baseline, block only what is new or worse, and never
  relax a threshold to make a change pass
- Keep thresholds, reasons and commands in the member skill; keep a
  repository's measured baseline and its exceptions in that repository

## Evidence Levels

- **Process (strongest):** relative churn predicts defect density and
  absolute churn does not (Nagappan and Ball, International Conference
  on Software Engineering (ICSE) 2005,
  https://doi.org/10.1109/icse.2005.1553571); process metrics beat code
  metrics (Rahman and Devanbu, ICSE 2013,
  https://doi.org/10.1109/ICSE.2013.6606589)
- **Clones:** inconsistent changes to clones are frequent and induce a
  significant number of faults (Juergens et al., ICSE 2009,
  https://doi.org/10.1109/ICSE.2009.5070547)
- **Cognitive complexity:** correlates with comprehension time and rated
  understandability, mixed on correctness (Muñoz Barón et al., Empirical
  Software Engineering and Measurement (ESEM) 2020,
  https://doi.org/10.1145/3382494.3410636)
- **Coverage and mutation:** both weaken once suite size is controlled
  (Inozemtseva and Holmes, ICSE 2014,
  https://doi.org/10.1145/2568225.2568271; Papadakis et al., ICSE 2018,
  https://doi.org/10.1145/3180155.3180183)
- **Size confounds metrics:** El Emam et al., IEEE Transactions on
  Software Engineering 2001,
  https://doi.org/10.1109/32.935855; in a case study of four systems only
  size and low cohesion were strongly tied to maintenance effort
  (Sjøberg et al., ESEM 2012, https://doi.org/10.1145/2372251.2372269)
- **No peer-reviewed validation found:** CRAP (Change Risk Anti-Patterns,
  first named Change Risk Analysis and Prediction), per its PHPUnit
  maintainer (https://phpunit.expert/articles/nineteen-years-of-crap.html);
  the erosion and verbosity scores of SlopCodeBench, a benchmark of coding
  agents extending their own code, published as an arXiv preprint
  (https://arxiv.org/abs/2603.24755); the default thresholds of pylint,
  the Python linter
  (https://pylint.readthedocs.io/en/stable/user_guide/configuration/all-options.html)

## Placement by Cost

- Cost decides where a check runs, not whether it is a quality dimension
- After every edit: checks that finish within about 5 seconds on the
  changed file
- At task end: checks that finish within about 90 seconds
- Periodically: anything slower, such as a full test suite
- Both budgets come from the constraint-driven-development skill in
  Addy Osmani's agent-skills collection
  (https://github.com/addyosmani/agent-skills): 90 seconds is its
  default, 5 seconds its build-phase budget, both stated without a source;
  measure each check on the repository before placing it

## Members

- `@smith-maintainability-rework/SKILL.md` - Share of commits a later fix
  rewrites; the outcome every other signal is judged against

## Related

- @smith-principles/SKILL.md - MECE and Occam's razor behind the evidence levels
  and the choice of members
- `@smith-sdlc/SKILL.md` - the control bands of "Stage 6: Maintain" watch
  one such metric
- `@smith-tests/SKILL.md` - Test-first work that coverage measures

## Before You Finish

- Each signal used names its evidence level and its source
- Each number sits next to the size it was measured on
- Blocking checks are per-function and stable; history-based ones warn
- Baselines and exceptions live in the repository, not in this skill
