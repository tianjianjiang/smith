---
name: smith-ralph
description: Ralph Loop integration patterns for iterative AI development. Use when starting Ralph loops, managing iterations, or recovering from context compaction. Covers TDD, debugging, context management, and memory persistence.
---

# Ralph Loop Integration

<metadata>

- **Load if**: Starting `/ralph-loop`, managing iterations, recovering from compaction
- **Prerequisites**: @smith-ctx/SKILL.md, `@smith-git/SKILL.md`, `@smith-serena/SKILL.md`

</metadata>

## CRITICAL: Ralph Fundamentals (Primacy Zone)

<required>

**Ralph = iterative prompt loop**: Same prompt fed repeatedly, Claude sees previous work in files.

**Essential patterns:**
1. Clear completion criteria with `<promise>` tag
2. `--max-iterations` as safety limit (always set)
3. Atomic commits mark iteration boundaries
4. Serena memory persists state across compaction

</required>

## Skills Integration

### TDD Workflow (smith-tests)

**Pattern**: test → implement → run pytest → iterate until `<promise>TESTS PASS</promise>`.

Each test file = iteration boundary. Commit after green.

### Debugging Workflow (smith-validation)

**Pattern**: hypothesis → test → eliminate → iterate until `<promise>ROOT CAUSE FOUND</promise>`.

- Strong Inference: Each hypothesis test = one iteration
- 5 Whys: Each "Why?" deepening = one iteration
- Delta Debugging: Split → test → recurse

### Task Decomposition (smith-dev)

**Pattern**: Phase milestones = iteration boundaries. Quality gates between.

```text
Phase 1: [milestone] + tests
Phase 2: [milestone] + tests
Output <promise>COMPLETE</promise> after all phases.
```

### Exploration Workflow (smith-guidance)

**Ralph = structured exploration**: Read files → Form hypothesis → Design test → Execute → Loop.

## Context Management

<required>

**Ralph burns context rapidly.** ~1-3.5k tokens per iteration.

**Compaction strategy:**
- At 50%: Prepare retention criteria, continue
- At 60%: `/compact`, persist Ralph state to Serena memory
- After compaction: `read_memory()` to resume

**Phase boundaries:** At phase boundaries, if context >50%,
recommend `/clear` to user. Plan-claude auto-reloads via
state-based detection. Always update plan file and write
Serena memory before recommending `/clear`.

**Essential retention:**
- Iteration number
- Hypotheses tested/remaining
- Test results summary
- File:line references

</required>

## Commit Strategy

<required>

**Atomic commits mark iteration boundaries.**

1. Complete iteration (test passes or hypothesis proven)
2. Commit with iteration number: `fix(feature): iteration 3 - resolved null check`
3. If regression, use `git bisect` to find breaking iteration

</required>

## Memory Persistence

<required>

**Serena memories persist Ralph state across compaction.**

**Memory fields**: `ralph_[task]_state`
- iteration, hypotheses (tested/remaining), test_results, next_action

**Sync timing:**
- After each iteration: `write_memory()`
- Before/after compaction: `write_memory()` / `read_memory()`

</required>

<related>

- `@smith-tests/SKILL.md` - TDD workflow
- `@smith-validation/SKILL.md` - Debugging techniques
- `@smith-dev/SKILL.md` - Task decomposition
- @smith-guidance/SKILL.md - Exploration workflow
- @smith-ctx/SKILL.md - Context management
- `@smith-git/SKILL.md` - Commit patterns
- `@smith-serena/SKILL.md` - Memory persistence

</related>

## ACTION (Recency Zone)

<required>

**Starting Ralph:**
```shell
/ralph-loop "[task]" --completion-promise "[DONE]" --max-iterations 20
```

**During iterations:**
1. Read files before changes
2. Form ONE testable hypothesis
3. Execute and record result
4. Commit if progress made
5. `write_memory()` after each iteration

**On compaction:**
1. `write_memory()` with full state
2. After `/compact`: `read_memory()` to resume

</required>
