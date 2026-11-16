#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
SKILL="$REPO/smith-guidance/SKILL.md"
DOC="$REPO/smith-guidance/references/RULE-CONFLICTS.md"

fail() { echo "FAIL: $1"; exit 1; }

non_permanent_github_links() {
  grep -oE 'https://github\.com/[^ )>]+' "$1" \
    | grep -vE '^https://github\.com/[^/]+/[^/]+/blob/[0-9a-f]{40}/'
}

control=$(mktemp)
trap 'rm -f "$control"' EXIT
printf '%s\n' '- Branch link: https://github.com/owner/repo/blob/main/SKILL.md' \
  '- Permanent link: https://github.com/owner/repo/blob/e9e1f06aa4e26e95cd4ed37210a0632202c429e9/SKILL.md' \
  > "$control"
planted=$(non_permanent_github_links "$control")
[ "$planted" = "https://github.com/owner/repo/blob/main/SKILL.md" ] \
  || fail "control: link check must flag only the branch-name link, got: $planted"

grep -q 'references/RULE-CONFLICTS.md' "$SKILL" \
  || fail "smith-guidance/SKILL.md does not name references/RULE-CONFLICTS.md"
[ -f "$DOC" ] || fail "smith-guidance/references/RULE-CONFLICTS.md is missing"
grep -q 'https://github\.com/' "$DOC" \
  || fail "RULE-CONFLICTS.md has no github.com link to check"
bad=$(non_permanent_github_links "$DOC")
[ -z "$bad" ] || fail "RULE-CONFLICTS.md has non-permanent github.com links: $bad"
grep -q '^## Sources$' "$DOC" || fail "RULE-CONFLICTS.md has no Sources section"

echo "PASS: rule-conflicts"
