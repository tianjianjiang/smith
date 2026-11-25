---
name: smith-undoable
description: Use when a command, script, hook or test would delete, overwrite or truncate a file.
---

# Undoable Operations

**Scope:** How an erase, overwrite or truncation is done in commands,
scripts, hooks and tests
**Prerequisites:** @smith-guidance/SKILL.md

## Rule

- Make every operation undoable: move a file or send it to the system
  Trash (on macOS, `/usr/bin/trash`), never erase it, in commands,
  scripts, hooks and tests alike. Judge an operation by whether it can be
  undone, not by its command's name: it is undoable when what it erases
  can be rebuilt from a source that survives it, such as an empty folder
  (`rmdir`), a container rebuilt from its image, or a branch whose commits
  a squash merge already holds; a file whose content exists nowhere else
  still goes to a move or the Trash

## Limits

- Ask first still applies: being undoable decides how an erase is done,
  not whether to ask before it (smith-guidance Safety Rules, "Ask before
  any destructive or hard-to-reverse action")
- Scope: local files, folders, branches and worktrees. A push or a sent
  message is an external write, governed by smith-guidance's External
  writes section
- Overwriting or truncating a file erases its old content: move the file
  aside first when that content exists nowhere else
- A move must not overwrite: check that the target does not exist, or use
  `mv -n`
- `/usr/bin/trash` exists on macOS 15 and later; elsewhere, move into a
  scratch folder made with `mktemp -d`
- A squash merge keeps a branch's changes, not its commits: compare the
  branch's diff with the squash commit before deleting the branch
- A container is rebuildable from its image only when it keeps no state
  of its own
- `rmdir` is undoable only for an empty folder

## Enforcement

- The erase-guard PreToolUse hook, `smith-ctx-claude/scripts/erase-guard.mjs`,
  denies `rm`, `unlink`, `shred`, `find -delete`, `git clean -f`,
  `git rm -f` and `claude rm` with `--discard-unpushed` or
  `--force-remove-worktree` in a Bash command and names the move or
  `/usr/bin/trash` in its reason. It judges the command's name, since a
  command cannot show whether what it erases exists elsewhere; its limits
  are in `smith-ctx-claude/references/HOOKS.md` "erase-guard"
- `smith-ctx-claude/scripts/tests/erasing-calls.test.sh` fails on any
  erasing call in a tracked script that
  `smith-ctx-claude/scripts/tests/erasing-calls.allowlist` does not cover.
  Each allowlist entry marks its line `mention` (text, not a call) or
  `rebuildable` (undoable under the rule above) and says why

## Related

- @smith-guidance/SKILL.md - Safety Rules and External writes
- `@smith-worktree/SKILL.md` - Removing a worktree and its branch after a
  squash merge

## Before You Finish

- Every erase is a move, a move to the Trash, or rebuildable from a
  surviving source
- No move lands on an existing file
- A new erasing call in a tracked script has an allowlist entry, or is
  converted to a move
