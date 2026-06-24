---
name: smith-ctx-claude
description: Claude Code context management with /clear, /compact mechanics, stop hook enforcement at 60%, JSONL state recall, tool-output hygiene, auto memory, and system reminders. Reference dumps (hooks, permission modes, agent features, model routing) live in companion REFERENCE.md. Use when operating in Claude Code IDE or when context exceeds 50%.
---

# Claude Code Context Management

<metadata>

- **Load if**: Using Claude Code, context >50%
- **Prerequisites**: @smith-ctx/SKILL.md
- **Companion (Layer 3, read on demand)**: `smith-ctx-claude/REFERENCE.md` —
  hooks reference, recommended linting hooks, permission modes, agent
  features + dispatch, /goal, model routing, tool search, plugin discovery,
  session analytics. Read it only when configuring those surfaces; it is not
  needed for routine context management.

</metadata>

## CRITICAL: Context Commands (Primacy Zone)

<required>

**Agent prompts for context status**, then recommends action.

**Thresholds and actions (graduated)**:
- 40-50%: Consider "Summarize from here" (targeted compression)
- 50%: Warning - recommend action (summarize or /clear)
- 60%: Critical - /clear mandatory (stop hook enforced)

**"Summarize from here"** (preserves early context):
- Access: Esc+Esc (or /rewind) -> select checkpoint -> Summarize
- Keeps conversation before checkpoint intact
- Compresses everything after checkpoint into summary
- Optional: provide focus instructions for the summary
- Best when early decisions matter but later exploration is verbose

**"/clear"** (full reset, save state first):
- Stop hook enforced at 60% via `smith-plan-claude`
- Uses `stop_hook_active` (official best practice)

</required>

<forbidden>

- `/clear` without checking uncommitted work

</forbidden>

## /compact — Mechanics and When to Avoid

<context>

`/compact` summarizes the **entire** conversation into a model-written
summary and continues in the **same** session (contrast `/clear`, which wipes
history). Auto-compact also fires automatically near the context limit unless
disabled. The `PreCompact` hook fires first (use it to persist state).

**Prefer "Summarize from here" or /clear** because /compact is lossy and
non-deterministic about what it keeps — you cannot pick the checkpoint, and
file:line refs / decisions can silently drop. "Summarize from here" lets you
choose the boundary and give focus instructions; /clear gives a known-clean
reset after an explicit **Reload with:** block.

If /compact does run (manual or auto): pass focus instructions where the UI
allows, and treat the result as lossy — re-verify file:line refs and open
decisions against the repo afterward.

</context>

## Tool-Output Hygiene

<required>

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

</required>

## /clear - Full Context Reset

<required>

**Before `/clear`:**
1. Update plan file with current progress (if active)
2. Commit current work with detailed message
3. Save state to Serena memory with `write_memory()`
4. AFTER all tool calls complete, output a self-contained **Reload with:** block (plan path if applicable, memory name, resume command)

**Preserved**: Project files, CLAUDE.md, plan files
**Lost**: All conversation history

**After `/clear`:**
1. Plan auto-reloads with todo reconstruction ONLY if a flag file exists (explicit reload intent from enforce-clear or on-plan-exit). State file alone = informational, not auto-resume.
2. If Serena MCP available: call list_memories(), read relevant memories for session state
3. Re-read relevant files as needed

**JSONL state recall (recovery when no memory was saved):** the transcript is
preserved at `~/.claude/projects/<project-slug>/*.jsonl` and survives /clear
and compaction. Prior user prompts, decisions, and errors are recoverable from
it — `ctx_search(sort: "timeline")` indexes it, or grep the JSONL directly.
Use this to reconstruct intent before asking the user to repeat themselves.

</required>

## Commit-Early Pattern

<required>

- Do not batch commits to end of session — context resets lose uncommitted work
- If 15+ tool calls pass without a commit and there are uncommitted changes, commit with `#WIP` prefix to preserve progress
- Before destructive operations (rebase, `/clear`), commit or stash current work

</required>

## Stop Hook (Unified)

<context>

Stop hook enforcement is handled by `smith-plan-claude/scripts/enforce-clear.sh`. Uses real token counts from transcript JSONL (same data as Claude Code statusline) to calculate context percentage. A single unified hook covers both plan-active and non-plan contexts:

- **Real percentage**: Blocks at 60% context (from transcript token usage, not byte count)
- **Three branches**: Plan+pending, plan+completed, no-plan (plan filepath shown first, Serena optional)
- **Loop prevention**: Uses `stop_hook_active` field (official best practice)

**Config**: Only one Stop hook entry in `settings.json` (in `smith-plan-claude`).

</context>

## Auto Memory (Claude Code Native)

<context>

**Claude Code auto memory** stores agent-generated notes at:
`~/.claude/projects/<project-slug>/memory/`

- `MEMORY.md` - First 200 lines auto-loaded every session
- Topic files (e.g. `debugging.md`) - Read on demand
- Browse: `/memory` command
- Disable: `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`

