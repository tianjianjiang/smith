# Cognitive Guards

<metadata>

- **Scope**: Guarding against cognitive traps in decision-making
- **Load if**: Making decisions, evaluating approaches, risk assessment
- **Prerequisites**: @talk.md

</metadata>

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

<related>

**Research:**

- Croskerry, P. (2003). Cognitive forcing strategies in clinical decision making
- Kahneman, D. & Tversky, A. (1979). Planning fallacy
- Goldratt, E. (1997). Critical Chain (Student Syndrome, Parkinson's Law)

**Related files:**

- @talk.md - Anti-sycophancy, questioning techniques
- @think.md - Pre-mortem analysis, constraint thinking

</related>
