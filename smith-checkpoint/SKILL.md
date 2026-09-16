---
name: smith-checkpoint
description: Memory checkpoint
metadata:
  argument-hint: "[label] [plan=path] [body=path] [serena=path]"
---

# /smith-checkpoint — persist session state to both memories

Capture what would otherwise be lost across sessions. Arguments:
- `label`: short checkpoint label (required)
- `plan=path`: plan file path (optional, provided by ctx-claude stop hook)
- `body=path`: file holding the session body you drafted (see Procedure);
  without it the script records plan title, pending items and git state only
- `serena=path`: directory of the Serena project to write to (optional;
  resolved to an absolute path; must contain `.serena/project.yml`). Default
  is the primary checkout; outside git and without `serena=` no project is
  passed and the Serena CLI's own default applies. When the current directory is itself a Serena
  project other than the chosen one, the script prints a divergence warning
  with the `serena=` value that would target it

Save the SAME facts to both backends, each in its own format; do not skip one.

## What to capture

Durable only (not transient chatter): goals/decisions, file:line anchors,
PR/commit SHAs, open follow-ups, and any correction the user gave on how to
work. Convert relative dates to absolute. Omit what the repo/git already
records.

## Compression Requirements

**Guideline**: aim for ~400 tokens per checkpoint body (the script prints a
note past ~1600 bytes). Completeness is the binding requirement: never drop a
decision, file:line anchor, PR/commit reference, or open follow-up to fit
this number — an oversized-but-complete checkpoint is a successful
checkpoint; a compact-but-incomplete one is not.

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

`write-checkpoint.sh` reads the existing memory/note under the label first
and merges the new dated entry into it instead of replacing it: the doc
under a given label is a continuously accumulating log, newest first, each
checkpoint opening with a `## «timestamp»` line. The body's own `##`
headings (Completed/Decisions/Next/Related, per Compression Requirements
below) sit at that same markdown level rather than nested under it — a
reader tells entries apart by the `## «timestamp»` lines, not by heading
depth. Nothing prior is dropped regardless of how compact today's entry
is — writing a ~400-token entry is safe because it lands on top of the
existing history, not in place of it.

Both backends use the same read-merge-write shape: read whatever exists
under the label, strip its `# LABEL` title line, and write back `# LABEL` +
the new entry + the prior entries as one document. Neither backend's write
primitive appends, so the merge happens in the script, not the CLI. A
backend-native `prepend`/`append` edit was deliberately NOT used for
Basic-Memory: it inserts before/after the whole note body, which would push
the `# LABEL` title line down under the growing entry stack instead of
leaving it at the top.

1. **Serena** (`serena memories read` + `serena memories write`): a
   snake_case memory named after the label, written into the primary
   checkout's project (works from a worktree), passed to the CLI as an
   absolute path. A Serena project is never auto-created: the script checks
   `serena=` for `.serena/project.yml` and exits before any write when it is
   missing; the primary checkout is passed unchecked and the Serena CLI
   itself refuses a directory without that file. Worktree-local memories
   (`<worktree>/.serena/memories/*.md`, left behind by MCP `write_memory`
   calls from a worktree session) are relocated into the primary checkout
   (always the primary checkout, regardless of `serena=`) before the write:
   moved when the name is new there, deleted when byte-identical, kept under
   `<name>__from_worktree_<worktree>.md` (numbered `_2`, `_3`, … when that
   name is taken) when the two differ; nothing already in the primary
   checkout is ever overwritten. When the primary checkout has no
   `.serena/memories/` directory the files stay where they are and a warning
   says so.
2. **Basic-Memory** (`basic-memory tool read-note` + `write-note --overwrite`):
   a note titled from the label, type `guide`, tag `checkpoint`, in the
   project selected per Runtime prerequisites "Backend selection" below
   (`--project <name>` on both calls when a project is configured and no
   profile lock is active; under a lock both calls omit it).
   `--overwrite` is passed unconditionally — it is safe on both a first
   write (nothing to conflict with) and a re-checkpoint (the payload is
   already the full merged document, so there is nothing to lose). The
   folder is taken from the existing note's own `file_path` (from the same
   `read-note` call) when one is found, so a re-checkpoint lands back in
   whatever folder the note already lives in rather than being force-moved;
   only a brand-new note falls back to the project folder (primary checkout
   name, else the current directory name when outside git).
   Known limitation: the read side still addresses the note by bare title,
   not by a folder-qualified permalink, so if the same label is ever
   checkpointed from two different Basic-Memory projects the read could
   resolve to the wrong project's note under Basic-Memory's title-search
   fallback. Not yet hardened — avoid reusing a label across projects.

