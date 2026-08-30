---
name: smith-checkpoint
description: Memory checkpoint — save the current session's durable state into both memory systems (Serena memory, Basic-Memory note) in their required formats. Invoke with /smith-checkpoint.
argument-hint: [label] [plan=path]
---

# /smith-checkpoint — persist session state to both memories

Capture what would otherwise be lost across sessions. Arguments:
- `label`: short checkpoint label (required)
- `plan=path`: plan file path (optional, provided by ctx-claude stop hook)

Save the SAME facts to both backends, each in its own format; do not skip one.

## What to capture

Durable only (not transient chatter): goals/decisions, file:line anchors,
PR/commit SHAs, open follow-ups, and any correction the user gave on how to
work. Convert relative dates to absolute. Omit what the repo/git already
records.

## Targets and formats

1. **Serena** (`mcp__serena__write_memory`): a snake_case memory capturing the
   checkpoint; update the matching existing memory if present.
2. **Basic-Memory** (`mcp__basic-memory__write_note`): a note under the project
   folder; type `decision` for material decisions, else `guide`/`note`.

## Naming strategy

**Use semantic names based on checkpoint context, not generic labels:**

- **With plan file**: Use plan basename
  - Serena: `plan_basename` (snake_case, e.g., `priority_2_context_dry`)
  - Basic-Memory: Title Case (e.g., "Priority 2: Context DRY")
- **Without plan**: Use descriptive label from current work context
  - Never use bare "context-limit" or standalone timestamps
  - Example: `feature_auth_implementation`, `bugfix_memory_leak`
- **Label argument**: Passed from enforce-clear.sh, derived from plan basename or session timestamp

**Consistency**: Same semantic name across label, Serena memory, Basic-Memory note (modulo format).

## Procedure

1. **Draft checkpoint content once** (the shared canonical facts).
2. **Transform to both formats** from the same content:
   - Serena: `write_memory(name=label, content=facts)`
   - Basic-Memory: `write_note(title=readable_label, type=..., content=facts)`
3. Reconcile against existing entries in each system (update, don't duplicate).
4. Write to both backends; confirm each write succeeded.
5. If any backend write fails, do NOT report success: name which succeeded
   and which failed, retry the failed one, and flag the systems left out of
   sync (no silent partial checkpoint).
6. On full success, report in-band what was saved and where
   (paths/permalinks/slugs).
7. **Arm the reload flag (Claude Code only), then emit the Reload block.** On Claude Code,
   run the bridge and check its exit status BEFORE emitting the block, so the block only
   claims a flag when one was actually written:

   ```
   ~/.claude/skills/smith-plan-claude/scripts/write-reload-flag.sh "«label»"
   ```

   The script exits non-zero (without printing "Wrote reload flag") if the flag could not be
   written. If it fails — or on any non-Claude-Code platform where you don't run it — emit the
   block with the `Reload flag` line dropped and rely on the manual `/smith-recon` line. On
   success it writes a `.pending-memory-restore-*` flag that the next `/clear` scans.

   What that `/clear` then does with the flag branches on several inputs, and the conditions
   that select between those branches are stated in ONE place: the "Checkpoint memory-restore
   flag" section of `smith-plan-claude/references/HOOKS.md`, whose verdict table names each
   outcome that becomes a row. Send readers there. Do not restate those conditions, here or in
   the block below; every attempt so far has been wrong in one direction or another, because
   writing out one algorithm in two prose passages leaves them free to drift apart. The block
   names outcomes, and when a restore happens — never which one you will get. It is emitted into
   projects that have no copy of this repository, so it must carry that much on its own and must
   not cite a path from here.

   Three things you DO need in order to word the block correctly. Exit 0 proves the flag was
   WRITTEN, not that anything will read it. A restore, where one happens, executes at the user's
   FIRST PROMPT after `/clear` (any prompt): SessionStart hook output is context-only, and no
   hook can start a model turn in an interactive session — a Claude Code limit, not configurable
   (`initialUserMessage` applies only to `-p` non-interactive runs), so never describe this as
   restoring "on /clear" or without user input. And the whole path needs the smith-plan-claude
   SessionStart hook registered plus the Serena / Basic-Memory MCP servers available (see README
   "Hooks").

## Reload after /clear

End every checkpoint with this block — the canonical reload recipe. Fill real
values; annotate each anchor with where it is reachable from, in plain language
(no shorthand codes). Include the `Reload flag` line only if the bridge (step 6)
reported success:

```
## Reload after /clear   (checkpoint: «label», «ISO-8601 local timestamp»)
Reload flag: written on THIS machine. A restore is NOT guaranteed — the next /clear may instead list this checkpoint for you to pick, or delete the flag without restoring anything. If it does restore, that happens at your FIRST PROMPT after /clear: type anything; nothing visible happens at /clear itself (Claude Code limit: hooks cannot start a turn). Do not rely on it: use the manual line below, wherever the stores listed under it are reachable.
Manual resume: /smith-recon "resume my work thread on «label»"
Where this checkpoint's state lives (reachable from):
- Serena:       «snake_case_name»          — this machine only, unless .serena/memories is committed
- Basic-Memory: «permalink»                — this machine only, unless Basic-Memory Cloud is enabled
- plan (if any): ~/.claude/plans/«file».md — this machine only
A cloud/fresh-clone run (/schedule, /code-review ultra, web) sees only committed git/PR state — none of the above unless noted portable.
```

This skill is platform-neutral: any agent can write the backends and emit the block; the
step-6 bridge is the Claude Code layer.
