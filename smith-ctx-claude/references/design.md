# Claude Code steering — Design (ADR log)

> Per-feature contracts live in each change's spec.md; this doc owns the
> *why* for decisions that outlive any single one of them.

The subsystem is what steers the agent under Claude Code: the skills, the
hooks, and the profile settings that register them. ADR stands for
Architecture Decision Record; the format is defined in
`smith-sdlc/references/PLAYBOOK.md`.

How evidence is cited here. A source carries its URL and the quoted
passage. A measurement is not recorded in this log: the entry names the
command or the record file that reproduces it. The counts over session
history come from

    node smith-ctx-claude/scripts/correction-census.mjs --until 2026-10-01T21:08:00.000Z

which reads the personal profile's sessions and prints counts only. That
run is the baseline, and `instruction-enforcement/plan.md` states its
figures. Its matching rules are the regular expressions at the top of that
script, and its output says what the count leaves out.

## Decision index

- [ADR-001 — Where a rule lives](#adr-001)
- [ADR-002 — A judged check must pass a replay before it may refuse a turn](#adr-002)
- [ADR-003 — Skill loading is enforced at the governed action](#adr-003)
- [ADR-004 — Skill files hold no point-in-time content](#adr-004)
- [ADR-005 — The outcome is the owner's corrections, recounted](#adr-005)

## ADR-001

**Title**: Where a rule lives

**Context and problem**: The owner repeated three corrections across many
sessions. Every earlier fix added text for the agent to read: a paragraph in
a skill, a rule file, a memory note. In the baseline the owner still points
at a loose end and still names a skill the agent had not loaded.

**Decision drivers**:
- Instruction text is advisory. Claude Code documentation,
  https://code.claude.com/docs/en/memory.md: "Claude treats them as context,
  not enforced configuration. To block an action regardless of what Claude
  decides, use a PreToolUse hook instead."
- https://code.claude.com/docs/en/features-overview.md: "If a rule must hold
  every time, make it a hook rather than a prompt instruction."
- https://code.claude.com/docs/en/skills.md: "Claude skipped a rule that
  must hold every time: move the rule into a hook."
- Executable feedback beats the same rules as text. Sharma, "ContextCov"
  (https://arxiv.org/pdf/2603.00822, version 2): more patches were free of
  violations with executable checks than with the instruction file alone.
  Limits: the checks grade themselves, and every rule tested is one a
  program can decide.
- obra/superpowers writing-skills,
  https://raw.githubusercontent.com/obra/superpowers/main/skills/writing-skills/SKILL.md,
  on what not to write a skill for: "Mechanical constraints (if it's
  enforceable with regex/validation, automate it—save documentation for
  judgment calls)".
- Yang, He and Zhou (https://arxiv.org/html/2607.26819): "agents follow
  instructions that extend their work but not instructions that undo it".
- Two always-loaded rules pull against each other:
  `smith-guidance/SKILL.md` asks to "Report what was not verified" and, ten
  lines later, says "Close gaps — don't just disclose them".

**Considered options**:
- More or stronger text. Pros: cheap, no code. Cons: it is what was tried
  each time; McMillan (https://arxiv.org/pdf/2605.10039) finds compliance
  with instruction text varying widely by task.
- Everything into hooks. Pros: deterministic. Cons: most of the rules need
  judgement. In ActPlane (https://arxiv.org/html/2606.25189v2) pattern
  hooks reach about the same decision compliance as a model filter on a
  benchmark built around indirect execution paths, and neither reaches
  half.
- Place each rule by its kind. Pros: uses the deterministic layer where it
  is sound and nowhere else; the ActPlane authors say of rules about file
  content that they "are better served by linters and static analyzers".
  Cons: more parts to keep alive.

**Decision outcome**: Place by kind. A rule that must hold every time and
that a program can decide is a hook. A rule that must hold every time and
needs judgement is a model-judged check at the moment it applies, under
ADR-002. A procedure for one kind of task is a skill. A standing fact about
the machine or the owner is a short rule file. Anything true only at a point
in time is a commit message, a pull request or a reference document. A
correction the owner makes a second time becomes a hook, a judged statement
or an evaluation, not another paragraph.

**Consequences**: Always-loaded text shrinks as rules move into hooks. Each
hook needs a test and can fail open, so dead registrations have to be
reported at session start. Rules that need judgement stay weaker than rules
a program can decide.

## ADR-002

**Title**: A judged check must pass a replay before it may refuse a turn

**Context and problem**: Whether a last message leaves a loose end, or hands
the owner an item without its context, needs judgement. The harness offers a
prompt hook for that: a single call to a small model that can refuse the end
of a turn.

**Decision drivers**:
- A reviewing model can make results worse. ContextCov, section 4.3: the
  configuration in which a second model reviewed each patch left fewer
  patches clean than no feedback did, and often ran into the cap on review
  rounds.
- https://code.claude.com/docs/en/best-practices.md: "A reviewer prompted to
  find gaps will usually report some, even when the work is sound, because
  that is what it was asked to do."
- A phrase match is too blunt. Over the turn-final messages that the owner
  answered, the census's detector for a declared gap ("unverified", "not
  checked", "shall I check" and their Mandarin equivalents) fires on many
  sound ones, and it precedes only about half of the owner messages that
  point at a loose end.
- What the hook can see and do,
  https://code.claude.com/docs/en/hooks.md: it receives
  `last_assistant_message`; a prompt hook's `impossible` answer means
  "Claude Code then lets the turn end"; "Claude Code applies an
  8-consecutive-continuation cap".
- The documentation recommends such a gate
  (https://code.claude.com/docs/en/best-practices.md: a Stop hook "blocks
  the turn from ending until it passes"); none of the sources read measures
  its effect on loose ends.

**Considered options**:
- Register the prompt hook outright. Pros: simplest. Cons: unmeasured, and
  the one study of a reviewing model shows harm.
- Phrase matching only. Pros: deterministic. Cons: refuses many sound
  turns and misses about half of the cases.
- Register it as advice when it falls short. Pros: keeps some signal. Cons:
  advice from a judge that failed its test is the drift ContextCov measured.
- Gate registration on a replay. Pros: the decision rests on this owner's
  own history, and the census gives the totals the replay set must match.
  Cons: the bar is
  set by judgement.

**Decision outcome**: The prompt hook is registered only if, replayed over
the baseline's turn-final messages on the model it will use, it flags at
least half of the messages the owner answered by pointing at a loose end
and at most 10% of the others. Below that bar it is not registered in
any form. A command hook refuses only the narrow pattern of asking the owner
whether the agent should check something.

**Consequences**: The first two requirements of the instruction-enforcement
specification may end up resting on the command hook and on text alone. The
prompt hook judges the last message only, so a claim of "done" that earlier
output does not support, and a part of the request left unfinished
without being mentioned, are left to review and to the recount under
ADR-005. A changed prompt or model means a
new replay.

## ADR-003

**Title**: Skill loading is enforced at the governed action

**Context and problem**: The agent acts without loading the skill that
covers the task until the owner names it.

**Decision drivers**:
- Until this decision almost no description said when to use the skill;
  most bodies carried the condition in a `**Load if:**` line instead.
  Reproduce on commit `438aeb1` with `git grep -h '^description:' 438aeb1
  -- 'smith-*/SKILL.md'` and `git grep -l '^\*\*Load if:\*\*' 438aeb1 --
  'smith-*/SKILL.md'`. In the published libraries most or all descriptions
  say when to use the skill (https://github.com/anthropics/skills,
  https://github.com/openai/skills, https://github.com/obra/superpowers).
- The body is not read until the skill triggers. anthropics skill-creator,
  https://raw.githubusercontent.com/anthropics/skills/main/skills/skill-creator/SKILL.md:
  "All 'when to use' info goes here, not in the body", and "currently Claude
  has a tendency to 'undertrigger' skills".
- A good description helps and is not enough. Before the descriptions were
  shortened, most had a use-when clause (`git grep -il
  '^description:.*use when' '943d76e^' -- 'smith-*/SKILL.md'`), and the
  keyword router had already been added because, in the words of its commit
  `fb9bddd`, "smith skills under-trigger". In the baseline the router
  suggested the pull-request, development-workflow and naming skills in
  several times as many sessions as then loaded them.
- https://code.claude.com/docs/en/skills.md: Claude Code "drops some
  descriptions to fit the listing's character budget, which removes the
  keywords Claude needs to match your request".
- Rewritten descriptions raise the trigger rate and still leave skills that
  never trigger, the ones the entry file always loads among them.
  `smith-ctx-claude/scripts/skill-trigger-eval.mjs` measures it; the
  records are `instruction-enforcement/skill-trigger/before.jsonl` and
  `after.jsonl`, and `compare` on the two files prints the table. A
  condition the session cannot meet suppresses loading: "Use when Serena
  MCP is available" in a session without that server. An imperative clause
  raises it: "ALWAYS load before writing, resuming or updating a plan
  file".
- The skill listing of the personal profile is over its character budget
  with or without the smith descriptions, so no length of description
  makes it fit (`claude -p "say hi" --debug --debug-file «file»`, then
  search the file for "Skill listing").
  https://code.claude.com/docs/en/skills.md: "The budget scales at 1% of
  the model's context window. When the listing overflows, Claude Code
  drops descriptions starting with the skills you invoke least".
- Measured after the descriptions merged, the harness does drop by use. On
  the default model every smith description survives. On a model with a
  small context window the default budget is spent on the skill names and
  the built-in descriptions, and every smith description is dropped. A
  fixed budget well below the size of the full listing keeps every smith
  description on both and still drops those of plugin skills that are not
  used. `instruction-enforcement/plan.md`, under Risks, has the figures
  and how they were measured.
- A hook cannot load a skill.
  https://code.claude.com/docs/en/hooks-guide.md, "Limitations": command
  hooks "can't trigger `/` commands or tool calls."

**Considered options**:
- Restore the descriptions only. Pros: the native mechanism. Cons: the
  history above shows it was not enough.
- Force-load more skills. Pros: certain. Cons: the always-loaded files are
  already large (`cat smith-principles/SKILL.md smith-standards/SKILL.md
  smith-guidance/SKILL.md smith-ctx/SKILL.md AGENTS.md | wc -c`);
  obra/superpowers writing-skills marks an `@` link to a skill as bad:
  "(force-loads, burns context)".
- Rely on the keyword router. Pros: exists. Cons: advisory; most of its
  events do not follow a prompt the owner typed, and many of its
  suggestions name a skill already loaded in the session.
- Refuse the governed action until its skill is loaded, with descriptions
  and the router as aids. Pros: deterministic at the points where a skipped
  skill costs most. Cons: covers only tasks that have such an action.

**Decision outcome**: A table maps each governed action to its skill, and a
hook refuses the action while that skill is not loaded in the session.
Descriptions state what the skill is and when to use it, as a short noun
phrase and one use-when sentence that does not list the sections of the body, with no `**Load
if:**` line in the body; `skill-lint.mjs` reports a description without a
when-to-use clause, and a rewritten description is kept only where
`skill-trigger-eval.mjs compare` passes for its skill: the trigger count
did not fall and the near-miss count did not rise. The personal
profile sets `SLASH_COMMAND_TOOL_CHAR_BUDGET` to `20000` in the `env`
block of its `settings.json`: the smallest measured budget at which a
session on a model with a small context window keeps every smith
description, and lower than the default budget of the default model. The
listing stays over that budget, so the harness keeps dropping the
descriptions of the skills invoked least, and no plugin skill is hidden.
The router acts on owner-typed prompts only and never
suggests a loaded skill.

**Consequences**: A task with no governed action still depends on the
description and the router; the recount under ADR-005 shows whether that
holds. The table is one more thing to keep in step with the skills. The
descriptions take more of the listing than before. The listing stays over
its budget, so the descriptions of little-used skills are dropped in every
session. The budget covers the skill names, the built-in descriptions and
the descriptions used most, in that order; when skills are added or
descriptions grow it has to be measured again, or a smith description is
dropped without notice. A description must
not make its only condition depend on something the session may lack;
the description of `smith-serena` names conditions that hold without that
server: a prompt that mentions Serena, and phase and session boundaries.

## ADR-004

**Title**: Skill files hold no point-in-time content

**Context and problem**: Skill files had gathered dates, status, incident
accounts and pull-request references. Many of them carried a calendar date
or a pull-request or issue reference (`grep -c -E
'[0-9]{4}-[0-9]{2}-[0-9]{2}|\(#[0-9]+\)|\bPR
#?[0-9]+|pull/[0-9]+|issues/[0-9]+' smith-*/SKILL.md`); status wording and
incident accounts come on top and are counted by the lint. Two rules asked
for a retrieval date on every citation, and the rules that ask for a locator
on every claim listed a commit and a ticket among its kinds; none said where.

**Decision drivers**:
- Skill authoring best practices,
  https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md,
  section "Avoid time-sensitive information", and its checklist: "No
  time-sensitive information (or in 'old patterns' section)".
- openai skill-creator,
  https://raw.githubusercontent.com/openai/skills/main/skills/.system/skill-creator/SKILL.md:
  a skill "should not contain auxiliary context about the process that went
  into creating it".
- obra/superpowers writing-skills,
  https://raw.githubusercontent.com/obra/superpowers/main/skills/writing-skills/SKILL.md:
  "Skills are NOT: Narratives about how you solved a problem once".
- Owner decision: clean the skill files only; documents under `references/`
  stay as they are.

**Considered options**:
- Keep retrieval dates in skill files as part of the citation. Pros: the
  citation is complete where it is read. Cons: it is the content that goes
  stale, and the owner's words exclude dates.
- Move all point-in-time content out of the repository. Pros: nothing to
  go stale. Cons: the owner chose to keep the reference documents.
- Skill files keep the rule and the source's URL or path; dates, tool
  versions and history live under `references/`. Pros: the evidence stays
  reachable. Cons: a reader of the skill has to follow a link for the date.

**Decision outcome**: The third option, checked by a lint that runs in the
test runner and on every write to a skill file. The citation rules ask for a
retrieval date on every citation except in a skill file, and the locator
rules allow a skill file a URL or a path.

**Consequences**: An upstream issue or pull request that a rule still rests
on moves to a document under the skill's `references/` folder; what the
other removed lines recorded moves to the commit message of their removal.
The lint has to allow date formats given as examples and
placeholders. This log and the work documents beside it are where dated
evidence goes.

## ADR-005

**Title**: The outcome is the owner's corrections, recounted

**Context and problem**: Earlier fixes were declared done when the text was
merged. Nothing measured whether the owner stopped having to correct.

**Decision drivers**:
- The baseline named at the top of this log counts three corrections: the
  owner points at a loose end, names an unloaded skill, and objects to
  point-in-time content in a skill.
- The owner's stated outcome is to stop having to make the three
  corrections.
- Session content of other projects must not reach this public repository.
- A quiet fortnight proves little: the baseline spans hundreds of
  sessions.

**Considered options**:
- Tests and replay only. Pros: available at once. Cons: they show the parts
  work, not that the corrections stopped.
- A relative drop as the bar. Pros: reachable. Cons: the owner said stop,
  and a drop still leaves the owner correcting.
- Recount by the baseline's command, bar of zero, after 14 days and 200
  sessions. Pros: measures the stated outcome. Cons: strict; one correction
  means not reached.

**Decision outcome**: The third option. Each correction found in the
recount is tied to the requirement it shows broken, or stated as not
covered, which then opens a new intent. Only counts and error kinds are
written to the repository.

**Consequences**: The work is not finished at merge. The census script is a
maintained part of the subsystem, and its matching rules have to stay fixed
between baseline and recount.
