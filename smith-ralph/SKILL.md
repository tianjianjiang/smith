---
name: smith-ralph
description: Ralph Loop integration patterns
---

# Ralph Loop Integration

**Load if:** Starting `/ralph-loop`, managing iterations, recovering from context reset
**Prerequisites:** @smith-ctx/SKILL.md, `@smith-git/SKILL.md`, `@smith-serena/SKILL.md`

## CRITICAL: Ralph Fundamentals

**Ralph = iterative prompt loop**: Same prompt fed repeatedly, Claude sees previous work in files.

**Essential patterns:**
1. Clear completion criteria with `<promise>` tag
2. `--max-iterations` as safety limit (always set)
3. Atomic commits mark iteration boundaries
4. Serena memory persists state across context resets

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
Phase 1: «milestone» + tests
Phase 2: «milestone» + tests
Output <promise>COMPLETE</promise> after all phases.
```

### Exploration Workflow (smith-guidance)

**Ralph = structured exploration**: Read files → Form hypothesis → Design test → Execute → Loop.

## Context Management

**Ralph burns context rapidly.** ~1-3.5k tokens per iteration.

**Reactive: Auto-exit at critical context (hook-managed):**
- At 40-50%: "Summarize from here" -- consolidate verbose output.
- At 50%: Advisory. Save iteration state to Serena immediately.
- At 60%: Loop auto-exits (max_iterations set to current).
  Resume state saved. After /clear, loop auto-restarts via Skill tool.

**Proactive: Phase boundaries (ALWAYS clear, even at low context):**
- After completing each phase's tasks (all [x] for current phase):
  1. Output promise to exit Ralph
  2. Save state: write_memory("ralph_«task»_phase_N")
  3. Tell user: "Phase N complete. Run /clear for Phase N+1."
  4. After /clear: loop auto-restarts for next phase
- Rationale: Fresh context per phase prevents degradation even before threshold.

**After /clear (both cases):**
- Agent auto-invokes /ralph-loop via Skill tool (no user intervention)
- Serena memory restored for iteration continuity

**Essential retention:**
- Iteration number
- Hypotheses tested/remaining
- Test results summary
- File:line references

## Phase Boundary Protocol

**At EVERY phase boundary (regardless of context level):**
1. Mark completed tasks [x] in plan file
2. Commit current work
3. Save phase state: `write_memory("ralph_«task»_phase_N")`
4. Output the configured completion promise (default: `<promise>PHASE_COMPLETE</promise>`). Ensure this matches the Ralph loop's `--completion-promise` value.
5. AFTER all tool calls, output:

**Reload with:**
- Plan: `«plan_path»`
- Memory: `ralph_«task»_phase_N` (read via read_memory() after /clear)
- Ralph: auto-restarts for next phase
- Resume: Phase N+1 - «next phase description»

6. Tell user to run /clear

**Phase = group of tasks under the same ## heading in the plan.**
If plan has no ## headings, each `- [ ]` task = one phase.

## Commit Strategy

**Atomic commits mark iteration boundaries.**

1. Complete iteration (test passes or hypothesis proven)
2. Commit with iteration number: `fix(feature): iteration 3 - resolved null check`
3. If regression, use `git bisect` to find breaking iteration

## Memory Persistence

**Serena memories persist Ralph state across context resets.**

**Memory fields**: `ralph_«task»_state`
- iteration, hypotheses (tested/remaining), test_results, next_action

**Sync timing:**
- After each iteration: `write_memory()`
- Before/after context reset: `write_memory()` / `read_memory()`

## Orchestration Mode (Pattern B)

Parent spawns workers via Task tool; each worker gets fresh context. See `references/ORCHESTRATION.md` for full workflow, delegation practices, and state file format.

## Agent Teams Mode (Pattern C)

Team lead spawns teammates; each gets independent context. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings.json. See `references/TEAMS.md` for setup, workflow, display modes, known issues, and quality gate hooks.

## Pattern Decision Guide

- **Pattern A** (`/ralph-loop`): Simple focused tasks, <20 iterations, moderate context (1-3.5k/iter), no parallelism, interaction between iterations, low token cost, stable (official plugin), no setup
- **Pattern B** (`ralph orch`): Multi-step plans, 20-100+ iterations, low context (parent light), sequential (v1), interaction between workers, medium token cost, stable (Task tool), no setup
- **Pattern C** (`ralph team`): Large parallel-safe tasks, 10-50+ iterations, no context pressure (separate instances), native parallelism, interaction with any teammate, high token cost, experimental, requires settings.json env block (or export)

**Recommendation flow**:
1. Simple TDD/debug loop -> Pattern A (`/ralph-loop`)
2. Multi-step plan, sequential tasks -> Pattern B ("ralph orchestrate")
3. Parallel-safe tasks, research/review -> Pattern C ("ralph team")

## Related

- `@smith-tests/SKILL.md` - TDD workflow
- `@smith-validation/SKILL.md` - Debugging techniques
- `@smith-dev/SKILL.md` - Task decomposition
- @smith-guidance/SKILL.md - Exploration workflow
- @smith-ctx/SKILL.md - Context management
- `@smith-git/SKILL.md` - Commit patterns
- `@smith-serena/SKILL.md` - Memory persistence

## Before You Finish

**Starting Ralph:**
```shell
/ralph-loop "«task»" --completion-promise "«DONE»" --max-iterations 20
```

**Starting Orchestration (Pattern B):**
Say "ralph orchestrate" with a plan file. Parent spawns workers via Task tool.

**Starting Agent Teams (Pattern C):**
Say "ralph team" with a plan file. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (set via settings.json env block or shell export).

**During iterations:**
1. Read files before changes
2. Form ONE testable hypothesis
3. Execute and record result
4. Commit if progress made
5. `write_memory()` after each iteration

**On context reset:**
1. `write_memory()` with full state
2. After context reset: `read_memory()` to resume
