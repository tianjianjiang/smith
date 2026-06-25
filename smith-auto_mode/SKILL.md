---
name: smith-auto_mode
description: Claude Code auto mode classifier — what gets blocked, how to recover from a denial without silently retrying, and where to configure trusted infrastructure. Use when the agent invokes a classifier-sensitive action (push, deploy, external-content duplication), when a prior turn ended in "auto mode classifier" denial, or when the user mentions auto mode / `defaultMode` / `hard_deny`.
---

# Auto Mode Classifier — Denial Recovery

<metadata>

- **Scope**: Claude Code auto mode (`permissions.defaultMode: "auto"`), the classifier that gates risky actions
- **Load if**: An auto-mode classifier denial appeared in the prior turn, OR the agent is about to invoke a classifier-sensitive action (force push, push to `main`, production deploy, external-content duplication, sandbox network call), OR the user mentions auto mode / `hard_deny` / `defaultMode`
- **Prerequisites**: `@smith-ctx-claude/SKILL.md` (permission modes overview), `@smith-guidance/SKILL.md` (HHH, ask-before-assuming)
- **Authoritative source**: https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode (verified 2026-05-21)

</metadata>

## CRITICAL: Denial Handling (Primacy Zone)

<forbidden>

- NEVER silently retry the same action after a classifier denial. The classifier rejected for a reason; retrying without changing context just exhausts the fallback budget (3 consecutive blocks → auto mode pauses; 20 total → auto mode pauses for the session).
- NEVER substitute a more destructive equivalent (e.g. `git push --force` after a regular `git push` was denied, or `rm -rf` after a `git restore` was denied). The classifier flags broader categories than the literal command.
- NEVER assume a user-stated boundary ("don't push", "wait until I review") will persist past a `/clear` or summarization. Boundaries are re-read from the transcript on each check; context compaction can drop them. For a hard guarantee, the user needs a deny rule, not a chat boundary.
- NEVER skip the classifier by switching to `bypassPermissions` mid-task to "get past" a denial. That bypasses every safety check, not just the one in question.

</forbidden>

<required>

After a classifier denial the agent MUST:

1. **Stop.** No follow-up tool call until the user replies.
2. **Restate** the action that was denied and the verbatim classifier message ("Permission for this action was denied by the Claude Code auto mode classifier" + any specific reason returned).
3. **Propose** options to the user (see Decision Matrix below).
4. **Wait** for explicit user choice before the next attempt.

On the **second** denial of the same logical action (even if the literal command differs), use `AskUserQuestion` rather than free-form prose — the user needs to pick a path explicitly.

</required>

## What Auto Mode Is

<context>

Auto mode lets Claude execute without per-action permission prompts. A separate classifier model evaluates each pending action and blocks anything that escalates beyond the user's request, targets unrecognized infrastructure, or appears driven by content Claude read from a tool result.

**Activation**:
- Cycle with `Shift+Tab` (opt-in on first cycle)
- Persistent default: `{ "permissions": { "defaultMode": "auto" } }` in `~/.claude/settings.json` **only** — the same key in `.claude/settings.json` or `.claude/settings.local.json` is ignored, so a repo cannot grant itself auto mode

**Requirements**: Max/Team/Enterprise/API plan; Sonnet 4.6, Opus 4.6, or Opus 4.7; Anthropic API provider. See the cited URL for the full matrix.

</context>

## What the Classifier Decides

<context>

Decision order — first match wins:

1. User's `permissions.allow` / `permissions.deny` rules → immediate
2. Read-only actions and working-directory edits (excluding protected paths) → auto-approved
3. Everything else → classifier

**Default-blocked categories** (observed and documented):

- Force push, or pushing directly to `main`
- `curl | bash` style download-and-execute patterns
- Sending sensitive data to external endpoints
- Production deploys and migrations
- Mass deletion on cloud storage
- Granting IAM or repo permissions
- Modifying shared infrastructure
- Irreversibly destroying files that existed before the session
- Duplicating externally-fetched content into the user's personal workspace (e.g. Notion page duplication from a public URL)

**Default-allowed** (for awareness): read-only ops, working-dir edits, lock-file installs, read-only HTTP, push to session-created branches.

Run `claude auto-mode defaults` for the live rule lists. Trusted infrastructure is configured via `autoMode.environment` — see https://code.claude.com/docs/en/auto-mode-config.

</context>

## Decision Matrix on Denial

<required>

Four outcomes after a classifier block — pick exactly one, surface it to the user:

