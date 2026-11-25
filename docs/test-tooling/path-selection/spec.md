# Select tests by path — Spec (the contract)

Status: draft, begun on 2026-11-24 and last changed on 2026-11-25, for the
repository owner's review.

> The *why* lives in `docs/test-tooling/path-selection/intent.md`. This
> file states what must hold; how and in which order it is made to hold
> belongs in a later `docs/test-tooling/path-selection/plan.md`. Each
> requirement is written in EARS (Easy Approach to Requirements Syntax)
> with GWT (Given-When-Then) acceptance scenarios, as in
> `docs/test-tooling/layout/spec.md`.

Vocabulary, on top of `docs/test-tooling/layout/spec.md`:
- Owner: the top-level folder that holds a file, such as `smith-git/`; a
  test's owner is the first folder under `tests/`, as `tests/«owner»/…`.
- Shared path: the root folder `lib/`, which belongs to no skill; a file
  under it is shared code. Decided by the repository owner on 2026-11-24.
- Owner tree: a new git repository with one commit that holds only the files
  at the repository root, one owner's folder, its folder under `tests/`,
  `lib/` and `tools/test/`; root files have no owner, so a change to them
  runs the full suite by §no-silent-skip. Only the owner tree of owner `lib`
  holds `tests/lib/`, its folder under `tests/`, which holds only the tests
  of the root `lib/`; every other owner tree leaves it out. Test helpers
  shared across owners sit in `tools/test/helpers/`, so a change to one runs
  the full suite by the shared rule.
- Poisoned tree: the owner tree plus every tracked and untracked, not
  ignored, file the owner tree does not hold, such as the rest of `tools/`
  outside `tools/test/`, each such file kept at its path and mode but with
  its content replaced by the poison content: the one line
  `SMITH POISONED FILE «path»` followed by a NUL byte, which is no valid
  Markdown
  front matter, JSON, JavaScript or shell script that the repository's tests
  check; a symbolic link there becomes a regular file with the poison
  content, since a link target cannot hold a NUL byte. On 3cd2f68 the one
  tracked symbolic link is the root `CLAUDE.md`, which no tree poisons.
- Use and read: code uses a file when it runs, imports or sources it; a file
  is read when it is opened as data, listed, or tested for existence, and a
  folder is read when it is listed or tested for existence, as
  `[ ! -d smith-b/new ]` tests it; listing the repository root or `tests/`
  reads the folder of every owner. A use decides §shared-code-has-a-path,
  and a read by a test decides §live-reads-stay-with-their-owner.
- Live file: a file of another owner at its place in the repository, outside
  `lib/` and `tools/test/`; a test may read `lib/` and `tools/test/`, its
  fixtures in `tools/test/fixtures/` included, since a change to either runs
  the full suite by the shared rule.
- Paths: an existing file is named at its path on 3cd2f68; the step of
  `docs/test-tooling/layout/plan.md:148` that moves tests and tooling, and
  the moves under `lib/` that §shared-code-has-a-path asks for, change those
  paths, and a requirement that applies after them means the same file at
  its new path.
- Runner: the runner `run.sh` together with the change-based entry point
  `smith-ctx-claude/scripts/tests/run-affected.sh`, which
  `smith-ctx-claude/scripts/tests/run.sh:22` hands every run with no tests
  given; selection lives in `run-affected.sh`.
- Change: the files that differ between the working tree, its untracked,
  not ignored, files included, and its merge base with the default branch,
  as `docs/test-tooling/layout/spec.md` §names-say-what has the runner use
  "the changes against the default branch"; a renamed file counts as both
  its old and its new path.
- macOS host: the Mac with 10 processors and a third-party endpoint security
  extension, outside any container. Every measurement in this file and in
  `intent.md` ran on that Mac; the container runs ran in a Linux virtual
  machine on it, so they are not runs on the macOS host.

## §selection-reads-paths

**EARS**: When the runner is given no tests, it shall select, for each file
the change touches, from that file's path alone, by four named rules: the
test rule, for a file under `tests/«owner»/`, selects that test and every
other test under `tests/«owner»/`; for any other file outside `lib/` and
`tools/test/`, the mirror rule selects its mirrored test and the owner rule
every test under `tests/«owner»/` of its owner; and the shared rule selects
the full suite when the file sits under `lib/` or `tools/test/`. Only tests
that exist in the working tree are run; a deleted or renamed test's old path
still selects the other tests under its owner. It shall print each selected
test with every touched file that selected it and every rule that did.

