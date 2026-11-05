#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../../.."
GH_PR="$ROOT/smith-gh-pr/SKILL.md"
SHIP="$ROOT/smith-ship/SKILL.md"
HOME_HEADING='## PR Body Format'

failures=0
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

section() {
  awk -v start="$2" '
    $0 == start { inside = 1; print; next }
    inside && /^## / { exit }
    inside { print }
  ' "$1"
}
outside_section() {
  awk -v start="$2" '
    $0 == start { inside = 1; next }
    inside && /^## / { inside = 0 }
    !inside { print }
  ' "$1"
}
bullet_line_of() {
  awk -v label="$2" 'index($0, label) == 1 { print NR; exit }' "$1"
}

TEMPLATE="$(mktemp)"
SCRATCH="$(mktemp -d)"
trap 'rm -f "$TEMPLATE"; rm -rf "$SCRATCH"' EXIT
section "$GH_PR" "$HOME_HEADING" > "$TEMPLATE"
[ -s "$TEMPLATE" ] || fail "smith-gh-pr/SKILL.md has no '$HOME_HEADING' section"

previous=0
previous_label="the section heading"
for label in '- **What/Why**' '- `Not touched:' '- `Testing:' '- **How to revert**' '- `Depends on:' '- The `Assisted-by:'; do
  at=$(bullet_line_of "$TEMPLATE" "$label")
  if [ -z "$at" ]; then
    fail "template home lacks the '$label' label"
    continue
  fi
  [ "$at" -gt "$previous" ] || fail "template label '$label' is not after '$previous_label'"
  previous=$at
  previous_label=$label
done

grep -F -- 'Not touched:' "$TEMPLATE" | grep -q -i 'only when' \
  || fail "the 'Not touched:' line is not marked conditional ('only when')"
grep -F -- 'Depends on:' "$TEMPLATE" | grep -q -i 'only when' \
  || fail "the 'Depends on:' line is not marked conditional ('only when')"
grep -F -- 'Depends on:' "$TEMPLATE" | grep -q -F -- 'Blocks:' \
  || fail "the dependencies line does not name both 'Depends on:' and 'Blocks:'"
grep -F -- 'Testing:' "$TEMPLATE" | grep -q -i 'one line' \
  || fail "the 'Testing:' line is not marked as one line"
grep -q -i -F -- 'no CI check' "$TEMPLATE" \
  || fail "the template does not say the Testing line states that no CI check backs it"
grep -q -F -- 'skill-lint' "$TEMPLATE" \
  || fail "the template does not name skill-lint as the document evidence that exists today"

grep -q -i -F -- 'Never paste results' "$TEMPLATE" \
  || fail "the template lacks the 'Never paste results' rule"
LEAVE_OUT="$(tr '\n' ' ' < "$TEMPLATE" | sed 's/  */ /g')"
for omitted in 'Leave out a link to the plan' 'a deviations section' 'a reading guide' 'review receipt'; do
  printf '%s\n' "$LEAVE_OUT" | grep -q -F -- "$omitted" \
    || fail "the 'Leave out' sentence does not name '$omitted'"
done

grep -q -w -- 'Risk' "$TEMPLATE" \
  && fail "the template has a Risk line (the risk tiers change adds it, not this one)"
grep -q -i -F -- 'NO Test plan section' "$GH_PR" && fail "smith-gh-pr/SKILL.md still says 'NO Test plan section'"

outside_section "$GH_PR" "$HOME_HEADING" | grep -q -F -- 'What/Why' \
  && fail "smith-gh-pr/SKILL.md restates 'What/Why' outside '$HOME_HEADING' (one home only)"
outside_section "$GH_PR" "$HOME_HEADING" | grep -q -F -- 'How to revert' \
  && fail "smith-gh-pr/SKILL.md restates 'How to revert' outside '$HOME_HEADING'"

STACKED="$(section "$GH_PR" '## Stacked PRs')"
[ -n "$STACKED" ] || fail "smith-gh-pr/SKILL.md has no '## Stacked PRs' section"
printf '%s\n' "$STACKED" | grep -q -F -- 'Depends on:' \
  && fail "the Stacked PRs section restates 'Depends on:' instead of pointing to '$HOME_HEADING'"
printf '%s\n' "$STACKED" | grep -q -F -- 'PR Body Format' \
  || fail "the Stacked PRs section does not point to 'PR Body Format'"

