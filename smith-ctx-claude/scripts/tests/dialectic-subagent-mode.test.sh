#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$HERE/../../../smith-dialectic/SKILL.md"
NAME=smith-dialectic
LABEL=subagent-mode-v1
ANCHOR="<a name=\"$LABEL\"></a>"
CITATION="@$NAME/SKILL.md#$LABEL"
status=0

fail() { echo "FAIL: dialectic-subagent-mode: $1"; status=1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

anchored_section() {
  awk -v a="$ANCHOR" 'on && /^## / { exit }
       on { print; next }
       held && /^## / { on = 1; print; next }
       { held = ($0 == a) }' "$1"
}

citing_section() {
  awk -v cite="$CITATION" '
    function flush() { if (found) printf "%s", text; found = 0 }
    /^## / { if (found) { flush(); exit } text = ""; stepped = 0 }
    { text = text $0 "\n" }
    /^[0-9]+\. / { stepped = 1 }
    !stepped && index($0, cite) { found = 1 }
    END { flush() }' "$1"
}

problems() {
  f=$1
  mode=$(anchored_section "$f")
  [ -n "$mode" ] || echo "no section heading sits directly below the anchor $LABEL"
  [ -n "$(printf '%s\n' "$mode" | sed 1d | tr -d '[:space:]')" ] || echo "the section anchored as $LABEL is empty"
  protocol=$(citing_section "$f")
  [ -n "$protocol" ] || echo "no section cites $CITATION before its first numbered step"
  steps=$(printf '%s\n' "$protocol" | grep -E '^[0-9]+\. ')
  [ -n "$steps" ] || echo "control: the section that cites the Subagent Mode anchor has no numbered step"
  links=$(grep -oE 'https://github\.com/[^/]+/[^/]+/blob/[^/]+/' "$f")
  [ -n "$links" ] || echo "control: no GitHub blob link"
  printf '%s\n' "$links" | grep -vE '^$|/blob/[0-9a-f]{40}/$' \
    | sed 's/^/a GitHub link is not pinned to a commit: /'
}

expect() {
  printf '%s\n' "$(problems "$1")" | grep -qF -- "$2" || fail "control: $3 was not reported"
}

[ -f "$SKILL" ] || { fail "missing $SKILL"; exit 1; }

real=$(problems "$SKILL")
if [ -n "$real" ]; then
  printf '%s\n' "$real" | while IFS= read -r line; do echo "FAIL: dialectic-subagent-mode: $line"; done
  status=1
fi

C="$WORK/SKILL.md"

awk '{ gsub(/\/blob\/[0-9a-f]+\//, "/blob/main/") } { print }' "$SKILL" > "$C"
expect "$C" "a GitHub link is not pinned to a commit" "a branch link"

awk -v name="$NAME" '{ gsub("@" name "/SKILL\\.md#[a-z0-9-]+", "") } { print }' "$SKILL" > "$C"
expect "$C" "no section cites $CITATION" "a missing anchor citation"

grep -vxF "$ANCHOR" "$SKILL" > "$C"
expect "$C" "no section heading sits directly below the anchor $LABEL" "a missing anchor"

awk -v a="$ANCHOR" 'on && /^## / { on = 0 } on { next } held && /^## / { print; on = 1; held = 0; next }
     { held = ($0 == a) } { print }' "$SKILL" > "$C"
expect "$C" "the section anchored as $LABEL is empty" "an empty anchored section"

awk -v a="$ANCHOR" 'held && /^## / { print "## Renamed Mode Heading"; held = 0; next }
     { held = ($0 == a) } /^## / && !renamed && !held { renamed = 1; print "## Renamed Protocol Heading"; next }
     { print }' "$SKILL" > "$C"
grep -qxF '## Renamed Mode Heading' "$C" || fail "control: the heading below the anchor was not renamed in the copy"
[ "$(problems "$C")" = "$(problems "$SKILL")" ] \
  || fail "control: renaming the headings changed the result, so a section is still found by its heading text"

[ "$status" = 0 ] && echo "PASS: dialectic-subagent-mode"
exit "$status"
