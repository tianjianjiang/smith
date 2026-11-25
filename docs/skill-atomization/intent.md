# Intent: move the always-loaded rules to atomic skills and hooks

Author: repository owner. Status: proposed on 2026-11-25.

## Problem

Four skills load in every session, named on the "Always loaded" line of
the repository's `AGENTS.md` (read as `~/.smith/CLAUDE.md`):
`smith-principles`, `smith-standards`, `smith-guidance` and `smith-ctx`.
That file sets a budget of under 2,000 tokens per skill. Counted on
3ebaac8d with the cl100k_base tokenizer, as commits a3e85af7 (#299),
ca7d3fbf (#304) and bee37de4 (#308) counted file totals; a rule's count
covers its own lines:

| File | Tokens | Rules | Procedure rules (tokens) |
|---|---|---|---|
| `smith-principles/SKILL.md` | 526 | 25 | 2 (73) |
| `smith-standards/SKILL.md` | 1,163 | 42 | 4 (89) |
| `smith-guidance/SKILL.md` | 2,273 | 62 | 28 (1,262) |
| `smith-ctx/SKILL.md` | 866 | 51 | 11 (190) |

`smith-guidance` has been over budget since 6e431f3c (#321) took it from
1,987 to 2,138 tokens; 3ebaac8d (#408) added the undoable-operations
rule, 135 more. Every new rule has met the same limit: #299 cut the file
from 3,491 to 1,999 tokens by compressing wording, and later rules
pushed it over again. Compression has run out of room.

More than half of `smith-guidance`, 1,262 of 2,273 tokens, is procedure:
steps to carry out in one situation, such as before an external write or
before erasing a file. A procedure loaded in every session costs tokens in
the sessions that never meet its situation, and as prose it relies on the
agent remembering it at the moment it applies. Of the 180 rules counted,
which include 58 that carry no rule of their own, such as headings, links
and restatements (`plan.md` §Classification criterion), 12 could be
checked mechanically and 28 partly; 24 already have a hook or test behind
them, often only for part of the rule.

## Proposed outcome

- Always-loaded skills keep preferences: how to think, write or judge,
  plus the few small procedure groups whose move would save under 50
  tokens net of its pointer (`plan.md` §Ranked stacks). Each stays under the 2,000-token budget with room for growth.
- Each other procedure becomes an atomic skill: one operation or procedure per
  skill, with a description that says only when to use it ("Use when
  ..."), as these sources describe:
  https://github.com/obra/superpowers/blob/22f0b463/skills/writing-skills/SKILL.md
  lines 59 and 95-97,
  https://github.com/cursor/plugins/blob/41e40093/pstack/README.md line
  225, and
  https://github.com/addyosmani/agent-skills/blob/e997ac5b/CLAUDE.md line
  59, all read on 2026-11-25 when this intent was scoped.
- Where a rule is mechanically checkable, a hook or test enforces it, so
  the skill explains and the hook holds.
- The always-loaded file keeps a one-line pointer where a procedure left,
  so the trigger still reaches every session.
- The move is progressive: one rule, or a tight group, per stack of pull
  requests, each stack leaving the suite green.

## Affected users and systems

- Every agent session that loads smith: Claude Code, Cursor and Kiro read
  the same always-loaded files.
- `smith-guidance`, `smith-standards`, `smith-ctx` and, least,
  `smith-principles`.
- Hooks under `smith-ctx-claude/scripts/`, `smith-git/scripts/hooks/` and
  `smith-standards/scripts/`, registered in `~/.claude/settings.json` and
  listed in `README.md` "Hooks (manual registration)"; their tests under each skill's `scripts/tests/`.
- The skill-router trigger table `smith-ctx-claude/skill-triggers.json`
  and `smith-ctx-claude/REFERENCE.md`, which must learn each new skill's
  trigger.

## Constraints

- A rule's meaning does not change while it moves; a wording change is its
  own pull request.
- Hooks run only on Claude Code. On Cursor and Kiro the skill and its
  pointer are the only enforcement, so the pointer must stay in the
  always-loaded file.
- A hook judges a command's text, not whether its effect can be undone, so
  each hook states which cases it cannot see.
- No erasing call in any script, hook or test the stacks add
  (`smith-guidance/SKILL.md:67-74`).

## Open questions

- Whether `AGENTS.md` itself (1,489 tokens) and `smith-ctx-claude`
  (3,259 tokens, loaded first on Claude Code by `AGENTS.md` "Platform
  Context") get the same move. Decided by the owner on 2026-11-25: they
  stay outside this one; a later intent takes them up.
- The criterion that separates a preference from a procedure was decided
  by the owner on 2026-11-25: `plan.md` §Classification criterion.
