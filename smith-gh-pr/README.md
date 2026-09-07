# smith-gh-pr

GitHub Pull Request workflows: creation, review, stacking, merging.

## Hook Registration

### Attribution Format Enforcement

Register `enforce-attribution.sh` as a PreToolUse hook to validate PR comment attribution format:

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
- `gh pr comment` and `gh pr review` commands contain `Assisted-by: Claude:claude-[model]` format
- No "on behalf of" pattern
- Attribution from `~/.smith/smith-ctx-claude/scripts/attribution.sh` (never hand-typed)

## Related

- `SKILL.md` - Full skill documentation
- `references/REVIEW-WORKFLOW.md` - Review guidelines
- `references/intent.md` - Attribution format fix intent
- `references/spec.md` - Attribution format fix specification
- `references/plan.md` - Attribution format fix plan
