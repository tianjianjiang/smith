# Plan: instruction enforcement (from intent.md 2026-10-02)

> How the seven requirements of `spec.md` are made to hold. Where this plan
> and `spec.md` disagree, `spec.md` wins and this file is corrected in the
> same commit.

One principle decides where each rule lives. A rule that must hold every
time and that a program can decide goes into a hook. A rule that must hold
every time and needs judgement goes to a model-judged check at the moment it
applies, and only after that check has passed a replay of recorded turns. A
procedure for one kind of task stays a skill. Anything true only at a point
in time lives in a commit message, a pull request or a document under
`references/`.

## Files that change

New, in this repository:

- `smith-ctx-claude/scripts/skill-lint.mjs` and its test: checks every
  `SKILL.md` for valid frontmatter, a description that says when to use the
  skill, and the absence of calendar dates, work status, incident accounts,
  and pull-request, issue, commit and ticket references
  (§skill-file-holds-no-point-in-time-content).
- `smith-ctx-claude/scripts/lib/skills-invoked.mjs`: the transcript scan now
  inside `skill-claim-lint.mjs`, extracted so two hooks share it.
- `smith-ctx-claude/scripts/skill-load-gate.mjs`, its table
  `smith-ctx-claude/skill-gate.json`, and its test: before a governed action
  runs, refuses it when the governing skill has not been loaded in the
  session (§covering-skill-loaded-before-acting). Governed actions: commit,
  push, pull-request create, review and comment, a message draft to another
  person, a ticket write, a subagent spawn, a web fetch or search, a write
  to a `SKILL.md`, leaving plan mode. Command parsing reuses
  `smith-git/scripts/lib/git-command-tokenizer.mjs`.
- `smith-ctx-claude/scripts/turn-end-gate.mjs` and its test: a command
  hook that runs when a turn is about to end and refuses a last message
  that asks the owner whether the agent should check or verify something
  (§no-open-item-at-turn-end).
- `smith-ctx-claude/turn-end-judge.prompt.md`: the text of a prompt hook
  (`type: "prompt"`, a single call to a small model that the harness makes
  itself) registered on the same event. A command hook cannot call a model,
  so the judged layer is this separate registration. It sees the last
  message and nothing else of the turn, runs at every turn end, and passes
  at once a message that declares no gap and hands nothing to the owner.
  Otherwise it judges three statements: nothing is called unverified that
  the tools at hand could settle; no question is asked that the agent could
  answer itself; every item handed to the owner states what it is, where it
  lives, how many things it covers, what was done and the one thing needed
  (§no-open-item-at-turn-end, §owner-item-carries-its-context). Its
  `impossible` answer lets a turn end when the remaining step needs the
  owner.
- `smith-ctx-claude/scripts/stale-reference-check.mjs` and its test: before
  a commit, lists tracked files that still name a path the staged change
  deletes or renames, or a backticked name the staged change removes
  everywhere it touched; the commit proceeds when each is fixed or named
  under a `Left as is:` paragraph of the commit message
  (§change-reaches-every-reference).
- `smith-ctx-claude/scripts/hook-health-check.mjs` and its test: at session
  start, reports every registered hook whose file is missing or not
  executable, and prints the difference in hook registrations between the
  personal profile and the two other profiles. It never writes to a
  profile.
- `smith-ctx-claude/scripts/correction-census.mjs` and its test: counts the
  three corrections over the personal profile's sessions and prints counts
  and session totals only (§outcome-is-counted-the-way-the-baseline-was).
- `smith-ctx-claude/references/design.md`: the Architecture Decision Record
  (ADR) log that `smith-sdlc` defines, one file for the Claude Code steering
  subsystem (skills, hooks, profile settings), titled after the subsystem
  and not after this change. It is the record §change-carries-its-evidence
  asks for. Each entry fills every field of the template in
  `smith-sdlc/references/PLAYBOOK.md`; the sources and measurements go in
  "Decision drivers" and "Considered options", each with its URL and quoted
  passage or the command that reproduces it. Entries:
  - where a rule lives (hook, judged check, skill, or point-in-time record);
  - a judged check may refuse a turn only after it passes a replay of
    recorded turns, and is otherwise not registered;
  - skill loading is enforced at the governed action, with descriptions and
    the router as aids;
  - skill files hold no point-in-time content, and a citation carries its
    retrieval date everywhere except in a skill file;
  - the outcome is the owner's corrections recounted the way the baseline
    was, with a threshold of zero.
  A before-and-after count for one change goes in that change's commit
  message, which cites the entry it rests on.