**GWT**:
- Given a run with no tests given
- When the runner prints its plan
- Then each selected test is printed with every touched file and every rule
  that selected it

**GWT**:
- Given a change that touches only the test
  `tests/smith-git/scripts/hooks/branch-name-guard.mjs`
- When the runner runs with no tests given
- Then it runs every test under `tests/smith-git/`, among them the touched
  test, and no other test

**GWT**:
- Given a change that touches only
  `smith-git/scripts/hooks/branch-name-guard.mjs`, which no code of another
  owner runs, imports or sources
- When the runner runs with no tests given
- Then it runs every test under `tests/smith-git/`, and no other test

**GWT**:
- Given a change that touches only `smith-review/SKILL.md`
- When the runner runs with no tests given
- Then it runs every test under `tests/smith-review/`, among them the check
  of `smith-review/SKILL.md` itself, and no other test

**GWT**:
- Given a change that touches `lib/hook-utils.mjs`
- When the runner runs with no tests given
- Then it runs the full suite

**GWT**:
- Given the source of `run-affected.sh`
- When it is read
- Then selection opens no file to decide what to run: it reads the changed
  paths from git and the paths under `tests/`, and nothing else

## §no-silent-skip

**EARS**: If the rules of §selection-reads-paths select no test for a
touched file, then the runner shall run the full suite and name that file
and each rule that applies to it and selected nothing for it; the mirror
rule and the owner rule apply to every file outside `tests/«owner»/`,
`lib/` and `tools/test/`.

**GWT**:
- Given a change that touches `README.md`, which has no owner
- When the runner runs with no tests given
- Then it prints `README.md` with the mirror rule and the owner rule, each
  of which selected nothing, and runs the full suite

**GWT**:
- Given a change that touches only `docs/test-tooling/layout/spec.md`, whose
  owner `docs` has no folder under `tests/`
- When the runner runs with no tests given
- Then it prints that file with the mirror rule and the owner rule, each of
  which selected nothing, and runs the full suite

## §shared-code-has-a-path

**EARS**: While every test sits at the mirrored path of its subject, the
repository shall keep every file that an owner other than the one holding it
uses, by its code or by its tests, under `lib/`, and its test at
`tests/lib/«path inside lib»`; files under `tools/test/`, which the runner
and every test use by design, are outside this rule.

**GWT**:
- Given the default branch once every test sits at the mirrored path of its
  subject
- When the clean-tree checker runs every test in its owner tree and its
  poisoned tree
- Then no test fails in either tree, within the boundaries
  §owner-tree-proves-selection states

The checker measures only uses that some test exercises. A use by code that
no test runs cannot make selection skip a test, since no test depends on it,
but it still breaks this requirement; the inventory for the move, in
`docs/test-tooling/path-selection/plan.md`, is what finds it. Uses on
3cd2f68 that the move must cover include
`smith-git/scripts/lib/hook-utils.mjs`, which hooks of `smith-ctx-claude`
import; `smith-ctx-claude/scripts/write-reload-flag.sh` and
`smith-ctx-claude/scripts/ctx-reset-state.sh`, whose paths
`smith-checkpoint/scripts/write-checkpoint.sh:55` and `:80` build and whose
runs are at `:67` and `:86`; and
`smith-ctx-claude/scripts/attribution-model-source.sh`, which
`smith-style/scripts/attribution.sh:12` runs because the list
`smith-style/scripts/attribution-model-sources.txt`, read at `:17`, names
it, a use no search for a path finds. A test's read of another owner's file,
such as `smith-ctx-claude/scripts/tests/subagent-contract-guard.test.sh:4`
reading `smith-subagents/SKILL.md`, falls under
§live-reads-stay-with-their-owner instead.

`lib/` sits at the repository root beside `docs/`; it holds no `SKILL.md`,
so it is no skill and the naming rule of the Agent Skills specification, the
published format of a skill folder, https://agentskills.io/specification
(read on 2026-11-24), quoted in
`docs/test-tooling/path-selection/intent.md`, does not reach it. Claude Code
finds skills one level deep only, `~/.claude/skills/<skill-name>/SKILL.md`
in https://code.claude.com/docs/en/skills.md, read on 2026-11-24, and a
trial with Claude Code 2.1.331 on that date loaded no skill from a folder
without `SKILL.md` and reported no error. Like `tools/test/`, which
`docs/test-tooling/layout/plan.md:162` on 3cd2f68 bars from it, it may never
hold `.claude-plugin/plugin.json`.

## §owner-tree-proves-selection

