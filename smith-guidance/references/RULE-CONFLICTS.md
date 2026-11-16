# Rule Conflicts

**Scope:** Two written rules (skills, personal rule files, repository
instructions, recorded user decisions) that prescribe different actions
for one case
**Prerequisites:** @smith-guidance/SKILL.md

## Reconcile First

1. **List, change neither.** Write each conflict on one line, quoting
   both texts with their locators. Stop the work that depends on it
   while it is open. Let a script or lint find conflicts where it can,
   so detection does not depend on someone noticing.
2. **Confirm the conflict is real.** State what each rule governs and
   find one concrete case where the two prescribe different actions.
   With no such case, record "no conflict" with the reasoning and stop.
   Challenge whether a rule applies to the case, not the rule itself.
   Carry forward only conflicts an independent check confirmed.
3. **Trace each rule to its source and its Why.** Reconcile against the
   source, not one rule against the other: the user's words, their date
   and approval, and the failure the rule exists to prevent.
4. **Generate candidates that satisfy both Whys.**
   - Reframe: a disagreement often marks a missing distinction; name it
     instead of averaging the two rules
   - Merge: one rule that covers both cases
   - Scope: give each rule its own cases so they stop overlapping
   - Keep both readings, each with its counter-arguments, until decided
   Test every candidate against both Whys; judge it by the Why it serves
   worst. A candidate that passes both goes to the user as a proposal.

## Decide Second

5. **Apply only a recorded precedence.** The lower rule is adjusted;
   it is not diluted, reinterpreted or silently ignored. Changing the
   higher rule is a separate, explicit update.
6. **Without a recorded precedence, respect frozen text.** Text the user
   approved is frozen. Both frozen: ask the user with the quoted pair,
   the case, and why reconciliation failed. One frozen: amend the other
   and record the change. A fix that edits agent-context files (skills,
   rule files, AGENTS.md, CLAUDE.md) leaves the running task and is
   handled on its own.
7. **Classify conflicts in review and fix loops.** A finding whose fix
   would choose between rules is "conflict, to the user", ranked above
   "actionable". A reviewer who raises it again without new evidence
   does not reopen it.
8. **Write the outcome once.** One rule holds the decision with a
   precedence clause and a test of the case; the other points to it.
   Rewrite the item in place; never append an amendment.

## Example

- Conflict: a workflow-sizing rule allows a skeptic agent only where the
  output feeds an external write or a user decision; a verification rule
  requires a skeptic pass for a finding that contradicts a documented rule
- Real only where a finding contradicts a rule and the output is report
  only; a command whose output always feeds a user decision has none
- Whys: the first caps agent count after one verifier per candidate made
  a workflow too large; the second guards findings costly to get wrong
- Reframe: a skeptic pass is not a skeptic agent. Every qualifying
  finding gets the pass; passes are batched three to five per agent
- The candidate passes both Whys, so it goes to the user as a proposal

## Sources

- List contradictions, never auto-align: https://github.com/google/elephant-goldfish-model/blob/e9e1f06aa4e26e95cd4ed37210a0632202c429e9/skills/egm-draft/SKILL.md
- Constitution conflicts adjust the lower text: https://github.com/github/spec-kit/blob/c43849408ac0de2ca6a52f14eaae71449776057b/templates/commands/analyze.md
- Frozen human-owned intent: https://github.com/bmad-code-org/BMAD-METHOD/blob/e734d3ac3c0f4ea31cc2c2bbbe79e86e54f2cae6/skills/bmad-build/plan-template.md
- Defer fixes to agent-context files: https://github.com/bmad-code-org/BMAD-METHOD/blob/e734d3ac3c0f4ea31cc2c2bbbe79e86e54f2cae6/skills/bmad-build/step-04-review.md
- Reconcile classification order: https://github.com/addyosmani/agent-skills/blob/301b02b12bff98e4688e6984af6556802322bbde/skills/doubt-driven-development/SKILL.md
- Reframe and re-run rather than averaging: https://github.com/cursor/plugins/blob/6b0300214a09fd6029cfb7077043125758cd1fd2/pstack/skills/arena/SKILL.md
- Resolve contradictions against the source: https://github.com/cursor/plugins/blob/6b0300214a09fd6029cfb7077043125758cd1fd2/pstack/skills/how/references/explainer-prompt.md
- Challenge the inference, not the rule (GSN Community Standard v3): https://scsc.uk/r1386.pdf

## Before You Finish

- Conflict listed with both texts quoted; neither text changed
- Real case named, or "no conflict" recorded with the reasoning
- Both Whys written; candidates tested against both
- Outcome approved by the user, written once, with a test
