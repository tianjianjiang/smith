---
name: smith-validation
description: Validation of fitness for intended use, in the stakeholder's own words. Use when checking a plan, document, deliverable or revision against the request it answers, when a revision may have dropped or replaced part of that request, or before handing a page to a reader who has not seen the work. Whether the work meets its specification and its claims hold is the separate question of verification; load smith-verification for it.
metadata:
  smith-question: validation
---

# Validation

**Scope:** Fitness for intended use: does the object serve the use its
stakeholder asked for, judged against the stakeholder's own words
**Prerequisites:** @smith-guidance/SKILL.md

<a name="critical-rules-v1"></a>
## Critical Rules

- Judge fitness against the request as written, never against a summary
  or a restatement of it
- A requested element that a revision drops or replaces is a fitness
  defect, even when every claim in the revision is true, unless the
  stakeholder approved the drop or the replacement; cite that approval
- Rewording that leaves every requested element served is not a defect:
  "can you write up the plan?" is served by a written plan without the
  word "can"
- Verification and validation answer different questions; run each that
  applies, and report each under its own name

<a name="quote-the-request-v1"></a>
## Quote the Request Verbatim

- Before judging, quote the stakeholder's words verbatim, with a locator
  a reader can open: a message, a ticket, a plan line (`path:line`)
- Quote every request the object answers, including later
  clarifications, each with its own locator
- Where the words cannot be found, say "request not located" and stop:
  a paraphrase from memory is not the request
- Keep the quote unedited: no trimming of clauses, no normalized
  wording, no merged sentences

<a name="requested-elements-v1"></a>
## Check Each Requested Element

- Split the quote into its elements: each noun the stakeholder asked
  for, each verb they asked to happen, each constraint and each
  question
- Mark each element with a verdict and its evidence (`path:line` or a
  quoted passage of the object):
  - served: the object delivers it as asked
  - not served: the object omits it
  - changed: the object delivers something else in its place
- A not served element (a dropped word) or a changed element (a
  replaced word) is a defect unless the stakeholder approved the drop or
  the replacement; cite that approval
- For a revision, compare each element with the version before it too:
  an element served before and not served after is a regression; record
  it as not served, cite the version that served it, and treat it as a
  defect under the same approval rule
- Example: the request asks for "perspectives"; the revision offers
  "options". The element "perspectives" is changed, so the revision
  fails fitness although every option it lists is accurate

<a name="cold-reader-method-v1"></a>
## Cold Reader Method

- Hand the object, and only the object, to a fresh subagent that has
  not seen the conversation, the plan or the request (blind spawn per
  `@smith-subagents/SKILL.md`)
- Ask it to report:
  - every term or code it cannot resolve from the page alone
  - the purpose it reads, stated briefly
  - for each decision the object asks of its reader, whether the page
    alone gives enough to answer it, and what is missing when not
- Compare the purpose it reads with the quoted request, as a test that
  can refute the page (`@smith-analysis/SKILL.md#hypothesis-testing-v1`):
  a mismatch is a fitness defect of the object, not of the reader
- An author fixes each unresolvable term and each unanswerable decision
  in the object, then runs a fresh cold reader on the result; reuse of
  the same subagent is not blind
- A reviewer that may not edit the object reports each as a finding
  instead, with the term or decision and what the page lacks
- Where no subagent tool exists, say so and mark the cold reading as
  not run; a self-reading by the author is not a cold reading

<a name="fitness-versus-verification-v1"></a>
## Fitness Versus Verification

- Verification and validation are two questions about the same object:
  - Validation (fitness): does the object serve the intended use, in
    the stakeholder's own words; this skill asks it
  - Verification: does the object meet its stated specification, and
    are its claims supported; `@smith-verification/SKILL.md` asks it
- A method is chosen per check, apart from the question it serves: the
  cold reader above is one way to check fitness, and the ways to check
  a specification or a claim are listed in
  `@smith-verification/SKILL.md#methods-v1`
- The names come from the systems and software engineering vocabulary
  (https://pascal.computer.org/sev_display/index.action); the questions
  above are this skill's working reading of them, not quotations of its
  definitions
- An object can pass verification and fail validation: a page whose
  every claim is sourced (verified) can still answer a question the
  stakeholder did not ask (not fit)

<a name="related-v1"></a>
## Related

- `@smith-verification/SKILL.md` - Verification of claims, findings,
  status reports and requirements
- `@smith-analysis/SKILL.md#hypothesis-testing-v1` - Strong Inference
  and falsification, which the cold reader comparison applies
- `@smith-subagents/SKILL.md` - Blind subagent spawns and returns
- @smith-guidance/SKILL.md - Recorded identifiers, locators for every
  finding

<a name="before-you-finish-v1"></a>
## Before You Finish

- Quoted the stakeholder's words verbatim, each with a locator
- Gave every requested element a verdict (served, not served, changed)
  with evidence, and recorded every regression as not served
- Treated every dropped (not served) or replaced (changed) element as a
  defect, unless the stakeholder's approval of it is cited
- Ran a cold reader on the object alone, or said why none ran, and
  fixed (author) or reported (reviewer) each gap it found
- Reported fitness and verification results under separate names
