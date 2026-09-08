# Fix smith-checkpoint's over-strict token budget

## Context

Mike observed that `smith-checkpoint` "almost always over summarize/trim/truncate,"
undermining its own stated purpose: "faithful and complete handover between
sessions" (`smith-checkpoint/SKILL.md:8` — "Capture what would otherwise be
lost across sessions").

Investigation (two read-only Explore agents) confirmed the root cause is
instructional, not code:

- `smith-checkpoint/SKILL.md:27` states a hard-sounding **"Target: <400
  tokens per checkpoint body"** with no stated exception for complex
  sessions.
- `smith-checkpoint/SKILL.md:112-113` repeats the same `<400 tokens` framing
  in the drafting step of the Procedure.
- The only code-level enforcement is `write-checkpoint.sh:95-102`
  (`warn_if_body_exceeds_budget`), which prints a **stderr warning** past
  1600 bytes and does **not** truncate or summarize anything — `body=$(cat
  "$body_path")` (`write-checkpoint.sh:113`) passes the drafted body through
  verbatim.
- Meanwhile `SKILL.md:153` brands an incomplete checkpoint ("not successful
  until all three backend writes succeed") as the actual failure mode.

Nothing in the skill reconciles these two requirements. Because the
instructions are the only enforcement mechanism (the script never trims),
the drafting agent reads "<400 tokens" as a hard ceiling and cuts durable
content to fit it — the over-summarization/trimming Mike is seeing. The fix
is to rewrite the instructional language so completeness is explicitly the
binding requirement and the token figure is a non-binding starting aim, and
to reword the script's warning message to match (still a warning, never a
truncation).

Per Mike's directions: apply the `smith-sdlc` artifact chain to this fix
(`intent.md` → `spec.md` → this `plan.md`), and per his correction, place
these SDLC artifacts in the skill's own `references/` folder — the
convention this agentskills.io-compliant repo already uses for skills'
durable supplementary docs (e.g. `smith-sdlc/references/PLAYBOOK.md`,
`smith-mode-plan-claude/references/HOOKS.md`).

## Files that change

- `smith-checkpoint/references/intent.md` — new. Problem/outcome/affected
  systems/constraints per the `smith-sdlc` intent template
  (`smith-sdlc/references/PLAYBOOK.md:30-48`).
- `smith-checkpoint/references/spec.md` — new. EARS + Given-When-Then
  requirements contract per smith's addition to the playbook
  (`smith-sdlc/references/PLAYBOOK.md:61-82`), covering: budget language is
  a guideline not a ceiling; completeness takes precedence in any conflict;
  the warning stays non-blocking.
- `smith-checkpoint/references/plan.md` — new. This plan, committed as the
  Build-stage artifact per `smith-sdlc/SKILL.md:156-163`.
- `smith-checkpoint/SKILL.md` — edit:
  - `## Compression Requirements` (lines 25-27): replace the hard `Target:
    <400 tokens` line with a guideline framing — e.g. "**Guideline**: aim
    for ~400 tokens per checkpoint body when the content allows it.
    Completeness is the binding requirement: never drop a decision,
    file:line anchor, PR/commit reference, or open follow-up to fit this
    number. An oversized-but-complete checkpoint is a successful
    checkpoint; a compact-but-incomplete one is not (see `SKILL.md:153`)."
  - Procedure step 4 (lines 112-113): update `<400 tokens` framing to match
    — "Draft the body (~400 tokens as a starting aim — extend as needed to
    capture everything durable; do not omit content to hit the number)."
- `smith-checkpoint/scripts/write-checkpoint.sh` — edit
  `warn_if_body_exceeds_budget` (lines 95-102): reword the stderr message
  so it reads as an informational conciseness check rather than an implied
  hard limit, e.g. "Note: body is ${bytes} bytes (guideline ~1600); keep it
  if the content is necessary for a complete handover." No behavior change
  — it already only warns and never truncates.

No changes needed to `extract-session-facts.sh` (its `MAX_FILES=30` cap is
an unrelated, already-reasonable line-count guard, not a token-budget
mechanism) or to `scripts/tests/write-checkpoint.test.sh` (confirmed via
grep: no test asserts on the exact warning wording).

## Order of work

1. Write `smith-checkpoint/references/intent.md`.
2. Write `smith-checkpoint/references/spec.md`.
3. Copy this plan to `smith-checkpoint/references/plan.md` (Build-stage
   artifact, committed alongside the diff per `smith-sdlc`).
4. Edit `smith-checkpoint/SKILL.md` per above.
5. Edit `smith-checkpoint/scripts/write-checkpoint.sh` per above.
6. Run the existing test suite:
   `smith-checkpoint/scripts/tests/write-checkpoint.test.sh`.
7. Create branch/worktree (branch-guard requires this before any edit —
   already pending since plan mode blocked edits until now), commit with a
   message describing the fix, and report back. Push only if explicitly
   authorized (per `@smith-guidance` external-writes rule) — commit is
   already covered by "actually fix it," push is not, so ask before
   pushing.

## Risks

- Loosening the budget language could regress toward the *other* failure
  mode (bloated, unfocused checkpoints) if "completeness wins" is read as
  license to include transient chatter. Mitigated by keeping the existing
  "Durable only" scoping (`SKILL.md:18-23`) and "Use references, not
  content duplication" format rules (`SKILL.md:29-33`) unchanged — only the
  budget-vs-completeness precedence changes, not what counts as durable.
- `spec.md`'s EARS+GWT requirements must stay verifiable by re-reading the
  edited `SKILL.md`/`write-checkpoint.sh` text, not just by narrative
  description, so the contract is checkable later.

## Proof

- `write-checkpoint.sh`'s test suite passes unchanged (`scripts/tests/write-checkpoint.test.sh`).
- Manual re-read of the edited `SKILL.md` and `write-checkpoint.sh` sections
  confirms: (a) no hard token ceiling remains in the prose, (b) the
  precedence of completeness over the token guideline is explicit, (c) the
  script still only warns (grep for `exit` near `warn_if_body_exceeds_budget`
  shows no exit-on-budget path, before and after).