**EARS**: The clean-tree checker shall run each test in the owner tree and
in the poisoned tree of its owner, and a test that passes in the repository
but fails in either tree shall fail the checker, naming the test and each
tree it fails in.

**GWT**:
- Given a test under `tests/smith-ctx-claude/` that reads
  `smith-checkpoint/SKILL.md`, a file of another owner outside `lib/`, and
  fails when that file is absent
- When the checker runs it
- Then the checker fails and names that test and, among the trees it fails
  in, the owner tree

**GWT**:
- Given a test under `tests/smith-ctx-claude/` that, only when
  `smith-checkpoint/SKILL.md` exists, reads it and checks its front matter,
  a check the poison content fails
- When the checker runs it
- Then the checker fails and names that test and the poisoned tree

**GWT**:
- Given a test under `tests/smith-ctx-claude/` that reads every `*/SKILL.md`
  it finds and checks the front matter of each, a check the poison content
  fails
- When the checker runs it
- Then the checker fails and names that test and the poisoned tree

**GWT**:
- Given a test under `tests/smith-git/` that sources a file under
  `tests/lib/`
- When the checker runs it
- Then the checker fails and names that test and, among the trees it fails
  in, the owner tree, since the owner tree of `smith-git` holds no
  `tests/lib/`

**GWT**:
- Given the checker's source
- When it is read
- Then it builds both trees from the test's owner path and the tracked and
  untracked, not ignored, paths that `git ls-files --cached --others
  --exclude-standard` lists, and does not call
  `smith-ctx-claude/scripts/tests/select.mjs`

The test helpers on 3cd2f68,
`smith-ctx-claude/scripts/tests/lib/set-aside.sh`, `json-string.sh` and
`json-inputs.sh`, move to `tools/test/helpers/` in the step of
`docs/test-tooling/layout/plan.md:148` that moves every test, not to
`tests/lib/`.

This one check gives the three signals that `intent.md` leaves open: what
replaces `select.mjs files`, how a file that a second owner uses outside
`lib/` is noticed, and how path selection is shown to skip no affected test.
The owner tree catches a test that needs another owner's file to exist; the
poisoned tree catches one that reads another owner's file whenever it
exists, by name or by pattern, and fails on the poison content. Two
boundaries are stated, not checked. A test that reads outside the repository
is not covered. Nor is a test that depends on another owner's files, their
content or their paths, in a way that neither tree changes, such as one that
reads such a file but passes on the poison content too: one that fails only
when such a file holds a certain string, or only when such paths grow by
one, passes in both trees and is still skipped when that owner changes. Such
a test still breaks §live-reads-stay-with-their-owner, so the rule forbids
what the checker cannot see.

## §live-reads-stay-with-their-owner

**EARS**: A test shall read no live file or folder of another owner; a check
of a real file, such as linting `smith-review/SKILL.md`, shall sit under
`tests/«owner»/` of the file's owner, and a tool's own test shall read
fixtures.

**GWT**:
- Given `smith-ctx-claude/scripts/tests/hidden-reads.json` on 3cd2f68, whose
  6 entries each name a file and the live files it reads or runs
- When path selection is the default
- Then that file no longer exists on the default branch, and each entry is
  resolved: the four
  tools that read every `*/SKILL.md`, `skill-lint.mjs`,
  `skill-claim-lint.mjs`, `correction-census.mjs` and
  `skill-trigger-eval.mjs` of `smith-ctx-claude/scripts/`, take the folder
  to read as input, so their tests pass them a fixture and each owner's
  tests check its own `SKILL.md`;
  `smith-ctx-claude/scripts/tests/ctx-reset-state.test.sh` reads a fixture
  in place of `smith-checkpoint/SKILL.md`; and
  `smith-ctx-claude/scripts/attribution-model-source.sh`, which
  `smith-style/scripts/attribution.sh` runs, sits under `lib/` by
  §shared-code-has-a-path, and the list
  `smith-style/scripts/attribution-model-sources.txt` names it at that path

The linting of every real `SKILL.md` that
`smith-ctx-claude/scripts/tests/skill-lint.test.sh` does at its end is the
first example: each skill's tests check its own `SKILL.md`, so a linter that
the tests of every owner run is used by more than one owner;
§shared-code-has-a-path puts it under `lib/`, its own cases, against
fixtures, move to its mirrored path under `tests/lib/`, and a change to it
runs the full suite. The name of the test that checks a `SKILL.md` is open:
by `docs/test-tooling/layout/spec.md` §names-say-what a test carries its
subject's name, which here is `SKILL.md`.