- **(a) Safer alternative exists** — Propose a non-blocked variant. Example: classifier blocked `git push --force` → propose `git push --force-with-lease` only if the original intent was safety-flagged; if intent was "rewrite history", ask the user.
- **(b) Destructive but the user actually wants it** — Ask the user to (i) state explicit consent in chat (treated as a single-turn boundary lift), or (ii) add an `allow` rule to `~/.claude/settings.json`. Do not proceed on assumption.
- **(c) Ambiguous intent** — `AskUserQuestion` to clarify what they really want. Often the right answer is a less risky path the agent didn't see.
- **(d) Defer or abandon** — Tell the user the action is blocked and the task can't proceed without their decision. Park the work, document state, and stop.

</required>

## User-Stated Boundaries

<context>

Phrases like "don't push", "wait until I review", or "we don't deploy on Fridays" are treated as **block signals** by the classifier — even when the default rules would allow the action. Important properties:

- Boundaries are **not stored as rules**. The classifier re-reads them from the transcript on each check.
- Boundaries can be **lost on context compaction** (`/clear`, "Summarize from here", or summary rollover). For a guarantee that survives compaction, recommend the user add a `permissions.deny` rule in `~/.claude/settings.json`.
- Claude's own judgment that a boundary's condition was met does **not** lift it. Only an explicit user message lifts a boundary.

</context>

## Hard Deny Rules

<context>

`hard_deny` blocks an action unconditionally; no `allow` rule overrides it. The user owns the configuration; the agent's job is to recognize the outcome and route to **(d) abandon** — never propose workarounds.

</context>

## Fallback Thresholds

<context>

- **3 consecutive blocks** → auto mode pauses; CLI resumes prompting. Any allowed action resets the consecutive counter.
- **20 total blocks** in a session → auto mode pauses for the rest of the session.
- Non-interactive `-p` mode → repeated blocks **abort** the session (no user to prompt).

</context>

## Subagent Behavior

<context>

Subagents inherit the parent's classifier (checked at spawn, per-action, and on return). A subagent's `permissionMode` frontmatter is **ignored** in auto mode.

</context>

## Protected Paths

<context>

Writes to repo/Claude config dots (`.git`, `.claude/*` except commands/agents/skills/worktrees, shell rc files, `.mcp.json`, `.claude.json`, etc.) route to the classifier and usually block. See https://code.claude.com/docs/en/permission-modes#protected-paths for the full enumeration.

Editing `~/.claude/settings.json` from inside a project session almost always trips the classifier. Recommend the user edit it themselves, or invoke the Claude Code `update-config` plugin command.

</context>

## Pre-approved Operation Patterns

<context>

**Reducing classifier friction for known-safe operations**
via `~/.claude/settings.json`:

`permissions.allow` accepts `{ "tool": "Bash", "command": "[glob]" }`.
Common patterns that reduce denial loops without compromising safety:
- `git push --force-with-lease origin feat/*` — session branches
- `gh pr merge --squash *` — gh handles its own confirmations
- `rm -rf .claude/worktrees/*` — session artifact cleanup

**Principle:** Pre-approve only operations bounded by session-local
state (branches you created, worktrees you own). Never pre-approve
operations on shared state (main, production, IAM).

**Note:** `AskUserQuestion` authorization is conversational — the
classifier does not recognize it as a persistent permission grant.
For repeat ops, the fix is `permissions.allow` in settings, not
asking again each time.

</context>

<related>

- `@smith-ctx-claude/SKILL.md` - Permission modes overview (this skill is the deep-dive for the `auto` mode)
- `@smith-git/SKILL.md` - Force-push and push-to-main behavior (common classifier triggers)
- `@smith-gh-pr/SKILL.md` - PR push and merge flows
- `@smith-guidance/SKILL.md` - Ask-before-assuming, anti-sycophancy (the denial-recovery protocol is an application of these)

</related>

## ACTION (Recency Zone)

<required>

**On every classifier denial:**
1. Pause — no follow-up tool call this turn
2. Restate action + verbatim classifier reason
3. Map to outcome (a)–(d) and surface to user

**On second denial of the same logical action:**
- Use `AskUserQuestion` (not prose) to force a choice

**On `hard_deny`:**
- Never propose a workaround — outcome (d) abandon

**Before invoking known classifier-sensitive actions:**
- Force push, push to `main`, production deploys, IAM grants, cloud-storage mass deletes → confirm with the user first, even before the first classifier check

</required>
