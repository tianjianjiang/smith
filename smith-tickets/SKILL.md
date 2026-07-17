---
name: smith-tickets
description: Ticket creation by convention — create Jira issues/sub-tasks in Job Story form, Japanese description, under the correct parent Epic, after reading the relevant context. Invoke with /smith-tickets.
argument-hint: [work to ticket]
---

# /smith-tickets — create tickets that follow the conventions

Turn a piece of work into well-formed Jira tickets. Argument = the work to
break down.

## Conventions (enforced)

- **Job Story** format: "When «situation», I want to «motivation», so I can
  «expected outcome»" — describe problem + outcome, not the implementation
  (`@smith-style` External Communication / Issue format).
- **Description in Japanese** (match the team's working language); titles and
  code artifacts stay English.
- **Correct parent Epic** — find the best-match Epic before creating; link as
  child. Atomic tickets, one concern each (one-to-one with a future PR).

## Procedure

1. **Gather context first** — read the relevant Notion/Jira/repo context (or
   run `/smith-recon` for the topic) so tickets are grounded, not guessed.
2. **Decompose** — propose the numbered ticket list (title + Job Story + parent
   Epic) and get scope approval before creating (`@smith-guidance` Scope
   Verification; no presuming).
3. **Resolve identities/parents from source** — confirm the Epic and any
   assignee via the API, not by guessing (`@smith-gh-cli` identity rule applies
   to trackers too).
4. **Create** — via the Atlassian MCP tools. Use the correct Jira hierarchy
   field per issue type: a sub-task uses the `parent` field; a story/task links
   to its Epic via the Epic Link (or `parent` on team-managed projects). Set
   the Job Story body (Japanese) + labels. Report created keys + URLs in-band.
5. **Verify** — re-read each created ticket to confirm parent + format; fix any
   that drifted.

A ticket body is authored content: draft it, show it, and create only on an
explicit yes — never bulk-create on a guess. Step 2's approved numbered list IS
that yes for the tickets on it; anything not on it needs its own. Canonical
rule: `@smith-guidance` Harmless — external writes.
