---
name: smith-dialectic
description: Socratic interview that stress-tests a plan. Use when the user asks to grill, challenge, interrogate or stress-test a plan, to play devil's advocate, or wants shared understanding before implementing.
---

# Socratic Plan Interview

**Scope:** Relentless Socratic questioning of user's plan against project docs and code
**Prerequisites:** @smith-guidance/SKILL.md (Anti-Sycophancy)
**Based on:** [mattpocock/skills grilling](https://github.com/mattpocock/skills/blob/7739eaed7f8f3915437a8def198a6d0d7206dbc7/skills/productivity/grilling/SKILL.md)

## CRITICAL: Interview Protocol

**A subagent given a written plan follows Subagent Mode instead:**
`@smith-dialectic/SKILL.md#subagent-mode-v1`.

**The interview targets the USER's plan, never a third party's work.**
To red-team FINDINGS instead — your own or a third party's — use
`@smith-verification` Adversarial Verification, not this interview.

Interview the user relentlessly about every aspect of their plan until reaching shared understanding. Walk down each branch of the design decision tree, resolving dependencies one by one.

**For each question:**
1. Ask ONE question at a time: each reply holds a single question, in one
   sentence with one question mark. A compound question, a list of
   sub-questions and a follow-up such as "and what is driving this?" are
   each a further question; keep them for later replies
2. Provide your recommended answer: the answer to that question that the
   evidence supports best, not advice on what to do meanwhile ("hold off
   until this is settled" answers nothing)
3. Wait for user feedback before continuing: the reply ends after the
   question and its recommended answer
4. If the question can be answered by exploring the codebase, explore the codebase instead of asking

**Before starting, confirm scope:**
- What plan/design is being stress-tested?
- Which project docs to use as evidence? (default: CLAUDE.md + README)

**Keep the interview scoped and adversarially honest:**
- Evaluate only the user's own plan, never a third party's work
- Ask open-ended Socratic questions rather than using checklist-audit pass/fail grading or scoring rubrics
- Confirm the user's objective before expanding scope
- Challenge substantively rather than rubber-stamping ("looks good")
- Ask one question per response, not a batch

<a name="subagent-mode-v1"></a>
## Subagent Mode

A subagent given this skill and a written plan, and any thread asked to
return its result to the main thread, runs no interview and
asks nobody, neither the user nor the main thread: it cannot ask the
user, and it cannot know which questions the conversation has already
settled. Its return, below, replaces every step of this skill that
asks, waits for or confirms with the user, in any section.

- Read the plan and the evidence it names (project docs, code)
- Return the assumptions the plan rests on, each with:
  - **Evidence**: one of two forms and no other. Either a `path:line`
    or URL that supports or contradicts it; a path always carries its
    line number. Or, where the search found nothing (no caller, no
    mention), the words "none found" and the files read
  - **If wrong**: what in the plan breaks; a claim whose failure breaks
    nothing is not an assumption the plan rests on, so leave it out
  - **Confidence**: exactly one of high, medium or low that the
    assumption holds, given the evidence found, and low where none was
    found; the one word alone, never another word or a range. It rates
    each assumption, never the plan, so the ban on scoring rubrics above
    does not apply
- Return the questions in dependency order (a question whose answer
  hinges on another comes after it), each with:
  - **Recommended answer**: an answer to the question itself, the one
    the evidence supports best; where the evidence is silent, the answer
    that leaves the plan safest. "Unknown" and an instruction to the
    plan's author are not answers
  - **Why it changes the plan**: the step of the plan that each answer
    changes, named by its number or heading for every question; a risk
    stated without the step it changes does not count
- Add nothing after the listed questions: no closing question and no
  condition that someone must answer before work continues. The
  recommended answers stand until the main thread says otherwise

**Main thread**: the thread that spawns the subagent invokes this skill
too, names it for the subagent with the written plan, and on return
drops the questions already settled in the conversation or in recorded
decisions, then asks the rest per the Interview Protocol.

## During the Interview

**Challenge against project docs:**
When the user's plan conflicts with CLAUDE.md, README, or project conventions, surface it immediately. "CLAUDE.md says X, but your plan assumes Y — which is right?"

**Sharpen fuzzy language:**
When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'service' — do you mean the API layer or the background worker? Those have different constraints."

**Discuss concrete scenarios:**
When relationships or dependencies are discussed, stress-test with specific scenarios. Invent edge cases that force the user to be precise about boundaries.

**Cross-reference with code:**
When the user states how something works, check whether the code agrees. Surface contradictions: "Your code does A, but you just said B — which is current?"

## Questioning Style

Socratic Method:

- **Clarify**: "What exactly do you mean when you say X covers Y?"
- **Challenge**: "The README says this requires A. Your plan assumes B. How do you reconcile?"
- **Evidence**: "Which doc supports this? Checked Z: no mention."
- **Implications**: "If this assumption is wrong, what breaks downstream?"

Maintain adversarial posture. Apply smith-guidance Anti-Sycophancy rules throughout.

## Related

- @smith-guidance/SKILL.md - Anti-Sycophancy (foundation)
- `@smith-analysis/SKILL.md` - Constructive reasoning (complement)
- `@smith-clarity/SKILL.md` - Cognitive traps (defensive complement)
- `@smith-verification/SKILL.md` - Hypothesis testing; adversarial verification of findings

## Before You Finish

**In Subagent Mode:** finish with the return that Subagent Mode
specifies; the list below is for the interview.

**When conducting a dialectic session:**
1. Confirm user's plan and doc scope before starting
2. Read all relevant project docs + explore code
3. Walk the design decision tree branch by branch
4. One question at a time, with your recommended answer
5. Challenge language, assumptions, and claims against evidence
6. Continue until shared understanding is reached
