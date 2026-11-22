# Plan: test tooling layout (from intent.md 2026-11-22)

> How `spec.md` is made to hold; why, in `../design.md` ADR-001. Where this
> plan and `spec.md` disagree, `spec.md` wins and this file is corrected in
> the same commit.

## Rules for cutting the work

- One reason to change per pull request, and one kind of change per pull
  request. The commit type follows the Angular definitions,
  https://raw.githubusercontent.com/angular/angular/main/contributing-docs/commit-message-guidelines.md:
  `docs` is "Documentation only changes"; `refactor` "neither fixes a bug
  nor adds a feature"; `test` is "Adding missing tests or correcting
  existing tests"; `build` covers "Changes that affect the build system".
- A refactoring keeps observable behaviour,
  https://martinfowler.com/bliki/DefinitionOfRefactoring.html, and stays
  apart from feature changes and bug fixes,
  https://google.github.io/eng-practices/review/developer/small-cls.html
  "Separate Out Refactorings". By the owner's rule it also stays apart from
  test changes, so that the unedited tests prove the behaviour kept.
- Each step leaves the suite green and every named path resolving, so a
  step that renames or moves a file carries every reference to it, however
  many files those are. Splitting such a step would leave broken paths on
  the default branch.
- At most four pull requests per stack, managed with `gh stack`. A later
  stack is planned in full only after the earlier one lands, from what it
  taught; the end of each stack is a checkpoint with the owner.
- Other skills' runners have no caller but documents, so they are replaced
  whole rather than strangled:
  https://learn.microsoft.com/en-us/azure/architecture/patterns/strangler-fig
  says the pattern might not be suitable when "You migrate a small system
  and replacing the whole system is simple." Their removal still lands with
  the replacement, because "If the contract phase is not executed you might
  end up in a worse state than you started",
  https://martinfowler.com/bliki/ParallelChange.html.
- Before every first push: `smith-secret-guard-local`, then `/smith-review`
  to convergence. Every branch name, commit message and pull request text is
  shown to the owner and written only on a yes.

## Files that change

Stack one, in `smith-ctx-claude/scripts/tests/`: `run-all.sh`,
`run-affected.sh`, `check-test-deps.sh`, `test-deps.mjs`, `test-deps.json`,
`run-all.test.sh` and `run-affected.test.sh`; and the documents that name
them: `README.md`, `smith-ctx-claude/REFERENCE.md`,
`smith-ctx-claude/references/HOOKS.md`,
`smith-ctx-claude/scripts/tests/records/README.md`,
`smith-ctx-claude/references/instruction-enforcement/plan.md` and
`smith-git/references/HOOKS.md`.

Stack four, in addition: every other `«skill»/scripts/tests/run-all.sh`, and
the documents that name them, among them
`smith-checkpoint/references/checkpoint-audit/plan.md`,
`smith-serena/references/HOOKS.md` and
`smith-standards/references/HOOKS.md`.

## Order of work

### Stack one: rename the test tooling inside smith-ctx-claude

Landed on the default branch as one pull request,
https://github.com/tianjianjiang/smith/pull/373.

1. `test(ctx-claude)!: rename the test tooling`
   - In place inside `smith-ctx-claude/scripts/tests/`, to the names
     approved in §names-say-what: `run-all.sh` to `run.sh`,
     `check-test-deps.sh` to `verify-self-containedness.sh`,
     `test-deps.mjs` to `select.mjs` with its command `select` renamed
     `tests`, `test-deps.json` to `hidden-reads.json`, and `run-all.test.sh`
     to `run.test.sh`; `run-affected.sh` and `run-affected.test.sh` keep
     their names. The tests keep `.test.sh` until they move, since the
     runner finds them by it.
   - Carries every reference named under "Files that change" and
     `RUNNER_FILES` in the selector. `smith-ctx-claude/references/HOOKS.md`
     names this runner and the `smith-standards` one in the same sentence;
     only the first changes here.
   - Renames the job count variable `RUN_ALL_JOBS` to `SMITH_TEST_JOBS`,
     and the runner test's closing line `PASS: run-all` to `PASS: run`.
   - Not a refactoring: a tool's file name, command and variables are its
     interface, and renaming them changes how a caller reaches it. The
     commit type is therefore `test`, marked `!` with a `BREAKING CHANGE:`
     footer that lists every old name with its new one.
   - Done when: §names-say-what, §references-resolve and §suite-stays-green
     hold.
   - Depends on: nothing. Size: M, mechanical.

