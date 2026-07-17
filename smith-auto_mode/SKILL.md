---
name: smith-auto_mode
description: Claude Code auto mode classifier — what gets blocked, how to recover from a denial without silently retrying, and where to configure trusted infrastructure. Use when the agent invokes a classifier-sensitive action (push, deploy, external-content duplication), when a prior turn ended in "auto mode classifier" denial, or when the user mentions auto mode / `defaultMode` / `hard_deny`.
---

# Auto Mode Classifier — Denial Recovery

**Scope:** Claude Code auto mode (`permissions.defaultMode: "auto"`), the classifier that gates risky actions
**Load if:** An auto-mode classifier denial appeared in the prior turn, OR the agent is about to invoke a classifier-sensitive action (force push, push to `main`, production deploy, external-content duplication, sandbox network call), OR the user mentions auto mode / `hard_deny` / `defaultMode`
**Prerequisites:** `@smith-ctx-claude/SKILL.md` (permission modes overview), `@smith-guidance/SKILL.md` (HHH, ask-before-assuming)
**Authoritative source:** https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode (verified 2026-05-21)

## CRITICAL: Denial Handling

- After a classifier denial, change something material before retrying — the classifier rejected the action for a reason, and a silent identical retry just exhausts the fallback budget (3 consecutive blocks → auto mode pauses; 20 total → auto mode pauses for the session)
- Stay within the same risk category after a denial — e.g. a denied `git push` should not be escalated to `git push --force`, nor a denied `git restore` to `rm -rf`; the classifier flags broader categories than the literal command
- Treat a user-stated boundary ("don't push", "wait until I review") as re-read from the transcript on each check, not as a persisted rule — context compaction (`/clear`, summarization) can drop it, so for a hard guarantee recommend the user add a `permissions.deny` rule instead of relying on the chat boundary
- Keep the classifier engaged through to task completion — switching to `bypassPermissions` mid-task to get past a denial disables permission prompts and protected-path safety checks broadly, not just the one denial in question. A few narrow exceptions still prompt even in this mode (explicit `ask` rules, the `rm -rf /`/`rm -rf ~` circuit breaker, MCP tools marked `requiresUserInteraction`) — that isn't a reason to treat the switch as safe; it remains an emergency escape, not a routine unblock (https://code.claude.com/docs/en/permission-modes#skip-all-checks-with-bypasspermissions-mode, retrieved 2026-07-12)

After a classifier denial the agent MUST:

1. **Stop.** No follow-up tool call until the user replies.
2. **Restate** the action that was denied and the verbatim classifier message ("Permission for this action was denied by the Claude Code auto mode classifier" + any specific reason returned).
3. **Propose** options to the user (see Decision Matrix below).
4. **Wait** for explicit user choice before the next attempt.

On the **second** denial of the same logical action (even if the literal command differs), use `AskUserQuestion` rather than free-form prose — the user needs to pick a path explicitly.

## What Auto Mode Is

Auto mode lets Claude execute without per-action permission prompts. A separate classifier model evaluates each pending action and blocks anything that escalates beyond the user's request, targets unrecognized infrastructure, or appears driven by content Claude read from a tool result.

**Activation**:
- Cycle with `Shift+Tab` (opt-in on first cycle)
- Persistent default: `{ "permissions": { "defaultMode": "auto" } }` in `~/.claude/settings.json` **only** — the same key in `.claude/settings.json` or `.claude/settings.local.json` is ignored, so a repo cannot grant itself auto mode

**Requirements**: Max/Team/Enterprise/API plan; Sonnet 4.6, Opus 4.6, or Opus 4.7; Anthropic API provider. See the cited URL for the full matrix.

## What the Classifier Decides

Decision order — first match wins:

1. User's `permissions.allow` / `permissions.deny` rules → immediate
2. Read-only actions and working-directory edits (excluding protected paths) → auto-approved
3. Everything else → classifier

**Default-blocked categories** (observed and documented):

- Bare `--force` push, or pushing directly to a shared or default branch
  (`--force-with-lease` is the non-blocked variant — see the escape patterns below)
- `curl | bash` style download-and-execute patterns
- Sending sensitive data to external endpoints
- Production deploys and migrations
- Mass deletion on cloud storage
- Granting IAM or repo permissions
- Modifying shared infrastructure
- Irreversibly destroying files that existed before the session
- Duplicating externally-fetched content into the user's personal workspace (e.g. Notion page duplication from a public URL)

**Default-allowed** (for awareness): read-only ops, working-dir edits, lock-file installs, read-only HTTP, push to session-created branches.

Run `claude auto-mode defaults` for the live rule lists. Trusted infrastructure is configured via `autoMode.environment` (prose entries naming trusted repos/buckets/domains; the default trusts the working repo + its remotes). To extend the built-in list instead of replacing it, include the literal string `"$defaults"` in the array — the defaults splice in at that position. See https://code.claude.com/docs/en/auto-mode-config.

## Decision Matrix on Denial

Four outcomes after a classifier block — pick exactly one, surface it to the user:

- **(a) Safer alternative exists** — Propose a non-blocked variant. Example: classifier blocked `git push --force` → propose `git push --force-with-lease` only if the original intent was safety-flagged; if intent was "rewrite history", ask the user.
- **(b) Destructive but the user actually wants it** — Ask the user to (i) state explicit consent in chat (treated as a single-turn boundary lift), or (ii) add an `allow` rule to `~/.claude/settings.json`. Do not proceed on assumption.
- **(c) Ambiguous intent** — `AskUserQuestion` to clarify what they really want. Often the right answer is a less risky path the agent didn't see.
- **(d) Defer or abandon** — Tell the user the action is blocked and the task can't proceed without their decision. Park the work, document state, and stop.

