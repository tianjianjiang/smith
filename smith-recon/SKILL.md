---
name: smith-recon
description: Guided multi-source investigation — asks which sources to sweep (jsonl history, memories, Notion, Slack, Jira, Drive, GitHub) for a topic, reads them bounded and cross-verified, and returns an evidence-linked brief. Invoke with /smith-recon.
argument-hint: [topic or question]
---

# /smith-recon — guided, bounded multi-source investigation

Hydrate context for a topic from chosen sources, then synthesize a verified,
evidence-linked brief. Designed to be GUIDED and CHEAP — it asks scope before
sweeping, rather than blindly firing a large subagent fleet (costly and
low-quality). Argument = the topic/question.

## Procedure

1. **Scope first (ask)** — use AskUserQuestion to confirm: (a) which sources to
   read — jsonl convo history, Serena + Basic-Memory, Notion, Slack, Jira,
   Google Drive, GitHub; (b) the precise question; (c) depth/breadth and output
   language (zh-Hant by default per user preference). Do NOT presume the source
   set.
2. **Plan the sweep** — list the concrete reads per chosen source. Cap fan-out:
   prefer a few targeted reads (and, when iterating, a `/loop`/ralph loop that
   re-shares the relevant smith skills + topic + accumulated context —
   `@smith-ralph`, `@smith-automation`) over many one-shot parallel subagents.
   Load `@smith-research`/`@smith-validation` (verify before asserting) and
   `@smith-subagents` (returns are claims; restate in-band).
3. **Read bounded** — for noisy history use a scripted full scan (counts +
   denominator), not sampling (`@smith-guidance` Scope Verification: close
   gaps, don't just disclose them). Quote source lines / URLs as you go.
4. **Cross-verify** — reconcile sources; flag contradictions; mark anything
   unverified explicitly. Verify suspicious claims before relying on them.
5. **Brief** — return a synthesis with evidence URLs/`file:line` for every
   claim, in the requested language. Note any source deliberately not covered
   and why (no silent omissions).

If the topic is broad, widen only after asking — never silently.
