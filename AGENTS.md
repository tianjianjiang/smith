# Smith AI Agent Skills

AI agent skills for development with progressive disclosure.

**Always loaded:** @smith-principles/SKILL.md, @smith-standards/SKILL.md, @smith-guidance/SKILL.md, @smith-ctx/SKILL.md
**Load condition:** Session start (all platforms)
**Token budget:** per-skill <2000 tokens; keep this always-loaded index minimal

## Platform Context (Load First)

**Auto-detect platform in order:**
1. **MCP servers**: Check for `cursor-ide-browser` or `cursor-browser-extension` → **Cursor** → Load `@smith-ctx-cursor/SKILL.md`
2. **MCP servers**: Check for `kiro-*` → **Kiro** → Load `@smith-ctx-kiro/SKILL.md`
3. **System prompt**: If mentions "Claude Code" → **Claude Code** → Load `@smith-ctx-claude/SKILL.md`
4. **Default**: Ask user or use Cursor (most common)

## Claude Code Skills Integration

**Symlink for skill discovery:**
```shell
ln -sf $HOME/.smith $HOME/.claude/skills
```

All skills use "smith-" prefix to avoid conflicts with Claude Code built-in commands (`/context`, `/ide`, `/skills`, etc.).

## Serena MCP Integration (If Available)

When Serena MCP is available, prefer Serena tools for file I/O and semantic
edits, and use Serena project memories for durable cross-session context.
See `@smith-serena/SKILL.md` for tool-preference and memory-sync rules.

**Loading protocol** (self-contained — no external memory required):
- On entry, read each workspace `AGENTS.md` / `CLAUDE.md`. Claude Code
  auto-loads `CLAUDE.md` (not a bare `AGENTS.md`) — see `@smith-skills/SKILL.md`.
- Load applicable smith skills via the Semantic Activation triggers below.

## Checkpoint & Reload Prerequisites

`/smith-checkpoint` (`@smith-checkpoint/SKILL.md`) captures durable state to three
backends and ends with a Reload block. Its dependencies:
- **MCP servers**: Serena (`write_memory`/`read_memory`) and Basic-Memory
  (`write_note`) — all **local-only** by default (Serena memories gitignored;
  Basic-Memory local SQLite unless cloud enabled; auto-memory under `~/.claude`).
- **Reload flag**: the memory-restore directive is injected as context on the next
  `/clear` only if the `smith-plan-claude` SessionStart:clear hook is registered
  (see README.md "Hooks" / `smith-plan-claude/references/HOOKS.md`); the restore
  itself runs at the user's first prompt after `/clear` — no hook can start a turn
  in an interactive session. Otherwise resume manually via the Reload block's
  `/smith-recon "resume …"` line.
- **Cloud/fresh-clone runs** (`/schedule`, `/code-review ultra`, web) see none of the
  local backends — only committed git/PR state.

## Core Principles

DRY, KISS, YAGNI, SOLID, HHH — defined in @smith-principles/SKILL.md
(force-loaded), HHH in @smith-guidance/SKILL.md. Not restated here.

## Skill Loading

**Skills auto-trigger by their frontmatter `description`** — the native Claude
Code mechanism. The `skill-router` UserPromptSubmit hook
(`@smith-ctx-claude/scripts/skill-router.mjs`, table `skill-triggers.json`)
deterministically surfaces candidate skills from your input every prompt as a
safety net.

**When a trigger fires, invoke the skill via the Skill tool** — that loads its
SKILL.md for you. Read a SKILL.md by hand only to quote or edit it, never as a
substitute for invoking.

No "identify → Read → unload" bookkeeping: it depended on model discipline and
was ~0% executed in practice (smith-* skills almost never loaded; the router
hook replaces it). See `@smith-ctx-claude/SKILL.md`.

## Guard Hooks

Two PreToolUse guards ship alongside the router (registered user-globally in
`~/.claude/settings.json`; registration snippets in README.md "Hooks"):
`branch-guard` blocks file edits while a repo is on its default branch —
create the dedicated branch/worktree BEFORE the first edit (rule in
`@smith-git/SKILL.md`; per-repo opt-out `.claude/branch-guard.disabled`);
`worktree-dirty-guard` blocks `EnterWorktree` on a dirty checkout because
uncommitted changes never carry into a new worktree (details in
`@smith-worktree/SKILL.md`).

## Skill Notification

ALWAYS emit one line per skill invocation, in the message where it shapes your
work: `using @skill-name (reason)`. Group multiple skills on one line. This is
the user's only in-conversation visibility into which skills actually loaded —
do not skip it because the Skill tool already logs the call.

## Proactive Context Management

- **At warning threshold**: Warn, prepare retention criteria, unload unused skills
- **At critical threshold**: CRITICAL - context reset required (see platform skill for thresholds and command)

## Available Skills

The live skill list is injected by the harness every session. Full curated
catalog (categorized, with descriptions) lives in
`smith-ctx-claude/REFERENCE.md`.

## Semantic Activation

Skills auto-trigger by frontmatter `description`; the skill-router
UserPromptSubmit hook (`@smith-ctx-claude/scripts/skill-router.mjs`, table
`skill-triggers.json`) is the deterministic safety net. The full human-readable
trigger table lives in `smith-ctx-claude/REFERENCE.md` (keep it in sync with
`skill-triggers.json`). The verify-before-proposing rule for
external-dependency recommendations lives in `@smith-research/SKILL.md`.

## Platform Compatibility

**Native AGENTS.md**: Claude Code, OpenAI Codex, Amp, Jules, Kiro, Cursor
**Config required**: Gemini CLI, Aider
**Note**: Cursor also supports `.mdc` format, but AGENTS.md works via MCP integration

## Kiro Terminal (CRITICAL)

- Use Python scripts for file generation
- Prefer Serena MCP tools over Kiro native file operations
- Use single quotes, or write to a file, instead of echo with double quotes
  — double-quoted echo hangs in Kiro's terminal
- Heredoc syntax fails in Kiro's terminal — write to a file instead
- Complex zsh themes hang in Kiro's terminal — keep the shell theme simple

## Related

- @smith-principles/SKILL.md - Core principles (DRY, KISS, YAGNI, SOLID)
- @smith-standards/SKILL.md - Universal coding standards
- @smith-guidance/SKILL.md - AI agent behavior patterns
- @smith-ctx/SKILL.md - Context management, proactive recommendations
