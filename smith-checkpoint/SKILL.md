---
name: smith-checkpoint
description: Memory checkpoint
metadata:
  argument-hint: "[label] [plan=path] [body=path]"
---

# /smith-checkpoint — persist session state to both memories

Capture what would otherwise be lost across sessions. Arguments:
- `label`: short checkpoint label (required)
- `plan=path`: plan file path (optional, provided by ctx-claude stop hook)
- `body=path`: file holding the session body you drafted (see Procedure);
  without it the script records plan title, pending items and git state only

Save the SAME facts to both backends, each in its own format; do not skip one.

## What to capture

Durable only (not transient chatter): goals/decisions, file:line anchors,
PR/commit SHAs, open follow-ups, and any correction the user gave on how to
work. Convert relative dates to absolute. Omit what the repo/git already
records.

## Compression Requirements

**Target**: <400 tokens per checkpoint body (the script warns above about 1600 bytes)

**Format rules**:
1. **Use references, not content duplication**:
   - File locations: `file:line` only (e.g., `plan.md:244-296`)
   - Memory anchors: permalink/name only (e.g., `Serena: memory_name`)
   - NO full content quotes or verbose explanations
2. **Minimal prose**:
   - Decisions: one-line statement + consequence (if non-obvious)
   - Status: checklist format (markdown checkboxes)
   - Next steps: action verb + brief context
3. **Single-source content**:
   - Draft facts ONCE in canonical form
   - Transform to Serena (snake_case) and Basic-Memory (frontmatter + body)
   - Content body IDENTICAL except format-specific metadata

**Example body file** (the script prepends the title, Date, Plan and Session
header itself; the body starts at `## Completed`):
```markdown
## Completed
- [x] OAuth flow impl (`auth.ts:234-567`)
- [x] Token refresh logic (`refresh.ts:89-156`)

## Decisions
- Use JWT with 1h TTL (security requirement from `SECURITY.md:45`)
- Store refresh tokens in httpOnly cookies (prevents XSS)

## Next
Implement rate limiting (`auth-plan.md:121-145`)

## Related
- PR #789 (awaiting review)
- Serena: `oauth_implementation_status`
```

## Targets and formats

Both writes are done by `write-checkpoint.sh` through each backend's CLI
(`serena memories write`, `basic-memory tool write-note`):

1. **Serena**: a snake_case memory named after the label, written into the
   primary checkout's project (works from a worktree); re-checkpoint replaces it.
2. **Basic-Memory**: a note titled from the label under the project folder,
   type `guide`, tag `checkpoint`, written with `--overwrite` (re-checkpoint is
   an update, not a new note).

## Naming strategy

**Use semantic names based on checkpoint context, not generic labels:**

- **With plan file**: slug of the plan's first `# ` heading (filename only
  when the plan has no heading)
  - Serena: snake_case (e.g., `fix_smith_checkpoint_basic_memory_note_already_exists`)
  - Basic-Memory: the same words in Title Case
- **Without plan**: Use descriptive label from current work context
  - Never use bare "context-limit" or standalone timestamps
  - Example: `feature_auth_implementation`, `bugfix_memory_leak`
- **Label argument**: Passed from enforce-clear.sh: plan-title slug, else
  `consolidated_plan_checkpoint`, else `«cwd»_checkpoint`

**Consistency**: Same semantic name across label, Serena memory, Basic-Memory note (modulo format).

## Procedure

When invoked via `/smith-checkpoint` (no arguments required):

1. **Extract deterministic facts** (if transcript available):
   ```bash
   ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/smith-checkpoint/scripts/extract-session-facts.sh "$TRANSCRIPT_PATH"
   ```
   Provides: completed tasks, file edits, PRs, commits, git state

2. **Check for an active plan** — list `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plans/*.md` and check
   whether one matches this session's current work. If one does, pass it
   explicitly as `plan=«path»` in step 4; never rely on inference alone.
   (write-checkpoint.sh also falls back to the ctx-claude plan-state file
   when `plan=` is omitted, but an explicit path is more reliable when a
   plan is visibly in play.)

