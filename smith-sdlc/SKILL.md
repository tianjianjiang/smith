---
name: smith-sdlc
description: AI-native software development lifecycle — intent.md/spec.md/plan.md per-feature artifact chain (spec.md as EARS+GWT contract), plus durable cross-cutting knowledge (CLAUDE.md, skills, an optional per-subsystem design.md ADR log), hooks/evals as governance, control-band maintenance loop. Use when scoping a new feature end-to-end, setting up a repo's SDLC artifacts, or asked about Anthropic's AI-native SDLC playbook.
license: MIT
metadata:
  version: "1.2.0"
  tags: ["sdlc", "intent", "spec", "design", "adr", "plan", "governance", "evals"]
---

# AI-Native Software Development Lifecycle

Source: Anthropic, ["The AI-Native SDLC playbook"](https://claude.com/blog/the-ai-native-sdlc-playbook)
(published 2026-08-21, retrieved 2026-09-08); companion posts
["How Anthropic secures its AI-native software development lifecycle"](https://claude.com/blog/how-anthropic-secures-its-ai-native-software-development-lifecycle)
and ["Claude on call: How Claude Tag serves as Anthropic's first responder for CI/CD failures"](https://claude.com/blog/ai-ci-cd-on-call).
Full per-stage detail (exact prompts, file templates, governance/measurement
per play) lives in `references/PLAYBOOK.md`; this file is the map.

**Scope:** The six-stage artifact loop (Plan, Design, Build, Test, Deploy,
Maintain) that replaces the traditional phase-and-sign-off SDLC once code
generation is no longer the bottleneck.
**Load if:** Scoping a feature end-to-end, setting up a repo's SDLC
artifact conventions, asked about the AI-native SDLC / agentic SDLC, or
deciding where `intent.md`/`spec.md`/`plan.md` should live.
**Prerequisites:** @smith-guidance/SKILL.md

## The Core Shift

Traditional SDLC gates assume every stage runs at human speed. Once an
agent collapses the Build stage from weeks to hours, the traditional gates
around it — plan, review, deploy — become the bottleneck, and process
that ran fine at human speed becomes intractable at agent speed. The
AI-native SDLC keeps the same six stages and the same human accountability
points, but restructures each stage around one committed, version-controlled
artifact that the next stage reads and acts on. The stages form a loop, not
a line: Maintain's findings re-enter as a new `intent.md`.

## The Artifact Chain

Each stage ends by committing one artifact to version control; committing
it is what triggers the next stage:

1. **Plan** → `intent.md` — a human-readable, machine-actionable proto-spec
2. **Design** → `spec.md` — requirements + design in one pass, applied
   against organizational skills (brand, security, compliance, UX)
3. **Build** → `plan.md` — Claude Code's plan-mode output, committed (see
   Build stage below); then the diff and its tests
4. **Test** → test output pasted into the session/PR, plus the continuous
   eval suite's pass/fail
5. **Deploy** → the PR with its review findings, then the merged commit
6. **Maintain** → a detected control-band breach or scan finding, written
   back as a new `intent.md`

The chain of commits is the audit trail: who asked for what, what the
agent produced, and who approved it at each gate. Early-stage artifacts
are markdown because a non-engineer and an agent must both read and act on
the same file; from Build onward the artifact is code and its records.

## Stage 1: Plan — intent.md

The originator brainstorms the problem with Claude in their own words —
no formal language required — until scope, users, constraints and success
criteria are concrete. Claude writes the result as `intent.md` (problem,
proposed outcome, affected users/systems, constraints, open questions)
using an organization template (encode this as a skill). The product owner
corrects and commits it. Home: an `intent/` folder in the product repo for
a single product; a directory in a monorepo; a dedicated intent repo only
when intent spans many repositories.

**Measure:** time from first conversation to committed `intent.md`
(leading); the survival rate of intents accepted into Design vs. closed,
and `intent.md` changes made after the first `spec.md` commit (lagging).

## Stage 2: Design — spec.md (+ optional design.md)

Once `intent.md` is accepted, one session — not two handoffs — produces
the requirements-and-design spec, constrained by the organization's skills
for brand, security, compliance and UX. The product owner reviews the spec
against the intent and routes flagged concerns to policy owners before
engineering sees it. Front-end work mocks up in Claude Design from the
`intent.md`, then exports to Claude Code to build. Commit `spec.md`
alongside `intent.md`.

**The playbook mandates no internal notation for `spec.md`** — only that
one session produces it, org skills constrain it, and committing it
triggers Build. That leaves room to require `spec.md` as the normative
contract, in EARS (Easy Approach to Requirements Syntax: ubiquitous /
event-driven / state-driven / optional-feature / unwanted-behaviour
requirement forms) paired with a Given-When-Then acceptance scenario per
requirement, without contradicting anything the playbook actually
prescribes. Reference authoritative schemas/code by name rather than
restating their fields. `spec.md` is per feature/change, same cardinality
as `intent.md` and `plan.md`.

### design.md as an ADR log (optional, durable — not per-cycle like spec.md)

Design decisions get *made* in this stage's session, which is why this
lives here rather than under Build — but the log itself doesn't share
`spec.md`'s cardinality: one `design.md` per subsystem/component, not per
feature, appended to only when a decision made during a Design-stage
session is significant enough to outlive the current change. Most
sessions produce no ADR entry at all; the decision's rationale just lives
in `spec.md` (or later, `plan.md`'s `Risks` section) and needs nothing
more durable than that.

Every artifact in this chain is already git-committed and permanently
versioned (the playbook's own words: `plan.md` "joins the audit trail"),
so versioning is never the gap `design.md` fills. What git's commit
history doesn't give you for free is **curation**: a decision like "this
subsystem uses Postgres, not DynamoDB, because X" can inform fifty later
`spec.md`/`plan.md` cycles; leaving it embedded in whichever cycle first
made that call means a future reader has to know which commit to search
rather than reading one indexed log. Structure it as an append-only ADR
(Architecture Decision Record) log in MADR-minimal form
(context-and-problem → decision drivers → considered options → decision
outcome → consequences), with a decision index at the top; never edit a
decided entry, append a new one that supersedes it.

**If nobody will maintain the index, skip `design.md` entirely** —
`git log -- '**/spec.md'` is a legitimate, YAGNI-consistent decision
history on its own for a small or single-maintainer repo; the index earns
its keep only once enough decisions and enough readers exist to justify
curating it. This is a smith-level addition, not something the playbook
prescribes or even mentions — its own minimal example uses one `spec.md`
file for both requirements and design, with no ADR concept.

**Don't confuse this with a tool-native "spec" feature some editors
ship** (a three-file `requirements.md` + `design.md` + `tasks.md` bundle)
— that convention's `design.md` is the architecture/implementation design
for one feature, not a cross-cutting decision-rationale log; the two are
not interchangeable, and this skill's `design.md` means the ADR-log sense
only. Because both conventions use the same filename inside a repo that
might run either, name the actual directory unambiguously (e.g.
`docs/<subsystem>/design.md` for the ADR-log sense) rather than relying on
context to disambiguate.

**Measure:** elapsed time between the `intent.md` and `spec.md` commits
(leading); `spec.md` commits dated after the first `plan.md` commit for
the same change, i.e. requirements rework after build starts (lagging).

## Stage 3: Build — plan.md, CLAUDE.md, skills, hooks

**`plan.md` is Claude Code's native plan mode, committed.** It is not a
separate artifact type — see `@smith-mode-plan-claude/SKILL.md` for what
plan mode is and how Claude Code implements it. The playbook's addition on
top of plan mode itself: commit the approved plan to the repo's own git
history as `plan.md` so it joins the audit trail, and check the eventual
diff against it at PR review (Stage 5). `@smith-mode-plan/SKILL.md` covers
tracking progress through a plan's tasks once implementation starts.

Four other build-stage plays, all things smith already does in spirit —
this skill just names them against the playbook's vocabulary:

- **`CLAUDE.md` as institutional knowledge** — commands, conventions,
  architecture, common mistakes. Generate with `/init`, cut to a page,
  update whenever Claude repeats a mistake twice.
- **Skills as policy** — explicit, version-controlled, applied whenever
  their trigger matches; write one for institutional knowledge that must
  be applied consistently, not for what belongs in `CLAUDE.md` or a
  prompt. A skill is advisory; it makes a violation rare.
- **Hooks as build-time guardrails** — the deterministic layer behind a
  skill: block edits to protected paths, run the formatter/linter, keep
  credentials out of the diff. A hook makes a violation close to
  impossible. An approval-asking hook belongs at Stage 5 (Deploy), not
  here — a mid-build approval prompt blocks every parallel session on one
  person.
- **Parallel sessions and subagents** — separate git worktrees per stream
  of independent work; recurring jobs become `.claude/agents/<name>.md`
  subagents with their own tools and context.

(`design.md`, the ADR log, is covered under Stage 2 above — it's produced
during Design-stage sessions, not Build, even though it shares Build's
durable/cross-cutting lifecycle rather than `spec.md`'s per-feature one.)

**Legacy systems sidebar:** for every artifact, name one system as the
source of truth (the repo, the legacy system with the repo as a working
copy, or linkage as the minimum bar — record ID in the artifact, commit
SHA in the legacy record). Don't let two systems both claim authority
with no link between them.

## Stage 4: Test — feedback loop + continuous evals

Give every session a way to check its own work — a single command that
exits non-zero on failure, documented in `CLAUDE.md`, with a quantifiable
target. For bug fixes: write the failing test first, commit it, then block
the agent from editing that test file via a hook while it fixes the bug.
For UI: a browser/screenshot tool and 2-3 iterate rounds against the mock.

**Continuous evals** regression-test the agent's own configuration
(`CLAUDE.md`, skills, hooks) the way CI regression-tests code: 20-50 real
tasks with accepted outcomes, run on a schedule and on any PR touching
`CLAUDE.md`/`.claude/**`, gating the config change on pass rate. Every
production incident becomes a permanent eval. Smith has no existing
convention for this — it is new territory relative to `@smith-tests/SKILL.md`,
which covers testing code, not testing the agent's own steering files.

**Measure:** first-pass CI success rate for agent-written changes
(leading); review time per PR and change-failure rate (lagging), for the
feedback loop. Eval pass rate over time, and time for an incident to
become a permanent eval (leading); regressions caught in CI vs. production
(lagging), for continuous evals.

## Stage 5: Deploy — PR review loop + approval-gate hooks

Claude both reviews incoming PRs (bugs, security, compliance passes
defined in a `REVIEW.md` at the repo root) and addresses review comments
on its own PRs via `@claude`. Findings are ranked by severity; a human
code owner's approval is still required by branch protection — the agent
that wrote the code has no path to approve it. `REVIEW.md` also defines
what counts as Important vs. Nit and what to skip.

**Hooks as approval gates** enforce the human sign-offs that must survive:
production-deploy authorization, change-management sign-off for
migrations, protected-path edits. Team hooks live in `.claude/settings.json`;
non-negotiable ones live in admin-owned managed settings an engineer
cannot override. A block should explain itself and name the approval
route. See `references/PLAYBOOK.md` for a worked managed-settings example
(deny/allow lists, sandboxing, plugin allowlisting).

**CI/CD:** run Claude non-interactively for judgment steps (triage a
failed build, draft a changelog), sandboxed with scoped, short-lived
credentials and no standing production access. Expose deployment as MCP
tools (deploy/status/rollback), tiered by environment — free in dev, gated
in staging, authorization-required in prod. Rehearse rollback until it is
the single most-exercised path in the pipeline; Stage 6's highest
autonomy tier invokes it.

**Measure:** time to first review and share of comments resolved without
a human touching the branch (leading); defects/vulnerabilities caught
before merge vs. escaping to production (lagging).

## Stage 6: Maintain — closing the loop

The loop closes here: a trigger invokes Claude with no person in the
invocation path, and what it finds re-enters as `intent.md`.

- **Control bands** — a deterministic script (mean/stddev, Western
  Electric rules) watches one metric with a stable baseline (CI failure
  rate, post-deploy 5xx rate, PR cycle time). At 1σ: log only. At 2σ:
  invoke Claude read-only to diagnose. At 3σ: Claude may open a PR or
  trigger a pre-approved runbook. Tier boundaries live in version-controlled
  config (e.g. `bands.yaml`); detection itself stays deterministic, never
  a model call.
- **Recurring codebase scans** (Claude Security) — scheduled, validated,
  confidence-rated findings; bounded fixes go through the normal PR
  review gate, wider findings become `intent.md`.
- **Claude on call** (Claude Tag) — incidents arriving via Slack/Teams get
  Claude as first responder under its own identity; the channel thread is
  the audit trail. Small fixes become a PR; larger work becomes `intent.md`.

Every finding that ships a fix also adds a permanent eval for that
incident class, so the same regression cannot reach production twice
without CI catching it first.

**Measure:** time from band breach to `intent.md` in the triage queue
(leading); share of findings that become merged fixes, and repeat
incidents of the same class — which should fall as evals accumulate
(lagging).

## What Smith Already Covers vs. What's New

- `plan.md` / plan mode → `@smith-mode-plan-claude/SKILL.md` (Claude
  Code's ExitPlanMode mechanics) and `@smith-mode-plan/SKILL.md`
  (platform-neutral definition + progress tracking through a plan's tasks).
- `CLAUDE.md`, skills, hooks as institutional knowledge/policy/guardrails →
  smith's own skill/hook system already is this pattern; this skill just
  names it against the playbook's stage vocabulary.
- PR review discipline → `@smith-review/SKILL.md`, `@smith-gh-pr/SKILL.md`.
- `spec.md` as an EARS+GWT contract, plus an optional `design.md` ADR log
  (see Stage 2 above) reconciles this skill against a real prior
  convention, not the playbook's own minimal single-file example —
  reconciled because it fits within what the playbook actually mandates
  (procedural, not notational): `spec.md` stays per-feature; `design.md`
  is a durable, per-subsystem log produced *during* Design-stage sessions
  but shaped like `CLAUDE.md`'s cross-cutting lifecycle, not `spec.md`'s
  per-cycle one — skip it entirely if nobody will maintain it as an index.
  A tool-native three-file `requirements.md`/`design.md`/`tasks.md` spec
  bundle, where it exists in a given editor, is a different, unrelated
  convention — don't conflate its `design.md` (architecture) with this
  skill's `design.md` (ADR log).
- `intent.md`, evals-on-agent-config, and the Stage 6
  control-band/scan/on-call maintenance loop have no prior smith
  convention — this skill is their home until a repo adopts real file/folder
  conventions for them (deliberately left unprescribed here: pick a home
  per the Legacy Systems sidebar above, per project).

## Related

- `@smith-mode-plan-claude/SKILL.md` - Claude Code's plan-mode mechanics (Build stage)
- `@smith-mode-plan/SKILL.md` - platform-neutral plan-mode definition + progress tracking
- `@smith-review/SKILL.md` - multi-round local review loop (Deploy stage)
- `@smith-gh-pr/SKILL.md` - PR workflows (Deploy stage)
- `@smith-tests/SKILL.md` - testing code (distinct from evals-on-agent-config, Test stage)
- `@smith-tickets/SKILL.md` - ticket creation by convention (adjacent to intent.md)
- `@smith-guidance/SKILL.md` - core agent steering this skill's governance sections build on

## Before You Finish

**Before treating a task as SDLC-stage work:**
1. Identify which stage the task is actually in — don't skip straight to
   Build without an `intent.md`/`spec.md` if the org has adopted them.
2. Name the artifact the stage should commit, and where it lives (see the
   Legacy Systems sidebar in `references/PLAYBOOK.md`).
3. Confirm who the human approver is for this stage's gate before treating
   an agent's output as ready to hand off.
4. If setting up new tooling (a hook, a skill, an eval), check whether
   smith already covers it before inventing a parallel mechanism.
