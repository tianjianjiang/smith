---
name: smith-maintainability-rework
description: Rework census, the share of commits whose added lines a later fix rewrites (the SZZ algorithm of Śliwerski, Zimmermann and Zeller). Use when measuring whether quality measures cut fix-ups, setting a repository's rework baseline, or tracking rework as a control-band metric.
---

# Rework Census

**Scope:** Measuring rework from git history with the SZZ algorithm;
not a DORA (DevOps Research and Assessment) delivery metric
**Prerequisites:** `@smith-maintainability/SKILL.md`

## Definition

Rework here is the share of commits whose added lines a later fix
rewrites (SZZ, Śliwerski et al. 2005), not DORA's deployment rework rate.

- SZZ: for each fix commit, blame the lines the fix removed or changed in
  its parent; the commits that last touched those lines are
  fix-inducing (Śliwerski, Zimmermann and Zeller, "When do changes induce
  fixes?", Mining Software Repositories workshop 2005,
  https://doi.org/10.1145/1083142.1083147)
- A file the fix renames is followed to its path in the parent, so only
  its changed lines are blamed
- This is an SZZ variant: it finds fixes by commit subject instead of
  issue-tracker links, and applies no bug-report date filter, so its
  numbers are not comparable with published SZZ results
- DORA defines its deployment rework rate over unplanned deployments,
  which a repository without deployments cannot measure
  (https://dora.dev/guides/dora-metrics/history/)

## Critical Rules

- Measure rework before adding any other signal: it is the outcome the
  other `smith-maintainability-*` members are judged against
- Report it descriptively; compare equal-length windows of the same
  repository, never two repositories
- Leave out the newest commits when comparing windows: a commit counts as
  fix-inducing only after a fix arrives, so recent commits look clean
- Report `unattributableFixes` and `introducersOutsideRange` beside the
  share: SZZ cannot link a fix that changes no counted line, and a narrow
  `--range` drops the commits that introduced a fix's lines

## Running the Census

Run it from any repository; the script ships with the skill:

```shell
SKILLS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
node "$SKILLS/smith-maintainability-rework/scripts/rework-census.mjs" \
  --ext .py
```

- `--repo`: the repository to read, or any directory inside it (default
  `.`); only read-only git commands run, with git configuration that
  changes their output overridden; a partial clone missing objects fails
  instead of fetching them, which needs git 2.45 or later
- `--range`: the window of candidate commits, one revision-range argument
  for `git log` (default `HEAD`), e.g. `main..feat/x` or `«sha»..HEAD`
- `--fixes-through`: the revision whose history is scanned for fixes
  (default `HEAD`), so a fix that lands after the window still counts;
  set it the same distance after each window compared
- `--ext`: count only paths ending this way, both for added lines and for
  the lines a fix changes; repeat it for several; without it every file
  counts
- `--fix-pattern`: the regular expression a fix commit's subject matches;
  default `^fix(\([^)]*\))?!?:`, case-sensitive

## Reading the Output

- `range`, `fixesThrough`, `extensions`, `fixPattern`: the options the
  run used
- `commits`: non-merge commits in `--range`
- `candidates`: those commits that added text lines in the counted files;
  a file a commit only renames adds none
- `fixes`: non-merge, non-root commits up to `--fixes-through` whose
  subject matches the fix pattern, whatever files they touch
- `unattributableFixes`: fixes that change no line in the counted files,
  such as a fix that only adds lines or touches only other files
- `introducersOutsideRange`: commits a fix's changed lines blame to
  that are not candidates, such as commits outside `--range` or merge
  commits inside it; they are not counted in `share`
- `fixInducing`: candidates a later fix rewrote, each with `sha`,
  `subject` and `fixedBy`
- `share`: the number of `fixInducing` commits divided by `candidates`;
  `null` when there are no candidates
- Known SZZ bias: a fix that also reformats or moves lines blames the
  commits that wrote them, so `share` overstates rework

## Related

- `@smith-maintainability/SKILL.md` - Evidence levels and placement rules
  this member follows
- `@smith-sdlc/SKILL.md` - the control bands of "Stage 6: Maintain" can
  watch `share`

## Before You Finish

- The census ran on the same `--ext` and `--fix-pattern`, and an equal
  `--fixes-through` distance, for every window compared
- `share` is reported with `candidates`, `fixes`, `unattributableFixes`
  and `introducersOutsideRange`
- The newest commits are left out of any window comparison