## §inference-leaves-default

**EARS**: When path selection becomes the default, the repository shall move
`select.mjs`, `smith-ctx-claude/scripts/tests/run-affected.test.sh`,
`hidden-reads.json` and the `run-affected.sh` that calls `select.mjs` from
the default branch to the unstable branch `feat/select-tests-by-inference`,
so that the selector still runs there, in the same change that makes path
selection the default; in that change the change-based entry point
`smith-ctx-claude/scripts/tests/run-affected.sh` selects by
§selection-reads-paths, the clean-tree checker
`smith-ctx-claude/scripts/tests/verify-self-containedness.sh` builds its
trees by §owner-tree-proves-selection, and
`smith-ctx-claude/references/HOOKS.md` describes path selection, so none of
them names `select.mjs`.

**GWT**:
- Given the default branch after that change
- When tracked files are searched for `select.mjs`, alongside a control term
  known to hit, leaving out `docs/test-tooling/` and every `fixtures/`
  folder, as `docs/test-tooling/layout/spec.md` §references-resolve does
- Then `select.mjs` is found nowhere and the control term is found; and `git
  ls-tree -r --name-only feat/select-tests-by-inference` lists files named
  `select.mjs`, `run-affected.test.sh`, `hidden-reads.json` and
  `run-affected.sh`

**GWT**:
- Given `feat/select-tests-by-inference` right after that change
- When `run-affected.test.sh` runs on it
- Then it passes

**EARS**: The repository shall keep the name of
`smith-ctx-claude/scripts/tests/list-folders.sh` until it is retired in the
step of `docs/test-tooling/layout/plan.md` that moves every test to
`tests/«owner»/`, and shall retire it in that step, since listing `tests/`
then reads the folder of every owner; the places that name it are listed in
the section "Changes to `docs/test-tooling/layout/`".

**GWT**:
- Given the default branch after that step
- When tracked files are searched for `list-folders.sh`, alongside a control
  term known to hit, leaving out `docs/test-tooling/` and every `fixtures/`
  folder
- Then `list-folders.sh` is found nowhere and the control term is found

Path selection becomes the default only after the step of
`docs/test-tooling/layout/plan.md` that will "Move the test tooling to
`tools/test/` and every test to its mirrored path under `tests/`" has landed
and §shared-code-has-a-path holds, as `intent.md` Constraints require.

## §local-run-stays-short

**EARS**: The full suite, run on the macOS host with 10 jobs, shall pass in
each of 5 rounds and take a median of at most 120 s over them.

**GWT**:
- Given the default branch, on the machine and with the 10 jobs and 5 rounds
  of the measurement in `intent.md`
- When the full suite runs 5 times
- Then the median run time is at most 120 s, and every run prints `ALL PASS`