</context>

<required>

**Auto memory vs Serena memory - complementary, not competing:**

**Auto memory** (long-lived project knowledge): architecture, conventions,
recurring debugging patterns, discovered user preferences, build/test quirks.

**Serena memory** (task-scoped continuity): session state, current task +
next steps, Ralph loop state, phase-boundary checkpoints, cross-reset
continuity.

**No sync needed** - different lifecycles. Auto memory accumulates knowledge;
Serena handles continuity.

</required>

## System Reminders (Auto-Injected Context)

<context>

Claude Code auto-injects system-reminder blocks in response to events. They look like user messages but are NOT user input — don't treat them as acknowledgements or replies. Common triggers:

- **Task tools idle nudge** — `TaskCreate`/`TaskUpdate` present but unused
- **File modification notice** — a touched file changed outside the agent's tool calls
- **Skills available list** — periodic re-enumeration of Skill entries (informational)
- **Plan-mode transitions** — `EnterPlanMode`/`ExitPlanMode`, and post-`/clear` auto-resume flag (see `@smith-plan-claude/SKILL.md`)
- **Auto-memory staleness** — reading a memory flagged old (verify against current code before asserting)
- **Background task completion** — a `Bash(run_in_background)` task ended
- **Date change** — local date rolled over
- **Auto mode active** — session is in auto mode (see `@smith-auto_mode/SKILL.md`)
- **bg-isolation guard refusal** — first edit in a bg session without a worktree (see `@smith-worktree/SKILL.md`)

Respond to the underlying event only when action is required.

</context>

## AskUserQuestion — Body Prose Is Hidden

<required>

The AskUserQuestion UI shows the user only the question text plus each
option's label and description — the surrounding prose in your message is NOT
rendered beside the dialog. Put every decision-critical fact (trade-offs,
recommendation, what each choice commits to) INSIDE the question and option
fields, never only in the message body. Recommendation goes as the first
option labelled "… (Recommended)". (Pairs with one-scope-decision-per-turn.)

</required>

## Slash Command Invocation

<required>

When the user names a slash command (e.g. `/insights`, `/commit`, `/foo`), invoke it directly via the `Skill` tool. The user naming the command IS the confirmation it exists. A failed `Skill` call costs one round-trip; an exhaustive existence audit costs dozens of tool calls plus a confidently wrong conclusion.

</required>

<forbidden>

- Searching `~/.claude/plugins/`, marketplace catalogs, or plugin cache to "prove" a slash command exists before invoking it
- Grepping transcript JSONL files for prior invocations as existence proof
- Concluding a slash command "doesn't exist on this system" without trying `Skill(skill="<name>")` first

</forbidden>

**If the `Skill` call fails** with "skill not found": surface the error, ask the user to confirm the name or install the plugin. Do not escalate to filesystem search.

## CLAUDE.md Persistence

**Location**: `$WORKSPACE_ROOT/.claude/CLAUDE.md` or `$HOME/.claude/CLAUDE.md`

<required>

**Put in CLAUDE.md** (always active): critical guardrails (NEVER/ALWAYS),
reference to @AGENTS.md, project-specific preferences.

**Put in skill files** (context-triggered): detailed technical guidelines,
platform-specific patterns.

</required>

<related>

- @smith-ctx/SKILL.md - Universal context strategies
- `smith-ctx-claude/REFERENCE.md` - Hooks, permission modes, agent features, model routing (Layer-3 dumps)
- `@smith-ctx-cursor/SKILL.md` - Cursor IDE context
- `@smith-ctx-kiro/SKILL.md` - Kiro platform context
- `@smith-plan-claude/SKILL.md` - Plan-specific hooks
- `@smith-ralph/SKILL.md` - Orchestration patterns (B/C)
- `@smith-git/SKILL.md` - Git commits, worktrees
- `@smith-prompts/SKILL.md` - Prompt caching optimization
- `@smith-style/SKILL.md` - Commit conventions, `#WIP` prefix
- `@smith-auto_mode/SKILL.md` - Auto-mode classifier denial recovery
- `@smith-worktree/SKILL.md` - EnterWorktree/ExitWorktree, bgIsolation guard
- `@smith-automation/SKILL.md` - /loop, ScheduleWakeup, Monitor, /schedule

</related>

## ACTION (Recency Zone)

<required>

**Proactive context management:**
1. At 40-50%: Try "Summarize from here" first
   - Esc+Esc -> select checkpoint -> Summarize
   - Guide: "Focus on [task], [decisions], [file:line refs]"
2. At 50%: Warn, prepare retention criteria
3. At 60%: Commit, update plan, save to Serena, "/clear"
4. After /clear: Plan auto-reloads; check Serena memories; recall from JSONL if no memory saved

**Throughout:** keep tool-output spill out of context (sandbox-process, delegate, reference by path).

**Agent RECOMMENDS - user executes the command.**

</required>