3. **Infer label automatically**:
   - If plan file exists: slug of its first heading (snake_case)
   - Otherwise: infer from current session's primary work
   - Follow Naming strategy above (semantic, descriptive)

4. **Draft the body** (<400 tokens, format above: Completed / Decisions /
   Next / Related, no title or Date/Plan/Session header):
   - Combine extracted facts (step 1) with rich context/reasoning
   - Add decisions (why, consequences), next steps with context
   - List Serena memories and Basic-Memory notes written this session under Related
   - Create file with Bash heredoc (Write tool requires Read first, even for new files):
     ```bash
     cat > "${CLAUDE_JOB_DIR:-/tmp}/checkpoint-body.md" <<'EOF'
     ## Completed
     - [x] ...
     
     ## Decisions
     ...
     
     ## Related
     ...
     EOF
     ```
   - Omit `body=` only when session produced nothing durable

5. **Call write-checkpoint.sh**:
   ```bash
   ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/smith-checkpoint/scripts/write-checkpoint.sh "«label»" "plan=«path»" "body=«body-file»"
   ```

6. The script (exit 0 on success):
   - Without `plan=`, falls back to the ctx-claude plan-state file for this
     session's cwd (same source the stop hook uses)
   - Prepends header (label, date, plan, session)
   - Adds plan path as first Related entry
   - Without `body=`, falls back to metadata only
   - Writes to both backends (Serena + Basic-Memory)
   - Outputs success to stderr, Reload block to stdout

7. If script exits non-zero, report stderr error.
8. On success, output Reload block to user.

## Runtime prerequisites

`/smith-checkpoint` (capture) and its post-`/clear` reload flag have runtime
dependencies. If they are missing, capture may still be attempted but the
checkpoint is **incomplete** — it is not successful until all three backend
writes succeed (the skill reports which failed rather than claiming success),
and reload degrades:

- **MCP servers** — the lifecycle writes and reads through them: **Serena**
  (`write_memory`/`read_memory`), **Basic-Memory** (`write_note` / note search).
  Both are **local-only** in a default setup (Serena memories live under
  `.serena/memories`, typically gitignored; Basic-Memory is a local SQLite DB
  unless Basic-Memory Cloud is enabled).
- **Reload-flag hook** — the memory-restore directive is injected as context on
  the next `/clear` only if the `smith-plan-claude` **SessionStart:clear** hook
  (`on-session-clear.sh`) is registered. A restore is NOT guaranteed; the full
  conditions and outcomes are in `smith-plan-claude/references/HOOKS.md`
  "Checkpoint memory-restore flag". Without that hook, use the manual
  `/smith-recon "resume …"` path printed in the checkpoint's Reload block.
- **Session-restart marker hook** — register `mark-session-restart.sh` on
  **SessionStart** for BOTH `clear` and `compact`. Without it, `inject-plan.sh`
  cannot tell a real restart from a high-context Stop the user simply worked
  through, and announces "POST-CLEAR RESUME" (plus the recent-plans listing) on
  the next prompt either way — including after a `/compact`. Registering it is
  what makes that announcement fire once per actual restart and name the route
  it took. Auto-reload keeps its old ungated behaviour until the hook has run
  once, so updating the scripts without this registration loses nothing. The
  registration block lives with the rest of the hook set in
  `smith-plan-claude/references/HOOKS.md` ("Configure the Hooks"), so there is
  one copy to keep correct rather than two.
- **Cloud / fresh-clone reach** — a cloud run (`/schedule`, `/code-review ultra`,
  Claude Code web) clones the repo fresh with no local home dir, so it sees
  **none** of the local backends — only committed git/PR state. Portable resume
  there needs committed-to-repo state or an enabled cloud MCP (deferred).
