# Plan: move the always-loaded rules to atomic skills and hooks (from intent.md 2026-11-25)

> What is asked for, and why, in `intent.md`. This plan holds the rule
> inventory, the criterion that sorts it, and the order of the move.

## Glossary

- **Always-loaded skill**: a skill named on the "Always loaded" line of
  the repository's `AGENTS.md` (read as `~/.smith/CLAUDE.md`), so every
  session reads it: `smith-principles`, `smith-standards`,
  `smith-guidance`, `smith-ctx`.
- **Atomic skill**: one operation or procedure per skill, with a
  description that says only when to use it ("Use when ..."), backed by a
  hook or test wherever the rule is mechanically checkable.
- **Rule**: one bullet, numbered item, paragraph or fenced block of an
  always-loaded skill's body, below its frontmatter, as the inventory
  script splits it (§Inventory method).
- **Pointer**: the one line an always-loaded skill keeps where a
  procedure left, naming the skill that now holds it and its trigger.
- **Stack**: a series of at most four pull requests that land in order,
  managed with `gh stack`, the GitHub command-line extension for stacked
  pull requests that `smith-gh-pr/SKILL.md` "Stacked PRs" describes, as
  in `docs/test-tooling/layout/plan.md` §Rules for cutting the work.
- Principle names in the `smith-principles` rows, each defined in
  `smith-principles/SKILL.md`: DRY (Don't Repeat Yourself), KISS (Keep It
  Simple, Stupid), YAGNI (You Aren't Gonna Need It), MECE (Mutually
  Exclusive, Collectively Exhaustive) and SINE (Simple Is Not Easy).
- Ralph loop: the iterative agent loop of the `ralph-loop` plugin, whose
  context rules live in `smith-ralph/SKILL.md`. Serena: the Serena MCP
  server for symbol-level code tools and project memories,
  `smith-serena/SKILL.md`.

## Rules for cutting the work

- One rule, or a tight group of rules that share one trigger, per stack.
- A rule's meaning does not change while it moves. The procedure skill
  starts as the moved wording; a rewording is its own pull request.
- Where a group has a hook or test, it lands before the pointer replaces
  the rule, so the always-loaded file never names enforcement that does
  not exist yet.
- Each pull request leaves the suite green and every named path resolving.
- Stacks one and two are planned now; each stack after them is planned
  in full only after the one before it lands, from what it taught. The
  end of each stack is a checkpoint with the owner.

## Classification criterion

Decided by the owner on 2026-11-25, accepting the drafted proposal.

A rule is a **procedure** when both hold:

1. Its trigger can be written as "Use when «an observable situation»":
   a tool call, an artifact or an event the agent can recognise at the
   moment it happens, such as "a command would erase a file" or "a write
   leaves this session".
2. It prescribes actions to carry out in that situation, in an order or
   as a checklist, rather than a standard to judge by.

Otherwise it is a **preference**: a way to think, write or judge that
applies in every task and that one tool call cannot show was followed.

A unit is **neither** when it carries no rule of its own: a heading or
label, a navigation link, a definition used by other rules, reference
data, a rationale, an example, or a "Before You Finish" line that
restates a rule above it. Each such row names which in the Class column.

Two borderline rules, as the inventory classifies them:

- `smith-guidance/SKILL.md:13-14`, "Read the relevant files before
  proposing a change; never assume their contents": classified
  **preference**. It names a moment ("before proposing a change") and an
  action ("read"), which would make it a procedure, but that moment comes
  in almost every task, so it works as a standing habit; Claude Code
  already refuses an Edit without a prior Read.
