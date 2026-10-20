# smith-gh-pr

GitHub Pull Request workflows: creation, review, stacking, merging.

## Attribution enforcement

Pull request text is checked by `attribution-guard`, the one Claude Code
attribution adapter (`smith-ctx-claude/scripts/attribution-guard.sh`, matcher
`Bash|mcp__.*`); its registration is in `smith-ctx-claude/references/HOOKS.md`
"Registration" and its behaviour in that file's "attribution-model-stamp"
section. Which gh calls are covered writes, and the exact shapes allowed, are
declared as data in `smith-style/scripts/attribution-signatures.json`:

- Covered: `gh pr create|new|comment|merge|revert`, `gh pr edit` and
  `gh pr review` when they may carry a body, `gh pr|issue close|reopen` with a
  `-c`/`--comment`, `gh issue comment`, the `gh pr-review` writes
  (`review --add-comment`, `review --submit`, `comments reply`), and a `gh api`
  write of pull request or comment text other than a delete.
- Allowed: a covered write that matches a declared signature exactly, whose
  payload passes the rule in `smith-style/scripts/lib/attribution.mjs`. The
  body comes only from `-F`/`--body-file «absolute path»`, run as a command of
  its own; `gh pr-review --body` and the close/reopen `--comment` are read as
  literal text, since gh offers no file there. `gh pr merge` without a body
  and `gh pr review --approve` without a body pass, since the session writes
  none of that text.
- Blocked: everything else that is covered, including a literal `--body`
  where `--body-file` exists, `--fill`, `--recover`, `--attach`, a short flag
  cluster, a relative or expanded path, `gh pr revert` without a body, and
  every covered `gh api` write.

Out of scope, left to permissions: `gh issue create`/`edit` (the attribution
policy in `@smith-style` covers pull request text, not issues), a gh alias the
user defined, `gh api` calls that write commits directly (contents `PUT`,
`POST …/merges`, GraphQL `createCommitOnBranch` or `mergeBranch`), and any
program other than gh that holds the GitHub token.

Write the body to a draft file at an absolute path, append the trailer with
`~/.smith/smith-style/scripts/attribution.sh >> «file»` in a separate Bash
call, show the file, and pass `--body-file «file»`; never hand-type the
trailer. `gh pr-review` has no `--body-file`: run `attribution.sh` first and
end a single-quoted `--body '…'` with the line it printed, unchanged.

## Related

- `SKILL.md` - Full skill documentation
- `references/REVIEW-WORKFLOW.md` - Review guidelines
- `references/intent.md` - Attribution format fix intent
- `references/spec.md` - Attribution format fix specification
- `references/plan.md` - Attribution format fix plan