The cost of starting `node`, the Node.js JavaScript runtime that runs the
hooks, https://nodejs.org/ (read on 2026-11-25), was measured on the macOS
host on 2026-11-17: `node -e 0` started at 5.3 per second with 1 worker and
9.9 per second with 10, while `/usr/bin/true` went from 306.7 to 601.8 per
second. One `node -e 0` timed alone took about 108 ms and one call of
`smith-ctx-claude/scripts/external-write-guard.mjs` about 129 ms, so the
hook's own logic costs little next to the start; a start alone is faster
than the 189 ms that 5.3 per second gives, which counts a stream of starts
back to back. The endpoint security extension used the most processor time,
about 139%; that it causes the cap is inferred, not measured. Earlier, on
2026-10-17, `smith-ctx-claude/scripts/tests/external-write-guard.test.sh`
ran 229 cases, each starting `node` 1 to 3 times at about 0.25 s. A full run
is therefore bounded below by its count of `node` starts divided by the 6.9
to 9.9 per second measured with 10 workers, whatever the job count, on the
macOS host. On 2026-11-24 the same machine started `node -e 0` at 4.8 per
second with 1 worker and 6.9 with 10 on the host, and at 49.9 and 96.4 in a
Linux container of Rancher Desktop, a desktop application that runs
containers in a Linux virtual machine, https://rancherdesktop.io/ (read on
2026-11-25), given 2 processors; the full suite at 3cd2f68 ran in that
container in 173 s with 10 jobs, 400 cases passing, 2 tests failing on
checkpoint warnings and 1 skipped for a case-sensitive file system, against
the 367 s median that `intent.md` gives for the host on 3551966, whose suite
had one test more, `smith-review/scripts/tests/review-scope.test.sh`, which
68227d5 removed. With the container given 8 of the machine's 10 processors,
5 rounds of the full suite with 10 jobs took 98.2, 103.4, 99.8, 101.7 and
98.5 s, a median of 99.8 s, each round failing the same 2 tests; that is
below 120 s but does not meet §local-run-stays-short, which asks for the
macOS host and passing rounds. The 2 failures are test bugs on GNU tools:
`smith-checkpoint/scripts/tests/audit-checkpoint.test.sh:25` writes to
`/dev/stdout`, which Linux reopens and truncates, and
`smith-checkpoint/scripts/tests/write-checkpoint.test.sh:382` passes `yes` a
string that starts with `-`, which `yes` of GNU coreutils, the GNU core
utilities, https://www.gnu.org/software/coreutils/ (read on 2026-11-25),
takes as an option. On the host, 30 sequential `node -e 0` took 5.77 s of
wall time but 1.47 s of `node`'s own processor time, user and system, so
about three quarters of each start is spent waiting outside `node`. Sampled
with `top` on 2026-11-25, the macOS process monitor, man page top(1), the
endpoint security extension used 1.4 to 4.2% of a processor at rest and 103
to 104% while processes started in bulk, `node` or `/usr/bin/true`, while
the macOS checkers stayed near 0%: `syspolicyd`, the System Policy daemon,
man page syspolicyd(8); `xprotectd`, the XProtect daemon, man page
xprotectd(8); and `trustd`, which "performs trust evaluations", man page
trustd(8). The waiting therefore goes with the endpoint security extension,
not with the macOS checkers; proving cause would need a run with that
extension excluded, which this spec does not ask for. Before any change for
speed, the `node` starts of each of the 10 slowest tests are counted; the
counts go into `docs/test-tooling/path-selection/plan.md`, not here.

## Changes to `docs/test-tooling/layout/`

Agreed with the work those files order, not made by this spec:
- `spec.md` §tooling-outside-tests: `tests/lib/` mirrors the root `lib/`.
- `spec.md` §names-say-what: the name of the test whose subject is a
  `SKILL.md`, per §live-reads-stay-with-their-owner.
- `spec.md` §names-say-what: the selector, `select.mjs`, and
  `hidden-reads.json` leave the approved list once §inference-leaves-default
  holds.
- `spec.md` §suite-stays-green: the clean-tree checker's trees follow
  §owner-tree-proves-selection, which runs each test twice; it checks each
  new or changed test after each change, as now, and every test for
  §shared-code-has-a-path.
- `spec.md` opening vocabulary, "The clean-tree checker verifies each test
  against the stated rule that it passes with only its declared files": with
  no declarations left, the rule becomes that the test passes in its owner
  tree and its poisoned tree.
- `spec.md` opening vocabulary: "Test tooling means the runner, the
  change-based entry point, the selector, the selector's hidden-read
  declarations and the clean-tree checker", and the lines that call the
  selector's own test a verification of the selector and the checker's
  results a validation of it; both lose the selector and the hidden-read
  declarations once §inference-leaves-default holds.
- `spec.md` §names-say-what, "Change-based entry point: `run-affected.sh`":
  it keeps the name and selects by §selection-reads-paths.
- `docs/test-tooling/layout/plan.md:135`: it lists `review-scope.test.sh`,
  which 68227d5 removed.
- `docs/test-tooling/layout/plan.md:184-191`, the problem of tests that read
  the live repository, whose done condition is "Done when every test's reads
  are visible to the scan, or each remaining declaration is justified on its
  own": it needs the scan and `hidden-reads.json`, so it becomes
  §live-reads-stay-with-their-owner.
- `docs/test-tooling/layout/plan.md:195-198`, on the fake repositories of
  `run-affected.test.sh`, and `:228-237`, on the selector's `files` command
  and the tooling key in `runnerChange`: both describe the selector, which
  leaves the default branch by §inference-leaves-default, so they move with
  it.
- `docs/test-tooling/layout/plan.md:238-245`, on places that read one tests
  folder: of the two it names, `testsToCheck` in `select.mjs` leaves with
  the selector, and `list_every_test` in `run-affected.sh` stays on the
  default branch, rewritten by §inference-leaves-default, so the risk stays
  for it.
