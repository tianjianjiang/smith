#!/bin/sh
set -eu

usage() {
  echo "usage: anchors-lock.sh [--print | --accept-new] [root]" >&2
  echo "Re-attests smith-ctx-claude/anchors.lock: one row per section anchor of every SKILL.md under root," >&2
  echo "and one frontmatter:description row per skill that declares metadata.smith-question." >&2
  echo "An existing label keeps its question; a new label is written only with --accept-new, which prints it." >&2
  exit 2
}

mode=write
case "${1:-}" in
  --print) mode=print; shift ;;
  --accept-new) mode=accept; shift ;;
  -h|--help) usage ;;
esac
[ "$#" -le 1 ] || usage
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${1:-$HERE/../..}" && pwd)"
LOCK="$ROOT/smith-ctx-claude/anchors.lock"
GRAMMAR="$HERE/anchors-grammar.awk"
DESC="frontmatter:description"
TAB="$(printf '\t')"

grammar() {
  awk -v want="$1" -v file="$3" -v tab="$TAB" -f "$GRAMMAR" "$2"
}

section() {
  awk -v anchor="<a name=\"$2\"></a>" '
    function level(s) { match(s, /^#+/); return RLENGTH }
    function is_fence(s) { return s ~ /^[[:space:]]*(```|~~~)/ }
    !on {
      if (!fence && $0 == anchor) { on = 1; print; getline; depth = level($0); print }
      else if (is_fence($0)) fence = !fence
      next
    }
    {
      if (!fence && !is_fence($0) && $0 ~ /^#+ / && level($0) <= depth) exit
      if (held != "") { print held; held = "" }
      if (is_fence($0)) { fence = !fence; print; next }
      if (!fence && $0 ~ /^<a name="[^"]*"><\/a>$/) { held = $0; next }
      print
    }' "$1"
}

fresh_rows() {
  bad=0
  for f in "$ROOT"/*/SKILL.md; do
    [ -f "$f" ] || continue
    rel=${f#"$ROOT"/}
    question=$(grammar question "$f" "$rel")
    if [ -n "$question" ]; then
      blob=$(grammar description "$f" "$rel" | git hash-object --stdin)
      printf '%s\t%s\t%s\t%s\n' "$DESC" "$rel" "$question" "$blob"
    else
      question=-
    fi
    scan=$(grammar anchors "$f" "$rel")
    problems=$(printf '%s\n' "$scan" | awk -F "$TAB" '$1 == "PROBLEM" { print $2 }')
    if [ -n "$problems" ]; then
      printf '%s\n' "$problems" >&2
      bad=1
    fi
    for label in $(printf '%s\n' "$scan" | awk -F "$TAB" '$1 == "ANCHOR" { print $3 }'); do
      blob=$(section "$f" "$label" | git hash-object --stdin)
      printf '%s\t%s\t%s\t%s\n' "$label" "$rel" "$question" "$blob"
    done
  done
  return "$bad"
}

keep_questions() {
  awk -F "$TAB" -v OFS="$TAB" -v newlist="$2" '
    FILENAME == ARGV[1] {
      if (FNR == 1) next
      old[$1 SUBSEP $2] = $3
      files[$1] = files[$1] SUBSEP $2
      next
    }
    { fresh[$1 SUBSEP $2] = 1; row[++n] = $0 }
    END {
      print "label", "file", "question", "blob"
      for (i = 1; i <= n; i++) {
        split(row[i], f, FS)
        q = ""
        if ((f[1] SUBSEP f[2]) in old) q = old[f[1] SUBSEP f[2]]
        else if (f[1] in files) {
          k = split(files[f[1]], was, SUBSEP)
          for (j = 2; j <= k; j++) if (!((f[1] SUBSEP was[j]) in fresh)) { q = old[f[1] SUBSEP was[j]]; break }
        }
        if (q == "") { q = f[3]; print f[1], f[2], f[3], f[4] > newlist }
        print f[1], f[2], q, f[4]
      }
    }' "$1" -
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
[ -f "$LOCK" ] && cp "$LOCK" "$WORK/old" || : > "$WORK/old"
: > "$WORK/new"
fresh_rows > "$WORK/fresh"
keep_questions "$WORK/old" "$WORK/new" < "$WORK/fresh" > "$WORK/rows"

case "$mode" in
  print)
    cat "$WORK/rows"
    ;;
  write)
    if [ -s "$WORK/new" ]; then
      sed 's/^/new row needs --accept-new: /' "$WORK/new" >&2
      exit 1
    fi
    cp "$WORK/rows" "$LOCK"
    ;;
  accept)
    sed 's/^/new row: /' "$WORK/new"
    cp "$WORK/rows" "$LOCK"
    ;;
esac
