---
name: smith-settings
description: Claude Code settings files — which config lives where (user / project / project-local / managed, and their precedence) plus a runnable convention-validator hook recipe that blocks actions violating repo rules. Use when editing settings.json or .claude config, deciding which scope a key belongs in, or building a hook that enforces a convention (commit/branch/file rules). For hooks internals see smith-ctx-claude; for permissions/auto-mode see smith-auto_mode.
---

# Claude Code Settings

<metadata>

- **Scope**: Settings file layout + scope precedence, and a convention-validator
  hook recipe. NOT a hooks or permissions deep-dive — those live elsewhere.
- **Load if**: Editing `settings.json` / `.claude` config, choosing which scope a
  key belongs in, OR building a hook that enforces a repo convention.
- **Prerequisites**: `@smith-ctx-claude/SKILL.md` (hooks + permission-mode
  deep-dive), `@smith-auto_mode/SKILL.md` (permissions, `$defaults`, classifier)
- **Authoritative source**: https://docs.claude.com/en/docs/claude-code/settings
  + .../hooks (verified 2026-06-25)

</metadata>

## CRITICAL: One Key, One Scope (Primacy Zone)

<required>

- Put a key in the RIGHT file: shared team config → committed
  `.claude/settings.json`; personal/secret/machine-specific → gitignored
  `.claude/settings.local.json`; cross-project defaults → `~/.claude/settings.json`.
- A key set in a higher-precedence scope overrides the same key lower down;
  omitting it leaves the lower value in place (keys merge, they don't wipe).
- `permissions.defaultMode: "auto"` is honored ONLY in `~/.claude/settings.json`
  — it is ignored in project/local settings, so a repo can't grant itself auto.

</required>

<forbidden>

- Re-documenting hook events/handlers or permission rules HERE — cross-ref
  `@smith-ctx-claude/SKILL.md` and `@smith-auto_mode/SKILL.md` instead (DRY).
- Committing secrets or a personal `defaultMode` into `.claude/settings.json` —
  that file ships to every teammate. Personal overrides go in `.local.json`.

</forbidden>

## Settings files & precedence

<context>

Four scopes, highest precedence first (a managed policy can't be overridden):

- Managed policy settings — org/MDM deployed; absolute.
- `.claude/settings.local.json` — your personal, gitignored project overrides.
- `.claude/settings.json` — committed, shared project config.
- `~/.claude/settings.json` — your cross-project user defaults.

Command-line `--settings <file-or-json>` merges as a temporary top layer.
The same scope names appear as `ConfigChange` hook matchers (`user_settings`,
`project_settings`, `local_settings`, `policy_settings`, `skills`) — use that
event to audit or block settings changes.

</context>

## Convention-validator hook recipe

<context>

A `PreToolUse` hook can ENFORCE a repo convention by rejecting the offending
tool call (`exit 2` blocks it and shows stderr to Claude). The `if` field
narrows the handler to just the calls you care about, using permission-rule
syntax. Example: block any `git commit` made on a protected branch — enforcing
the smith "never commit to main/master/develop" rule mechanically.

In committed `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/block-protected-commit.sh",
            "args": [],
            "if": "Bash(git commit *)"
          }
        ]
      }
    ]
  }
}
```

`args` is set (to `[]`) because `command` uses the `${CLAUDE_PROJECT_DIR}` path
placeholder — that selects exec form, where the placeholder is substituted and
no shell re-tokenizes the path.

In `.claude/hooks/block-protected-commit.sh` (chmod +x):

```bash
#!/usr/bin/env bash
set -euo pipefail
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
case "$branch" in
  main|master|develop)
    echo "Blocked: commit on protected branch '$branch'. Use a feature branch." >&2
    exit 2
    ;;
esac
exit 0
```

Generalize the same shape: swap the `if` pattern and script to validate branch
names (`Bash(git checkout -b *)`), file paths (`Edit(*)`), or a commit-message
format. For richer control than `exit 2`, a PreToolUse hook can return
`hookSpecificOutput.permissionDecision: "deny"` with a reason — see
`@smith-ctx-claude/SKILL.md`.

</context>

<related>

- `@smith-ctx-claude/SKILL.md` - Hook events/handlers, permission modes (deep-dive)
- `@smith-auto_mode/SKILL.md` - Permissions rules, `$defaults`, classifier lists
- `@smith-dev/SKILL.md` - Pre-commit checks this hook can enforce
- `@smith-git/SKILL.md` - The protected-branch rule the recipe enforces

</related>

## ACTION (Recency Zone)

<required>

**Placing a key:**
1. Shared team behavior → committed `.claude/settings.json`
2. Personal/secret/machine-specific → gitignored `.claude/settings.local.json`
3. Cross-project default → `~/.claude/settings.json` (only home for `auto`)

**Building a convention validator:**
1. `PreToolUse` + `matcher: "Bash"` + an `if` permission-rule to scope it
2. Script exits 2 to block (stderr is shown to Claude); use exec form (`args`)
   when `command` references a `${CLAUDE_PROJECT_DIR}` path placeholder

</required>
