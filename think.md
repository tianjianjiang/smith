# Thinking Frameworks

<metadata>

- **Scope**: Reasoning, problem decomposition, and analysis techniques
- **Load if**: Planning implementation, evaluating arguments, estimating scope, decomposing tasks
- **Prerequisites**: @talk.md

</metadata>

<context>

**Foundation**: Based on OODA Loop's Orient phase (Boyd) - the "cognitive engine" that drives decision-making through mental models, prior experience, and analysis/synthesis.

**When to use**: Problem framing, solution design, risk assessment, logical validation.

</context>

## Reasoning Patterns

<required>

### Deductive Reasoning

General principles to specific conclusions (logically certain):

**Pattern**: If all A are B, and C is A, then C is B.

1. Start with general premise (known to be true)
2. Apply to specific case
3. Derive guaranteed conclusion

**For coding**: "All API endpoints require authentication (premise). /users is an endpoint. Therefore /users requires authentication."

### Inductive Reasoning

Specific observations to general patterns (probabilistic):

**Pattern**: Observed A1, A2, A3... all have property B. Therefore all A probably have B.

1. Gather specific observations
2. Identify patterns
3. Form general hypothesis (may be wrong)

**For coding**: "These 5 failing tests all timeout after 30s. The timeout setting is probably too short."

**Caution**: Inductive conclusions can be wrong. "All observed swans are white" was disproven by black swans.

### Abductive Reasoning

Best explanation from incomplete observations (inference to best explanation):

**Pattern**: B is observed. A would explain B. Therefore A is probably true.

1. Observe surprising/unexpected result
2. Generate candidate explanations
3. Select most plausible explanation
4. Test to confirm or falsify

**For debugging**: "API returns 500 only on Mondays. Most likely: scheduled job causes resource contention."

</required>

## Problem Decomposition

<required>

### First Principles Thinking

Break down to fundamentals, reason up:

1. **Identify assumptions** - What do we take for granted?
2. **Decompose** - What are the fundamental truths?
3. **Reconstruct** - Build solution from first principles only

**For coding**: Instead of copying patterns, ask "What problem are we solving? What's the simplest solution?"

### Polya's 4-Step Method

Universally applicable problem-solving:

1. **Understand the problem**
   - What is the unknown? What are the data? What is the condition?
   - Can you restate in your own words?

2. **Devise a plan**
   - Have you seen this before? Know a related problem?
   - Can you solve a simpler problem first?

3. **Carry out the plan**
   - Execute each step, check as you go
   - Can you prove each step correct?

4. **Look back**
   - Can you check the result differently?
   - Can you use this for other problems?

</required>

## Estimation

<required>

### Fermi Estimation

Order-of-magnitude approximation with limited data:

1. Break complex question into simpler sub-questions
2. Make reasonable assumptions for each part
3. Combine estimates (multiply/add as appropriate)
4. Sanity check: Is result reasonable?

**For engineering**: "How many queries/second can this handle?"
- Break down: connections x queries/connection x time
- Estimate each factor with reasonable bounds
- Result: Order of magnitude (10s, 100s, 1000s)

</required>

## Constraint Thinking

<required>

### TOC Five Focusing Steps

Systematic bottleneck elimination (Goldratt):

1. **Identify** - Find the constraint limiting throughput
2. **Exploit** - Maximize constraint output without additional investment
3. **Subordinate** - Align everything else to support the constraint
4. **Elevate** - Increase constraint capacity if still limiting
5. **Repeat** - Find the new constraint (it will shift)

**For coding**: "What single factor is blocking progress? Focus there first."

### Three-Point Estimation (PERT)

Handle uncertainty with optimistic, likely, pessimistic:

- **O**: Best case (everything goes right)
- **M**: Most likely (typical scenario)
- **P**: Pessimistic (realistic worst case)
- **Expected**: (O + 4M + P) / 6

**For coding**: "This refactor could take 2 hours (O), probably 4 hours (M), or 8 hours if we hit edge cases (P). Expected: ~4.3 hours."

### Current Reality Tree (CRT)

Trace symptoms to root cause:

1. List Undesirable Effects (UDEs) - symptoms observed
2. Connect with "if...then" cause-effect logic
3. Trace backward to find common root cause
4. Validate: Does root cause explain ALL symptoms?

**For debugging**: "5 different errors → trace back → all stem from misconfigured auth service"

</required>

## Risk Assessment

<required>

### Pre-Mortem Analysis

Before implementation, imagine failure has occurred:

1. **Assume failure** - "The project failed. Why?"
2. **Generate causes** - List reasons independently
3. **Categorize** - Group failure modes
4. **Mitigate** - Address highest-risk items in plan

**For coding**: Before implementing, ask "How could this fail in production?"

**Research**: Increases identification of potential problems by 30% (Klein, 2007).

### Inversion Thinking

Think backward to avoid failure:

- Instead of "How do I succeed?" ask "How could I fail?"
- Instead of "How to make this fast?" ask "What would make this slow?"
- Avoid stupidity rather than seeking brilliance

**Key insight**: "Spend less time being brilliant, more time avoiding obvious stupidity." (Munger)

</required>

## Comprehensive Review

<required>

### Six Thinking Hats

Ensure coverage by examining from 6 perspectives:

- **White** (Facts): What data/evidence do we have?
- **Red** (Intuition): What does gut feeling say? Any concerns?
- **Black** (Caution): What could go wrong? What are the risks?
- **Yellow** (Optimism): What are the benefits? Best case?
- **Green** (Creativity): What alternatives exist? New approaches?
- **Blue** (Process): Are we on track? What's the next step?

**For code review**: Cycle through each hat for comprehensive analysis.

</required>

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

<related>

**Research:**

- Boyd, J. (1995). The Essence of Winning and Losing (OODA Loop)
- Polya, G. (1945). How to Solve It
- Klein, G. (2007). Performing a project premortem
- Munger, C. Inversion thinking in decision-making
- de Bono, E. (1985). Six Thinking Hats
- Goldratt, E. (1984). The Goal (Theory of Constraints)
- Malcolm, D.G. et al. (1959). PERT (Program Evaluation Review Technique)

**Related files:**

- @talk.md - Questioning techniques, Socratic method
- @verify.md - Hypothesis testing, root cause analysis
- @guard.md - Cognitive guards
- @design.md - Design principles (SOLID)

</related>
