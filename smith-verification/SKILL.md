---
name: smith-verification
description: Verification of claims, findings, status reports and requirements. Use when a finding, a status or a count is about to be reported as fact, when a claim needs its evidence or a disproof attempt, when a surprising result may contradict a recorded decision, or when checking that work meets every part of its requirement as its author stated it.
metadata:
  smith-question: verification
---

# Verification

**Scope:** Verification: does the work meet its stated requirements, and
are its claims supported by evidence
**Prerequisites:** @smith-guidance/SKILL.md

<a name="adversarial-verification-v1"></a>
## Adversarial Verification of Findings

The Falsification Principle
(`@smith-analysis/SKILL.md#hypothesis-testing-v1`), applied to FINDINGS
rather than to a debugging hypothesis — for any investigation whose results
will be reported as fact: code, documents, external systems, history.

Two gates, not one. **Every** finding you report carries a locator. A
**skeptic pass** is only for findings that would cost something to get wrong:
one that contradicts a documented rule, one that drives an irreversible or
externally-visible action (a merge, push, deploy, ticket transition, message
send — reporting the finding itself is not one), or one you would not want to
be wrong about in front of whoever asked.

- **Name the disproof, then hunt it — for every finding you report.** Write
  down the specific observation that would kill the FINDING — the log line,
  file, or command output that, if it existed, would prove it wrong — then go
  looking for exactly that. It stays unproven until a search that should have
  surfaced the disproof comes back empty — not after a fixed number of passes.
- **Red-team what qualifies.** Hand a read-only skeptic subagent
  (`@smith-subagents` SKEPTIC role: contract pasted inline, blind per the
  `@smith-subagents` evaluator rule) the claim and its evidence; ask for a
  verdict of refuted / survived / insufficient evidence, plus the evidence
  that would have changed
  it. No skeptic available? Record "not run" and why, then conclude — never
  promote it silently.
- **Locator per claim.** Every claim carries a durable locator: a URL,
  `file:line`, commit, ticket, or a command whose output can be re-run (in a
  skill file a URL or a path only) —
  format per `@smith-research` Source Citation (external), `@smith-ctx`
  Information Retention (in-repo), `@smith-recon` (multi-source briefs). No
  locator means the claim is labelled unsourced, never asserted, and an
  unsourced claim is a gap to close before concluding (`@smith-guidance` close
  gaps).
- **Scale the machinery, not the floor.** A trivial lookup needs a locator, not
  a skeptic. Bias mechanics: `@smith-clarity` (Confirmation Bias, Premature
  Closure).

