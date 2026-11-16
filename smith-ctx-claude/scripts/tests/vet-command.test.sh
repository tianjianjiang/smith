#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
VET="$ROOT/smith-vet/SKILL.md"
status=0

fail() { echo "FAIL: vet-command: $1"; status=1; }

part() {
  awk -v want="$1" 'NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---" { inside = 0; body = 1; next }
    want == "frontmatter" && inside { print }
    want == "body" && body { print }' "$2" 2>/dev/null
}

[ -f "$VET" ] || fail "smith-vet/SKILL.md missing"

part frontmatter "$VET" | grep -qxF 'disable-model-invocation: true' ||
  fail "smith-vet/SKILL.md frontmatter lacks disable-model-invocation: true"

request_first='i usually ask for exploration and verification and validation and planning instruction below:'
request_second='> use independent subagents effectively and efficiently with specific smith skills each. at least /smith-analysis /smith-clarity /smith-dialectic /smith-research /smith-validation must be individual subagents, respectively.'
verbatim() {
  awk -v first="$request_first" -v second="$request_second" '
    previous == first && $0 == second { found = 1 }
    { previous = $0 }
    END { exit found ? 0 : 1 }' "$1" 2>/dev/null
}
verbatim "$VET" ||
  fail "smith-vet/SKILL.md does not quote the user's instruction byte for byte"
planted=$(mktemp)
printf '%s\n%s\n' "$request_first" \
  "$(printf '%s' "$request_second" | sed 's/respectively\./respectively/')" > "$planted"
! verbatim "$planted" ||
  fail "control: the verbatim check accepted an instruction with its last character removed"
rm -f "$planted"

is_tracked_skill() { [ -n "$(git -C "$ROOT" ls-files -- "$1/SKILL.md")" ]; }
is_tracked_skill smith-subagents ||
  fail "control: the tracked check rejected smith-subagents"
! is_tracked_skill smith-no-such-lens ||
  fail "control: the tracked check accepted a skill that does not exist"
for skill in $(part body "$VET" | grep -o 'smith-[a-z0-9-]*[a-z0-9]' | sort -u); do
  is_tracked_skill "$skill" ||
    fail "smith-vet/SKILL.md names $skill, which is not a tracked skill directory"
done

pointer_bullets() {
  awk '/^## /{ if (bullet != "") print bullet; bullet = ""; inside = ($0 == "## Pointers"); next }
    inside && /^- / { if (bullet != "") print bullet; bullet = $0; next }
    inside && /^  / && bullet != "" { bullet = bullet " " $0; next }
    inside { if (bullet != "") print bullet; bullet = "" }
    END { if (bullet != "") print bullet }' "$1" 2>/dev/null
}
names_tracked_skill() {
  for skill in $(printf '%s\n' "$1" | grep -o '@smith-[a-z0-9-]*[a-z0-9]/SKILL\.md' |
    sed 's|^@||; s|/SKILL\.md$||'); do
    is_tracked_skill "$skill" && return 0
  done
  return 1
}
unnamed_pointers() {
  pointer_bullets "$1" | while IFS= read -r bullet; do
    names_tracked_skill "$bullet" || echo "$bullet"
  done
}
planted=$(mktemp)
printf '%s\n' '## Pointers' '' '- `@smith-subagents/SKILL.md` - spawning' \
  '- A rule stated inline, which points to no' '  skill' '' '## Next' > "$planted"
[ "$(unnamed_pointers "$planted")" = '- A rule stated inline, which points to no   skill' ] ||
  fail "control: the Pointers check did not single out a bullet that names no skill"
rm -f "$planted"
[ -n "$(pointer_bullets "$VET")" ] || fail "smith-vet/SKILL.md has no Pointers bullets"
unnamed=$(unnamed_pointers "$VET")
[ -z "$unnamed" ] ||
  fail "smith-vet/SKILL.md Pointers holds a bullet that names no tracked skill: $unnamed"

instruction_skills() { printf '%s\n' "$request_second" | grep -o '/smith-[a-z0-9-]*[a-z0-9]' | sed 's|^/||' | sort -u; }
unpointed_skills() {
  bullets=$(pointer_bullets "$1")
  for skill in $(instruction_skills); do
    printf '%s\n' "$bullets" | grep -qF "@$skill/SKILL.md" || echo "$skill"
  done
}
ANCHORED_POINTERS="smith-dialectic smith-validation"
bare_pointers() {
  pointer_bullets "$1" | while IFS= read -r bullet; do
    for skill in $ANCHORED_POINTERS; do
      case "$bullet" in
        *"@$skill/SKILL.md"*)
          printf '%s\n' "$bullet" | grep -qE "@$skill/SKILL\\.md#[a-z0-9-]+-v[0-9]+" ||
            echo "$bullet (cites $skill without an anchor)" ;;
      esac
    done
  done
}
[ -n "$(instruction_skills)" ] ||
  fail "control: no skill named with a slash was found in the quoted instruction"
missing=$(unpointed_skills "$VET")
[ -z "$missing" ] ||
  fail "smith-vet/SKILL.md Pointers lacks a bullet citing a skill the instruction names: $(echo $missing)"
bare=$(bare_pointers "$VET")
[ -z "$bare" ] ||
  fail "smith-vet/SKILL.md Pointers cites an anchored skill without an anchor: $bare"
planted=$(mktemp)
if [ -f "$VET" ]; then
  awk '/^- `@smith-validation\/SKILL\.md/ { skip = 1; next } skip && /^  / { next } { skip = 0; print }' "$VET" > "$planted"
  unpointed_skills "$planted" | grep -qx 'smith-validation' ||
    fail "control: a Pointers section without the smith-validation bullet was not reported"
  sed 's|@smith-validation/SKILL\.md#[a-z0-9-]*-v[0-9]*|@smith-validation/SKILL.md|' "$VET" > "$planted"
  bare_pointers "$planted" | grep -qF 'cites smith-validation without an anchor' ||
    fail "control: a smith-validation pointer turned into a bare skill citation was not reported"
else
  fail "control: the Pointers coverage and anchor controls need smith-vet/SKILL.md"
fi
rm -f "$planted"

[ "$status" = 0 ] && echo "PASS: vet-command"
exit "$status"
