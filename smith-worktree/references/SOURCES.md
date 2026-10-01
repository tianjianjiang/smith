# smith-worktree — sources and test records

Dated evidence behind rules in `smith-worktree/SKILL.md`. The skill file
states the rules; this document holds when and against what each was
checked.

## Documentation checks

- https://code.claude.com/docs/en/changelog (`worktree.baseRef` v2.1.133,
  `bgIsolation` v2.1.143): verified 2026-05-21.
- https://code.claude.com/docs/en/worktrees "How Claude Code enforces
  isolation": verified 2026-09-07 on v2.1.263.
- https://code.claude.com/docs/en/worktrees,
  https://code.claude.com/docs/en/hooks,
  https://code.claude.com/docs/en/memory: retrieved 2026-09-24.

## Tests on this machine

- `.worktreeinclude` is honoured by `EnterWorktree` and by
  `claude --worktree`: tested 2026-09-24 on v2.1.281.
- Directory symlinks are not copied by `.worktreeinclude`: probed
  2026-09-26 on v2.1.282.
- With `exclude_commands = ["git"]` in rtk's configuration, `rtk hook
  check` returns `No rewrite` for `git status`, `git -C /x status` and
  `git push -u origin main`: verified 2026-09-07.

## Upstream issues

- A dedicated local-skills directory was declined:
  https://github.com/anthropics/claude-code/issues/81110
- Copying `.claude/` subdirectories into a worktree, open when retrieved
  on 2026-09-24: https://github.com/anthropics/claude-code/issues/28041
- rtk rewrites git inside a worktree session into a shape the isolation
  guard refuses: https://github.com/rtk-ai/rtk/issues/3864
- rtk multi-word exclusion prefixes miss the `git -C` form:
  https://github.com/rtk-ai/rtk/issues/3838
- `gh pr merge --delete-branch` from a worktree skips the local cleanup
  with a warning from gh 2.99.0 on: cli/cli#14007, which fixes
  cli/cli#3442.
