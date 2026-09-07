# Spec: Multi-round code review effort level control
Status: approved. Based on: `intent/multi-round-review-effort-control.md`

## Requirements

### Functional Requirements

**FR1**: `smith-review/SKILL.md` MUST instruct using `/code-review low` in all convergence rounds
- Location: Procedure § Full automated pass (after existing text)
- Format: New sub-item "Effort level in iterative reviews"

**FR2**: `smith-review/SKILL.md` MUST instruct including "use low effort level" in pr-review-toolkit spawn prompts
- Same location as FR1
- Clarify that pr-review-toolkit does not auto-inherit session effort

**FR3**: `smith-review/SKILL.md` MUST instruct running exactly one instance of each review tool per round
- Same location as FR1
- Format: New sub-item "One instance per tool per round"

**FR4**: `smith-subagents/SKILL.md` MUST add "Multi-Round Review Discipline" section
- Location: After "Spawning: scope and tools", before "Contract template"
- Three rules: single instance, low effort, cost guard strategy

### Non-Functional Requirements

**NFR1**: Preserve review signal quality
- Low effort must still catch high-confidence bugs
- Verification: existing convergence criteria unchanged

**NFR2**: Maintain tool coverage
- All applicable tools still run (no reduction in coverage)
- Change is effort level only, not tool selection

**NFR3**: Align with Claude Code parameters
- Use official effort level names: `low`, `high`, `xhigh`, `max`
- Reference official documentation (retrieved 2026-09-08)

## Design

### File Modifications

**smith-review/SKILL.md**:
```markdown
2. **Full automated pass** — [existing text...]
   
   **Effort level in iterative reviews**: Use LOW effort for all convergence rounds:
   - `/code-review low` — quick check sufficient for iterative rounds
   - For `pr-review-toolkit:review-pr`, include "use low effort level" in the 
     subagent spawn prompt (does not auto-inherit session effort)
   - Rationale: shallow levels return fast, high-confidence findings; deep effort 
     reserved for single-pass pre-merge reviews
   
   **One instance per tool per round**: Run exactly ONE instance of each tool 
   per round, not multiple in parallel. The tools internally parallelize their 
   own subagents (/code-review launches 4 agents; pr-review-toolkit coordinates 
   6). Running multiple instances of the SAME tool is redundant and wastes tokens.
```

**smith-subagents/SKILL.md**:
```markdown
## Multi-Round Review Discipline

When spawning review tools in an iterative convergence loop (e.g., 
`@smith-review`, `/smith-ship`):

1. **One tool instance per round**: Spawn ONE instance of each designated 
   review tool (e.g., one `/code-review low`, one `pr-review-toolkit:review-pr`) 
   per round. The tools internally fan out their own subagents — multiple 
   instances of the same tool are redundant and waste tokens.

2. **Low effort level**: Use LOW effort for all rounds in convergence loops:
   - `/code-review low` — explicit flag
   - `pr-review-toolkit:review-pr` — include "use low effort level" in the 
     spawn prompt (does not auto-inherit session effort)
   - Rationale: shallow levels return fast, high-confidence findings sufficient 
     for iterative rounds; deep effort reserved for single-pass pre-merge reviews

3. **Cost guard per round**: The cost control is "bounded per round + verify 
   findings", not "fewer tools". Run all applicable tools, but run each ONCE 
   with LOW effort.
```

### Design Decisions

**D1**: All rounds use low effort (not just subsequent rounds)
- Rationale: User confirmed strategy 2026-09-08
- Alternative considered: first round default, others low (rejected)

**D2**: Explicit prompt instruction for pr-review-toolkit
- Rationale: Tool does not auto-inherit session effort level
- Evidence: No documentation of automatic inheritance

**D3**: Add guidance to both smith-review and smith-subagents
- Rationale: smith-review is the orchestrator; smith-subagents is the spawning discipline
- Ensures consistency at both orchestration and execution levels

**D4**: Place new section in smith-subagents after "Spawning: scope and tools"
- Rationale: Extends spawning guidance with review-specific discipline
- Maintains logical flow: general spawning → review-specific → contract template

## Dependencies

**External**:
- Claude Code `/code-review` plugin (v2.1.101+)
- Claude Code `pr-review-toolkit` plugin

**Internal**:
- `smith-review/SKILL.md` (modified)
- `smith-subagents/SKILL.md` (modified)
- `smith-ship/SKILL.md` (references smith-review, no changes)
- `smith-automation/SKILL.md` (references smith-review, no changes)

## Acceptance Criteria

**AC1**: `grep -n "effort\|/code-review low" smith-review/SKILL.md` returns new guidance
**AC2**: `grep -n "Multi-Round Review Discipline" smith-subagents/SKILL.md` returns new section
**AC3**: New text mentions both `/code-review low` AND pr-review-toolkit in both files
**AC4**: Existing convergence criteria in smith-review unchanged
**AC5**: No reduction in tool coverage (all applicable tools still required)

## Evidence Base

- [Code Review - Claude Code Docs](https://code.claude.com/docs/en/code-review) (retrieved 2026-09-08)
- [Effort Levels for Code Review](https://thakicloud.com/tech-blog/en/dev/claude-code-review-effort-levels/) (retrieved 2026-09-08)
- [Claude Code effort level and model selection](https://claude.com/blog/claude-model-and-effort-level-in-claude-code) (retrieved 2026-09-08)

## Impact

**Expected benefit**: 60-80% cost reduction in multi-round review loops
**Risk**: Low (shallow effort still catches high-confidence bugs per official docs)
**Affected users**: Engineers running `/smith-review` or `/smith-ship`
