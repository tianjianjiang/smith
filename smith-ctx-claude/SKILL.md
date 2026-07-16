---
name: smith-ctx-claude
description: Claude Code context management with /clear, /compact mechanics, stop hook enforcement at 60%, JSONL state recall, tool-output hygiene, auto memory, and system reminders. Reference dumps (hooks, permission modes, agent features, model routing) live in companion REFERENCE.md. Use when operating in Claude Code IDE or when context exceeds 50%.
---

# Claude Code Context Management

**Load if:** Using Claude Code, context >50%
**Prerequisites:** @smith-ctx/SKILL.md
**Companion (Layer 3, read on demand):** `smith-ctx-claude/REFERENCE.md` — hooks, linting hooks, permission modes, agent features + dispatch, /goal, model routing, tool search, plugin discovery, session analytics, moved trigger table + skill catalog. Read only when configuring those surfaces.

## CRITICAL: Context Commands

**Agent prompts for context status**, then recommends action.

**Thresholds and actions (graduated)**:
- 40-50%: Consider "Summarize from here" (targeted compression)
- 50%: Warning - recommend action (summarize or /clear)
- 60%: Critical - /clear mandatory (stop hook enforced)

**"Summarize from here"** preserves context before a checkpoint and compresses
everything after into a summary; pass focus instructions to steer it (access
via `/rewind`; full path in ACTION below).

**"/clear"** (full reset, save state first): stop hook enforced at 60% via
`smith-plan-claude` using `stop_hook_active` (official best practice).

Check for uncommitted work before running `/clear`.

## /compact — When to Avoid

`/compact` summarizes the **entire** conversation in-place; auto-compact fires
near the limit unless disabled (`PreCompact` hook runs first — persist state).
Prefer "Summarize from here" or /clear: /compact is lossy and non-deterministic
(you cannot pick the checkpoint; file:line refs / decisions can silently drop).
If it does run, pass focus instructions where allowed and re-verify file:line
refs + open decisions against the repo afterward.

## Tool-Output Hygiene

Every byte a tool returns persists in context for the rest of the session and
is itself re-summarized on compaction. Large spills (full file reads,
verbose command output, subagent transcripts) are the main avoidable context
cost.

- Process, don't dump: filter/aggregate noisy output in a sandbox
  (context-mode `ctx_execute`/`ctx_batch_execute`) so only the derived answer
  enters context.
- Delegate noisy investigation (grep sweeps, log trawls) to a subagent; keep
  only its findings.
- Reference artifacts by `file:line` / path, not pasted content.
- Read targeted ranges, not whole files, when a section suffices.

## /clear - Full Context Reset

**Before `/clear`:**
1. Update plan file with current progress (if active)
2. Commit current work with detailed message
3. Save state to Serena memory with `write_memory()`
4. AFTER all tool calls complete, output a self-contained **Reload with:** block (plan path, memory name, resume command) — canonical format + reachability annotation in `@smith-checkpoint/SKILL.md` "Reload after /clear"

**Preserved**: Project files, CLAUDE.md, plan files. **Lost**: conversation history.

**After `/clear`:**
1. Plan auto-reloads with todo reconstruction ONLY if a flag file exists (from enforce-clear or on-plan-exit); state file alone = informational, not auto-resume
2. If Serena MCP available: list_memories(), read relevant memories
3. Re-read relevant files as needed
4. No memory saved? Recover intent from the JSONL transcript — see `smith-ctx-claude/REFERENCE.md` "JSONL State Recall"

## Commit-Early Pattern

- Do not batch commits to end of session — context resets lose uncommitted work
- If 15+ tool calls pass without a commit and there are uncommitted changes, commit with `#WIP` prefix to preserve progress
- Before destructive operations (rebase, `/clear`), commit or stash current work

## Stop Hook (Unified)

Stop hook enforcement is handled by `smith-plan-claude/scripts/enforce-clear.sh`. Uses real token counts from transcript JSONL (same data as Claude Code statusline) to calculate context percentage. A single unified hook covers both plan-active and non-plan contexts:

- **Real percentage**: Blocks at 60% context (from transcript token usage, not byte count)
- **Three branches**: Plan+pending, plan+completed, no-plan (plan filepath shown first, Serena optional)
- **Loop prevention**: Uses `stop_hook_active` field (official best practice)

**Config**: Only one Stop hook entry in `settings.json` (in `smith-plan-claude`).

## Auto Memory (Claude Code Native)

**Claude Code auto memory** stores agent-generated notes at:
`~/.claude/projects/«project-slug»/memory/`

- `MEMORY.md` - First 200 lines auto-loaded every session
- Topic files (e.g. `debugging.md`) - Read on demand
- Browse: `/memory` command
- Disable: `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`

