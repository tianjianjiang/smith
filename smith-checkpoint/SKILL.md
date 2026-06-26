---
name: smith-checkpoint
description: User-invoked memory checkpoint — save the current session's durable state into all three memory systems (Serena memory, Basic-Memory note, auto-memory) in their required formats. Invoke with /smith-checkpoint.
disable-model-invocation: true
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
