#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
ALLOW="$HERE/verification-seam.allow"
SEAM="$ROOT/smith-verification/SKILL.md"
BODIES="$ROOT/smith-validation/SKILL.md"
status=0

fail() { echo "FAIL: verification-seam: $1"; status=1; }

unlisted_hits() {
  needle="$1"
  shift
  git -C "$ROOT" grep -n -F "$needle" -- "$@" |
  awk -v allow="$ALLOW" -v root="$ROOT" '
    function heading_text(line) { sub(/^#+[ \t]*/, "", line); return line }
    function heading_level(line) { match(line, /^#+/); return RLENGTH }
    function mark_sections(path,    file, line, n, fenced, level, active, active_level) {
      file = root "/" path
      n = 0; fenced = 0; active = 0
      while ((getline line < file) > 0) {
        n++
        if (line ~ /^```/) fenced = !fenced
        if (!fenced && line ~ /^#+ /) {
          level = heading_level(line)
          if (active && level <= active_level) active = 0
          if ((path "#" heading_text(line)) in section) { active = 1; active_level = level }
        }
        if (active) allowed_line[path ":" n] = 1
      }
      close(file)
      marked[path] = 1
    }
    BEGIN {
      while ((getline entry < allow) > 0) {
        if (entry == "") continue
        if (index(entry, "#") > 0) section[entry] = 1
        else whole[entry] = 1
      }
    }
    {
      path = substr($0, 1, index($0, ":") - 1)
      rest = substr($0, index($0, ":") + 1)
      lineno = substr(rest, 1, index(rest, ":") - 1)
      for (entry in whole) {
        if (path == entry) next
        if (substr(entry, length(entry)) == "/" && index(path, entry) == 1) next
      }
      if (!(path in marked)) mark_sections(path)
      if ((path ":" lineno) in allowed_line) next
      print
    }'
}

[ -f "$ALLOW" ] || fail "allowlist missing: $ALLOW"

[ -n "$(unlisted_hits '# ' smith-ctx-claude/references/design.md)" ] ||
  fail "control: the scan printed no heading of design.md"

leftover=$(unlisted_hits 'smith-validation' .)
[ -z "$leftover" ] || fail "lines outside the allowlist still name smith-validation:
$leftover"

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
points_to_seam "$BODIES" ||
  fail "smith-validation description does not point to smith-verification"
awk 'NR == 1, NR > 1 && $0 == "---" { if ($0 ~ /^description:/) { print "description: Technique bodies. Use when asked."; next } } { print }' \
  "$BODIES" > "$WORK/bodies.md"
printf 'description: see smith-verification\n' >> "$WORK/bodies.md"
grep -qx 'description: Technique bodies. Use when asked.' "$WORK/bodies.md" ||
  fail "control: the planted description was not written into the copy"
points_to_seam "$WORK/bodies.md" &&
  fail "control: a description without the pointer passed because a body line names smith-verification"

forwarded=$(awk '/^## /{inside = ($0 == "## Where the Techniques Live"); next}
  inside && /^- /' "$SEAM" 2>/dev/null | grep -o '\*\*[^*]*\*\*' | tr -d '*')
[ -n "$forwarded" ] || fail "smith-verification forwards no section by name"
printf '%s\n' "$forwarded" | while IFS= read -r name; do
  [ -z "$name" ] && continue
  grep -q -e "^## $name\$" -e "^## $name:" "$BODIES" ||
    echo "FAIL: verification-seam: forwarded section has no heading in smith-validation/SKILL.md: $name"
done | grep . && status=1
sed -n 's/^## \([^:]*\).*/\1/p' "$BODIES" | while IFS= read -r name; do
  case "$name" in ("Before You Finish" | Related) continue ;; esac
  printf '%s\n' "$forwarded" | grep -qxF "$name" ||
    echo "FAIL: verification-seam: smith-validation/SKILL.md section not forwarded: $name"
done | grep . && status=1

[ "$status" = 0 ] && echo "PASS: verification-seam"
exit "$status"
