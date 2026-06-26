---
name: smith-review
description: Multi-round local review loop — review the current worktree change with all relevant smith review skills plus Claude Code review tools (/code-review, /review-pr, CodeRabbit, code-simplifier), iterating until convergence, without shipping. Invoke with /smith-review.
argument-hint: [optional focus area]
allowed-tools: Bash(git *), Bash(gh *)
---

# /smith-review — review the current change until convergence

Review-only (no commit/push/merge). For the full pipeline use `/smith-ship`.

## Live state

- Diff stat: !`git diff --stat`
- Branch: !`git branch --show-current`

## Procedure

<required>

**Plugin-pass receipt (every round).** A round MUST end with a one-line receipt
naming each Claude Code review tool and whether it ran:
`coderabbit [ran/NA] · /code-review [ran/NA] · pr-review-toolkit:review-pr
[ran/NA] · security-review [ran/NA] · code-simplifier [ran/NA]`. `NA` needs a
one-word reason (e.g. `NA:docs`). The change is NOT converged until the receipt
shows every applicable tool ran. Disclosing a skipped tool is not a substitute
for running it (`@smith-guidance` close-gaps). Resist the bias to "use fewer
tools".

</required>

Marshal ALL relevant review resources — both smith skills AND Claude Code
plugins/skills — not just one tool. Pick every one that applies to the change:
- smith: `@smith-gh-pr` (Code Review Cycle + Convergence), `@smith-validation`,
  `@smith-tests`, `@smith-subagents`, `@smith-skills`, `@smith-standards`,
  `@smith-style`, plus the language skills (`@smith-python`/`@smith-typescript`/
  `@smith-nuxt`/...) the diff touches.
- Claude Code plugins/skills: `/code-review`, `/review-pr` (pr-review-toolkit;
  its applicable agents), CodeRabbit, `code-simplifier`, and relevant reviewer
  subagents.

1. **Self-audit** against the applicable smith conventions first (cheap, no
   API call).
2. **Full automated pass** — run EVERY applicable tool above each round, not
   CodeRabbit alone; for code-bearing diffs include `/review-pr`'s multi-agent
   pass. Use the tools that fit the change; do not skip available reviewers to
   save effort.
3. **Verify, don't rubber-stamp** — each finding is a claim; check it against
   the actual lines. For a bugfix, audit the execution path, not just style
   (`@smith-validation` Bugfix Discipline).
4. **Fix & iterate** — apply high-confidence fixes; re-review with the full set.
   Cost guard is bounded PER ROUND + verify findings (not fewer tools). Drive
   iteration as a `/loop`/ralph loop that re-shares the relevant skills + diff
   each round (`@smith-ralph`, `@smith-automation`).
5. **Converge** — stop on a clean round (0 actionable) or 2 consecutive
   Info-only rounds, AND only once the latest round's plugin-pass receipt shows
   no applicable tool skipped. Report findings + verdict + the receipt in-band.

Restate the outcome in your own message; do not point at tool output.
