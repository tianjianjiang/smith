# smith-gh-pr

GitHub Pull Request workflows: creation, review, stacking, merging.

## Hook Registration

### Attribution Format Enforcement

Register `enforce-attribution.sh` as a PreToolUse hook to validate PR body/comment attribution format:

```json
{
  "hooks": {
    "PreToolUse": [
      "~/.smith/smith-gh-pr/scripts/enforce-attribution.sh"
    ]
  }
}
```

Add to `~/.claude/settings.json` or project `.claude/settings.json`.

The hook validates:
- `gh pr comment`, `gh pr review`, `gh pr create`, and `gh pr edit` commands contain
  `Assisted-by: Claude:claude-[model]` format — including a heredoc body
  (`--body "$(cat <<'EOF' ...)"`), not just `-b`/`--body=`/`-F`
- No "on behalf of" pattern
- Attribution from `~/.smith/smith-ctx-claude/scripts/attribution.sh` (never hand-typed)

The regex and "on behalf of" check live in `smith-ctx-claude/scripts/attribution-lib.sh`'s
`attribution_check_body` function, shared with `smith-git`'s
`commit-attribution-guard.sh` (see `@smith-git/SKILL.md` Commit Standards) so the two
hooks can't drift apart the way the docs and the enforced regex once did (#261).

## Related

- `SKILL.md` - Full skill documentation
- `references/REVIEW-WORKFLOW.md` - Review guidelines
- `references/intent.md` - Attribution format fix intent
- `references/spec.md` - Attribution format fix specification
- `references/plan.md` - Attribution format fix plan