## User-Stated Boundaries

Phrases like "don't push", "wait until I review", or "we don't deploy on Fridays" are treated as **block signals** by the classifier — even when the default rules would allow the action. Important properties:

- Boundaries are **not stored as rules**. The classifier re-reads them from the transcript on each check.
- Boundaries can be **lost on context compaction** (`/clear`, "Summarize from here", or summary rollover). For a guarantee that survives compaction, recommend the user add a `permissions.deny` rule in `~/.claude/settings.json`.
- Claude's own judgment that a boundary's condition was met does **not** lift it. Only an explicit user message lifts a boundary.

## Hard Deny Rules

`hard_deny` blocks an action unconditionally; no `allow` rule overrides it. The user owns the configuration; the agent's job is to recognize the outcome and route to **(d) abandon** — never propose workarounds.

## Fallback Thresholds

- **3 consecutive blocks** → auto mode pauses; CLI resumes prompting. Any allowed action resets the consecutive counter.
- **20 total blocks** in a session → auto mode pauses for the rest of the session.
- Non-interactive `-p` mode → repeated blocks **abort** the session (no user to prompt).

## Subagent Behavior

Subagents inherit the parent's classifier (checked at spawn, per-action, and on return). A subagent's `permissionMode` frontmatter is **ignored** in auto mode.

## Protected Paths

Writes to repo/Claude config dots (`.git`, `.claude/*` except commands/agents/skills/worktrees, shell rc files, `.mcp.json`, `.claude.json`, etc.) route to the classifier and usually block. See https://code.claude.com/docs/en/permission-modes#protected-paths for the full enumeration.

Editing `~/.claude/settings.json` from inside a project session almost always trips the classifier. Recommend the user edit it themselves, or invoke the Claude Code `update-config` plugin command.

## Pre-approved Operation Patterns

**Reducing classifier friction for known-safe operations**
via `~/.claude/settings.json`:

`permissions.allow` accepts `{ "tool": "Bash", "command": "«glob»" }`.
Common patterns that reduce denial loops without compromising safety —
scope each glob to the literal branch/PR/worktree the session owns, not a
shared naming prefix that also matches other contributors' work:
- `git push --force-with-lease origin «your-branch»` — not `feat/*`: that
  prefix is a repo-wide naming convention (see `@smith-style/SKILL.md`),
  so the glob would also cover branches you didn't create
- `gh pr merge --squash «pr-number»` — not a bare `*`: merging is a
  shared-state operation (affects `main`), so a wildcard would pre-approve
  merging ANY PR without confirmation
- `rm -rf .claude/worktrees/«your-worktree-name»` — not `*`: a wildcard
  would also delete worktrees you don't own, including ones from other
  concurrent sessions

**Principle:** Pre-approve only operations bounded by session-local
state (branches you created, worktrees you own). Reserve operations on
shared state (main, production, IAM) for explicit per-instance approval.

**Note:** `AskUserQuestion` authorization is conversational — the
classifier does not recognize it as a persistent permission grant.
For repeat ops, the fix is `permissions.allow` in settings, not
asking again each time.

## Classifier Rule Lists (`autoMode.*`)

The classifier is a **second gate** that runs after the permissions system.
`permissions.deny` (tool-pattern blocks) fires *before* the classifier and
cannot be overridden — use it for absolutes. The classifier's own rule lists
live in `~/.claude/settings.json`, each an array of **prose** descriptions (not
regex/tool patterns):

- `autoMode.hard_deny` — unconditional security boundaries (see [Hard Deny Rules](#hard-deny-rules)).
- `autoMode.soft_deny` — destructive actions that specific user intent can clear.
- `autoMode.allow` — exceptions that override matching `soft_deny`.
- `autoMode.environment` — trusted infra (covered above).

**Four-tier precedence:** `hard_deny` (unconditional) > `soft_deny` > `allow`
(overrides matching `soft_deny`) > explicit specific user intent (clears
remaining soft blocks; a general request like "clean up the repo" does **not**
count — the message must describe the exact action). As with `environment`,
include the literal `"$defaults"` in any of these arrays to keep the built-in
rules while adding your own.

## Related

- `@smith-ctx-claude/SKILL.md` - Permission modes overview (this skill is the deep-dive for the `auto` mode)
- `@smith-git/SKILL.md` - Force-push and push-to-main behavior (common classifier triggers)
- `@smith-gh-pr/SKILL.md` - PR push and merge flows
- `@smith-guidance/SKILL.md` - Ask-before-assuming, anti-sycophancy (the denial-recovery protocol is an application of these)
- `@smith-settings/SKILL.md` - Where permission keys live; convention-validator hook recipe

## Before You Finish

**On every classifier denial:**
1. Pause — no follow-up tool call this turn
2. Restate action + verbatim classifier reason
3. Map to outcome (a)–(d) and surface to user

**On second denial of the same logical action:**
- Use `AskUserQuestion` (not prose) to force a choice

**On `hard_deny`:**
- Never propose a workaround — outcome (d) abandon

**Before invoking known classifier-sensitive actions:**
- Bare `--force` push, push to a shared or default branch (`main`, `develop`, etc. — never assume `main`), production deploys, IAM grants, cloud-storage mass deletes → confirm with the user first, even before the first classifier check. `--force-with-lease` on a branch you own is NOT in this set — it is mechanics (`@smith-guidance` Harmless, external writes); the lease is the safety check, and it is the recommended form above. "Own" means a personal or PR branch, never a shared or default one (`@smith-git`); where a PR exists, its ownership gate (`@smith-gh-pr`) is the test — before one exists, the branch being yours is.
