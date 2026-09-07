# Intent: Multi-round code review effort level control
Author: Mike Tian-Jian Jiang. Status: approved.

## Problem
Multi-round convergence code reviews (`@smith-review`, `/smith-ship`) 
accumulate high costs because each round runs review tools 
(`/code-review`, `pr-review-toolkit:review-pr`) at default effort levels. 
The tools internally parallelize (4-6 subagents), but the smith skills 
lack explicit guidance on:
- Using LOW effort in iterative rounds
- Running ONE instance of each tool per round (not multiple in parallel)

This affects: development teams using smith skills for PR quality gates.

## Proposed outcome
`smith-review/SKILL.md` and `smith-subagents/SKILL.md` explicitly instruct:
- Use `/code-review low` in all convergence rounds
- For `pr-review-toolkit:review-pr`, explicitly include "use low effort level" in spawn prompt (explicit statement ensures consistent effort level)
- Spawn exactly one instance of each review tool per round

Engineers see significant cost reduction in multi-round review loops while 
maintaining convergence quality.

## Affected users and systems
**Files to modify:**
- `smith-review/SKILL.md` (Procedure § Full automated pass — add effort level guidance)
- `smith-subagents/SKILL.md` (new section: Multi-Round Review Discipline)

**Dependent workflows:**
- `smith-ship/SKILL.md` (orchestrates `/smith-review` loop)
- `smith-automation/SKILL.md` (references `/smith-review`)
- `smith-gh-pr/SKILL.md` (mentions review tools and convergence protocol)

**End users:**
- Engineers running `/smith-review` or `/smith-ship` with multiple iterations

## Constraints
- Must preserve review signal quality (low effort still catches high-confidence bugs)
- Cannot reduce tool coverage (still run all applicable tools, just once each at low effort)
- Must align with Claude Code's `/code-review` effort levels (low/medium/high/max/ultra per official docs)
- All rounds use low effort (strategy confirmed 2026-09-07)

## Open questions
None.