- `smith-principles/SKILL.md:34-35`, "Before removing something, state
  its purpose and why that purpose no longer holds (Chesterton's fence)":
  classified **procedure**. It sits among principles, but its trigger, a
  removal, is observable and it prescribes an action, stating the purpose.
  It is not moved (§Ranked stacks, "Procedure rules left in place"):
  with its checklist line `:49` it would save 48 tokens net, under the
  50-token threshold there.

## Inventory method

- Scope: the four always-loaded skills, at 3ebaac8d. `AGENTS.md` itself
  and `smith-ctx-claude`, which `AGENTS.md` "Platform Context" loads first
  on Claude Code, are outside it (`intent.md` §Open questions).
- Tokenizer: cl100k_base through `tiktoken`, the method commits a3e85af7
  (#299), ca7d3fbf (#304) and bee37de4 (#308) used. File totals count the
  whole file, frontmatter included, as those commits did; a rule's count
  covers its own lines.
- Splitting: a script reads each file's body and starts a new rule at each
  `- ` or `1. ` item and after each blank line or heading; continuation
  lines and fenced blocks stay with their rule. It reports, per file, the
  rule count, the tokens in rules and the tokens in the file, and refuses
  an annotation whose locator matches no rule. On 3ebaac8d it found 180
  rules and matched all 180 annotations. The script is not committed with
  this plan; a follow-up adds it under `smith-skills/scripts/` with a test
  before stack one re-measures (decided by the owner on 2026-11-25).
- Class, mechanical check and existing enforcement are annotated by hand,
  against the hooks table in `README.md` "Hooks (manual registration)",
  the hook reference `smith-ctx-claude/references/HOOKS.md`, the
  settings example in `smith-ctx-claude/REFERENCE.md`, and the tests under
  `smith-*/scripts/tests/`. Line locators in the tables below are at
  3ebaac8d; each stack re-reads them before it edits. "Mechanical
  check" is yes when a hook or test can decide the rule from a tool call
  or a file alone, partly when it can decide some cases, no otherwise.

## Inventory

| File | Rules | Tokens in rules | Tokens in file | Procedure rules (tokens) | Preference rules (tokens) | Neither (tokens) |
|---|---|---|---|---|---|---|
| `smith-principles/SKILL.md` | 25 | 462 | 526 | 2 (73) | 20 (335) | 3 (54) |
| `smith-standards/SKILL.md` | 42 | 1,091 | 1,163 | 4 (89) | 17 (643) | 21 (359) |
| `smith-guidance/SKILL.md` | 62 | 2,192 | 2,273 | 28 (1,262) | 20 (634) | 14 (296) |
| `smith-ctx/SKILL.md` | 51 | 775 | 866 | 11 (190) | 20 (243) | 20 (342) |
| **All four** | **180** | **4,520** | **4,828** | **45 (1,614)** | **77 (1,855)** | **58 (1,051)** |

Of the 180 rules, 12 (290 tokens) are mechanically checkable, 28 (1,124
tokens) partly, and 140 (3,106 tokens) not. 24 rules (918 tokens) have
a hook or test behind them, most for part of the rule only.
`smith-guidance` is 273 tokens above 2,000; the budget in `AGENTS.md` is
"<2000", so it must lose at least 274.

### `smith-principles/SKILL.md`

25 rules, 462 tokens in rules, 526 tokens in the whole file.

| Locator | Gist | Class | Mechanical check | Existing hook or test | Tokens |
|---|---|---|---|---|---|
| `:8-9` | Prerequisites and sources pointer | neither: navigation | no | none | 15 |
| `:13` | DRY before adding features | preference | no | none | 8 |
| `:14-15` | DRY is per piece of knowledge, not per code text | preference | no | none | 28 |
| `:16` | KISS: choose the simplest solution | preference | no | none | 10 |
| `:17` | Simplest in the SINE sense, not the most familiar | preference | no | none | 16 |
| `:18` | YAGNI: defer unneeded implementation | preference | no | none | 11 |
| `:19-20` | YAGNI presumes changeable code; does not excuse half-done work | preference | no | none | 29 |
| `:21` | Single Responsibility: one reason to change per module | preference | no | none | 11 |
| `:22-23` | A reason is a person or role asking for changes | preference | no | none | 22 |
| `:24` | Open/Closed | preference | no | none | 13 |
| `:25` | Liskov Substitution | preference | no | none | 15 |
| `:26` | Substitutable in behaviour, not only signature | preference | no | none | 16 |
| `:27` | Interface Segregation | preference | no | none | 12 |
| `:28` | Dependency Inversion | preference | no | none | 15 |
| `:29` | MECE: complete coverage without overlap | preference | no | none | 9 |
| `:30` | MECE: name the boundary or an "other" group | preference | no | none | 19 |
| `:31` | Occam's Razor: fewest assumptions | preference | no | none | 10 |
| `:32-33` | Occam applies among equally explanatory options only | preference | no | none | 25 |
| `:34-35` | Chesterton's fence: state purpose before removing | procedure | no | none | 25 |
| `:36-37` | Via negativa: say what a thing is not | preference | no | none | 21 |
| `:38` | Via negativa is not deletion | preference | no | none | 15 |
| `:39-40` | SINE: simple is not easy | preference | no | none | 30 |
| `:44` | Related link: smith-standards | neither: navigation | no | none | 15 |
| `:45` | Related link: smith-guidance | neither: navigation | no | none | 24 |
| `:49` | Before implementing: run the principles checklist | procedure | no | none | 48 |
| **Total** | | | | | **462** |

### `smith-standards/SKILL.md`

42 rules, 1,091 tokens in rules, 1,163 tokens in the whole file.

| Locator | Gist | Class | Mechanical check | Existing hook or test | Tokens |
|---|---|---|---|---|---|
| `:8-9` | Scope and prerequisites | neither: navigation | no | none | 31 |
| `:13-17` | No decorative emoji in code, logs, docs | preference | yes | none | 73 |
| `:18` | Minimal blank lines between code blocks | preference | partly | none | 9 |
| `:20` | Label "Inline Comments" | neither: heading | no | none | 5 |
| `:21` | No inline comments | preference | yes | inline-comment-lint (advisory) + inline-comment-lint.test.sh | 8 |
| `:22` | When a comment seems needed, ask the user instead | procedure | partly | inline-comment-lint (advisory) | 24 |
| `:23` | Code self-documents by naming and extraction | preference | no | none | 21 |
| `:24` | Exception: config value documentation | preference | yes | inline-comment-lint (advisory) | 15 |
| `:26` | Label "File Format" | neither: heading | no | none | 5 |
| `:27` | Exactly one newline at end of file | preference | yes | none | 12 |
| `:28` | Run formatters before commits | procedure | yes | none | 10 |
| `:29` | Descriptive names by language convention | preference | no | none | 8 |
| `:33-37` | Expansion rules cover every output, no internal exemption | neither: scope statement | no | none | 68 |
| `:39-41` | Expand every short form introduced, on first use | preference | partly | coined-shorthand-lint (advisory, index codes only) | 51 |
| `:42-45` | Keep the field's standing terms | preference | no | none | 64 |
| `:46-47` | Expand terms that fit neither group | preference | no | none | 32 |
| `:48-52` | Identifiers follow smith-style | preference | partly | branch-name-guard (branch names only) | 79 |
| `:53-58` | Name referenced works in full with gloss and locator | preference | no | none | 97 |
| `:59-61` | Replace index codes and coined names | preference | partly | coined-shorthand-lint (advisory) + coined-shorthand-lint.test.sh | 57 |
| `:62-64` | Expand standing terms when output leaves the repository | preference | no | none | 34 |
| `:65` | Say an expansion is unknown rather than guess | preference | no | none | 14 |
| `:66-67` | Scan output for short forms before calling it done | procedure | partly | coined-shorthand-lint (advisory) | 29 |
| `:68-69` | Glossary in addition to inline expansion | preference | no | none | 32 |
| `:73-74` | Timestamps: local timezone, ISO 8601 with offset | preference | partly | none | 37 |
| `:76` | Label "Examples" | neither: heading | no | none | 4 |
| `:77` | Python example of a local ISO 8601 timestamp | neither: example | partly | none | 21 |
| `:78` | JavaScript example of a local ISO 8601 timestamp | neither: example | partly | none | 43 |
| `:82` | Check existing scripts before creating new ones | procedure | no | none | 26 |
| `:86` | Related link: smith-principles | neither: navigation | no | none | 15 |
| `:87` | Related link: smith-style | neither: navigation | no | none | 16 |
| `:88` | Related link: smith-guidance | neither: navigation | no | none | 18 |
| `:89` | Related link: smith-dev | neither: navigation | no | none | 14 |
| `:90` | Related link: smith-tests | neither: navigation | no | none | 14 |
| `:91` | Related link: smith-git | neither: navigation | no | none | 14 |
| `:92` | Related link: smith-gh-pr | neither: navigation | no | none | 17 |
| `:93` | Related link: smith-gh-cli | neither: navigation | no | none | 17 |
| `:97` | Label "Before committing or sending" | neither: heading | no | none | 7 |
| `:98` | Checklist: no decorative emoji (restates 13-17) | neither: restatement | yes | none | 9 |
| `:99` | Checklist: one trailing newline (restates 27) | neither: restatement | yes | none | 7 |
| `:100` | Checklist: zero inline comments (restates 21) | neither: restatement | yes | inline-comment-lint (advisory) | 13 |
| `:101` | Checklist: shorthand expanded (restates 39-41) | neither: restatement | partly | coined-shorthand-lint (advisory) | 11 |
| `:102` | Checklist: ISO 8601 timestamps (restates 73-74) | neither: restatement | partly | none | 10 |
| **Total** | | | | | **1,091** |

### `smith-guidance/SKILL.md`

62 rules, 2,192 tokens in rules, 2,273 tokens in the whole file.

| Locator | Gist | Class | Mechanical check | Existing hook or test | Tokens |
|---|---|---|---|---|---|
| `:8-9` | Prerequisites and rationale pointer | neither: navigation | no | none | 27 |
| `:13-14` | Read files before proposing a change | preference | partly | none; Claude Code itself refuses an Edit without a prior Read | 17 |
| `:15-16` | Change only what the task needs | preference | no | none | 28 |
| `:17-18` | Remove what your change left unused; report the rest | preference | no | none | 23 |
| `:19-20` | Unrequested cleanup stays small | preference | no | none | 25 |
| `:21-22` | Follow existing style; still point out problems | preference | no | none | 23 |
| `:26-28` | Every source and finding has an openable locator | preference | partly | none | 43 |
| `:29-33` | Treat claims as unverified; quote sources; check outside systems | procedure | no | none | 87 |
| `:34-36` | Research current best practice before recommending | procedure | no | none | 35 |
| `:37-45` | No anthropomorphism, no first-person pronoun | preference | partly | none | 147 |
| `:46-48` | Use recorded identifiers, never coined synonyms | preference | no | none | 40 |
| `:49-53` | Read recorded decisions before explaining a surprise; confirm a check ran | procedure | no | none | 79 |
| `:57-58` | Own branch or worktree before the first edit | procedure | yes | branch-guard + branch-guard.test.sh | 31 |
| `:59-62` | Find the owner before proposing a change to shared things | procedure | no | none | 66 |
| `:63-66` | Ask before destructive or hard-to-reverse actions | procedure | partly | stack-merge-guard, amend-shared-commit-guard, gh-stack-guard (+ tests) | 54 |
| `:67-74` | Make every operation undoable: move or Trash, never erase | procedure | partly | no-erase greps over named files: move-to-temp.test.sh:64-66, set-aside.test.sh:159, write-checkpoint.test.sh:1093, skill-trigger-eval.test.sh:251 | 135 |
| `:75-78` | Commit, push, pull request, merge only on explicit instruction | procedure | partly | external-write-guard, skill-load-gate (+ tests) | 66 |
| `:80` | Label "External writes" | neither: heading | no | none | 14 |
| `:82-85` | Defines transaction and payload | neither: definition | no | none | 59 |
| `:86-89` | Show the payload and wait for a yes before the write | procedure | yes | external-write-guard (+ test) | 56 |
| `:90-96` | The only mechanics inside an approved transaction | procedure | partly | external-write-guard (+ test) | 99 |
| `:97-100` | Anything else needs a new yes | procedure | partly | external-write-guard (+ test) | 58 |
| `:101-102` | Retry a failed write once, then stop; NO-GO aborts | procedure | no | none | 32 |
| `:106-107` | Challenge assumptions; offer an alternative | preference | no | none | 20 |
| `:108-109` | Raise concerns; recommend with evidence | preference | no | none | 21 |
| `:110` | Judge before praising; never "Great idea!" | preference | partly | none | 15 |
| `:111` | Restate the strongest opposing view first | preference | no | none | 13 |
| `:112-113` | Keep a recommendation through one objection | preference | no | none | 21 |
| `:114` | Check own findings as hard as the user's | preference | no | none | 13 |
| `:115-116` | Disagreement in five steps | procedure | no | none | 25 |
| `:120-121` | Label "Before acting on something outside" | neither: heading | no | none | 27 |
| `:123-125` | Read what is recorded before acting | procedure | no | none | 36 |
| `:126-127` | List the full scope and get approval | procedure | no | none | 25 |
| `:129-130` | One decision per turn, each standing alone | procedure | partly | askuserquestion-arity (+ test) | 22 |
| `:132-133` | Decision: define the subject | procedure | no | none | 21 |
| `:134` | Decision: give its locator | procedure | no | none | 17 |
| `:135-136` | Decision: measured instance count | procedure | no | none | 28 |
| `:137-138` | Decision: options, recommendation, strongest counter | procedure | no | none | 22 |
| `:139-140` | Decision: limits and grounds | procedure | no | none | 19 |
| `:142` | Label "Ask or decide" | neither: heading | no | none | 6 |
| `:144-146` | When to ask instead of assuming | preference | no | none | 44 |
| `:147-149` | When to decide | preference | no | none | 41 |
| `:151-152` | On failure: one alternative, then stop and offer options | procedure | no | none | 26 |
| `:154-156` | Estimates as relative sizes, never invented numbers | preference | no | none | 36 |
| `:158-159` | Turn a vague ask into checkable criteria | procedure | no | none | 31 |
| `:161-162` | After completing: report done, remaining, confirmed vs assumed | procedure | no | none | 19 |
| `:164-166` | Defines a general correction | neither: definition | no | none | 43 |
| `:168-171` | Route a correction by its reach | procedure | no | none | 70 |
| `:172` | One rule per scope | preference | no | none | 15 |
| `:173-175` | Draft and show a rule; change only after approval | procedure | no | none | 40 |
| `:176-177` | Checkpoints and plans hold only a pointer to the rule | preference | no | none | 22 |
| `:179` | Label "Close gaps" | neither: heading | no | none | 11 |
| `:181-183` | Close a gap with full coverage before concluding | procedure | no | none | 50 |
| `:184-185` | Prefer a scripted full scan over sampling | preference | no | none | 27 |
| `:186` | Report done only after verification | procedure | no | none | 13 |
| `:190` | Pointer to In-Band Progress reference | neither: navigation | no | none | 11 |
| `:194-195` | Related link: smith-validation | neither: navigation | no | none | 29 |
| `:196` | Related link: smith-subagents | neither: navigation | no | none | 18 |
| `:200` | Checklist: files read, approval (restates 13-14, 126-127) | neither: restatement | no | none | 12 |
| `:201` | Checklist: one decision (restates 129-130) | neither: restatement | partly | askuserquestion-arity | 12 |
| `:202` | Checklist: payload shown (restates 86-89) | neither: restatement | yes | external-write-guard | 14 |
| `:203` | Checklist: verified before done (restates 186) | neither: restatement | no | none | 13 |
| **Total** | | | | | **2,192** |

### `smith-ctx/SKILL.md`

51 rules, 775 tokens in rules, 866 tokens in the whole file.

| Locator | Gist | Class | Mechanical check | Existing hook or test | Tokens |
|---|---|---|---|---|---|
| `:8` | Prerequisites pointer | neither: navigation | no | none | 13 |
| `:12` | Agent checks context and recommends | preference | no | none | 17 |
| `:14` | Context lifecycle stages | neither: definition | no | none | 21 |
| `:16` | How to check context usage | procedure | no | none | 18 |
| `:18` | Agent recommends, user executes the reset | preference | no | none | 17 |
| `:22-24` | Claude Code thresholds and commands | neither: reference data | yes | context-warning.sh, enforce-clear.sh (+ tests) | 42 |
| `:25` | Kiro thresholds and commands | neither: reference data | no | none | 20 |
| `:26` | Cursor thresholds and commands | neither: reference data | no | none | 22 |
| `:30` | Label "Loading order" | neither: heading | no | none | 9 |
| `:31` | Loading order 1: metadata scan | preference | no | none | 13 |
| `:32` | Loading order 2: targeted read | preference | no | none | 12 |
| `:33` | Loading order 3: full file only when modifying | preference | no | none | 11 |
| `:34` | Loading order 4: broad exploration to a subagent | preference | no | none | 15 |
| `:36` | Label "Rules" | neither: heading | no | none | 4 |
| `:37` | Grep before reading whole directories | preference | no | none | 10 |
| `:38` | Targeted sections over full files | preference | no | none | 12 |
| `:39` | Reuse files already read | preference | no | none | 15 |
| `:43` | Prefer Serena tools when available | preference | no | none | 15 |
| `:45` | Why Serena; Kiro pointer | neither: rationale | no | none | 34 |
| `:47` | Label "Tool preference" | neither: heading | no | none | 5 |
| `:48` | Reading tool order | preference | partly | none | 20 |
| `:49` | Writing tool order | preference | partly | none | 23 |
| `:50` | Claimed context saving | neither: rationale | no | none | 15 |
| `:54` | Label "Always preserve" | neither: heading | no | none | 5 |
| `:55` | Preserve task goals | preference | no | none | 4 |
| `:56` | Preserve file:line locations | preference | no | none | 6 |
| `:57` | Preserve architectural decisions | preference | no | none | 5 |
| `:58` | Preserve incomplete work | preference | no | none | 5 |
| `:60` | Label "Always discard" | neither: heading | no | none | 5 |
| `:61` | Discard verbose tool outputs | preference | partly | tool-output-hygiene (advisory, output over 5K tokens) | 6 |
| `:62` | Discard failed explorations | preference | no | none | 5 |
| `:63` | Discard redundant reads | preference | no | none | 7 |
| `:65` | Reference by file:line, not embedded content | preference | no | none | 25 |
| `:69-72` | Ralph loop: persist state before a reset | procedure | no | none | 60 |
| `:74` | Pointer to smith-ralph | neither: navigation | no | none | 20 |
| `:78` | Related link: smith-guidance | neither: navigation | no | none | 14 |
| `:79` | Related link: smith-ctx-claude | neither: navigation | no | none | 26 |
| `:80` | Related link: smith-ctx-cursor | neither: navigation | no | none | 24 |
| `:81` | Related link: smith-ctx-kiro | neither: navigation | no | none | 29 |
| `:82` | Related link: smith-serena | neither: navigation | no | none | 18 |
| `:86` | Label "Proactive context checks" | neither: heading | no | none | 7 |
| `:87` | Check context periodically | procedure | partly | context-warning.sh | 11 |
| `:88` | At warning: recommend reset with retention criteria | procedure | partly | context-warning.sh | 13 |
| `:89` | At critical: urgently recommend | procedure | partly | enforce-clear.sh | 12 |
| `:90` | User executes; agent continues | procedure | no | none | 12 |
| `:92` | Label "Before recommending context reset" | neither: heading | no | none | 9 |
| `:93` | Prepare: task summary | procedure | no | none | 5 |
| `:94` | Prepare: file paths with lines | procedure | no | none | 7 |
| `:95` | Prepare: design decisions | procedure | no | none | 5 |
| `:96` | Prepare: remaining todos | procedure | no | none | 4 |
| `:98-102` | Recommendation message format | procedure | no | none | 43 |
| **Total** | | | | | **775** |

## Files that change

This pull request adds only `docs/skill-atomization/intent.md` and
`docs/skill-atomization/plan.md`. The stacks below change, each in its
own pull requests:

- `smith-guidance/SKILL.md`, `smith-ctx/SKILL.md`: a rule replaced by its
  pointer. `smith-standards/SKILL.md` keeps its text; a new lint backs
  three of its preferences (rank 5).
- One new `smith-«name»/SKILL.md` per procedure skill, and its trigger in
  `smith-ctx-claude/skill-triggers.json` and
  `smith-ctx-claude/REFERENCE.md`.
- New hooks under `smith-ctx-claude/scripts/`, and the rank 5 lint under
  `smith-standards/scripts/` beside `inline-comment-lint.mjs`, each listed
  in `README.md` "Hooks (manual registration)" and in its own skill's
  `references/HOOKS.md`, with a test in its folder's
  `tests/`.
- Tracked scripts and tests that erase files (stack one).

## Order of work

### Stack one: undoable operations

Rule: `smith-guidance/SKILL.md:67-74`, "Make every operation undoable",
135 tokens. Its stack was decided by the owner.

1. **Scan and convert erasing calls in tracked code, plus a test against
   new ones.** Two scans of the 181 tracked `.sh`, `.mjs`, `.js`, `.py`
   and `.bash` files on 3ebaac8d, each with `grep -nE`:
   - `(^|[^a-zA-Z_.-])rm (-[a-zA-Z]+ )*[^ ]|unlinkSync|rmSync|rmdirSync|unlink\(|shutil\.rmtree|os\.remove|fs\.rm\(`
     matched 26 lines in 9 files;
   - the whole words `rm|unlink|rmSync|unlinkSync|rmdirSync|rmtree|os\.remove`
     (`grep -nwE`) matched 49 lines in 14 files.

   Both find the same eight erasing calls in code:
   `smith-ctx-claude/scripts/tests/auto-context-reset-conditions.live-eval.mjs:135,207,426,602`
   and `smith-ctx-claude/scripts/tests/auto-context-reset.live-eval.mjs:178,192,195,298`.
   Every other match is a string, a comment, a test case, an existing
   no-erase grep, or a removal the owner ruled rebuildable: `git rm` in a
   fixture repository, `docker rm` and `docker run --rm`, and `claude rm`
   without its discarding flags. `find -delete`, `git clean -f`,
   `truncate` and `shred` appear in no code outside strings and test
   cases. Four tests already grep for erasing calls in named files:
   `smith-ctx-claude/scripts/tests/move-to-temp.test.sh:64-66` (four
   files: `lib-context.sh` and three hooks),
   `smith-ctx-claude/scripts/tests/set-aside.test.sh:159`,
   `smith-checkpoint/scripts/tests/write-checkpoint.test.sh:1093` and
   `smith-ctx-claude/scripts/tests/skill-trigger-eval.test.sh:251`.
   The step converts each erasing call to a move into a `mktemp -d`
   folder or `/usr/bin/trash`, except the ones the rule calls undoable:
   `auto-context-reset.live-eval.mjs:195` is `rmdirSync` of an empty
   folder. Whether `auto-context-reset-conditions.live-eval.mjs:135`, which
   removes whatever symbolic link sits at the eval's skills path, is
   undoable is decided in this step, from whether the link's target
   survives. It replaces the
   four greps with one test over every tracked script, with an allowlist
   for the undoable cases.
2. **A PreToolUse erase-guard hook on Bash commands.**
   `smith-ctx-claude/scripts/erase-guard.mjs`, reading the command through
   `smith-ctx-claude/scripts/lib/shell-scan.mjs`, as
   `attribution-guard.mjs` (run by the registered `attribution-guard.sh`)
   and `skill-load-gate.mjs` do. It denies
   `rm`, `unlink`, `shred`, `find -delete` and `git clean -f`, and names
   the move or `/usr/bin/trash` in its reason. It matches `rm`, `unlink`
   and `shred` only as the command word, so the subcommands the owner
   ruled rebuildable stay allowed: `docker rm`, `docker run --rm`,
   `claude rm` and `git rm`. Two flags of those subcommands discard work
   and are denied: `claude rm` with `--discard-unpushed` or
   `--force-remove-worktree`, and `git rm` with `-f` or `--force`; without
   `-f`, git refuses to remove a file whose content differs from the
   committed one. It allows `rmdir`. Its tests show each allowed and each
   denied form. A command cannot show whether what it erases exists
   elsewhere, so the hook states that it judges the command's name.
   Decided by the owner on 2026-11-25: the hook denies
   rather than asks, because an approval prompt mid-build blocks parallel
   sessions (`smith-sdlc/SKILL.md` Stage 3).
3. **The procedure skill.** `smith-undoable`, holding the rule's current
   wording, its trigger ("Use when a command, script, hook or test would
   delete, overwrite or truncate a file"), and the hook's limits. Name and
   description decided by the owner on 2026-11-25.
4. **A one-line pointer in smith-guidance.** The rule at
   `smith-guidance/SKILL.md:67-74` becomes one line naming the skill and
   its trigger, about 25 tokens: the file falls from 2,273 to about 2,163,
   still over budget.

### Stack two: external writes

Rules: `smith-guidance/SKILL.md:75-78` and the "External writes" block at
`:80-102`, with its checklist line `:202`: 8 rules, 398 tokens. Hooks
already behind it: `smith-ctx-claude/scripts/external-write-guard.mjs`
and `skill-load-gate.mjs`, each with a test under
`smith-ctx-claude/scripts/tests/`; `attribution-guard.sh` checks only the
attribution of the same writes' text.

1. List which of the rules' cases the two hooks already decide and
   which they cannot, from `smith-ctx-claude/references/HOOKS.md` and the
   tests; add test cases for any decidable case not yet covered.
2. Move the block into a procedure skill, triggered "Use when a commit,
   push, pull request, merge, comment, ticket or message would leave this
   session". The `smith-guidance` "Safety Rules" keep the definition of a
   transaction only if a preference still cites it.
3. Replace the block with its pointer. `smith-guidance` falls to about
   1,790 tokens, or about 1,850 if step 2 keeps the 59-token definition
   at `:82-85`; either is under budget.

### Ranked stacks

Each candidate is ranked first by how much of it a hook or test can
check, then by its net saving, its tokens less a 25-token pointer.
Checkability comes first because a group with a hook behind it gains
enforcement as well as tokens. The checkability order is: checkable with
an existing hook, checkable with no hook yet, partly checkable, not
checkable. Stacks one and two come first, ahead of this order: stack one
by the owner's decision of 2026-11-25, and stack two because its net
saving, about 373 tokens, is the largest and brings `smith-guidance`
under budget after stack one. The order ranks the rest from 3.

A group moves its procedure rules and the headings, definitions,
reference data and restatements that serve only them; a preference stays in the always-loaded file even
when it sits beside a procedure, such as `smith-guidance/SKILL.md:144-149`
(when to ask or decide), `:172` and `:176-177` with the definition they
cite at `:164-166`, `:184-185` with its heading `:179`, and the checklist
line `:200`, which restates the preference `:13-14` and the procedure
`:126-127`; rank 8 cuts it to its first half. A
mechanically checkable preference gains a hook or test and stays.

| Rank | Group | Rules (locators) | Tokens | Net saving | Mechanical check | Existing hook or test |
|---|---|---|---|---|---|---|
| 3 | Context reset | `smith-ctx/SKILL.md:16, 22-26, 69-74, 86-102`; the thresholds at `:22-26` move to the platform skills | 310 | about 285 | yes for the Claude Code thresholds | `context-warning.sh`, `enforce-clear.sh` and their tests |
| 4 | Branch, ownership and destructive actions | `smith-guidance/SKILL.md:57-66` | 151 | about 126 | yes for the branch rule, partly for the rest | `branch-guard`, `stack-merge-guard`, `amend-shared-commit-guard`, `gh-stack-guard` |
| 5 | File hygiene lint, no move | backs the preferences `smith-standards/SKILL.md:13-17, 27, 73-74`, which stay | 0 | none | yes: emoji, trailing newline; partly: timestamp format | none; a new lint |
| 6 | Decision request | `smith-guidance/SKILL.md:129-140, 201` | 141 | about 116 | partly: one question per call | `askuserquestion-arity` |
| 7 | Verification | `smith-guidance/SKILL.md:29-36, 49-53, 158-162, 181-183, 186, 203` | 327 | about 302 | no | none; `smith-validation` already holds its long form |
| 8 | Scope before acting | `smith-guidance/SKILL.md:120-127, 151-152` | 114 | about 89 | no | none |
| 9 | Correction routing | `smith-guidance/SKILL.md:168-171, 173-175` | 110 | about 85 | no | none |

Rank 3 moves reference data that serves only its procedures: the
per-platform thresholds at `smith-ctx/SKILL.md:22-26`. Each platform
skill already states its own: `smith-ctx-claude/SKILL.md:16-18`,
`smith-ctx-cursor/SKILL.md:12` and `smith-ctx-kiro/SKILL.md:88-91`.
Cursor's "60-70%" there differs from the "70%" at `smith-ctx/SKILL.md:26`;
the stack settles which holds before it moves the line.

Procedure rules left in place: five small groups, each saving under 50
tokens net once a pointer replaces it:
`smith-standards/SKILL.md:66-67, 101` (the shorthand scan, a procedure,
and its checklist line, 40 tokens), `smith-standards/SKILL.md:22, 82` (ask
before commenting, check existing scripts first, 50),
`smith-standards/SKILL.md:28` (run formatters before commits, 10),
`smith-principles/SKILL.md:34-35, 49` (removal check and the principles
checklist, 73) and `smith-guidance/SKILL.md:115-116` (disagreement, 25).

## End state

Estimated from the inventory, with a 25-token pointer per moved group:

| File | Now | After stacks one to nine | Budget |
|---|---|---|---|
| `smith-principles/SKILL.md` | 526 | 526 | under 2,000 |
| `smith-standards/SKILL.md` | 1,163 | 1,163 | under 2,000 |
| `smith-guidance/SKILL.md` | 2,273 | about 1,070 | under 2,000 |
| `smith-ctx/SKILL.md` | 866 | about 580 | under 2,000 |

Each always-loaded file holds preferences, the definitions they cite,
pointers, and the procedure rules left in place above. Every moved
procedure lives in an atomic skill whose description says only when to
use it, and every mechanically checkable case of a moved group, and of
the rank 5 preferences, has a hook or test behind it.

## Risks

- A pointer is weaker than the rule it replaces: on Cursor and Kiro no
  hook runs, and the agent must follow the pointer to read the procedure.
  The skill-router trigger table is the safety net on Claude Code only.
- A hook that judges command names refuses rebuildable cases and misses
  erasures by other means, such as a redirection that truncates a file or
  a `mv` over an existing file. Each hook names what it cannot see.
- The estimates assume a 25-token pointer and unchanged wording; a stack
  re-measures before and after with the same tokenizer.
- The criterion leaves the agent to judge what counts as an observable
  situation; a different reading moves rows between the
  procedure and preference classes and re-ranks the stacks.

## Proof

- Each stack's pull request states the always-loaded file's token count
  before and after, counted with cl100k_base over the whole file.
- Each hook lands with a test that shows it denying or asking on the
  cases it decides and passing the cases the rule calls undoable or
  approved.
- The end-state table is re-measured after the last stack; every file is
  under 2,000 tokens.
