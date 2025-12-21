# Kiro Context Management

<metadata>

- **Scope**: Kiro-specific context management, terminal limitations, tool preferences
- **Load if**: Using Kiro IDE (ALWAYS load first in Kiro sessions)
- **Prerequisites**: None (this file loads before other rules)

</metadata>

## CRITICAL: Terminal Limitations (Primacy Zone)

<forbidden>

**Terminal commands that cause Kiro to freeze:**

- NEVER use `echo` with double quotes (causes hang)
- NEVER use heredoc syntax (`<<EOF`) (fails in Kiro terminal)
- NEVER use complex zsh themes (powerlevel10k, oh-my-zsh cause timeouts)
- NEVER use interactive editors (vim, nano) in automated commands
- NEVER use pagers (less, more) in automated commands
- NEVER chain commands with `&&` or `||` in complex scripts
- NEVER expect second command in same session to return reliably (zsh bug)

</forbidden>

<required>

**Terminal best practices for Kiro:**

- Use Python scripts instead of complex shell commands
- Write output to files, then read files (not echo)
- Use `-m` flag with git commit (avoid editor)
- Use `--no-pager` with git commands
- Use simple bash syntax over zsh features
- Run one command per terminal invocation when possible
- Add timeouts to long-running commands

</required>

## CRITICAL: File Operation Issues

<forbidden>

**Kiro native tool issues:**

- `strReplace` fails on duplicate content (use Serena instead)
- `readFile` silently truncates large files
- File writes can create duplicate sections
- Mid-operation aborts during file reads/edits

</forbidden>

<required>

**When Serena MCP available**: Prefer Serena tools over Kiro native. See @serena.md for tool preference order.

</required>

## Context Thresholds

- **Warning**: 70% capacity
- **Critical**: 80% capacity (auto-summarize triggers)
- **Action**: Start new session or wait for auto-summarize

**Context inspection**: Check context meter in Kiro chat panel

## AGENTS.md Integration

Kiro automatically loads AGENTS.md from workspace root (Kiro v0.5.0+). No separate `.kiro/steering/` files needed.

**How it works:**
- Place AGENTS.md at workspace root
- Kiro reads it automatically at session start
- Include instructions for loading domain-specific files
- Critical rules (terminal limitations) embedded directly with XML tags

**Benefits:**
- Single source of truth for all platforms
- No platform-specific setup required
- Works with Claude Code, Codex, Kiro, Amp, Jules

## Verification

**Test**: Ask Kiro to run a simple command. It should avoid echo with quotes and prefer file-based output.

<related>

- @context.md - Universal context strategies
- @serena.md - Serena MCP tools (preferred over Kiro native)

</related>


## ACTION (Recency Zone)

<required>

**In Kiro sessions:**
1. Avoid echo with double quotes
2. Use Python scripts for file generation
3. Prefer Serena MCP tools over native file ops
4. Check context meter at 70%

</required>
