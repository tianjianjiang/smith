# Intent: test tooling and tests on paths that say what they are

Author: repository owner. Status: accepted by the owner on 2026-11-22.

## Problem

`smith-ctx-claude/scripts/tests/` holds the test tooling and the tests side
by side. The runner `run-all.sh` sits beside its own test `run-all.test.sh`,
and the selector `test-deps.mjs` and its manifest `test-deps.json` sit among
the tests they select. A reader, human or model, cannot tell from a path
which file is a tool and which is a test. The tooling sits there only
because `run-all.sh` finds tests in its own folder.

Other skills keep their own `scripts/tests/run-all.sh`, each written
differently, and some skills have tests that no runner runs.

A test's name does not always say what it tests. `checkpoint-label.test.sh`
tests `lib-context.sh`; `enforce-clear-dispatch.test.sh` and
`enforce-clear.test.sh` both test `enforce-clear.sh`; and
`review-scope.test.sh` runs no code and only compares the wording of a
document with approved text.

Model evaluations, the `*.live-eval.mjs` and `*.classifier-eval.sh` files,
sit in the same folder as the tests and have no runner of their own.

## Proposed outcome

- Every path and name says what the file is, distinct from every other path
  and name.
- Tooling sits where its real scope is, and every test sits at the path
  that mirrors its subject and carries its subject's name.
- Evaluations belong in a root `evals/` tree of their own, apart from the
  tests, each at the path that mirrors its subject, run by a later
  `tools/eval/`. Moving them there is later work, which `plan.md` records
  among its problems for later stacks.
- The layout stays compatible with https://agentskills.io/specification and
  leaves a later move to independent Claude Code plugins possible.
- One runner runs every skill's tests, so a reader never meets two runners
  that carry the same name and run different tests.

## Affected users and systems

- The owner and every Claude Code session that runs, selects or checks the
  tests.
- Every skill folder that holds `scripts/tests/`.
- `README.md` and the reference documents that name test paths.
- Other sessions whose branches touch the same tooling and must rebase.

## Constraints

- Paths and names follow the owner's approved names; rejected names are
  never reused.
- Each change is one reason to change. A refactoring keeps observable
  behaviour and edits no test. A rename of a tool's file, command or
  variable changes its interface and is not a refactoring. Neither is a
  change that adds a seam, a place where behaviour can be altered without
  an edit at that place, in the sense of Michael Feathers, Working
  Effectively with Legacy Code, 2004: it adds a point of variation that
  was not there before.
- Evidence is a primary source quoted with its URL, or a measurement in this
  repository.
- This repository is public: no client name, private path or ticket key.
- Skills share code at run time, and removing that sharing is not part of
  this intent: a hook in `smith-ctx-claude/scripts/` imports
  `smith-git/scripts/lib/hook-utils.mjs`, for example. Sharing inside one
  collection is the ordinary case. https://github.com/addyosmani/agent-skills
  ships its skills as one plugin whose `hooks/`, `scripts/` and
  `references/` sit beside `skills/`, and its README says a per-skill
  install "copies only `skills/<name>/`, not the repo-level `references/`
  directory", read at commit 8c99fa36d900 on 2026-11-22. A move to
  independent plugins would first have to remove that sharing.

## Open questions

None.
