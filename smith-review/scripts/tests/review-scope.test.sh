#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$HERE/../../SKILL.md"
PROCEDURE_HEADING='## Procedure'
LIVE_STATE_HEADING='## Live state'
SCOPE_LABEL='**Review scope (every round).**'
CONVERGE_LABEL='5. **Converge**'
SCOPE_CLOSURE="fixed (verified), needing no change, rejected with evidence, deferred with the user's agreement, or deferred under Review scope as pre-existing, with its follow-up's locator; a"
BRANCH_DIFF_STAT="- Branch diff stat against the default branch: !\`git diff --merge-base origin/HEAD --stat 2>/dev/null || echo 'origin/HEAD unset'\`"
UNTRACKED_FILES='- Untracked files: !`git ls-files --others --exclude-standard :/`'

failures=0
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
flatten() { tr '\n' ' ' | sed 's/  */ /g; s/ $//'; }

expected_scope() {
  flatten <<'EOF'
**Review scope (every round).** Every review round reviews the branch
diff: everything the branch changes since it left its parent, uncommitted
changes and new files included, where the parent is the default branch
or, on a stacked branch, its parent branch. A finding in code the branch
diff changes is fixed in the change unless step 5 closes it otherwise; a
finding in code it does not change is not fixed in the change: report it
as pre-existing and record a follow-up citing its `path:line` for its own
change.
EOF
}
section_lines() {
  awk -v start="$1" '
    $0 == start { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
  ' "$SKILL"
}
procedure_paragraph() {
  section_lines "$PROCEDURE_HEADING" | awk -v label="$1" '
    index($0, label) == 1 { paragraph = 1 }
    paragraph && /^$/ { exit }
    paragraph { print }
  ' | flatten
}
numbered_step() {
  awk -v label="$1" '
    index($0, label) == 1 { inside = 1; print; next }
    inside && (/^[0-9]+\. / || /^## /) { exit }
    inside { print }
  ' "$SKILL" | flatten
}
label_lines() {
  awk -v label="$1" 'index($0, label) == 1 { n++ } END { print n + 0 }' "$SKILL"
}
label_inside_fence() {
  awk -v label="$1" '
    /^ *(```|~~~)/ { fenced = !fenced; next }
    fenced && index($0, label) == 1 { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$SKILL"
}

[ "$(label_lines "$SCOPE_LABEL")" = 1 ] \
  || fail "smith-review/SKILL.md does not have exactly one '$SCOPE_LABEL' paragraph"
label_inside_fence "$SCOPE_LABEL" \
  && fail "the review-scope rule sits inside a code fence, so it is an example, not a rule"
[ "$(procedure_paragraph "$SCOPE_LABEL")" = "$(expected_scope)" ] \
  || fail "the review-scope paragraph under '$PROCEDURE_HEADING' differs from the approved text"
numbered_step "$CONVERGE_LABEL" | grep -q -F -- "$SCOPE_CLOSURE" \
  || fail "step 5 does not list '$SCOPE_CLOSURE' among its closures"
section_lines "$LIVE_STATE_HEADING" | grep -q -x -F -- "$BRANCH_DIFF_STAT" \
  || fail "the live state does not show the branch diff stat against the default branch"
section_lines "$LIVE_STATE_HEADING" | grep -q -x -F -- "$UNTRACKED_FILES" \
  || fail "the live state does not list the untracked files"

if [ "$failures" = 0 ]; then
  echo "PASS: review-scope"
else
  echo "FAIL: review-scope ($failures failed)"
  exit 1
fi
