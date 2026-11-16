---
name: smith-vet
description: Independent subagent lenses on a plan, design or change. Use when the user runs /smith-vet.
argument-hint: "[plan, path or change to vet]"
disable-model-invocation: true
---

# /smith-vet — independent subagent lenses on a plan, design or change

**Scope:** The user's exploration, verification, validation and planning
instruction, applied to `$ARGUMENTS` or, without one, to the current work
**Prerequisites:** `@smith-subagents/SKILL.md`

## The Instruction

The user's instruction, verbatim:

i usually ask for exploration and verification and validation and planning instruction below:
> use independent subagents effectively and efficiently with specific smith skills each. at least /smith-analysis /smith-clarity /smith-dialectic /smith-research /smith-validation must be individual subagents, respectively.

Treat the named skills as a floor, not a cap: consider each, and add
others where they apply.

## Pointers

- `@smith-analysis/SKILL.md` - decomposition, scope and risk
- `@smith-clarity/SKILL.md` - cognitive traps and faulty reasoning
- `@smith-dialectic/SKILL.md#subagent-mode-v1` - the plan interview, run
  by a subagent
- `@smith-research/SKILL.md` - current evidence for external claims
- `@smith-verification/SKILL.md` - claims checked against their
  specification
- `@smith-validation/SKILL.md#cold-reader-method-v1` - fitness for
  intended use, including the cold reader
- `@smith-subagents/SKILL.md` - spawning, blind evaluators and returns

## Aggregation

Hand the returns to one more subagent, the aggregator, instead of
reconciling them in the main thread, which has its own view of what is
vetted. The aggregator is a new subagent. Its prompt is, in this order:
the text below, word for word; the path of what was vetted; then every
return in full, each under its own line `RETURN: «skill name»`. Add
nothing else of the main thread's own: no summary, ranking, emphasis,
opinion or closing instruction.

```text
Reconcile the returns below into one verdict on what was vetted. Name the
skill behind each finding, and say where returns disagree or overlap. Use
only these returns and the vetted file itself.
```

Report the aggregator's return, and mark anything the main thread adds as
its own.

## Batch Rule

The user's rule: three to five items per agent; a skeptic only where the
output feeds an external write or a user decision.
