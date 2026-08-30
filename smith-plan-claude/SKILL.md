---
name: smith-plan-claude
description: ExitPlanMode UI pattern for Claude Code plan mode — explain-first rule and rejection handling. For context/state/hooks see @smith-ctx-claude, for checkpoint see @smith-checkpoint, for Ralph see @smith-ralph.
license: MIT
metadata:
  author: claude-code-user
  version: "4.0.0"
  tags: ["plan-mode", "claude-code", "exitplanmode"]
---

# Plan Mode UI (Claude Code)

ExitPlanMode UI pattern for Claude Code. For context management, auto-resume, and hooks, see `@smith-ctx-claude/SKILL.md`.

**Load if:** Using ExitPlanMode in Claude Code plan mode
**Prerequisites:** `@smith-ctx-claude/SKILL.md`

## Explain Before ExitPlanMode

The approval modal shows the plan FILE and draws the user's eye away from your
chat message -- in-message prose is easily missed. Always put the explanation
(plain text; zh-Hant per user preference) in its OWN turn FIRST, then call
ExitPlanMode in a LATER turn. Do not bury a substantial explanation in the same
turn as the ExitPlanMode call. There is no "plan is obvious enough to skip"
exception -- deterministically enforced by the `exit-plan-mode-guard.mjs`
PreToolUse hook (`smith-ctx-claude/scripts/exit-plan-mode-guard.mjs`, README.md
Hooks), which blocks the call unless a prior turn in the exchange was
plain-text-only elaboration.

## ExitPlanMode Rejection Handling

ExitPlanMode rejection has three scenarios -- handle each differently:

1. **Rejection WITH user feedback** (normal revision flow):
   - Read the user's feedback from the rejection message
   - Revise the plan file based on their feedback
   - Send the revised explanation as its own plain-text turn first (the
     exit-plan-mode-guard hook requires fresh elaboration after ANY prior
     ExitPlanMode attempt, approved or rejected -- the original elaboration
     does not carry over)
   - Call ExitPlanMode again with the updated plan, in a later turn
   - Never call ExitPlanMode twice without making changes between calls

2. **Rejection WITHOUT feedback + "Re-entering Plan Mode"** (silent redirect):
   - This is a known Claude Code issue where ExitPlanMode bounces back
   - Do NOT enter an infinite edit-and-retry loop
   - Use AskUserQuestion to tell the user: "ExitPlanMode was silently redirected.
     Please exit plan mode manually (Escape or Shift+Tab), then tell me to proceed."

3. **Session ends after ExitPlanMode** (auto-accept and clear):
   - User clicked "auto-accept and clear context" -- session is killed
   - Preemptive flag from inject-plan.sh ensures plan auto-reload in next session
   - No agent action needed (agent doesn't see this -- session already ended)

[#20397]: https://github.com/anthropics/claude-code/issues/20397

## Related

- `@smith-plan/SKILL.md` - Portable plan tracking protocol
- `@smith-ctx-claude/SKILL.md` - Context management, auto-resume, hooks, state
- `@smith-ralph/SKILL.md` - Ralph Loop phase boundaries, resume
- `@smith-checkpoint/SKILL.md` - Checkpoint (Serena + Basic-Memory)
