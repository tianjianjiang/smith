# Intent: Fix smith-checkpoint's over-strict token budget

Author: Mike Tian-Jian Jiang (a.k.a. Chiang, Tien Chien). Status: implemented.

## Problem

`smith-checkpoint/SKILL.md:27` states a hard-sounding "Target: <400 tokens
per checkpoint body," repeated in Procedure step 4 (`SKILL.md:112-113`).
The only code-level check, `write-checkpoint.sh:95-102`
(`warn_if_body_exceeds_budget`), is a non-blocking stderr warning past 1600
bytes — it never truncates or summarizes; the drafted body is passed
through verbatim (`write-checkpoint.sh:113`). Because the prose is the only
enforcement that actually shapes drafting behavior, the drafting agent
reads "<400 tokens" as a hard ceiling and cuts durable content (decisions,
file:line anchors, follow-ups) to fit it. This contradicts the skill's own
completeness requirement: a checkpoint is "not successful until all three
backend writes succeed" (`SKILL.md:153`), and the skill's stated mission is
to "capture what would otherwise be lost across sessions" (`SKILL.md:10`).

## Proposed outcome

Reword the budget language so completeness is the explicit, binding
requirement and the token figure is a non-blocking starting aim. No code
behavior changes — the warning already only warns.

## Affected users and systems

- `smith-checkpoint` skill (`SKILL.md`, `scripts/write-checkpoint.sh`) —
  used by any Claude Code session running `/smith-checkpoint`, invoked
  manually or via the `enforce-clear.sh` stop hook in
  `smith-mode-plan-claude`.
- Every future session's post-`/clear` or post-restart handover quality
  depends on this.

## Constraints

- Must not regress the existing "durable only" scoping (`SKILL.md:18-23`)
  or "use references, not content duplication" format rules
  (`SKILL.md:33-37`) — only the budget-vs-completeness precedence changes.
- Must not turn the warning into a hard block; the script's job is to warn,
  not enforce.

## Open questions

None outstanding — resolved via `AskUserQuestion` with Mike: budget
direction is "soft guideline, completeness wins"; SDLC artifacts for this
fix live under `smith-checkpoint/references/` per this repo's
agentskills.io-compliant convention.
