---
name: smith-checkpoint
description: Memory checkpoint to Serena and Basic-Memory. Use when the user runs /smith-checkpoint, asks to save or hand off session state, asks to save a record such as a decision, a risk item or a follow-up queue to memory, and before recommending /clear.
metadata:
  argument-hint: "[label] [plan=path] [body=path] [serena=path] [roots=dirs] [audit=skip]"
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
- `roots=dir[:dir…]`: extra directories (another repository, for example)
  where the audit resolves `file:line` anchors and commit SHAs
- `audit=skip`: bypass the pre-write audit; only on the user's explicit
  say-so, and the Reload block reports it (the audit runs only with
  `body=`)

Save the SAME facts to both backends, each in its own format; do not skip one.

A durable record the user asks you to save (a risk item, a decision, a
follow-up queue) goes into a /smith-checkpoint run, so both backends get
the same facts without asking which.

## What to capture

Durable only (not transient chatter): goals/decisions, file:line anchors,
PR/commit SHAs, open follow-ups, and corrections the user gave that apply
to this work thread only. Convert relative dates to absolute. Omit what the
repo/git already records.

A correction that applies beyond this work thread follows
@smith-guidance/SKILL.md "Route general corrections to a general place":
once it is written to that place, the body lists only a pointer to it
under Related; a draft the user has not approved yet goes under Next.

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
   - Decisions: the statement plus a pointer to the record that holds its
     full conditions (@smith-guidance/SKILL.md "A decision carries its full
     conditions"); when this checkpoint is the only record, write the
     conditions here (scope, grounds, rejected alternative)
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
- Rule: re-run the failing test before claiming a fix →
  `~/.claude/rules/«topic».md`
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
   checkout is ever overwritten; a missing `.serena/memories/` directory in
   the primary checkout is created. When the primary checkout has no
   `.serena/project.yml` the files stay where they are and a warning says
   so. When the worktree's `.serena/memories` resolves to the same directory
   as the primary checkout's (the symlink made by the `link-worktree-memories`
   hook, or a symlinked `.serena`), there is nothing to relocate and no file
   is touched. When it holds `*.md` files and resolves, through a link at
   `.serena/memories` or at `.serena`, to a directory that is neither the
   worktree's own `.serena/memories` nor the primary checkout's (outside the
   worktree or elsewhere inside it), those files belong to that directory:
   they stay there and, when the primary checkout has
   `.serena/project.yml`, a warning names it. When the worktree's
   `.serena/memories` holds `*.md` files and the primary checkout's
   `.serena/memories` is a symbolic link to a directory that is missing or
   cannot be reached, or exists without being a directory, the script exits
   before any backend write and leaves the memories in place, wherever the
   worktree's directory resolves to. It exits the same way when the
   memories are the worktree's own and the primary directory cannot be
   created. Repair the path and rerun.
2. **Basic-Memory** (`basic-memory tool read` + `tool write --overwrite`,
   from the install in Runtime prerequisites "Basic-Memory version"
   below): a note titled from the label, type `guide`, tag `checkpoint`, in
   the project selected per Runtime prerequisites "Backend selection" below
   (`--project <name>` on both calls when a project is configured and no
   profile lock is active; under a lock both calls omit it).
   `--overwrite` is passed unconditionally — it is safe on both a first
   write (nothing to conflict with) and a re-checkpoint (the payload is
   already the full merged document, so there is nothing to lose). The
   folder is taken from the existing note's own `file_path` (from the same
   `read` call) when one is found, so a re-checkpoint lands back in
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
- If a plan file is in play, its one marker line
  `<!-- checkpoint-label-v1: «label» -->` pins the label across
  checkpoints and across plan files: a plan that continues a checkpointed
  thread carries that thread's exact memory name there (marker rules in
  `@smith-mode-plan/SKILL.md` "Checkpoint Label"). `plan-label.sh`
  (Procedure step 3) reads it; with no marker it suggests the heading
  slug (else the filename slug, else `plan_checkpoint`).
- Without a plan file, or when the plan has no marker, check for
  an existing checkpoint first: `serena memories list` (grep for a name
  matching the current work topic) and/or Basic-Memory `bm_search` /
  `bm_read` on the candidate title. If a match is found, reuse ITS exact
  name — do not derive a new one.
- Only fall back to deriving a fresh label (below) when no existing
  checkpoint for this work is found.

**Use semantic names based on checkpoint context, not generic labels:**

- **With plan file**: the plan's marker value, else the slug of its
  first `# ` heading (filename only when the plan has no heading), as
  `plan-label.sh` prints them
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

1. **Extract deterministic facts** (if transcript available). Claude Code
   hands `transcript_path` only to hooks, so without an argument the
   script finds this session's transcript from `CLAUDE_CODE_SESSION_ID`
   under `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects`; none found means
   no transcript:
   ```bash
   "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/smith-checkpoint/scripts/extract-session-facts.sh"
   ```
   Provides: completed tasks, file edits, PRs, commits, git state

