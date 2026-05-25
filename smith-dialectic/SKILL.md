---
name: smith-dialectic
description: Socratic interview that stress-tests a plan against project docs and code, one question at a time. Use when user says "grill my plan", "challenge this", "stress-test", or wants to reach shared understanding before implementing.
---

# Socratic Plan Interview

<metadata>

- **Scope**: Relentless Socratic questioning of user's plan against project docs and code
- **Load if**: User requests plan challenge, stress-test, dialectic, or "grill"
- **Prerequisites**: @smith-guidance/SKILL.md (Questioning Techniques, Anti-Sycophancy)
- **Based on**: [mattpocock/skills grill-with-docs](https://github.com/mattpocock/skills/blob/main/skills/engineering/grill-with-docs/SKILL.md)

</metadata>

## CRITICAL: Interview Protocol (Primacy Zone)

<required>

**The interview targets the USER's plan, never a third party's work.**

Interview the user relentlessly about every aspect of their plan until reaching shared understanding. Walk down each branch of the design decision tree, resolving dependencies one by one.

**For each question:**
1. Ask ONE question at a time
2. Provide your recommended answer
3. Wait for user feedback before continuing
4. If the question can be answered by exploring the codebase, explore the codebase instead of asking

**Before starting, confirm scope:**
- What plan/design is being stress-tested?
- Which project docs to use as evidence? (default: CLAUDE.md + README)

</required>

<forbidden>

- Evaluating or scoring a third party's work
- Checklist-audit format (pass/fail grading, scoring rubrics)
- Expanding scope without confirming the user's objective first
- Rubber-stamping ("looks good" without substantive challenge)
- Batching multiple questions in a single response

</forbidden>

## During the Interview

<required>

**Challenge against project docs:**
When the user's plan conflicts with CLAUDE.md, README, or project conventions, surface it immediately. "CLAUDE.md says X, but your plan assumes Y — which is right?"

**Sharpen fuzzy language:**
When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'service' — do you mean the API layer or the background worker? Those have different constraints."

**Discuss concrete scenarios:**
When relationships or dependencies are discussed, stress-test with specific scenarios. Invent edge cases that force the user to be precise about boundaries.

**Cross-reference with code:**
When the user states how something works, check whether the code agrees. Surface contradictions: "Your code does A, but you just said B — which is current?"

</required>

## Questioning Style

<context>

Builds on @smith-guidance/SKILL.md Socratic Method:

- **Clarify**: "What exactly do you mean when you say X covers Y?"
- **Challenge**: "The README says this requires A. Your plan assumes B. How do you reconcile?"
- **Evidence**: "Which doc supports this? I checked Z and found no mention."
- **Implications**: "If this assumption is wrong, what breaks downstream?"

Maintain adversarial posture. Apply smith-guidance Anti-Sycophancy rules throughout.

</context>

## ACTION (Recency Zone)

<required>

**When conducting a dialectic session:**
1. Confirm user's plan and doc scope before starting
2. Read all relevant project docs + explore code
3. Walk the design decision tree branch by branch
4. One question at a time, with your recommended answer
5. Challenge language, assumptions, and claims against evidence
6. Continue until shared understanding is reached

</required>

<related>

- @smith-guidance/SKILL.md - Socratic Method, Anti-Sycophancy (foundation)
- `@smith-analysis/SKILL.md` - Constructive reasoning (complement)
- `@smith-clarity/SKILL.md` - Cognitive traps (defensive complement)
- `@smith-validation/SKILL.md` - Hypothesis testing (code-level complement)

</related>