grep -q -F -- 'What/Why' "$SHIP" && fail "smith-ship/SKILL.md restates 'What/Why' instead of pointing to the template"
grep -q -F -- 'PR Body Format' "$SHIP" || fail "smith-ship/SKILL.md does not point to '@smith-gh-pr' 'PR Body Format'"

STACKS="$ROOT/smith-gh-pr/references/STACKS.md"
grep -q -x -- '## Stack' "$STACKS" \
  && fail "smith-gh-pr/references/STACKS.md has a '## Stack' body block instead of pointing to the template"
grep -q -F -- 'Depends on**' "$STACKS" \
  && fail "smith-gh-pr/references/STACKS.md restates a bold 'Depends on' template line"
grep -q -F -- 'PR Body Format' "$STACKS" \
  || fail "smith-gh-pr/references/STACKS.md does not point to 'PR Body Format'"

CHECKER="$ROOT/smith-gh-pr/scripts/check-pr-body.sh"
FIXTURES="$HERE/fixtures"
expect_accept() {
  sh "$CHECKER" "$FIXTURES/$1" > /dev/null 2>&1 \
    || fail "the body checker rejects fixtures/$1"
}
expect_reject() {
  out="$(sh "$CHECKER" "$FIXTURES/$1" 2>&1)"
  code=$?
  [ "$code" -eq 1 ] || fail "the body checker exits $code, not 1, for fixtures/$1"
  printf '%s\n' "$out" | grep -q -F -- "$2" \
    || fail "the body checker does not report '$2' for fixtures/$1"
}
if [ ! -f "$CHECKER" ]; then
  fail "the body checker smith-gh-pr/scripts/check-pr-body.sh does not exist"
else
  for accepted in pr-body-valid.md pr-body-minimal.md pr-body-whatwhy-mentions-revert.md \
    pr-body-revert-plain.md pr-body-revert-bold-colon.md pr-body-blocks-only.md; do
    expect_accept "$accepted"
  done
  while IFS='|' read -r rejected problem; do
    expect_reject "$rejected" "$problem"
  done <<'REJECTED'
pr-body-missing-revert.md|MISSING: a "How to revert:" label
pr-body-revert-mentioned-only.md|MISSING: a "How to revert:" label
pr-body-revert-empty-label.md|MISSING: a "How to revert:" label
pr-body-revert-before-testing.md|OUT OF ORDER: How to revert
pr-body-missing-testing.md|MISSING: a line starting "Testing:"
pr-body-assisted-by-not-last.md|OUT OF ORDER: Assisted-by:
pr-body-testing-multiline.md|Testing: is one line
pr-body-depends-before-revert.md|OUT OF ORDER: Depends on:
pr-body-revert-empty-bold-colon.md|MISSING: a "How to revert:" label
pr-body-testing-empty.md|MISSING: text after the "Testing:" label
pr-body-testing-twice.md|DUPLICATE: Testing:
pr-body-revert-twice.md|DUPLICATE: How to revert
pr-body-assisted-by-twice.md|DUPLICATE: Assisted-by:
pr-body-assisted-by-missing.md|MISSING: a final line starting "Assisted-by:"
pr-body-not-touched-after-testing.md|OUT OF ORDER: Not touched:
pr-body-missing-whatwhy.md|MISSING: What/Why text
REJECTED
  cp "$FIXTURES/pr-body-valid.md" "$SCRATCH/a=b.md"
  (cd "$SCRATCH" && sh "$CHECKER" a=b.md < /dev/null > /dev/null 2>&1) \
    || fail "the body checker rejects a valid body at a path that looks like an awk assignment (a=b.md)"
  usage_out="$(sh "$CHECKER" 2>/dev/null)"
  usage_code=$?
  [ "$usage_code" -eq 2 ] || fail "the body checker exits $usage_code, not 2, without an argument"
  [ -z "$usage_out" ] || fail "the body checker prints its usage error to stdout, not stderr"
  sh "$CHECKER" 2>&1 >/dev/null | grep -q -F -- 'Usage:' \
    || fail "the body checker does not print its usage error to stderr"
  sh "$CHECKER" "$FIXTURES/no-such-body.md" > /dev/null 2>&1
  [ "$?" -eq 2 ] || fail "the body checker does not exit 2 for an unreadable file"
fi

if [ "$failures" -gt 0 ]; then
  echo "FAIL: pr-body-template ($failures failed)"
  exit 1
fi
echo "PASS: pr-body-template"
