# Smith AI Agent Skills

AI agent skills for development with progressive disclosure.

<metadata>

- **Always loaded**: @smith-principles/SKILL.md, @smith-standards/SKILL.md, @smith-guidance/SKILL.md, @smith-ctx/SKILL.md
- **Load condition**: Session start (all platforms)
- **Token budget**: per-skill <2000 tokens; keep this always-loaded index minimal

</metadata>

## Platform Context (Load First)

<required>

**Auto-detect platform in order:**
1. **MCP servers**: Check for `cursor-ide-browser` or `cursor-browser-extension` → **Cursor** → Load `@smith-ctx-cursor/SKILL.md`
2. **MCP servers**: Check for `kiro-*` → **Kiro** → Load `@smith-ctx-kiro/SKILL.md`
3. **System prompt**: If mentions "Claude Code" → **Claude Code** → Load `@smith-ctx-claude/SKILL.md`
4. **Default**: Ask user or use Cursor (most common)

</required>

## Claude Code Skills Integration

<context>

**Symlink for skill discovery:**
```shell
ln -sf $HOME/.smith $HOME/.claude/skills
```

All skills use "smith-" prefix to avoid conflicts with Claude Code built-in commands (`/context`, `/ide`, `/skills`, etc.).

</context>

## Serena MCP Integration (If Available)

<context>

When Serena MCP is available, prefer Serena tools for file I/O and semantic
edits, and use Serena project memories for durable cross-session context.
See `@smith-serena/SKILL.md` for tool-preference and memory-sync rules.

**Loading protocol** (self-contained — no external memory required):
- On entry, read each workspace `AGENTS.md` / `CLAUDE.md`. Claude Code
  auto-loads `CLAUDE.md` (not a bare `AGENTS.md`) — see `@smith-skills/SKILL.md`.
- Load applicable smith skills via the Semantic Activation triggers below.

</context>

## Core Principles

DRY, KISS, YAGNI, SOLID, HHH — defined in @smith-principles/SKILL.md
(force-loaded), HHH in @smith-guidance/SKILL.md. Not restated here.

## Skill Loading

<required>

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

</required>

## Skill Notification

<required>

ALWAYS emit one line per skill invocation, in the message where it shapes your
work: `using @skill-name (reason)`. Group multiple skills on one line. This is
the user's only in-conversation visibility into which skills actually loaded —
do not skip it because the Skill tool already logs the call.

</required>

## Proactive Context Management

<required>

- **At warning threshold**: Warn, prepare retention criteria, unload unused skills
- **At critical threshold**: CRITICAL - context reset required (see platform skill for thresholds and command)

</required>

## Available Skills

The live skill list is injected by the harness every session. Full curated
catalog (categorized, with descriptions) lives in
`smith-ctx-claude/REFERENCE.md`.

## Semantic Activation

<required>

Skills auto-trigger by frontmatter `description`; the skill-router
UserPromptSubmit hook (`@smith-ctx-claude/scripts/skill-router.mjs`, table
`skill-triggers.json`) is the deterministic safety net. The full human-readable
trigger table lives in `smith-ctx-claude/REFERENCE.md` (keep it in sync with
`skill-triggers.json`). The verify-before-proposing rule for
external-dependency recommendations lives in `@smith-research/SKILL.md`.

</required>

## Platform Compatibility

**Native AGENTS.md**: Claude Code, OpenAI Codex, Amp, Jules, Kiro, Cursor
**Config required**: Gemini CLI, Aider
**Note**: Cursor also supports `.mdc` format, but AGENTS.md works via MCP integration

## Kiro Terminal (CRITICAL)

<forbidden>

- echo with double quotes (hangs)
- heredoc syntax (fails)
- Complex zsh themes (hangs)

</forbidden>

<required>

- Use Python scripts for file generation
- Prefer Serena MCP tools over Kiro native file operations
- Use single quotes or write to file instead of echo

</required>

<related>

- @smith-principles/SKILL.md - Core principles (DRY, KISS, YAGNI, SOLID)
- @smith-standards/SKILL.md - Universal coding standards
- @smith-guidance/SKILL.md - AI agent behavior patterns
- @smith-ctx/SKILL.md - Context management, proactive recommendations

</related>