Modified, in this repository:

- All 48 `smith-*/SKILL.md`: the description states what the skill is and
  when to use it; the `**Load if:**` line moves into the description; every
  line the lint reports is removed (45 lines in 16 files by the narrower
  search for dates and references that `design.md` gives; the lint's own
  rules find more). Where a rule still rests on an upstream issue
  or pull request, that locator moves to a document under the skill's
  `references/` folder and the skill file points to it; what the other
  lines recorded is kept in the commit message of the removal.
- `smith-guidance/SKILL.md`: the two rules that pull against each other
  ("report what was not verified" and "close gaps, don't just disclose
  them") become one statement: close what the tools at hand can close, and
  hand over only what the owner alone can give. The citation rule asks for
  a retrieval date on every citation except in a skill file, which carries
  the URL or path only.
- `smith-research/SKILL.md`: the same citation change.
- `smith-standards/SKILL.md`, `smith-validation/SKILL.md`,
  `smith-ctx-claude/skill-triggers.json`: the rules that ask for a locator
  on every claim say that in a skill file the locator is a URL or a path.
- `smith-ctx-claude/scripts/skill-router.mjs` and `skill-triggers.json`:
  the router acts only on prompts the owner typed, does not suggest a skill
  already loaded, loses its single-common-word patterns, and tells the
  agent to load with the Skill tool only. It gains a test.
- `smith-ctx-claude/scripts/skill-claim-lint.mjs`: uses the shared scan and
  refuses a last message that claims a skill it did not load.
- `smith-skills/SKILL.md`, `AGENTS.md`: one loading instruction; the
  placement principle above; the standing rule that a correction made a
  second time becomes a hook, a judged statement or an evaluation.
- `smith-ctx-claude/scripts/tests/run-all.sh`,
  `smith-ctx-claude/references/HOOKS.md`: list and document the new hooks.

Outside this repository:

- The personal profile's `settings.json`: registers the new hooks, with a
  dated backup beside the file. A
  new rule file states that primary sources are read as raw text.
- The two other profiles: no change until the owner has accepted the exact
  difference for each.
- The 18 untracked project-local skills in another repository: the same
  description and point-in-time cleanup, edited in place.

## Order of work

Each step is its own branch and pull request, small enough to review, and
each passes the repository's review, pre-ship and ship procedures. The
owner authorised, for every step, the push, the pull-request title and
body, and the merge into the default branch without a further yes, on two
conditions: the change ships through `/smith-ship`, and its tasks are
tracked in the task list and the plan file. Where a condition is not met,
each of those waits for the owner's yes.

1. `correction-census.mjs` with its test, and `design.md` with its five
   entries. The census comes first because every count in `design.md` is
   its output; no figure enters `design.md` without a command that
   reproduces it or a source in which the quoted passage was found. Later
   steps cite the entries of `design.md`.
2. `skill-lint.mjs` with tests, the removal of the lines it reports, and the
   citation and locator rule changes. The lint runs in the test runner from
   this step on, and on every write to a `SKILL.md` once step 7 registers
   it.
3. Descriptions for the 48 skills, restored from the commit before the
   compression and brought up to date. Before and after, each skill is run
   against about twenty should-trigger and should-not-trigger prompts; a new
   description is kept only where the trigger rate does not fall. The lint
   gains its rule that a description says when to use the skill here, when
   the files satisfy it.
4. `skills-invoked.mjs`, `skill-load-gate.mjs`, the router changes and the
   `skill-claim-lint.mjs` change, with tests.
5. `turn-end-gate.mjs`, `turn-end-judge.prompt.md` and the
   `smith-guidance/SKILL.md` change, with tests and the replay described
   under Proof. The prompt hook is registered only if the replay meets its
   bar.
6. `stale-reference-check.mjs` and `hook-health-check.mjs`, with tests.
7. Registration in the personal profile. Then the exact difference for each
   of the two other profiles, shown to the owner one at a time.
8. The 18 project-local skills.
9. The recount of §outcome-is-counted-the-way-the-baseline-was, once 14
   days and 200 sessions have passed since step 7.

## Risks

- A model that reviews another model's output can make things worse. In
  the ContextCov study the reviewing model left 50.3% of patches clean
  against 67.0% with no feedback. The judged layer is therefore held to a
  replay bar before it may refuse a turn, and below the bar it is not
  registered at all, not even as advice.
- A plain phrase match is too blunt to refuse on: over the baseline's 1,089
  last messages it fires on 126 and catches 16 of the 28 the owner answered
  by pointing at a loose end. The program-decided layer refuses only the narrow question
  pattern; the rest is judged.
- A gate that refuses a turn can loop. The harness stops after eight
  refusals in a row; the command hook reads the flag that says the turn is
  already continuing because of a refusal, and the prompt hook answers
  `impossible` when the only remaining step needs the owner.
- The prompt hook adds one small-model call to every turn end, with a
  30-second limit; a call that times out gives no decision and the turn
  ends. It judges the last message only, so it cannot tell whether a claim
  of "done" was backed by output earlier in the turn, nor whether every
  part of the request that does not depend on the owner was finished, the
  first clause of §owner-item-carries-its-context. Both stay with review
  and with the text of `smith-guidance/SKILL.md`; the recount of loose-end
  corrections shows whether that is enough.
- Text a gate feeds back is matched by the router as if it were a request.
  The router change (owner-typed prompts only) removes that path and ships
  before the gates are registered.
- A hook that exits with an ordinary error, times out, or is registered
  under a mistyped path fails open without notice. Every new hook has a
  test, and the health check reports dead registrations at session start.
- A suggestion to load a skill is mostly not followed: in the baseline the
  pull-request skill was loaded in 25 of the 88 sessions where the router
  suggested it, and 39 of 47 descriptions had a use-when clause when the
  router was found necessary. Descriptions and the router therefore cannot
  carry §covering-skill-loaded-before-acting; the gate does. For a
  task with no governed action the requirement rests on the description and
  the router, and the recount shows whether that is enough.
- Longer descriptions use the skill listing's budget, and descriptions that
  do not fit are dropped silently. The total is measured against the budget
  before step 3 merges.
- The lint can refuse legitimate text: a date format given as an example, a
  placeholder. Placeholders and format patterns are allowed, and the 48
  files must pass before the write-time check is registered.
- `stale-reference-check.mjs` covers paths and backticked names. A changed
  number, rule or behaviour is not decidable by it; those rest on the
  judged layer and on review.
- The census reads sessions of other projects under the personal profile.
  It prints counts and session totals only, and its test asserts that no
  message text appears in its output.
- The threshold of zero in the recount is strict; one correction reports
  the outcome as not reached. That is the specification, not a defect.

## Proof

- §no-open-item-at-turn-end, §owner-item-carries-its-context: the replay
  runs the command hook and the prompt text, on the model the hook will
  use, over the baseline's 1,089 last messages that the owner answered.
  The census prints counts only, so the replay script of step 5 selects
  those messages with the census's own matching rules and is checked
  against its totals (1,089 answered, 28 answered by pointing at a loose
  end). Bar for the prompt hook to be
  registered: it flags at least 14 of the 28 messages the owner answered by
  pointing at a loose end, and at most 10% of the other 1,061. Tests of the command hook cover the
  refusal and the already-continuing flag; the replay set includes turns
  whose only remaining step needed the owner.
- §change-reaches-every-reference: tests with a renamed path and a removed
  name still referenced elsewhere, in both directions, and the `Left as
  is:` paragraph. The health-check test covers a profile difference.
- §covering-skill-loaded-before-acting: a test for every row of
  `skill-gate.json`, refused without the skill and allowed with it; the
  trigger-rate comparison of step 3; one live session in which a governed
  action is attempted without its skill.
- §skill-file-holds-no-point-in-time-content: one failing fixture per lint
  rule; the 48 skill files pass; step 2 removes or rewrites no existing
  line of a document under `references/`, it only adds to them.
- §change-carries-its-evidence: every commit of steps 2 to 6 cites the
  `design.md` entry it rests on; each entry has every template field filled
  and, for each driver, a URL with a quoted passage or a command with its
  output.
- §outcome-is-counted-the-way-the-baseline-was: `correction-census.mjs`
  produces the baseline (30 messages in 20 sessions for the loose-end
  correction, 130 in 84 for naming an unloaded skill, 11 in 10 for
  point-in-time content in a skill) and, after the period, the recount
  with the same command and a `--since` argument.
- The whole hook suite, `smith-ctx-claude/scripts/tests/run-all.sh`, passes
  with the new tests listed in it.
