# Test tooling layout — Spec (the contract)

> The *why* lives in `intent.md`; the decision and its alternatives in
> `../design.md` ADR-001. This file states what must hold; how and in which
> order it is made to hold belongs in `plan.md`.

Vocabulary: verification asks whether an object meets its stated
specification, and validation, or fitness, asks whether it serves the
intended use; both are questions about one named object. The definition is
in `smith-validation/SKILL.md` "Fitness Versus Verification" on the branch
`feat/vet-command`, not yet on the default branch, and follows IEEE
1012-2016, https://standards.ieee.org/ieee/1012/5609/, on whether products
"conform to the requirements" and whether "the product satisfies its
intended use and user needs". Applied here, each check names its object:
- The selector's own test, against a fake repository with known answers,
  verifies the selector against its rules.
- The clean-tree checker verifies each test against the stated rule that it
  passes with only its declared files. Its results also serve as validation
  of the selector, whose intended use is that a change never skips a test
  it affects; the checker's name follows its object, the test.

Test tooling means the runner, the change-based entry point, the selector,
the selector's hidden-read declarations, the folder lister and the
clean-tree checker. Before the move a test file is a `*.test.sh` file, the
only kind the runner finds, and a `*.test.mjs` file runs only when a
`*.test.sh` file runs it; after the move, a test file
is a file under `tests/` whose mirrored subject exists, and `tests/` holds
nothing else. An evaluation is a `*.live-eval.mjs` or `*.classifier-eval.sh`
file.

## §tooling-outside-tests

**EARS (Easy Approach to Requirements Syntax)**: The repository shall keep
its test tooling only in `tools/test/` and its tests only in the root
`tests/` tree, each test at the mirrored path of its subject.

**GWT (Given-When-Then)**:
- Given the default branch after the move
- When `tools/test/`, `tests/` and every `smith-*/` folder are listed
- Then `tools/test/` holds only test tooling, the test helpers open to
  the tests of every owner in `tools/test/helpers/` and test data in
  `tools/test/fixtures/«mirrored path»`; every file under `tests/` is a
  test at `tests/«owner»/«path of its subject inside the owner»`, so if
  the repository root holds a `lib/` folder of shared code that belongs
  to no skill, its tests sit in `tests/lib/`; and no `smith-*/` folder
  holds a test file or a tooling file

**GWT**:
- Given a file under `tests/` whose mirrored subject does not exist
- When the runner runs the full suite
- Then the runner fails and names that file

## §one-runner

**EARS**: When a reader runs the repository's tests, the repository shall
offer one runner, `tools/test/run.sh`, in a folder that belongs to no
skill.

**GWT**:
- Given the default branch after the move
- When the runner runs the full suite
- Then it runs every test under `tests/`, and no file named `run-all.sh`
  exists in any `smith-*/` folder

## §names-say-what

**EARS**: Every tooling file shall carry a name that says what it does, and
no name shall be one the owner rejected.

Rules the owner set:
- A tool's name is a verb from `run`, `select`, `verify` and `validate`,
  then its object; a data file's name is a noun phrase.
- `test` and `tests` are nouns only, and a name inside `tools/test/` leaves
  them out, since the folder says it.
- A test carries its subject's name and is told apart only by its mirrored
  path under `tests/`, with no prefix such as `verify-` or `validate-` and,
  once there, no compound extension.

Approved, by role:
- Folder: `tools/test/`, and later `tools/eval/` for the evaluation runner,
  whose evaluations sit in the root `evals/` tree at the mirrored path of
  their subject, as tests sit in `tests/`.
- Test helpers open to the tests of every owner: `tools/test/helpers/`,
  which takes what `smith-ctx-claude/scripts/tests/lib/` holds today.
- Runner: `run.sh`; it runs the tests it is given. Given none, it runs the
  tests that the changes against the default branch affect, and `--all`
  runs the full suite, as the owner chose on 2026-11-18.
- Change-based entry point: `run-affected.sh`.
- Selector: `select.mjs`, with the commands `tests` and `files`.
- Hidden-read declarations: `hidden-reads.json`.
- Clean-tree checker: `verify-self-containedness.sh`.
- Folder lister, until stack four step 1 retires it: `list-folders.sh`,
  kept by the owner on 2026-11-25 although it breaks the verb rule.
- Job count variable: `SMITH_TEST_JOBS`.

Rejected by the owner: `verify-selection.sh`, `select-tests.validation.sh`,
`run-tests-execution.test.sh`, `run-tests-selection.test.sh`, `test-deps`
in any new name; `run-all.sh` for a runner that `run-affected.sh` calls with
a subset; `inputs` as the checker's object, a plural that reads as
machinery; `self-containment`, which carries another meaning; and
`hermeticity`.

**GWT**:
- Given a change that names or renames a tooling file
- When its new name is compared with the approved and rejected names
- Then it is an approved name, or one the owner approved for that change,
  and never a rejected one

## §references-resolve

**EARS**: Every path that `README.md` or a reference document names for
test tooling shall exist.

**GWT**:
- Given a change that moves or renames a tooling file
- When tracked files are searched for the old path, alongside a control
  term known to hit, leaving out `docs/test-tooling/` and every
  `fixtures/` folder
- Then the old path is found nowhere and the control term is found

The documents under `docs/test-tooling/` record the old paths as history,
and fixtures are test data, such as the pull request bodies in
`smith-gh-pr/scripts/tests/fixtures/` that quote a runner path; neither is a
reference a reader follows.

## §suite-stays-green

**EARS**: After each change, the tests it affects shall pass through the
runner, and the clean-tree checker shall report each new or changed test
passing with its dependencies alone.

**GWT**:
- Given any change of this work, checked out
- When the runner runs the tests the change affects, and the clean-tree
  checker checks the new or changed tests
- Then the runner prints `ALL PASS`, and the checker exits with status 0,
  printing `EVERY TEST PASSES WITH ITS DEPENDENCIES ALONE` or, when a test
  skips in the repository too,
  `EVERY TEST THAT RAN PASSES WITH ITS DEPENDENCIES ALONE; SKIPPED TESTS WERE NOT CHECKED`

## §refactoring-keeps-tests

**EARS**: When a change is a refactoring, the existing tests shall pass with
no edit to them. A rename of a tool's file, command or variable changes its
interface and is not a refactoring, and neither is a change that adds a
seam, a place where behaviour can be altered without an edit at that place.

**GWT**:
- Given a change whose commit type is `refactor`
- When its diff is listed
- Then it edits no test file, renames no tooling file, command or
  variable, and adds no seam, and the suite passes
