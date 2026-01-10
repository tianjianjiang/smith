---
name: smith-ctx-kiro
description: Kiro-specific context management with terminal limitations, Serena MCP as mandatory tool, and file operation workarounds. Use when operating in Kiro IDE. LOAD FIRST in all Kiro sessions - critical platform constraints that prevent hangs and failures.
---

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

## CRITICAL: Serena MCP is Mandatory

<required>

**When Serena MCP is available, you MUST use Serena tools for all file operations.**

Kiro native tools have known reliability issues:
- `strReplace` fails on duplicate content
- `readFile` silently truncates large files
- File writes can create duplicate sections
- Mid-operation aborts during file reads/edits

**Tool Preference Order (mandatory):**
1. **Reading code**: `find_symbol`, `get_symbols_overview` > `readFile`
2. **Editing code**: `replace_content` (regex mode) > `strReplace`
3. **Navigation**: `find_referencing_symbols` > `grepSearch`
4. **Context**: `write_memory`, `read_memory` for persistent state

</required>

<forbidden>

- Using Kiro `strReplace` when Serena `replace_content` is available
- Using Kiro `readFile` for large files when Serena tools are available
- Ignoring Serena MCP availability

</forbidden>

## Serena Activation Workflow

<required>

**At session start:**
1. Check if Serena MCP is available
2. Run `activate_project` to initialize
3. Run `check_onboarding_performed` to verify setup
4. Run `list_memories` to discover available context
5. Run `read_memory` for relevant project context

**During work:**
- Use `write_memory` for important discoveries
- Use semantic tools (`find_symbol`, `replace_content`) over text-based

**Before compaction (70% context):**
- Save session state with `write_memory`

</required>

## Context Thresholds

- **Warning**: 70% capacity
- **Critical**: 80% capacity (auto-summarize triggers)
- **Action**: Save to Serena memory, then start new session or wait for auto-summarize

**Context inspection**: Check context meter in Kiro chat panel

## AGENTS.md Integration

Kiro automatically loads AGENTS.md from workspace root (Kiro v0.5.0+). No separate `.kiro/steering/` files needed.

**How it works:**
- Place AGENTS.md at workspace root
- Kiro reads it automatically at session start
- Include instructions for loading domain-specific files
- Critical rules (terminal limitations) embedded directly with XML tags

<related>

- `@smith-ctx/SKILL.md` - Universal context strategies
- `@smith-serena/SKILL.md` - Serena MCP tools (mandatory for Kiro)

</related>

## ACTION (Recency Zone)

<required>

**In Kiro sessions:**
1. Avoid echo with double quotes
2. Use Python scripts for file generation
3. Use Serena MCP tools (mandatory, not optional)
4. Check context meter at 70%
5. Save state to Serena memory before compaction

</required>