- `docs/test-tooling/layout/plan.md:148`, the step that moves every test:
  it retires `smith-ctx-claude/scripts/tests/list-folders.sh`, by
  §inference-leaves-default, and edits every tracked file that names it
  outside `docs/test-tooling/` on 3cd2f68: under
  `smith-ctx-claude/scripts/tests/`, `run.sh:14`, `:32`,
  `run-affected.sh:12`, `verify-self-containedness.sh:17`, `select.mjs:9`,
  `run.test.sh:9` and `run-affected.test.sh:27`, `:948`, `:1013`, `:1161`,
  `:1164`; and `smith-ctx-claude/references/HOOKS.md:1274`, `:1313`.
- `spec.md:38-39` and `docs/test-tooling/layout/plan.md:153`:
  `tools/test/lib/` becomes `tools/test/helpers/`, and `spec.md` "Approved,
  by role" (`:75`) adds `tools/test/helpers/` as the folder of test helpers
  shared across owners, which `smith-ctx-claude/scripts/tests/lib/` holds
  on 3cd2f68.

## Owner decisions

Decided:
1. The shared path is the root `lib/` (repository owner, 2026-11-24).
2. A check of a real file sits under `tests/«owner»/` of that file's owner,
   with no folder set apart for whole-repository checks (repository owner,
   2026-11-24).
3. The median in §local-run-stays-short is at most 120 s, which at the
   measured 6.9 to 9.9 `node` starts per second allows about 830 to 1190
   starts in a full run on the macOS host (repository owner, 2026-11-24).
4. The unstable branch is named `feat/select-tests-by-inference`, whose
   prefix is a type of Conventional Commits, the commit message format at
   https://www.conventionalcommits.org/en/v1.0.0/ (read on 2026-11-25), as
   `smith-style/SKILL.md` Branch Names requires (repository owner,
   2026-11-24).
5. The repository owner rebases `feat/select-tests-by-inference` by hand,
   only when it is used, so between uses it may trail the default branch;
   this narrows `intent.md`'s "kept rebased", and the conflicts of each such
   rebase are the count that `intent.md` Assumptions to validate asks for
   (repository owner, 2026-11-24).
6. `feat/select-tests-by-inference` is frozen, no longer rebased and never
   deleted, once every stack of `docs/test-tooling/layout/plan.md` has
   landed and the clean-tree checker of §owner-tree-proves-selection has
   found no test that path selection skipped while it was the default
   (repository owner, 2026-11-24).
7. The full suite runs on the macOS host, not in a container, and
   §local-run-stays-short is met by fewer `node` starts per test; the
   container runs above are evidence of the cause, not a way to run the
   suite, so the 2 tests that fail only on GNU tools need no change
   (repository owner, 2026-11-25).
8. The clean-tree checker runs each test in a poisoned tree as well as in
   the owner tree, so that a read of another owner's file that depends on
   the file existing or on a pattern fails, at the cost of running each test
   twice (repository owner, 2026-11-25).
9. Only the owner tree of owner `lib` holds `tests/lib/`, which holds only
   the tests of the root `lib/`, so a test of another owner that sources a
   file under `tests/lib/` fails in its owner tree; test helpers shared
   across owners sit in `tools/test/helpers/`, not `tools/test/lib/`, and a
   change to one runs the full suite by the shared rule (repository owner,
   2026-11-25).
10. `smith-ctx-claude/scripts/tests/list-folders.sh` keeps its name, though
    `docs/test-tooling/layout/spec.md` §names-say-what makes a tool's name
    a verb from `run`, `select`, `verify` and `validate`, until it is
    retired in the step of `docs/test-tooling/layout/plan.md` that moves
    every test to `tests/«owner»/` (repository owner, 2026-11-25).

No owner decision is open in this spec. The name of the test whose subject
is a `SKILL.md` is settled with the work of `docs/test-tooling/layout/`, as
listed above.

## Open questions

Gaps that paths cannot close, recorded here as `intent.md` Constraints
require rather than patched with a list, a scan or a count:
- A test that depends on another owner's files, their content or their
  paths, in a way neither the owner tree nor the poisoned tree changes, such
  as one that falls back to the same result when an import fails, passes the
  clean-tree checker and is skipped when that owner changes; the rule of
  §live-reads-stay-with-their-owner forbids it, and no check finds it.
- A use by code of another owner's file that no test runs breaks
  §shared-code-has-a-path without failing any test. The inventory that
  `docs/test-tooling/path-selection/plan.md` makes for the move finds such
  uses once, as an aid to the move; it is never an input to selection, so it
  is not the list or scan that `intent.md` Not doing rejects, and a use
  added after the move is found only by a test that exercises it.
- A test that reads outside the repository is not covered by either tree.