Checkpoint after stack one: the pull request merged; the owner and the main
thread review what the stack taught and re-plan stack two.

### Stack two: the decision, the seam and several tests folders

Steps 1 and 2 landed on the default branch as
https://github.com/tianjianjiang/smith/pull/377 and
https://github.com/tianjianjiang/smith/pull/378. Step 3 is provisional.

1. `docs: record the test tooling layout decision`
   - Adds `docs/test-tooling/design.md` and this folder's `intent.md`,
     `spec.md` and `plan.md`.
   - Done when: the owner has approved their wording; every path they name
     for today's layout exists.
2. `test(ctx-claude): name the tests folder apart from the tooling`
   - `run.sh`, `run-affected.sh` and `verify-self-containedness.sh` set
     `TESTS` apart from `HERE`, and `select.mjs` reads `hidden-reads.json`
     and recognises runner edits from `TOOLING_FOLDER`;
     `run-affected.test.sh` stops hiding a failed copy of the tooling into
     its fake repository behind `2>/dev/null`. Both serve the separation of
     tooling from tests.
   - Done when: §suite-stays-green holds, a mutation of the seam makes the
     existing tests fail, and with a listed tooling source missing the test
     fails at the copy and names that source.
3. Run tests from several tests folders; the commit type is `test`, as for
   the rename and the seam, which change the same tooling. In addition to
   test files, the runner takes a tests folder as an argument and runs
   every `*.test.sh` in it, `--all` runs every test in every tests folder,
   and each log is named by repository-relative path instead of by
   `basename`; the selector reads several tests folders. How the runner and
   the selector learn the set of tests folders is for this step to settle.
   Given no argument, the runner still runs the tests that the changes
   against the default branch affect.

Checkpoint after stack two: its pull requests merged; the owner and the main
thread review what the stack taught and re-plan stack three.

### Stack three: every test mirrors a subject

Provisional.

1. Give every test a subject it mirrors, before the move makes the runner
   fail on a test without one. Tests named apart from their
   subject are renamed: `checkpoint-label.test.sh` after `lib-context.sh`
   and `pr-body-template.test.sh` after `check-pr-body.sh`. Tests that share
   a subject are merged: `enforce-clear-dispatch.test.sh` into
   `enforce-clear.test.sh`, and `smith-style`'s `attribution-core.test.sh`
   with `smith-ctx-claude`'s `attribution.test.sh`, both of which run
   `smith-style/scripts/attribution.sh`. `review-scope.test.sh`,
   `media-and-reading.test.sh` and `review-scope-alignment.test.sh` run no
   code and only compare document wording with approved text, so they are
   not tests: their approved text becomes data that a new `verify-` tool
   checks, its name and folder to be approved. `preflight-probe.test.sh`
   tests the live-state command written into `smith-preflight/SKILL.md`, so
   that command moves into a script under `smith-preflight/scripts/` that
   `SKILL.md` calls, and the test mirrors that script.

### Stack four: repository-root tooling and tests

Provisional.

1. Move the test tooling to `tools/test/` and every test to its mirrored
   path under `tests/`; the commit type is open, because `build` covers
   "the build system or external dependencies" and this is neither. Running
   the full suite, the runner runs every file under `tests/` whose mirrored
   subject exists and fails on any other file there; shared helpers move
   to `tools/test/lib/` and test data to `tools/test/fixtures/«mirrored
   path»`. Every line that sources `lib/set-aside.sh` follows, among them
   `smith-ctx-claude/scripts/test-inject-plan.sh` and the fixtures
   `dispatch-background-session-on-stop.sh` and `orca-stop-hook-clear.sh`;
   no runner runs `test-inject-plan.sh`, so it is run by hand after the
   move and must end with the same last line as before it. Running every
   test under `tests/` brings in the tests of `smith-git` and `smith-style`
   that no runner runs today. `README.md`, which says each hook's self-check
   is in its owning skill's `scripts/tests/`, follows the move.
   Neither folder may ever hold `.claude-plugin/plugin.json`, or a skills
   directory loads it as a plugin, since `~/.claude/skills` links to the
   repository root, https://code.claude.com/docs/en/plugins/loading.md.
