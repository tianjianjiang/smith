#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../../.."
GH_PR="$ROOT/smith-gh-pr/SKILL.md"
REVIEW="$ROOT/smith-gh-pr/references/REVIEW-WORKFLOW.md"
HOME_HEADING='## PR Body Format'
READING_HEADING='## Reading a PR'
POST_URL='https://claude.dev/blog/solving-code-review-at-anthropic/'

failures=0
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

flattened_section() {
  awk -v start="$2" '
    $0 == start { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
  ' "$1" | tr '\n' ' ' | sed 's/  */ /g'
}
flattened_bullet() {
  awk -v label="$2" '
    index($0, label) == 1 { inside = 1; print; next }
    inside && /^[^ ]/ { exit }
    inside { print }
  ' "$1" | tr '\n' ' ' | sed 's/  */ /g'
}
has() { printf '%s\n' "$1" | grep -q -i -F -- "$2"; }

BODY="$(flattened_section "$GH_PR" "$HOME_HEADING")"
[ -n "$BODY" ] || fail "smith-gh-pr/SKILL.md has no '$HOME_HEADING' section"
[ "$(grep -c '^Media:' "$GH_PR")" = 1 ] || fail "smith-gh-pr/SKILL.md does not have exactly one paragraph starting 'Media:'"
MEDIA="$(awk -v start="$HOME_HEADING" '
  $0 == start { inside = 1; next }
  inside && /^## / { exit }
  inside && /^Media:/ { paragraph = 1 }
  paragraph && /^$/ { exit }
  paragraph { print }
' "$GH_PR" | tr '\n' ' ' | sed 's/  */ /g')"
[ -n "$MEDIA" ] || fail "'$HOME_HEADING' has no paragraph starting 'Media:'"
for phrase in \
  'the body is text' \
  'a screenshot made by a script' \
  'under What/Why' \
  'a script committed with the change' \
  'never depends on' \
  'goes stale against later code' \
  'cannot be made again from the commit' \
  'Mermaid' \
  "$POST_URL" \
  'https://x.com/karpathy/status/2105819303471976479'
do
  has "$MEDIA" "$phrase" || fail "the media rule in '$HOME_HEADING' lacks '$phrase'"
done
has "$MEDIA" 'reviewer cannot read' \
  && fail "the media rule gives 'a reviewer cannot read it' as a reason; its reason is that outside artifacts go stale"
has "$MEDIA" 'ASD-STE100' \
  && fail "the media rule cites ASD-STE100, which is a text-quality reference, not a source of this rule"

NOT_TOUCHED="$(flattened_bullet "$GH_PR" '- `Not touched:')"
[ -n "$NOT_TOUCHED" ] || fail "smith-gh-pr/SKILL.md has no '- \`Not touched:' bullet"
has "$NOT_TOUCHED" 'REVIEW-WORKFLOW.md" "Reading a PR"' \
  || has "$NOT_TOUCHED" 'REVIEW-WORKFLOW.md` "Reading a PR"' \
  || fail "the 'Not touched:' bullet does not point to REVIEW-WORKFLOW.md \"Reading a PR\""

grep -q -x -F -- "$READING_HEADING" "$REVIEW" || fail "REVIEW-WORKFLOW.md has no '$READING_HEADING' section"
FIRST_HEADING="$(grep -m 1 '^## ' "$REVIEW")"
[ "$FIRST_HEADING" = "$READING_HEADING" ] \
  || fail "'$READING_HEADING' is not the first section of REVIEW-WORKFLOW.md (reading comes before posting findings)"
READING="$(flattened_section "$REVIEW" "$READING_HEADING")"
for phrase in \
  'Not touched:' \
  'against the diff' \
  'is a defect'
do
  has "$READING" "$phrase" || fail "'$READING_HEADING' lacks '$phrase'"
done
printf '%s\n' "$READING" | grep -q -i -w -- 'tier' \
  && fail "'$READING_HEADING' names a risk tier; tier order arrives with the risk tiers, which do not exist yet"
grep -q -i -F -- 'against the diff' "$GH_PR" \
  && fail "smith-gh-pr/SKILL.md restates the Not touched check (one home: REVIEW-WORKFLOW.md)"

if [ "$failures" -gt 0 ]; then
  echo "FAIL: media-and-reading ($failures failed)"
  exit 1
fi
echo "PASS: media-and-reading"