Source: Anthropic, "A harness for every task: dynamic workflows in Claude Code"
(https://claude.com/blog/a-harness-for-every-task-dynamic-workflows-in-claude-code)
— "For each spawned agent, run a separate spawned agent
to adversarially verify its output against a rubric or criteria", one of six
workflow patterns it lists. The post separately names self-preferential bias
("Claude's tendency to prefer its own results or findings, especially when
asked to verify or judge them against a rubric") among three failure modes that
isolated subagents combat. Aiming this pattern at that bias, and at your own
findings, is this skill's application — not a claim the post makes.

<a name="deviation-is-not-discovery-v1"></a>
## Deviation Is Not Discovery

The failure this guards: a recorded decision gets violated unnoticed by a
later session, which then narrates the consequences as a dramatic new finding
("verdict overturned", "assumption disproven") — and the rewrite propagates
through checkpoints. No internal trigger catches this; the read below is
unconditional, not fired by suspicion.

- Before interpreting ANY surprising or anomalous result, read the topic's
  recorded memory/decision set FIRST — especially when your current
  explanation seems coherent.
- If a recorded decision covers the situation and was violated, report
  **"the main thread deviated from the recorded protocol"** (or "the
  subagent …") — never "X was discovered" /
  "the verdict is overturned". Wrong-input or wrong-protocol runs are
  **void measurements**: they support no claim about the system under test.
- Tripwire words in your own draft that MANDATE the read before publishing:
  "overturned", "exonerated", "contrary to what we thought", "it turns out
  the assumption was false", 「翻案」「平反」.
- A later checkpoint QUOTES the earlier recorded decision it builds on; it
  never paraphrases it into a new story.
- **Checkpoint hygiene**: writing a checkpoint triggers an artifact census —
  enumerate EVERY file the session created outside the repo (temp dirs,
  `/tmp`, `~/Downloads`) and record each path or move it somewhere durable;
  no importance judgment (judging "which matter" is the part that fails).
  A checkpoint may claim "persisted to X" only with a same-turn directory
  listing of X quoted; without it the claim is fiction. Known gap: a session
  that ends abruptly without a checkpoint remains exposed — a Stop/PreCompact
  hook that scans the transcript for writes under volatile prefixes and lists
  them before exit would close it; until then, checkpoint early when
  artifacts accumulate.
- **A missing signal is never a passing one.** "No findings", an empty
  result, a silent tool, a fast acknowledgement or a failed lookup may mean
  the check never ran: confirm it ran, else record "not run", never "clean".
  An empty search is ambiguous between "absent" and "query broken": run,
  alongside it, a control query known to return hits through the same
  pipeline. A negative reported without one is a claim about your query,
  not about the world.
- **A queued decision carries its full conditions**, as listed under "A
  decision carries its full conditions" in @smith-guidance/SKILL.md.
  Can't write those down → not ready to queue.
- **Re-derive presented aggregates**: a count or "N open items" is a DERIVED
  value — re-run the enumeration against the primary source in the session
  that presents it; the cached value is only a checksum, and a mismatch is a
  finding, never silently papered over.
- **Re-derive every re-presented option from current state**: an option that
  only made sense under conditions that no longer hold must be withdrawn by
  you, not left for the user to shoot down.
- **Check every conjunct of the requirement AS STATED BY ITS AUTHOR** — not
  as reworded by your progress report. One unmet conjunct → the requirement
  is open. Watch the substitution tell: renaming the requirement after the
  part your last action satisfied. A snapshot is not version control:
  ongoing edit-work needs history, not a one-time copy of its start state.
- **Every proposed action traces to an open requirement.** After a
  correction, re-derive from scratch — "this work was already under way"
  is not a requirement; if the motivating question is answered, the
  follow-up dissolved with it. Fabricated work manufactures real risks.

<a name="methods-v1"></a>
## Methods

The question stays the same; the method is chosen per check. The four
methods are test, analysis, inspection and demonstration, as named in
section 5.3 "Product Verification" of the NASA Systems Engineering
Handbook, revision 2
(https://www.nasa.gov/reference/systems-engineering-handbook/).

- **Test: run the tool** for a mechanical check (a schema, a linter, a
  type checker, a test suite): its output is the evidence, and a tool
  that did not run is a missing signal, not a pass.
- **Analyse** a claim that no tool can run: name the observation that
  would refute it and look for it
  (`@smith-analysis/SKILL.md#hypothesis-testing-v1`).
- **Inspect** the work against each conjunct of the requirement as its
  author stated it.
- **Demonstrate** by running the work on the case the requirement names
  and quoting what it printed.

<a name="plugin-integration-v1"></a>
## Claude Code Plugin Integration

**When pr-review-toolkit is available:**

- **silent-failure-hunter agent**: Detects silent failures, inadequate error handling
- Analyzes catch blocks, fallback behavior, missing logging
- Trigger: "Check for silent failures" or use Task tool

<a name="related-v1"></a>
## Related

- @smith-guidance/SKILL.md - Anti-sycophancy, safety rules, making changes
- `@smith-analysis/SKILL.md#hypothesis-testing-v1` - Strong Inference and
  falsification, which claim checks apply
- `@smith-clarity/SKILL.md` - Cognitive guards, logic fallacies, confirmation bias, premature closure
- `@smith-subagents/SKILL.md` - Read-only skeptic role, blind evaluator
- `@smith-research/SKILL.md` - Source-citation format for evidence per claim
- `@smith-recon/SKILL.md` - Multi-source briefs, cross-verification

<a name="before-you-finish-v1"></a>
## Before You Finish

**When verifying a claim, a finding or a requirement:**
1. Chose the method per check: the tool for a mechanical check, a
   disproof attempt for a claim, inspection against each conjunct
2. Surprising result? Check the topic's recorded decisions FIRST — deviation
   is reported as deviation, not discovery
3. Checkpoint written? Artifact census done; every "persisted" claim carries
   its same-turn listing
4. Reporting something absent, clean or done? Confirm the check ran (a
   control query for a search); else record "not run", never "clean"
