---
name: smith-checkpoint
description: Memory checkpoint — save the current session's durable state into all three memory systems (Serena memory, Basic-Memory note, auto-memory) in their required formats. Invoke with /smith-checkpoint.
argument-hint: [short label]
---

# /smith-checkpoint — persist session state to all 3 memories

Capture what would otherwise be lost across sessions. Argument = a short label
for the checkpoint. Save the SAME facts to all three, each in its own format;
do not skip one.

## What to capture

Durable only (not transient chatter): goals/decisions, file:line anchors,
PR/commit SHAs, open follow-ups, and any correction the user gave on how to
work. Convert relative dates to absolute. Omit what the repo/git already
records.

## Targets and formats

1. **auto-memory** (`~/.claude/projects/<project>/memory/`): one file per fact
   with frontmatter (`name`, `description`, `metadata.type`:
   user|feedback|project|reference); body with `[[links]]`. Add a one-line
   pointer to `MEMORY.md`. Check for an existing file to UPDATE before creating
   a duplicate. See the memory rules in the session system prompt.
2. **Serena** (`mcp__serena__write_memory`): a snake_case memory capturing the
   same checkpoint; update the matching existing memory if present.
3. **Basic-Memory** (`mcp__basic-memory__write_note`): a note under the project
   folder; type `decision` for material decisions, else `guide`/`note`.

## Procedure

1. Draft the checkpoint content once (the shared facts).
2. Reconcile against existing entries in each system (update, don't duplicate).
3. Write to all three; confirm each write succeeded.
4. If any backend write fails, do NOT report success: name which succeeded
   and which failed, retry the failed one, and flag the systems left out of
   sync (no silent partial checkpoint).
5. On full success, report in-band what was saved and where
   (paths/permalinks/slugs).
6. **Arm auto-reload (Claude Code only), then emit the Reload block.** On Claude Code,
   run the bridge and check its exit status BEFORE emitting the block, so the block only
   claims auto-reload when the flag was actually written:

   ```
   ~/.claude/skills/smith-plan-claude/scripts/write-reload-flag.sh "«label»"
   ```

   The script exits non-zero (without printing "Wrote reload flag") if the flag could not be
   written. If it fails — or on any non-Claude-Code platform where you don't run it — emit the
   block with the `Auto-reload` line dropped and rely on the manual `/smith-recon` line. It drops
   a `.pending-memory-restore-<key>` flag that `on-session-clear.sh` reads to auto-inject the
   memory-restore directive on the next `/clear` — see `@smith-plan-claude/SKILL.md`. Needs the
   smith-plan-claude SessionStart hook registered and the Serena / Basic-Memory MCP servers
   available (see README "Hooks").

## Reload after /clear

End every checkpoint with this block — the canonical reload recipe. Fill real
values; annotate each anchor with where it is reachable from, in plain language
(no shorthand codes). Include the `Auto-reload` line only if the bridge (step 6)
reported success:

```
## Reload after /clear   (checkpoint: «label», «ISO-8601 local timestamp»)
Auto-reload: on the next /clear on THIS machine, a memory-restore directive is injected (flag written).
Manual resume: /smith-recon "resume my work thread on «label»"
Where this checkpoint's state lives (reachable from):
- auto-memory:  memory/«file».md          — this machine only (Claude Code home dir)
- Serena:       «snake_case_name»          — this machine only, unless .serena/memories is committed
- Basic-Memory: «permalink»                — this machine only, unless Basic-Memory Cloud is enabled
- plan (if any): ~/.claude/plans/«file».md — this machine only
A cloud/fresh-clone run (/schedule, /code-review ultra, web) sees only committed git/PR state — none of the above unless noted portable.
```

This skill is platform-neutral: any agent can write the backends and emit the block; the
step-6 bridge is the Claude Code layer.
