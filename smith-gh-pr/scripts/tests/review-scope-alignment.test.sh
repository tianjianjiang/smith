#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../../.."
GH_PR="$ROOT/smith-gh-pr/SKILL.md"
REVIEW="$ROOT/smith-review/SKILL.md"
CYCLE_HEADING='## Code Review Cycle'
AUDIT_STEP_LABEL='4. **Proactively audit similar issues**'
AUDIT_BULLET_LABEL='- Proactive audit:'
SCOPE_LABEL='**Review scope (every round).**'

failures=0
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
flatten() { tr '\n' ' ' | sed 's/  */ /g; s/ $//'; }

expected_audit_step() {
  flatten <<'EOF'
4. **Proactively audit similar issues** in other files not explicitly
   mentioned: fix one labelled Critical or Required (`@smith-review` step
   0) in code the branch diff changes; report one in code it does not
   change as pre-existing and record a follow-up citing its `path:line`
   (`@smith-review` "Review scope")
EOF
}
expected_audit_bullet() {
  flatten <<'EOF'
- Proactive audit: search codebase for similar issues before committing,
  then fix or record each one as step 4 says
EOF
}
cycle_lines() {
  awk -v start="$CYCLE_HEADING" '
    $0 == start { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
  ' "$GH_PR"
}
audit_step() {
  cycle_lines | awk -v label="$AUDIT_STEP_LABEL" '
    index($0, label) == 1 { inside = 1; print; next }
    inside && (/^[0-9]+\. / || /^$/ || /^\*\*/) { exit }
    inside { print }
  ' | flatten
}
audit_bullet() {
  cycle_lines | awk -v label="$AUDIT_BULLET_LABEL" '
    index($0, label) == 1 { inside = 1; print; next }
    inside && /^[^ ]/ { exit }
    inside { print }
  ' | flatten
}

[ "$(audit_step)" = "$(expected_audit_step)" ] \
  || fail "step 4 of '$CYCLE_HEADING' differs from the approved review-scope text"
[ "$(audit_bullet)" = "$(expected_audit_bullet)" ] \
  || fail "the '$AUDIT_BULLET_LABEL' bullet differs from the approved review-scope text"
grep -q -F -- "$SCOPE_LABEL" "$REVIEW" \
  || fail "smith-review/SKILL.md has no '$SCOPE_LABEL' paragraph for step 4 to point to"

if [ "$failures" = 0 ]; then
  echo "PASS: review-scope-alignment"
else
  echo "FAIL: review-scope-alignment ($failures failed)"
  exit 1
fi
