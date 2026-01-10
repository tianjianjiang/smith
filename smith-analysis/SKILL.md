---
name: smith-analysis
description: Reasoning frameworks and problem decomposition techniques. Use when planning implementation, evaluating arguments, estimating scope, decomposing complex tasks, or applying first principles thinking.
---

# Reasoning Frameworks

<metadata>

- **Scope**: Reasoning, problem decomposition, and analysis techniques
- **Load if**: Planning implementation, evaluating arguments, estimating scope, decomposing tasks
- **Prerequisites**: @smith-guidance/SKILL.md

</metadata>

<context>

**Foundation**: Based on OODA Loop's Orient phase (Boyd) - the "cognitive engine" that drives decision-making through mental models, prior experience, and analysis/synthesis.

**When to use**: Problem framing, solution design, risk assessment, logical validation.

**MECE relationship**:
- **smith-analysis** (this file) - Constructive thinking (how to reason)
- `@smith-clarity/SKILL.md` - Defensive thinking (what to avoid)
- `@smith-validation/SKILL.md` - Proving/testing (verifying correctness)

</context>

## Reasoning Patterns

<context>

### Deductive Reasoning

General principles to specific conclusions (logically certain):

**Pattern**: If all A are B, and C is A, then C is B.

1. Start with general premise (known to be true)
2. Apply to specific case
3. Derive guaranteed conclusion

### Inductive Reasoning

Specific observations to general patterns (probabilistic):

**Pattern**: Observed A1, A2, A3... all have property B. Therefore all A probably have B.

1. Gather specific observations
2. Identify patterns
3. Form general hypothesis (may be wrong)

**Caution**: Inductive conclusions can be wrong.

### Abductive Reasoning

Best explanation from incomplete observations (inference to best explanation):

**Pattern**: B is observed. A would explain B. Therefore A is probably true.

1. Observe surprising/unexpected result
2. Generate candidate explanations
3. Select most plausible explanation
4. Test to confirm or falsify

</context>

## Extended Thinking Guidance

Modern LLMs have built-in extended thinking for complex problem-solving.

**When to use**: Complex architectural decisions, multi-step refactoring, security analysis, performance optimization.

<forbidden>

- NEVER use "think step-by-step" prompts (counterproductive for models with built-in reasoning)
- NEVER ask for visible reasoning steps (defeats efficiency purpose)
- NEVER use for simple, straightforward tasks
- NEVER provide explicit reasoning instructions (focus on outcome specification, not process)

</forbidden>

## Problem Decomposition

<context>

### First Principles Thinking

Break down to fundamentals, reason up:

1. **Identify assumptions** - What do we take for granted?
2. **Decompose** - What are the fundamental truths?
3. **Reconstruct** - Build solution from first principles only

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

</context>

## Estimation

<context>

### Fermi Estimation

Order-of-magnitude approximation with limited data:

1. Break complex question into simpler sub-questions
2. Make reasonable assumptions for each part
3. Combine estimates (multiply/add as appropriate)
4. Sanity check: Is result reasonable?

</context>

## Constraint Thinking

<context>

### TOC Five Focusing Steps

Systematic bottleneck elimination (Goldratt):

1. **Identify** - Find the constraint limiting throughput
2. **Exploit** - Maximize constraint output without additional investment
3. **Subordinate** - Align everything else to support the constraint
4. **Elevate** - Increase constraint capacity if still limiting
5. **Repeat** - Find the new constraint (it will shift)

### Three-Point Estimation (PERT)

Handle uncertainty with optimistic, likely, pessimistic:

- **O**: Best case (everything goes right)
- **M**: Most likely (typical scenario)
- **P**: Pessimistic (realistic worst case)
- **Expected**: (O + 4M + P) / 6

### Current Reality Tree (CRT)

Trace symptoms to root cause:

1. List Undesirable Effects (UDEs) - symptoms observed
2. Connect with "if...then" cause-effect logic
3. Trace backward to find common root cause
4. Validate: Does root cause explain ALL symptoms?

</context>

## Risk Assessment

<context>

### Pre-Mortem Analysis

Before implementation, imagine failure has occurred:

1. **Assume failure** - "The project failed. Why?"
2. **Generate causes** - List reasons independently
3. **Categorize** - Group failure modes
4. **Mitigate** - Address highest-risk items in plan

Increases problem identification by 30%.

### Inversion Thinking

Think backward to avoid failure:

- Instead of "How do I succeed?" ask "How could I fail?"
- Instead of "How to make this fast?" ask "What would make this slow?"
- Avoid stupidity rather than seeking brilliance

</context>

## Comprehensive Review

<context>

### Six Thinking Hats

Ensure coverage by examining from 6 perspectives:

- **White** (Facts): What data/evidence do we have?
- **Red** (Intuition): What does gut feeling say? Any concerns?
- **Black** (Caution): What could go wrong? What are the risks?
- **Yellow** (Optimism): What are the benefits? Best case?
- **Green** (Creativity): What alternatives exist? New approaches?
- **Blue** (Process): Are we on track? What's the next step?

</context>

## ACTION (Recency Zone)

<required>

**When reasoning or planning:**
1. Use First Principles to break down complex problems
2. Apply Polya's 4-Step Method for systematic problem-solving
3. Use Pre-Mortem Analysis before implementation
4. Apply Six Thinking Hats for comprehensive review

</required>

<related>

- @smith-guidance/SKILL.md - Anti-sycophancy, HHH framework, exploration workflow
- `@smith-clarity/SKILL.md` - Cognitive guards, logic fallacies
- `@smith-validation/SKILL.md` - Hypothesis testing, debugging

</related>
