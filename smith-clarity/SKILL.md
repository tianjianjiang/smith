---
name: smith-clarity
description: Cognitive trap detection and logic fallacy identification. Use when making decisions, evaluating approaches, risk assessment, or detecting faulty reasoning in arguments.
---

# Thinking Clarity

<metadata>

- **Scope**: Guarding against cognitive traps and logical fallacies in decision-making
- **Load if**: Making decisions, evaluating approaches, risk assessment, detecting faulty reasoning
- **Prerequisites**: @smith-guidance/SKILL.md

</metadata>

<context>

**Foundation**: Defensive thinking techniques - avoiding errors rather than constructing solutions.

**MECE relationship**:
- `@smith-analysis/SKILL.md` - Constructive thinking (how to reason)
- **smith-clarity** (this file) - Defensive thinking (what to avoid)
- `@smith-validation/SKILL.md` - Proving/testing (verifying correctness)

</context>

## Logic Fallacies

<required>

### Formal Fallacies (structural)

- **Affirming the consequent**: If A then B; B; therefore A (invalid)
- **Denying the antecedent**: If A then B; not A; therefore not B (invalid)
- **Non sequitur**: Conclusion doesn't follow from premises

### Informal Fallacies (content)

- **Appeal to authority**: Claim valid solely because expert said it
- **Appeal to popularity**: "Most developers use X" doesn't mean X is correct
- **Ad hominem**: Dismissing idea based on who proposed it
- **Straw man**: Misrepresenting position to argue against weaker version
- **False dilemma**: Presenting only two options when more exist
- **Red herring**: Irrelevant information to distract

### When Detecting User's Fallacy

1. Identify fallacy type (internally)
2. Address reasoning error, not label it
3. Provide evidence-based counter-reasoning
4. Respect user while correcting logic

</required>

## Cognitive Traps

<forbidden>

### Einstellung Effect

Mental fixation on familiar solutions.

**Mitigation**: Generate 2-3 alternatives before committing

### Confirmation Bias

Seeking info that confirms existing beliefs.

**Mitigation**: Actively seek disconfirming evidence

### Anchoring

Over-relying on first piece of information.

**Mitigation**: "What if my first hypothesis is completely wrong?"

### Premature Closure

Stopping at first plausible explanation.

**Mitigation**: "What else could explain this?" (ask repeatedly)

### Availability Bias

Choosing recent/memorable over most likely.

**Mitigation**: Consider base rates, not vivid examples

### Planning Fallacy

Underestimating time, cost, and risk while overestimating benefits.

**Mitigation**: Use reference class forecasting (how long did similar tasks take?)

### Student Syndrome

Delaying start until deadline approaches, wasting safety margin.

**Mitigation**: Start immediately with minimal viable step; no deadlines on tasks, only priorities

### Parkinson's Law

Work expands to fill the time available for completion.

**Mitigation**: Set aggressive (50% probability) estimates; aggregate buffers at project level

</forbidden>

## Cognitive Forcing Strategies

<required>

1. **Cognitive timeout**: Pause before finalizing any solution
2. **Metacognition**: "What am I assuming? What could I be missing?"
3. **Forced alternatives**: Generate 2-3 options before committing

**Implementation for agents**:

1. Before proposing solution: Generate alternatives
2. Before implementing: Ask "What could go wrong?"
3. After fixing bug: Verify fix addresses root cause, not symptom
4. When user agrees: Ask "Are there downsides we haven't considered?"

</required>

## ACTION (Recency Zone)

<required>

**When making decisions or evaluating reasoning:**
1. Pause before finalizing (Cognitive timeout)
2. Ask "What am I assuming? What could go wrong?"
3. Generate 2-3 alternatives before committing
4. Seek disconfirming evidence, not confirming evidence

</required>

<related>

- @smith-guidance/SKILL.md - Anti-sycophancy, HHH framework, exploration workflow
- `@smith-analysis/SKILL.md` - Pre-mortem analysis, constraint thinking
- `@smith-validation/SKILL.md` - Hypothesis testing, debugging

</related>