**Auto memory vs Serena memory - complementary, not competing:**

**Auto memory** (long-lived project knowledge): architecture, conventions,
recurring debugging patterns, discovered user preferences, build/test quirks.

**Serena memory** (task-scoped continuity): session state, current task +
next steps, Ralph loop state, phase-boundary checkpoints, cross-reset
continuity.

**No sync needed** - different lifecycles. Auto memory accumulates knowledge;
Serena handles continuity.

## System Reminders (Auto-Injected Context)

Claude Code auto-injects system-reminder blocks in response to events. They
look like user messages but are NOT user input — don't treat them as
acknowledgements or replies. Respond to the underlying event only when action
is required.

Events: task-tools idle nudge, file-modification notice, skills-available list,
plan-mode transitions, auto-memory staleness, background-task completion, date
change, auto-mode active, bg-isolation guard refusal. Full descriptions (with
the relevant skill cross-refs) in `smith-ctx-claude/REFERENCE.md`
"System-Reminder Event Taxonomy".

## Active Plugin Side-Effects

Some plugins inject SessionStart hooks that alter behavior for the whole
session. Account for them; do not mistake their output for a user instruction
or an error.

- **caveman** — terse PROSE only; commits, PR/issue bodies, code, Slack drafts stay full prose (`@smith-slack`); its SessionStart hook restates the detail.
- **ponytail** — biases to the laziest working solution; build the full version when the user asks; its SessionStart hook restates the detail.
- **context-mode** — sandboxed analysis tools (`ctx_*`). Subprocess/`ctx_execute`
  writes do NOT persist to the host FS — use Write/Edit for real file changes.
  The recurring "vX outdated → /ctx-upgrade" banner is noise, not a failure.

These are output/behavioral contracts, not memory; they persist until the user
says "stop caveman" / "stop ponytail" / "normal mode".

## AskUserQuestion — Body Prose Is Hidden

The AskUserQuestion UI surfaces only the question text and each option's label
and description; surrounding message prose may be hidden. Put every
decision-critical fact (trade-offs, recommendation, what each choice commits to)
INSIDE the question and option fields, never only in the body. Recommendation
goes as the first option labelled "… (Recommended)".

**One scope decision per turn.** Ask ONE scope/approach decision at a time; do
not bundle several unrelated decisions into one AskUserQuestion call. A single
multiSelect for ONE coherent choice (e.g. which sources to sweep) is fine;
batching distinct decisions is not. (Implementation-phase confirmations that
follow logically from an approved plan need no re-ask.)

## Slash Command Invocation

When the user names a slash command (e.g. `/insights`, `/commit`, `/foo`), invoke it directly via the `Skill` tool. The user naming the command IS the confirmation it exists. A failed `Skill` call costs one round-trip; an exhaustive existence audit costs dozens of tool calls plus a confidently wrong conclusion.

Treat the user naming a slash command as sufficient grounds to try it — invoke `Skill(skill="«name»")` first rather than:
- Searching `~/.claude/plugins/`, marketplace catalogs, or plugin cache to "prove" the command exists before invoking it
- Grepping transcript JSONL files for prior invocations as existence proof
- Concluding a slash command "doesn't exist on this system" without trying `Skill(skill="«name»")` first

**If the `Skill` call fails** with "skill not found": surface the error, ask the user to confirm the name or install the plugin. Do not escalate to filesystem search.

## CLAUDE.md Persistence

**Location**: `$WORKSPACE_ROOT/.claude/CLAUDE.md` or `$HOME/.claude/CLAUDE.md`

**Put in CLAUDE.md** (always active): critical guardrails (NEVER/ALWAYS),
reference to @AGENTS.md, project-specific preferences.

**Put in skill files** (context-triggered): detailed technical guidelines,
platform-specific patterns.

## Related

- `smith-ctx-claude/REFERENCE.md` - Hooks, permission modes, agent features, model routing, moved trigger table + skill catalog (Layer-3 dumps)
- @smith-ctx/SKILL.md - Universal context strategies
- `@smith-auto_mode/SKILL.md` - Auto-mode classifier denial recovery
- `@smith-worktree/SKILL.md` - EnterWorktree/ExitWorktree, bgIsolation guard

## Before You Finish

**Proactive context management:**
1. At 40-50%: Try "Summarize from here" first
   - Esc+Esc -> select checkpoint -> Summarize
   - Guide: "Focus on «task», «decisions», «file:line refs»"
2. At 50%: Warn, prepare retention criteria
3. At 60%: Commit, update plan, save to Serena, "/clear"
4. After /clear: Plan auto-reloads; check Serena memories; recall from JSONL if no memory saved

**Throughout:** keep tool-output spill out of context (sandbox-process, delegate, reference by path).

**Agent RECOMMENDS - user executes the command.**
