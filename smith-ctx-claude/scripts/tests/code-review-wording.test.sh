#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"

fail() { echo "FAIL: $1"; exit 1; }

TMP="$(mktemp -d)" || fail "temporary directory not created"
trap 'rm -rf "$TMP"' EXIT

AGENT_COUNT='(^|[^a-z0-9])([0-9]+|two|three|four|five|six|seven|eight)[ -][a-z -]*(agents?|reviewers)'
OLD_CLAIM="/code-review[^,;]*(plug-?in|parallel agents|$AGENT_COUNT)|plug-?ins?[^,;]*/code-review"

old_plugin_claims() {
  git grep "$@" -q -F -e '/code-review' -- '*.md'
  case "$?" in
    0) ;;
    1) return 3 ;;
    *) return 2 ;;
  esac
  claims="$(git grep "$@" -n -i -E -e '/code-review' --and -e "$OLD_CLAIM" -- '*.md')"
  [ "$?" -le 1 ] || return 5
  printf '%s' "$claims"
}

claims_in() {
  mkdir "$TMP/$1" && printf '%s\n' "$2" >"$TMP/$1/${3:-doc}.md" || return 4
  (cd "$TMP/$1" && old_plugin_claims --no-index)
}

index=0
while IFS= read -r line; do
  index=$((index + 1))
  found="$(claims_in "old$index" "$line")" || fail "search failed on: $line"
  [ -n "$found" ] || fail "old claim not reported: $line"
done <<'EOF'
- Claude Code `/code-review` plugin (v2.1.101+)
- `/code-review` - Automated PR review with parallel agents
- **`/code-review`**: Launches 4 parallel agents with confidence scoring (threshold 80)
   own subagents (/code-review launches 4 agents; pr-review-toolkit coordinates
- Claude Code plugins/skills: `/code-review`, `/review-pr` (pr-review-toolkit;
`/code-review` runs five reviewer agents in parallel
`/code-review` uses 4 subagents
the `/code-review` plug-in
`/code-review` runs a 4-agent review
- `/code-review` runs three reviewers
- `/code-review` runs a five-agent review
- the plug-in that provides `/code-review`
- `/code-review` Plugin
- `/code-review` runs two agents
- `/code-review` runs four agents
- `/code-review` runs six agents
- `/code-review` runs seven agents
- `/code-review` runs eight agents
EOF

index=0
while IFS= read -r line; do
  index=$((index + 1))
  found="$(claims_in "current$index" "$line")" || fail "search failed on: $line"
  [ -z "$found" ] || fail "current wording reported: $line"
done <<'EOF'
- `/code-review` - review of the current branch's changes, committed or not,
- Claude Code: the bundled skill `/code-review`; plugins `/review-pr` and `code-simplifier`
- `/code-review` and the pr-review-toolkit:code-reviewer agent
- `/code-review`, a bundled skill, unlike the pr-review-toolkit plugin
- plugins `/review-pr`, and the bundled skill `/code-review`
- plugins `/review-pr`; bundled skill `/code-review`
- `/code-review` with lightweight agents
EOF

claims_in no-mention '- a review skill with no slash command' >/dev/null
[ "$?" -eq 3 ] || fail "a file without a /code-review mention was not refused as having no mention"

found="$(claims_in path '- `/code-review low`' plugins-and-skills)" || fail "search failed on a file whose name says plugins"
[ -z "$found" ] || fail "a file name was read as a claim: $found"

cd "$HERE/../../.." || fail "repository root not found"
found="$(old_plugin_claims)" || fail "search of tracked markdown failed or found no /code-review mention"
[ -z "$found" ] || fail "tracked files still describe /code-review as the old plugin: $found"

echo "PASS: code-review-wording"
