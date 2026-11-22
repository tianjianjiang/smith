# Test tooling — Design (ADR log)

> Per-feature contracts live in each feature folder's `spec.md`; this log
> owns the *why* for decisions that outlive any single one of them.

The subsystem is the repository's test tooling: the runner, the change-based
entry point, the selector with its hidden-read declarations, and the
clean-tree checker,
together with the place every skill keeps its tests. ADR stands for
Architecture Decision Record; the format is defined in
`smith-sdlc/references/PLAYBOOK.md`.

## Decision index

- [ADR-001 — Test tooling and tests live in two repository-root trees](#adr-001)

## ADR-001

**Title**: Test tooling and tests live in two repository-root trees

**Context and problem**: `smith-ctx-claude/scripts/tests/` holds the test
tooling beside the tests, because the runner finds tests in its own folder.
Most other skills with tests keep their own `scripts/tests/run-all.sh`,
each with its own list of tests or its own shell, and the tests of
`smith-git` and `smith-style` have no runner at all. A path does not say
whether a file is a tool or a test, and runners of different meaning can
name the same skill.

**Decision drivers**:
- Paths are context for the model. Anthropic, "Effective context
  engineering for AI agents",
  https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents:
  "the presence of a file named test_utils.py in a tests folder implies a
  different purpose than a file with the same name located in
  src/core_logic/".
- https://agentskills.io/specification defines `scripts/` as "executable
  code that agents can run" and says nothing about tests.
- The tooling's scope is the repository: the change-based entry point and
  the clean-tree checker call `git rev-parse --show-toplevel`, and the
  hidden-read declarations name files of other skills and the glob `*/SKILL.md`.
- A marketplace install copies only the plugin's own directory, "Files
  outside the plugin directory aren't copied",
  https://code.claude.com/docs/en/plugins/loading.md, and the same page's
  "Paths that escape the plugin directory" rejects a component path outside
  the plugin root however the plugin loads. An installed plugin never runs
  its tests, so tests outside a skill's folder cost a skill turned plugin
  nothing, and a plugin and its marketplace can stay in this repository.
- Repositories with tooling of more than one domain keep a generic root
  folder with one subfolder per domain: Chromium `tools/`,
  https://chromium.googlesource.com/chromium/src/+/af7f13600046b6fa4c007577e7fe6b24e1038903/tools/README.md,
  and CPython `Tools/`, whose `scripts/` holds the test runner
  `run_tests.py`, as its README says in a mirror of the main branch,
  https://remotebranch.eu/Stowage/cpython/raw/branch/main/Tools/README.
  Kubernetes keeps one domain flat and names its checks by verb, `hack/verify-*.sh`,
  https://cos.googlesource.com/third_party/kubernetes/+/refs/heads/upstream/release-1.36/hack/README.md.
  This repository has more than one domain: the test tooling, and a shared
  runner for model evaluations that the owner plans.
- No script or `SKILL.md` calls another skill's `run-all.sh`; only
  documents do. Every skill's tests pass under the `smith-ctx-claude`
  runner, as `sh smith-ctx-claude/scripts/tests/run.sh
  «skill»/scripts/tests/*.test.sh` shows for each skill.

**Considered options**:
- Tooling stays in `smith-ctx-claude/scripts/tests/`. Pros: no change.
  Cons: the problem itself.
- Tooling in `smith-ctx-claude/scripts/`, beside the hooks. Pros: small
  move. Cons: the path claims one skill owns repository-wide tooling, and
  the folder that holds runtime hooks then also holds development tools.
- Tooling in `smith-ctx-claude/scripts/test-runner/`. Pros: its own folder.
  Cons: the owner found it not distinct enough from `tests/`, and it still
  claims one skill owns it.
- Tooling in a folder at the repository root that belongs to no skill, one
  runner for every skill. Pros: path and scope agree; nothing of it ships
  with a skill turned plugin; one entry point. Cons: every skill's runner
  and the documents that name it change.

For the tests, these options were weighed:
- Each skill keeps its tests in `«skill»/tests/`, mirroring the skill.
  Pros: the tests travel with the skill. Cons: nothing needs them to
  travel, since an installed plugin never runs them and skills stay in this
  repository.
- One repository-root `tests/` tree mirrors every subject. Pros: one tree
  for every test, the tooling's tests included, and nothing of it ships
  with a skill. Cons: the word test repeats in the tooling's test paths.

**Decision outcome**: The last option for the tooling, in `tools/test/`,
beside a later `tools/eval/` for the evaluation runner; the root `tests/`
tree for the tests. A test sits at `tests/«owner»/«path of its subject inside
the owner»`: the test of `smith-review/scripts/review-receipt.mjs` goes under
`tests/smith-review/scripts/`, and the test of `tools/test/select.mjs` under
`tests/tools/test/`. Every `«skill»/scripts/tests/run-all.sh` is removed in
the same landing as the move.
Documents about repository-wide subsystems live under `docs/`, apart from the
tooling, as a skill keeps `references/` apart from `scripts/`. The work is
cut into stacked pull requests of one reason to change each, as
`layout/plan.md` orders them.

**Consequences**: `README.md` no longer says each hook ships a self-check
under its skill's `run-all.sh`. Neither `tools/` nor `tests/` may ever hold
`.claude-plugin/plugin.json`. Turning skills into independent plugins still
needs the runtime imports between skills removed first, which this decision
does not do.