2. **Check for an active plan** — list `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plans/*.md` and check
   whether one matches this session's current work. If one does, pass it
   explicitly as `plan=«path»` in steps 6 and 7; never rely on inference alone.
   (write-checkpoint.sh also falls back to the ctx-claude plan-state file
   when `plan=` is omitted, but an explicit path is more reliable when a
   plan is visibly in play.)

3. **Look up existing checkpoint identity before naming** (see Naming
   strategy above): with a plan file, run
   ```bash
   "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/smith-checkpoint/scripts/plan-label.sh" "«plan path»"
   ```
   - Exit 0: its output is the label; skip step 4.
   - Exit 3, or no plan file: check `serena memories list` / Basic-Memory
     `bm_search` for a match on the current work topic and reuse its exact
     name if found.
   - Exit 1: stderr names the cause. Several markers are listed as
     `«plan»:«line»:` (keep one and rerun); the others are a missing
     argument, or a plan that is missing or cannot be read.
     Any other exit is a script failure: report it instead of inventing a
     label.

4. **Infer label automatically** (only when step 3 found no existing
   checkpoint to reuse):
   - If plan file exists: the suggestion `plan-label.sh` printed with exit 3
   - Otherwise: infer from current session's primary work
   - Follow Naming strategy above (semantic, descriptive)

5. **Draft the body** (~400 tokens as a starting aim, per Compression
   Requirements above. Format: Completed / Decisions / Next / Related, no
   title or Date/Plan/Session header):
   - Combine extracted facts (step 1) with rich context/reasoning
   - Add decisions (why, consequences), next steps with context
   - Before writing Decisions, apply the test in @smith-guidance/SKILL.md
     "Route general corrections to a general place" to each user
     correction; a written one becomes a pointer under Related, an
     unapproved draft a Next item
   - List Serena memories and Basic-Memory notes written this session under
     Related. From a worktree, name Serena memories by the location the
     script prints on stderr after relocation (a memory written by MCP into
     the worktree ends up in the primary checkout, possibly under a
     `__from_worktree_` suffix)
   - Create the body file with `new-body-file.sh`. It prints the path of a
     new, empty, owner-only file in `CLAUDE_JOB_DIR`, else `TMPDIR`, else
     `/tmp`. Reuse that printed path literally as `«body-file»` here and in
     steps 6 and 7. If the script exits nonzero or prints nothing, stop and
     report it; never write to the literal text `«body-file»`. The file is
     left for the temporary directory's own cleanup:
     ```bash
     "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/smith-checkpoint/scripts/new-body-file.sh"
     ```
   - Fill it with a Bash heredoc (Write tool requires Read first, even for new files):
     ```bash
     cat > "«body-file»" <<'EOF'
     ## Completed
     - [x] ...
     
     ## Decisions
     ...
     
     ## Related
     ...
     EOF
     ```
   - Omit `body=` only when session produced nothing durable