**Other known limitations**, both accepted for now given a checkpoint is
one agent session's own tool, invoked sequentially rather than concurrently:
- **Read-merge-write is not atomic.** Two checkpoints racing for the same
  label (concurrent sessions, or a retry issued while the first attempt is
  still writing) can both read the same prior state and each write back
  `entry + prior`; whichever write lands second wins, silently dropping the
  other's entry. Likewise, if Serena's write succeeds but Basic-Memory's
  then fails, a naive retry re-reads Serena's already-updated memory and
  prepends a second near-duplicate entry there while Basic-Memory only gets
  one — there is no operation identifier to detect and dedupe a
  partially-completed retry.
- **The document has no size bound or rotation.** Every write sends the full
  accumulated history as one CLI argument; nothing truncates or archives old
  entries, so a long-lived label eventually risks hitting the `ARG_MAX`
  ceiling. Prune stale checkpoints under a label manually if this becomes a
  problem in practice.

Because both backends must carry the SAME facts, an existing note/memory
found under the label is always updated, never replaced wholesale — a
same-named re-checkpoint accumulates, it does not destroy.

## Naming strategy

**Look up the existing checkpoint identity before deriving a new label.**
A freshly-inferred label is only safe to use when nothing durable already
exists for this work thread — deriving a new label unconditionally each
checkpoint risks fragmenting one thread's history across several
similarly-named memories/notes (the read-then-merge behavior in `write-
checkpoint.sh` only accumulates when the label is an exact repeat). Before
step 3 below:
- If a plan file is in play, its `# ` heading already pins one deterministic
  label across checkpoints — no lookup needed unless the heading itself
  changed since the last checkpoint.
- Without a plan file (or if unsure the heading is unchanged), check for an
  existing checkpoint first: `serena memories list` (grep for a name
  matching the current work topic) and/or Basic-Memory `search-notes` /
  `read-note` on the candidate title. If a match is found, reuse ITS exact
  name — do not derive a new one.
- Only fall back to deriving a fresh label (below) when no existing
  checkpoint for this work is found.

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

3. **Look up existing checkpoint identity before naming** (see Naming
   strategy above): with a plan file, its heading already pins the label; without
   one, check `serena memories list` / Basic-Memory `search-notes` for a
   match on the current work topic and reuse its exact name if found.

4. **Infer label automatically** (only when step 3 found no existing
   checkpoint to reuse):
   - If plan file exists: slug of its first heading (snake_case)
   - Otherwise: infer from current session's primary work
   - Follow Naming strategy above (semantic, descriptive)

5. **Draft the body** (~400 tokens as a starting aim, per Compression
   Requirements above. Format: Completed / Decisions / Next / Related, no
   title or Date/Plan/Session header):
   - Combine extracted facts (step 1) with rich context/reasoning
   - Add decisions (why, consequences), next steps with context
   - List Serena memories and Basic-Memory notes written this session under
     Related. From a worktree, name Serena memories by the location the
     script prints on stderr after relocation (a memory written by MCP into
     the worktree ends up in the primary checkout, possibly under a
     `__from_worktree_` suffix)
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

6. **Call write-checkpoint.sh**:
   ```bash
   ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/smith-checkpoint/scripts/write-checkpoint.sh "«label»" "plan=«path»" "body=«body-file»"
   ```

