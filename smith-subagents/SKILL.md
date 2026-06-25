---
name: smith-subagents
description: Subagent spawning and return discipline — read-only by default, return findings not actions, treat every return as a claim to verify, reconcile against live state before mutating shared artifacts. Use when spawning Task/Agent subagents, delegating investigation, orchestrating parallel agents, or when a subagent will read or modify shared state (PRs, issues, files, remotes).
---

# Subagent Discipline

<metadata>

- **Scope**: Spawning, scoping, and consuming Task/Agent subagents and
  workflow orchestration; what tools to grant and how to trust returns
- **Load if**: About to spawn a subagent, delegate investigation, orchestrate
  parallel agents, OR a subagent will read/modify shared state (PR, issue,
  file, remote)
- **Prerequisites**: @smith-guidance/SKILL.md (delegation + in-band progress),
  @smith-ctx/SKILL.md (context isolation)

</metadata>

## CRITICAL: Spawn Narrow, Trust Nothing (Primacy Zone)

<required>

- Spawn READ-ONLY by default. Grant write/side-effecting tools only for a
  bounded edit you have explicitly described in the prompt.
- A subagent RETURNS findings; the main thread decides and acts. Investigators
  report `file:line` facts, not fixes.
- Treat every return as a CLAIM, not ground truth. Reconcile against live
  state before acting on it.
- Subagents do NOT inherit skills, AGENTS.md, or memory. Pass the rules the
  task needs INLINE in the prompt.
- Restate a subagent's key findings in your own message — a reader (and the
  classifier) sees only your text, never the subagent's return.

</required>

<forbidden>

- Granting an investigator/locator write, commit, push, or external-API tools.
- Letting a subagent mutate a shared artifact (PR title/body, issue, remote
  branch, tracked file) on its own — that is the main thread's call.
- Acting on a subagent's summary without re-reading the current state of what
  it described.
- Assuming a subagent saw your conventions because you follow them.

</forbidden>

## Spawning: scope and tools

<context>

- One concern per subagent. A locator finds; an editor changes one bounded
  thing; a reviewer critiques. Don't fuse roles.
- Parallelize INDEPENDENT subagents in a single message (multiple tool calls).
  Serialize only when one's input depends on another's output.
- Match the tool grant to the role: read-only (Read/Grep/Glob) for
  investigation; add Edit/Write only for an editor with a named target.
- Parallel file-mutating subagents need isolation — see
  `@smith-worktree/SKILL.md`. Read-only fan-out does not.

</context>

## Returns: findings, not actions

<context>

- The deliverable is DATA the main thread can act on: paths, line numbers,
  quoted evidence, a verdict. Not a side effect already taken.
- A subagent that "helpfully" edits a PR, commits, or writes external content
  has exceeded its mandate — even if asked to investigate. Scope the prompt to
  forbid this when the risk exists.
- Verify-from-source applies to returns too: if a subagent asserts a label or
  mechanism, confirm against the actual file/doc before you rely on it (see
  @smith-guidance/SKILL.md Honest).

</context>

## Reconcile vs live state

<context>

- Between spawn and return, the world can change: a PR gets retitled, a file
  gets edited, a branch moves. The subagent's snapshot is already stale.
- Before mutating a shared artifact a subagent reported on, RE-READ its current
  state and merge — never overwrite from the subagent's snapshot.
- Incident this guards against: a subagent overwrote a PR title from a stale
  read, discarding an intervening change. Reconcile first, then write.

</context>

<related>

- @smith-guidance/SKILL.md - Delegation, in-band progress, verify-from-source
- @smith-ctx/SKILL.md - Context isolation: keep findings, discard the noise
- `@smith-ralph/SKILL.md` - Iterative orchestration patterns
- `@smith-skills/SKILL.md` - Subagents don't auto-load skills; pass rules inline
- `@smith-worktree/SKILL.md` - Isolate parallel file-mutating subagents

</related>

## ACTION (Recency Zone)

<required>

**Before spawning:**
1. Pick ONE concern; grant read-only tools unless it is a named bounded edit
2. Inline the rules/conventions the task needs (no skill inheritance)
3. State the expected return shape; forbid side effects if risky

**On return:**
1. Treat it as a claim — re-read live state for anything it will mutate
2. Restate the key findings in your own message
3. Decide and act from the main thread; don't rubber-stamp the summary

</required>