6. **Audit before writing.** After `/clear` the next session has only the
   body, the plan and what they point at; make them current, correct and
   complete first (checks and resolution rules:
   `references/checkpoint-audit/spec.md`). Run these in order:
   1. Sync the plan file per `@smith-mode-plan/SKILL.md` Plan Sync
      Protocol: checkboxes match what is done, `<- CURRENT` moved,
      superseded tasks removed, a progress log entry added
   2. Sweep the conversation for omissions, which only the main thread can
      see: one row per user message, mid-turn messages and replies to
      side-agent notes included, naming the request or decision it made
      and the body or plan line that records it, or "not recorded"; add
      every "not recorded" item that is durable per "What to capture" and
      mark the others transient in the table
   3. Remove contradictions: the plan owns task state, the body owns
      decisions and context
   4. Run the scripted audit and fix every `FAIL`, judge every `WARN`:
      ```bash
      "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/smith-checkpoint/scripts/audit-checkpoint.sh" "«body-file»" "plan=«path»"
      ```
      An anchor that fails to resolve is wrong for the next reader too:
      write its path from the repository root, absolute, or add `roots=`;
      do not reach for `audit=skip`
   5. Verify and validate double-blind, in rounds: the author of the body
      never grades it. Both checkers are evaluators, blind per the
      `@smith-subagents` evaluator rule (new subagents, never forks; a new
      round never continues one with SendMessage, which carries the
      earlier round). Each prompt carries the `@smith-subagents` contract
      block, the body path and the plan path; the VERIFIER's prompt also
      carries the worktree path and the base ref of the branch's commits
      (such as `origin/main...HEAD`), which the COLD READER's prompt
      leaves out, since it must find the worktree in the body (the
      platform may still inject the working directory and git state,
      which the quote rule below discounts). The prompt allows
      reading only the body, the plan, the files the body and plan
      anchors name, the Serena memories and Basic-Memory notes the
      Related section names (read by those names), and any instruction
      text that holds no judgment of the body (skill files, the
      instruction files the platform loads at start, an MCP server's own
      manual such as Serena's `initial_instructions`), and for the
      VERIFIER also files in the worktree, `git` output and
      `gh` metadata fields only (`gh pr view --json
      state,headRefName,baseRefName,mergedAt`, never comments, reviews or
      the PR body, which hold judgments); it forbids everything else:
      judgments are stored in more places than a list could name (session
      transcripts, background task output, earlier rounds, the expected
      answers, review threads), and a transcript mixes evidence with
      judgments (the main thread's reasoning, side-agent notes, subagent
      returns). The allowed set overrides any skill, instruction-file or
      MCP server rule that calls for wider reads (a whole memory set, a
      workspace `AGENTS.md`, a search or listing call such as `bm_search`
      or a recent-activity or memory listing, which can surface earlier
      checkpoints); the checker reports such a rule instead of following
      it. It forbids spawning
      subagents, since each checker is itself the skeptic pass. It asks
      for every source read: a read outside the allowed set by either
      checker voids the whole round, which is re-run with both checkers
      as new blind subagents and counts toward the limit of three rounds
      below. It says how the platform expects the report delivered: a
      round missing either report is void the same way, since an
      undelivered report is a missing signal, never a pass
      - Before the first round of the first run of this item, write the
        expected answers (goal, current task, next action, worktree,
        every open decision) to a new file, so they cannot be fitted to
        the returns afterwards; the allowed set above already keeps both
        checkers out of it. A rerun from item 6 reuses that file.
        `mktemp "${TMPDIR:-/tmp}/checkpoint-expected.XXXXXX"` prints its
        path; later Bash calls reuse that path as a literal string
      - Each round spawns both checkers in one message:
        - VERIFIER (verification: is what is written true?), SKEPTIC
          role, named in its prompt to invoke `@smith-validation` and to
          list the skills it invoked (re-run with the rules inline when
          it did not): split the body and the plan into single claims (a
          commit, a checkbox state, the `<- CURRENT` task, a `file:line`,
          a PR state, a decision); for each, state its disproof and look
          for it with a command that can be re-run (`git log`,
          `gh pr view --json state`, `sed -n «N»p`); return refuted /
          survived / insufficient evidence, or conversation-only for a
          claim with no re-runnable source (a decision made only in
          conversation), or not checkable: «source» out of reach when
          the command that would check it is unavailable (no `gh`) or its
          source lies outside the allowed set (a ticket status, a CI
          result, a review approval), each with its locator and the
          evidence that would have changed the verdict; then list branch
          commits and plan tasks the body omits
        - COLD READER (validation: can a fresh session resume from it?),
          its rules inline and no skill named, since no skill fits (this
          one would have it spawn checkers and write a checkpoint): from
          the body, the plan and the Related anchors alone, answer,
          quoting the line each answer came from, or "not stated": what
          is the goal, what is the current task, what is the next action,
          which worktree holds the work, and what decisions are open?
      - After a round: fix every refuted claim by its locator, back an
        insufficient one with a source or drop it, and keep every
        conversation-only and not-checkable claim. Add every listed
        omission that is durable per "What to capture" (git already
        records the rest) and whatever the cold reader's answers miss or
        contradict against the expected file; a cold-reader answer counts
        only when its quote is found verbatim in the body, the plan or a
        Related anchor, and otherwise counts as "not stated" (completeness
        beats the ~400-token aim). Rewrite a changed plan item, never
        append to it. If anything was changed, rerun the scripted audit of
        item 4 and start a fresh round; the rounds end with a round in
        which neither checker returns anything to change. When the third
        round still returns changes, apply its fixes, stop, record
        "double-blind audit did not converge after 3 rounds" in the body
        and hand that round's findings to item 6. When the third round is
        void, stop, record "double-blind audit void in round 3" and go to
        item 6
      - No subagent tool available: run both checks inline and record
        "double-blind audit not run: «reason»" in the body
   6. Show the user the conversation-only and not-checkable claims of the
      last non-void round verbatim (a void round's returns are discarded;
      when every round was void, say that no checker result stands), any
      unconverged findings, and the sweep table, and wait for a
      confirmation or correction: such a claim has no other checker than
      the user. A correction is applied and written
      into the expected-answers file where it changes an answer; then
      item 5 runs again with a new count of at most three rounds, and
      this item repeats. Step 7 starts only after a confirmation

7. **Call write-checkpoint.sh**:
   ```bash
   "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/smith-checkpoint/scripts/write-checkpoint.sh" "«label»" "plan=«path»" "body=«body-file»"
   ```

8. The script (exit 0 on success):
   - Without `plan=`, falls back to the ctx-claude plan-state file for this
     session's cwd (same source the stop hook uses)
   - Refuses to run while `BASIC_MEMORY_CONFIG_DIR` or `BASIC_MEMORY_HOME`
     is set, or while `BASIC_MEMORY_MCP_PROJECT` names a different project
     than the repository's `basicMemory.primaryProject` (see Runtime
     prerequisites "Backend selection"); nothing is written in either case
     - A set `BASIC_MEMORY_CONFIG_DIR` / `BASIC_MEMORY_HOME` usually comes
       from an unmigrated repo `.claude/settings.local.json` env block, an
       unmigrated profile launcher script, a long-lived `claude daemon`
       started before the migration (`claude daemon stop --any`), or a
       stale shell export
   - With `body=`, runs `audit-checkpoint.sh` and exits before any write
     when it fails (`audit=skip` bypasses it)
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
   - Backs up each backend's prior document to
     `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/checkpoint-backups/«label»/`
     (last 5 per backend kept) before overwriting it, and aborts that
     backend's write when the backup cannot be made or is gone after
     pruning
   - Writes to both backends (Serena + Basic-Memory) and reads each one
     back: the new entry must be on top and the entry count must be the
     prior count plus one, and each backend must read back exactly what
     was written (leading and trailing newlines aside). On a mismatch or
     a failed write it writes the backup back,
     and the restore holds only when the document read back equals the
     backup; on a label's first checkpoint it deletes the document it
     created instead (Basic-Memory only by the permalink its write
     returned, never by title). It fails naming the backend and the
     outcome (see `references/checkpoint-audit/spec.md`). A Basic-Memory
     failure also rolls Serena back, so both backends keep the same
     entries. These verified writes are the only required success criteria
   - On Claude Code, also writes the post-`/clear` memory-restore flag via
     `write-reload-flag.sh` (see Runtime prerequisites below). This write is
     always optional: on another platform, or if that sibling script is
     missing, the step is skipped; if the sibling script runs but fails, its
     error is reported as a warning. Neither case fails the checkpoint —
     it only means auto-reload is unavailable for this checkpoint, not that
     the checkpoint itself failed
   - After that flag is written, deletes this session's earlier pending
     flags for the same directory and label (lines 3-5 of the flag equal),
     so repeated checkpoints before one `/clear` leave one pointer; a flag
     without a session key supersedes nothing. Only the pointer goes; the
     earlier entries stay in both backends
   - Outputs success to stderr, Reload block to stdout. The Reload block
     lists: the Serena memory file by absolute path (when a Serena project
     was resolved; outside git without `serena=`, the label and "Serena
     default project"), the Basic-Memory permalink
     with its project and folder, the plan, the worktree line (with the
     `EnterWorktree` step) when in a worktree, the relocation counts when
     any memory was moved, removed or renamed, the reload flag path, the
     superseded flag count when any was removed, the audit status, the verified entry count of each backend, and the
     backup directory when a backup was made

9. If script exits non-zero, report stderr error; the checkpoint is not
   done until it exits 0.
10. On success, output Reload block to user.

## Runtime prerequisites

`/smith-checkpoint` (capture) and its post-`/clear` reload flag have runtime
dependencies. If they are missing, capture may still be attempted but the
checkpoint is **incomplete** — it is not successful until both backend
writes succeed (the skill reports which failed rather than claiming success),
and reload degrades:

- **MCP servers** — the lifecycle writes and reads through them: **Serena**
  (`write_memory`/`read_memory`), **Basic-Memory** (`bm_write` / `bm_read` /
  `bm_search`, 1.0 tool names).
  Both are **local-only** in a default setup (Serena memories live under
  `.serena/memories`, typically gitignored; Basic-Memory is a local SQLite DB
  unless Basic-Memory Cloud is enabled).
- **Basic-Memory version** — `write-checkpoint.sh` runs the installed
  `basic-memory` executable (`uv tool install basic-memory`, 1.0 or later)
  and exits before any write when it is not on `PATH` or lacks the 1.0
  `tool read` command; launch the MCP server
  from the same install (`basic-memory mcp`). The CLI and the server share
  one SQLite database, and each runs pending migrations when it first opens
  it; a build that does not know the database's newest migration fails with
  `Can't locate revision`, so one install keeps both on one version. After
  upgrading it, restart the MCP server. The script reads with
  `tool read --json --no-include-frontmatter` and treats only a `NOT_FOUND`
  error as a brand-new note; any other read error fails the checkpoint.
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
  a divergence warning with the `serena=` value to pass. Only `uvx` (for
  Serena), the installed `basic-memory` and `jq` are required.
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