2. Retire every skill's own `run-all.sh`; the commit type is open. Deletes
   the per-skill runners and repoints every reference document that names
   one in the same change, so §references-resolve holds;
   lands with the previous step through `gh stack merge`.

Checkpoint after stack four: §tooling-outside-tests and §one-runner hold on
the default branch.

### Stack five: tests no runner runs

Provisional, after stack four, whose runner decides what counts as a test.

- `smith-ctx-claude/scripts/test-inject-plan.sh` sits outside any tests
  folder, and nothing runs it.

### Problems recorded for later stacks

Each is a problem to plan, not a chosen fix.

- Some tests read the live repository instead of fixtures, so the selector
  needs hand-written declarations in `hidden-reads.json` that a reader
  cannot see in the code: `skill-lint.test.sh` lints every real `SKILL.md`
  at its end, and `correction-census.mjs`, `skill-claim-lint.mjs` and
  `skill-trigger-eval.mjs` take the repository root as a constant.
  `attribution.sh` runs the scripts that `attribution-model-sources.txt`
  lists. Done when every test's reads are visible to the scan, or each
  remaining declaration is justified on its own.
- The job count is read in two places, `run.sh` and
  `verify-self-containedness.sh`, and only the runner rejects an invalid
  value.
- `run-affected.sh` finds the repository and the tests from the folder it
  sits in, so `run-affected.test.sh` can test it only inside a fake
  repository that holds a copy of every tool, each listed by name. Done
  when the test runs the tooling where it lives, with no copy.
- Model evaluations, the `*.live-eval.mjs` and `*.classifier-eval.sh`
  files, sit inside `smith-ctx-claude/scripts/tests/` with no shared
  runner; by `spec.md` §names-say-what they belong in the root `evals/`
  tree at the mirrored path of their subject, run by a later
  `tools/eval/`. The
  records they write under `records/` go with them, at a path not yet
  decided, and `enforce-clear-dispatch.test.sh` reads one of those
  records. Done when every evaluation runs from one entry point and
  its records have a decided home.

## Tracking

The task list of the working session and this file track the steps. A step
left for a later session is recorded as a Serena project memory, never as a
GitHub issue. A step is closed only on the owner's OK.

## Risks

- Another Claude Code session, named `run-all-vs-check-deps`, works on
  the same tooling. Each landed step is announced to that session with its paths,
  names, branch and commit, so it rebases onto small steps.
- A rename that misses one reference leaves a dead path in a document that
  agents read as instructions. The rename searches every old name with a
  control term known to hit.
- The runner moved in stack four runs every skill's tests in parallel with
  `bash`, while most per-skill runners run them one after another with
  `sh`. Every skill's tests already pass this way, by
  `sh smith-ctx-claude/scripts/tests/run.sh «skill»/scripts/tests/*.test.sh`
  for each skill; stack four repeats that as an acceptance test.
- Once stack four moves the tooling away from the tests, gaps that the
  seam leaves harmless become real. If the tooling folder ever sat
  outside the repository root, its key in `runnerChange` would start with
  `..` and an edit to the tooling would no longer force the full suite.
  And the selector's `files` command still takes and resolves a tests
  folder it no longer uses. And every fake repository in
  `run-affected.test.sh` holds the tooling in its tests folder, so the
  tests cannot yet tell the two folders apart. Stack two's third step
  states each of them in its acceptance tests, among them a fake repository
  whose tooling sits apart from its tests.
- Once stack two's third step has the tooling read more than one tests
  folder, any place that still reads one works on that folder alone. Two
  such places came after the seam, with the change that made the affected
  tests the runner's default,
  https://github.com/tianjianjiang/smith/pull/387: `list_every_test` in
  `run-affected.sh` and `testsToCheck` in `select.mjs`. Older ones remain
  throughout the tooling. That step finds every such place and states it
  in its acceptance tests.

## Proof

- Refactoring steps: the existing tests pass unedited.
- The seam commit: the suite passes, and a mutation of the seam makes the
  existing tests fail.
- Every step: §suite-stays-green.
- Path changes: §references-resolve.
