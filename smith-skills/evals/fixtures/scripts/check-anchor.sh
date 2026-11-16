#!/bin/sh
guidance="smith-guidance/SKILL.md"
citing="smith-review/SKILL.md"
lock="smith-ctx-claude/anchors.lock"
for f in "$guidance" "$citing"; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; exit 1; }
done
labels=$(grep -oE '@smith-guidance/SKILL\.md#[a-z0-9-]+' "$citing" | sed 's/.*#//' | sort -u)
[ -n "$labels" ] || { echo "FAIL: $citing cites no section of $guidance by fragment"; exit 1; }
status=0
found=0
for label in $labels; do
  case "$label" in
    *-v[0-9]*) ;;
    *) echo "FAIL: citation #$label has no -vN version suffix"; status=1; continue ;;
  esac
  if awk -v want="<a name=\"$label\"></a>" '
      prev == want && /^#+ / { hit = 1 }
      { prev = $0 }
      END { exit hit ? 0 : 1 }' "$guidance"; then
    echo "PASS: #$label is an empty anchor on the line above a heading in $guidance"
  else
    echo "FAIL: no line <a name=\"$label\"></a> directly above a heading in $guidance"
    status=1
    continue
  fi
  if [ -f "$lock" ] && awk -F '\t' -v label="$label" -v file="$guidance" '
      NR > 1 && NF == 4 && $1 == label && $2 == file && $3 == "-" && length($4) == 40 && $4 ~ /^[0-9a-f]+$/ { hit = 1 }
      END { exit hit ? 0 : 1 }' "$lock"; then
    echo "PASS: $lock has a row for $guidance#$label"
    found=1
  else
    echo "FAIL: $lock has no row label, file, question, blob for $guidance#$label"
    status=1
  fi
done
[ "$found" -eq 1 ] || status=1
exit $status
