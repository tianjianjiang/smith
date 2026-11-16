#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
SEAM="$ROOT/smith-verification/SKILL.md"
VALIDATION="$ROOT/smith-validation/SKILL.md"
status=0

fail() { echo "FAIL: verification-seam: $1"; status=1; }

readme_missing() {
  printf '%s\n' "$skills" |
  while IFS= read -r skill; do
    [ -z "$skill" ] && continue
    grep -q "^| \*\*.*\`$skill\`" "$1" || echo "$skill"
  done
}

frontmatter_description() {
  awk 'NR == 1 { if ($0 != "---") exit; next }
       $0 == "---" { exit }
       on && /^[[:space:]]+[^[:space:]]/ { print; next }
       { on = 0 }
       /^description:/ { sub(/^description:[[:space:]]*/, ""); print; on = 1 }' "$1" 2>/dev/null
}

points_to_seam() {
  frontmatter_description "$1" | grep -q 'smith-verification'
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

skills=$(git -C "$ROOT" ls-files | sed -n 's|^\(smith-[^/]*\)/SKILL\.md$|\1|p')
[ -n "$skills" ] || fail "control: no tracked smith-*/SKILL.md found"
missing=$(readme_missing "$ROOT/README.md")
[ -z "$missing" ] || fail "README skills table lacks: $missing"
first_skill=$(printf '%s\n' "$skills" | sed -n 1p)
grep -v "^| \*\*.*\`$first_skill\`" "$ROOT/README.md" > "$WORK/README.md"
readme_missing "$WORK/README.md" | grep -qxF "$first_skill" ||
  fail "control: a README without the row of $first_skill was not reported"

[ -f "$SEAM" ] || fail "smith-verification/SKILL.md missing"
points_to_seam "$VALIDATION" ||
  fail "smith-validation description does not point to smith-verification"
awk 'NR == 1, NR > 1 && $0 == "---" { if ($0 ~ /^description:/) { print "description: Technique bodies. Use when asked."; next } } { print }' \
  "$VALIDATION" > "$WORK/validation.md"
printf 'description: see smith-verification\n' >> "$WORK/validation.md"
grep -qx 'description: Technique bodies. Use when asked.' "$WORK/validation.md" ||
  fail "control: the planted description was not written into the copy"
points_to_seam "$WORK/validation.md" &&
  fail "control: a description without the pointer passed because a body line names smith-verification"

[ "$status" = 0 ] && echo "PASS: verification-seam"
exit "$status"