7. The script (exit 0 on success):
   - Without `plan=`, falls back to the ctx-claude plan-state file for this
     session's cwd (same source the stop hook uses)
   - Refuses to run while `BASIC_MEMORY_CONFIG_DIR` or `BASIC_MEMORY_HOME`
     is set, or while `BASIC_MEMORY_MCP_PROJECT` names a different project
     than the repository's `basicMemory.primaryProject` (see Runtime
     prerequisites "Backend selection"); nothing is written in either case
   - Relocates worktree-local Serena memories into the primary checkout
     (see Targets and formats) before touching either backend
   - Builds a dated entry: `## «timestamp»`, plan, session, `**Git**`
     (branch, short SHA, dirty count) and, from a worktree, `**Worktree**`,
     `**Branch**`, `**Primary**`, and `**Resume**: EnterWorktree
     path=«worktree» before any file edit` — the resuming session reads
     the switch instruction from the memory itself, the reload flag stays
     reload-only
   - Adds plan path as first Related entry
   - Without `body=`, falls back to metadata only
   - Reads any existing memory/note under the label and prepends the new
     entry to it (see Targets and formats above); only the first checkpoint
     under a label creates fresh state
   - Writes to both backends (Serena + Basic-Memory) — these two writes are
     the only required success criteria
   - On Claude Code, also writes the post-`/clear` memory-restore flag via
     `write-reload-flag.sh` (see Runtime prerequisites below). This write is
     always optional: on another platform, or if that sibling script is
     missing, the step is skipped; if the sibling script runs but fails, its
     error is reported as a warning. Neither case fails the checkpoint —
     it only means auto-reload is unavailable for this checkpoint, not that
     the checkpoint itself failed
   - Outputs success to stderr, Reload block to stdout. The Reload block
     lists: the Serena memory file by absolute path (when a Serena project
     was resolved; outside git without `serena=`, the label and "Serena
     default project"), the Basic-Memory permalink
     with its project and folder, the plan, the worktree line (with the
     `EnterWorktree` step) when in a worktree, the relocation counts when
     any memory was moved, removed or renamed, and the reload flag path

8. If script exits non-zero, report stderr error.
9. On success, output Reload block to user.

## Runtime prerequisites

`/smith-checkpoint` (capture) and its post-`/clear` reload flag have runtime
dependencies. If they are missing, capture may still be attempted but the
checkpoint is **incomplete** — it is not successful until both backend
writes succeed (the skill reports which failed rather than claiming success),
and reload degrades:

- **MCP servers** — the lifecycle writes and reads through them: **Serena**
  (`write_memory`/`read_memory`), **Basic-Memory** (`write_note` / note search).
  Both are **local-only** in a default setup (Serena memories live under
  `.serena/memories`, typically gitignored; Basic-Memory is a local SQLite DB
  unless Basic-Memory Cloud is enabled).
- **`jq`** — `write-checkpoint.sh` shells out to it to parse the Basic-Memory
  CLI's JSON output (note content on read, permalink on write) and the
  repository's `.claude/settings*.json`; not preinstalled on stock macOS.
  Its absence aborts the whole checkpoint (Serena side included) with a
  clear error before either backend is touched.
- **Backend selection** — one Basic-Memory config
  (`~/.basic-memory/config.json`) holds every project; the script never
  chooses a config directory. The project comes from
  `basicMemory.primaryProject` in the primary checkout's
  `.claude/settings.local.json`, else `.claude/settings.json` (the key the
  official Basic-Memory Claude Code plugin defines; the plugin itself is not
  required); unset means the config's `default_project`. A profile launcher
  that must confine every session to one project exports
  `BASIC_MEMORY_MCP_PROJECT=<name>`, which Basic-Memory's own resolver
  applies before any `--project` (MCP, CLI and background sync alike), so
  the script passes no `--project` and reports the lock instead. Three
  conditions abort before any backend call: `BASIC_MEMORY_CONFIG_DIR` or
  `BASIC_MEMORY_HOME` set (retired variables; a stale value silently creates
  or selects the wrong store), a lock that differs from the repository's
  `primaryProject` (the repository is open in the wrong profile), and a
  settings file that cannot be parsed or whose `primaryProject` is not a
  string. The checkpoint memory goes to the resolved Serena project's
  `.serena/memories/` (primary checkout, or `serena=`); worktree memories
  are always relocated to the primary checkout. When the current directory
  is itself a Serena project other than the resolved one, the script prints
  a divergence warning with the `serena=` value to pass. Only `uvx` and
  `jq` are required.
- **Reload-flag hook** — the memory-restore directive is injected as context on
  the next `/clear` only if the `smith-mode-plan-claude` **SessionStart:clear** hook
  (`on-session-clear.sh`) is registered. A restore is NOT guaranteed; the full
  conditions and outcomes are in `smith-mode-plan-claude/references/HOOKS.md`
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
  `smith-mode-plan-claude/references/HOOKS.md` ("Configure the Hooks"), so there is
  one copy to keep correct rather than two.
- **Cloud / fresh-clone reach** — a cloud run (`/schedule`, `/code-review ultra`,
  Claude Code web) clones the repo fresh with no local home dir, so it sees
  **none** of the local backends — only committed git/PR state. Portable resume
  there needs committed-to-repo state or an enabled cloud MCP (deferred).
