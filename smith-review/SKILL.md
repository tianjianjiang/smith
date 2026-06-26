---
name: smith-review
description: User-invoked multi-round local review loop — review the current worktree change with all relevant smith review skills plus CodeRabbit, iterating until convergence, without shipping. Invoke with /smith-review.
disable-model-invocation: true
argument-hint: [optional focus area]
allowed-tools: Bash(git *), Bash(gh *)
---

# /smith-review — review the current change until convergence

Review-only (no commit/push/merge). For the full pipeline use `/smith-ship`.

## Live state

- Diff stat: !`git diff --stat`
- Branch: !`git branch --show-current`

## Procedure

Load `@smith-gh-pr/SKILL.md` (Code Review Cycle + Convergence Protocol) and the
review-relevant smith skills for the change (`@smith-validation`,
`@smith-tests`, `@smith-subagents`, plus
`@smith-skills`/`@smith-standards`/`@smith-style` for docs and the language
skills as applicable).

1. **Self-audit** against the applicable smith conventions first (cheap, no
   API call).
2. **Automated pass** — CodeRabbit (`coderabbit review --agent`, or the
   PR-side review) and `/code-review`. For code-bearing diffs, `/review-pr` is
   the single multi-agent entry point; for docs-only diffs prefer the
   convention audit + CodeRabbit (low-yield otherwise — say so rather than
   firing a fleet).
3. **Verify, don't rubber-stamp** — each finding is a claim; check it against
   the actual lines. For a bugfix, audit the execution path, not just style
   (`@smith-validation` Bugfix Discipline).
4. **Fix & iterate** — apply high-confidence fixes; re-review. Cost guard:
   bound the reviewer count; widen only with reason. If iterating, drive it as
   a `/loop`/ralph loop that re-shares the relevant skills + diff each round
   (`@smith-ralph`, `@smith-automation`), not repeated blind fan-out.
5. **Converge** — stop on a clean round (0 actionable) or 2 consecutive
   Info-only rounds. Report findings + verdict in-band.

Restate the outcome in your own message; do not point at tool output.
