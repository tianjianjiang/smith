# Intent: select tests by path, not by inference

Author: repository owner. Status: proposed on 2026-11-24.

## Problem

The selector `smith-ctx-claude/scripts/tests/select.mjs`, 669 lines, finds
the tests a change reaches by reading shell and JavaScript source text with
regular expressions: `$(dirname "$0")`, `source`, `node "$HOOK"`, import
specifiers. Shell can build a path at run time, from variables, sourced
files, `eval` or an awk program, so text alone cannot settle which files a
test reads. Every fix to the scan meets a new form: in
https://github.com/tianjianjiang/smith/pull/394, read on 2026-11-24,
earlier drafts that recognised here-documents, strings and continuations
were dropped because reviewers found forms each one missed. Still open: double quotes counted per
line at `select.mjs:203-206`, and awk `$0` inside single quotes. A wrong
widening only slows a run; a wrong narrowing skips a test that the change
affects, with no signal.

The tests never declare what they read, which is why the selector infers
it. The only declarations are the 6 entries of
`smith-ctx-claude/scripts/tests/hidden-reads.json`.

Selection also cannot make a run fast on its own. Measured on 3551966 with
the 67 tests of 9 tests folders, 10 parallel jobs, 5 rounds, all passing:
a full run took a mean of 369 s, a median of 367 s and a 90th percentile of
376 s. The longest test, `set-aside.test.sh`, took a median of 253 s
while the others ran beside it, and the 10 slowest tests held 59% of summed
test time. Its time alone is not measured, so a selection that includes it
may stay near 253 s, about 69% of a full run's median.
Kernel time exceeded user time in a full run on b59c5d7, 366 s against
223 s, which points at the cost of starting a process for each case; this
is inferred, not measured per test.

## Proposed outcome

- Paths are the only declaration of which tests a change selects. A test
  at the mirrored path of its subject, as
  `docs/test-tooling/layout/spec.md` §tooling-outside-tests requires,
  names by its path its subject and its owner, the skill folder that holds
  the subject, as `tests/«owner»/…` in that section. Code that more than
  one owner uses sits at a path that marks it as shared. The default
  selection reads paths only: the mirrored test of each changed file,
  every test under the changed file's owner, and the full suite for a
  changed file at a shared path.
- `select.mjs` and its test `run-affected.test.sh` leave the default
  branch for a long-lived unstable branch, kept rebased and not deleted,
  so the open bug class of the scan no longer touches the default
  selection.
- The slowest tests spend less time per case, so a local run stays short
  whatever the selection. The repository owner decided on 2026-11-24 that
  the tests must still run locally, since their quality does not yet allow
  leaving them to continuous integration alone.

## Affected users and systems

- The repository owner and every Claude Code session that runs, selects
  or checks the tests.
- `run.sh`, `run-affected.sh`, `select.mjs`, `hidden-reads.json` and the
  clean-tree checker `verify-self-containedness.sh`, which takes each
  test's files from `select.mjs files` and needs another source once the
  selector leaves.
- `docs/test-tooling/layout/spec.md`, whose §names-say-what lists the
  selector and whose §suite-stays-green relies on the clean-tree checker,
  and the work that `docs/test-tooling/layout/plan.md` orders.
- Files that more than one owner uses, which move to a shared path once
  it is decided; the move is the declaration, and how a missed file is
  noticed is an open question below.
- The 10 slowest tests, among them `set-aside.test.sh`,
  `external-write-guard.test.sh`, `skill-load-gate.test.sh` and
  `attribution-guard.test.sh`.

## Constraints

- Path selection starts after stack four step 1 of
  `docs/test-tooling/layout/plan.md`, which moves every test to its
  mirrored path, and after every file that more than one owner uses sits at
  a shared path; until then `select.mjs` stays the default.
- Skills still share code at run time, as
  `docs/test-tooling/layout/intent.md` states, and making them independent
  is future work outside this intent. Marking shared code by its path is
  not future work: path selection needs it. For example,
  `smith-git/scripts/lib/hook-utils.mjs` serves hooks of other skills, and
  `smith-ctx-claude/scripts/lib-context.sh` is shared without sitting in a
  `lib/` folder.
- Selection reads nothing but paths: no declaration outside a path and no
  inference from source text. A gap that paths cannot close is recorded
  under Open questions, never patched with a list, a scan or a count.
- The shared path must fit the skill layout.
  The Agent Skills specification, the published format of a skill folder,
  https://agentskills.io/specification, read on 2026-11-24, says the
  `name` field "Must match the parent directory name" and "May only contain
  unicode lowercase alphanumeric characters (`a-z`, `0-9`) and hyphens
  (`-`)", and is silent on nested skill folders.
- No test may be skipped without a signal: a changed file that no rule
  covers runs the full suite. A file that more than one owner uses but that
  sits outside a shared path breaks the layout, as a test outside its
  mirrored path does.

## Not doing

- A hand-written list of shared files: it is a declaration outside the
  path, and a file it leaves out is skipped with no signal.
- Fixing the quote counting or awk `$0` in `select.mjs`: the bug class is
  open by nature.
- A real shell parser: it fixes lexing, not paths built at run time.
- Tracing file access at run time: it likely needs root on macOS, not
  verified.
- Running the tests only in continuous integration: the repository owner's
  decision above.

## Assumptions to validate

- The slowest tests spend their time starting a process per case: time
  each of the 10 slowest alone and count its process launches.
- The clean-tree checker can take its files from mirrored paths alone:
  try it on the tests of one owner; reads that paths cannot cover belong
  to the open question on live files below.
- Keeping the unstable branch rebased costs little: count its conflicts
  over the next stacks of the layout plan.

## Open questions

- Which path marks code as shared, within the skill layout above: for
  example a `scripts/lib/` folder inside the owning skill, a skill whose
  name says it is a library, or a folder that belongs to no skill.
- How a test that reads another owner's live files is selected by path
  alone: tests that read the live repository, such as
  `skill-lint.test.sh` linting every real `SKILL.md`. Selecting by the
  changed file's owner alone, a change to another skill's `SKILL.md`
  would skip it with no signal. `docs/test-tooling/layout/plan.md` records
  these reads among the problems for later stacks.
- How a file that a second owner uses but that sits outside a shared path
  is noticed without a scan or a list.
- How path selection is shown to skip no affected test without using a
  scan's result as the yardstick.
- How short a local run must be, measured as above, for the faster
  slowest tests to count as done; the repository owner sets the number.
- The unstable branch: its name, who keeps it rebased, and when it is
  retired.
- What replaces `select.mjs files` for `verify-self-containedness.sh`.
- Which changes `docs/test-tooling/layout/spec.md` and
  `docs/test-tooling/layout/plan.md` need, agreed with the work those
  files order.
