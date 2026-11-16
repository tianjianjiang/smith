#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
LOCK="smith-ctx-claude/anchors.lock"
LOCK_TOOL="smith-ctx-claude/scripts/anchors-lock.sh"
GRAMMAR="smith-ctx-claude/scripts/anchors-grammar.awk"
DESC="frontmatter:description"
QUESTIONS="verification validation analysis"
TAB="$(printf '\t')"
KNOWN_LIMITS="The heading-text ratchet fails \`@«skill»/SKILL.md\` followed directly, after an optional
backtick, spaces, quote or ' - ', by the leading words of a heading of a section anchored in that
same skill, or by an unversioned slug of such a heading. Known limits: heading text written
before the token is not checked, and heading text under a skill that never held the section is
not checked."
case "${1:-}" in
  -h|--help) printf '%s\n' "$KNOWN_LIMITS"; exit 0 ;;
esac
status=0

fail() { echo "FAIL: anchors: $1"; status=1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

copy_tracked() {
  mkdir -p "$1"
  (cd "$REPO" && git ls-files -z | tar --null -T - -cf -) | tar -xf - -C "$1"
}

skill_files() {
  for f in "$1"/*/SKILL.md; do
    [ -f "$f" ] && printf '%s\n' "${f#"$1"/}"
  done
}

grammar() {
  awk -v want="$2" -v file="$3" -v tab="$TAB" -f "$1/$GRAMMAR" "$1/$3"
}

scan_anchors() {
  skill_files "$1" | while read -r rel; do
    grammar "$1" anchors "$rel"
  done
}

citation_tokens() {
  grep -rIno --exclude-dir=.git -E '@[a-z0-9-]+/SKILL\.md#[a-z0-9-]+-v[0-9]+[a-z0-9-]*' "$1" \
    | awk -v root="$1/" -v tab="$TAB" '{
        $0 = substr($0, length(root) + 1)
        at = index($0, ":@")
        where = substr($0, 1, at - 1)
        cite = substr($0, at + 2)
        hash = index(cite, "/SKILL.md#")
        print where tab substr(cite, 1, hash - 1) tab substr(cite, hash + length("/SKILL.md#"))
      }'
}

list_citations() {
  citation_tokens "$1" | awk -F "$TAB" -v mode="$2" '
    (mode == "malformed") != ($3 ~ /^[a-z0-9]+(-[a-z0-9]+)*-v[0-9]+$/)'
}

ratchet() {
  awk -F "$TAB" '$1 == "ANCHOR" { print $2 FS $3 FS $5 }' "$2" > "$WORK/ratchet.anchors"
  [ -s "$WORK/ratchet.anchors" ] || return 0
  grep -rIl --exclude-dir=.git -E '@[a-z0-9-]+/SKILL\.md' "$1" > "$WORK/ratchet.files"
  [ -s "$WORK/ratchet.files" ] || return 0
  tr '\n' '\0' < "$WORK/ratchet.files" | xargs -0 awk -v root="$1/" -v list="$WORK/ratchet.anchors" '
    function words(s) {
      s = tolower(s)
      gsub(/[^a-z0-9]+/, " ", s)
      sub(/^ +/, "", s)
      sub(/ +$/, "", s)
      return s
    }
    function lead(h,   w, k) {
      k = split(words(h), w, " ")
      return k > 1 ? w[1] " " w[2] : w[1]
    }
    function opens_with(text, i) {
      return index(words(text) " ", prefix[i] " ") == 1
    }
    function starts_item(s) {
      return s ~ /^[[:space:]]*([-*+]|[0-9]+\.)[[:space:]]/ || s ~ /^#/ || s ~ /^[[:space:]]*$/
    }
    function following(rest, after_line,   slug) {
      if (rest ~ /^#/) {
        if (!match(rest, /^#[a-z0-9-]+/)) return ""
        slug = substr(rest, 2, RLENGTH - 1)
        return slug ~ /-v[0-9]+/ ? "" : slug
      }
      sub(/^`/, "", rest)
      if (!sub(/^[[:space:]]+-[[:space:]]+/, "", rest)) sub(/^[[:space:]]+/, "", rest)
      sub(/^["\047]/, "", rest)
      if (rest != "" && rest !~ /^[A-Za-z0-9]/) return ""
      return rest " " after_line
    }
    function judge(line, after_line, where,   rest, tok, text, i) {
      if (starts_item(after_line)) after_line = ""
      sub(/^[[:space:]]+/, "", after_line)
      rest = line
      while (match(rest, /@[a-z0-9-]+\/SKILL\.md/)) {
        tok = substr(rest, RSTART + 1, RLENGTH - length("/SKILL.md") - 1)
        rest = substr(rest, RSTART + RLENGTH)
        if (!(tok in owns)) continue
        text = following(rest, after_line)
        if (text == "") continue
        for (i = 0; i < n; i++)
          if (owner[i] == tok && opens_with(text, i))
            print "heading-text citation of " file[i] "#" label[i] " at " where "; cite the anchor instead"
      }
    }
    BEGIN {
      n = 0
      while ((getline row < list) > 0) {
        split(row, f, "\t")
        file[n] = f[1]
        label[n] = f[2]
        s = f[1]
        sub(/\/SKILL\.md$/, "", s)
        owner[n] = s
        owns[s] = 1
        prefix[n] = lead(f[3])
        n++
      }
    }
    FNR == 1 && held_where != "" { judge(held, "", held_where); held_where = "" }
    {
      if (held_where != "") judge(held, $0, held_where)
      held = $0
      held_where = substr(FILENAME, length(root) + 1) ":" FNR
    }
    END { if (held_where != "") judge(held, "", held_where) }
  '
}

problems() {
  root=$1
  scan="$WORK/scan"
  lockf="$root/$LOCK"
  [ -f "$lockf" ] || echo "missing lock: $LOCK"
  if [ ! -f "$root/$GRAMMAR" ]; then
    echo "missing anchor grammar: $GRAMMAR"
    return
  fi
  scan_anchors "$root" > "$scan"
  awk -F "$TAB" '$1 == "PROBLEM" { print $2 }' "$scan"
  awk -F "$TAB" '$1 == "ANCHOR" { print $2 "#" $3 }' "$scan" | sort | uniq -d \
    | sed 's/^/duplicate anchor: /'

  skill_files "$root" | while read -r rel; do
    q=$(grammar "$root" question "$rel")
    [ -n "$q" ] && printf '%s\t%s\n' "$rel" "$q"
  done > "$WORK/declared"
  while IFS="$TAB" read -r rel q; do
    case " $QUESTIONS " in
      *" $q "*) ;;
      *) echo "unknown question: $rel declares $q" ;;
    esac
  done < "$WORK/declared"
  cut -f2 "$WORK/declared" | sort | uniq -d | sed 's/^/question claimed by more than one skill: /'
  awk -F "$TAB" 'FILENAME == ARGV[1] { asks[$1] = 1; next }
                 $1 == "SECTION" && $4 == "bare" && ($2 in asks) { print "section without an anchor: " $2 ":" $3 }' \
    "$WORK/declared" "$scan"

  list_citations "$root" exact > "$WORK/citations"
  list_citations "$root" malformed \
    | awk -F "$TAB" '{ print "malformed citation: " $1 " cites @" $2 "/SKILL.md#" $3 "; a label ends at -v«N»" }'
  awk -F "$TAB" 'FILENAME == ARGV[1] { if ($1 == "ANCHOR") have[$2 "#" $3]++; next }
                 !(($2 "/SKILL.md#" $3) in have) { print "unresolved citation: " $1 " cites @" $2 "/SKILL.md#" $3 }' \
    "$scan" "$WORK/citations"
  ratchet "$root" "$scan"

  [ -f "$lockf" ] || return
  [ "$(head -n 1 "$lockf")" = "label${TAB}file${TAB}question${TAB}blob" ] \
    || echo "lock header is not label, file, question, blob: $LOCK"
  awk 'NR > 1' "$lockf" | sort | uniq -d | sed 's/^/duplicate lock row: /'
  awk -F "$TAB" '$1 == "ANCHOR" { print $2 "#" $3 }' "$scan" | sort -u > "$WORK/anchor.keys"
  awk -F "$TAB" -v desc="$DESC" 'NR > 1 && $1 != desc { print $2 "#" $1 }' "$lockf" | sort -u > "$WORK/lock.keys"
  comm -23 "$WORK/anchor.keys" "$WORK/lock.keys" | sed 's/^/anchor without a lock row: /'
  comm -13 "$WORK/anchor.keys" "$WORK/lock.keys" | sed 's/^/lock row without an anchor: /'
  cut -f1 "$WORK/declared" | sort -u > "$WORK/declared.keys"
  awk -F "$TAB" -v desc="$DESC" 'NR > 1 && $1 == desc { print $2 }' "$lockf" | sort -u > "$WORK/desc.keys"
  comm -23 "$WORK/declared.keys" "$WORK/desc.keys" | sed 's/^/skill without a description row: /'
  comm -13 "$WORK/declared.keys" "$WORK/desc.keys" | sed 's/^/description row for a skill that declares no question: /'
  awk -F "$TAB" 'FILENAME == ARGV[1] { q[$1] = $2; next }
                 FNR > 1 { want = ($2 in q) ? q[$2] : "-"
                           if ($3 != want) print "question differs: " $2 "#" $1 " is locked as " $3 ", the skill that holds it declares " want }' \
    "$WORK/declared" "$lockf"

  if [ ! -f "$root/$LOCK_TOOL" ]; then
    echo "missing lock tool: $LOCK_TOOL"
    return
  fi
  sh "$root/$LOCK_TOOL" --print "$root" > "$WORK/fresh" 2> "$WORK/fresh.err" \
    || { echo "lock tool failed: $(cat "$WORK/fresh.err")"; return; }
  awk -F "$TAB" -v tool="$LOCK_TOOL" -v desc="$DESC" '
    FILENAME == ARGV[1] { cites[$2 "/SKILL.md#" $3] = cites[$2 "/SKILL.md#" $3] " " $1; next }
    FILENAME == ARGV[2] { if (FNR > 1) fresh[$2 "#" $1] = $4; next }
    FNR > 1 && (($2 "#" $1) in fresh) && fresh[$2 "#" $1] != $4 {
      key = $2 "#" $1
      if ($1 == desc) print "description changed: " $2 " (re-attest with " tool ")"
      else print "section changed: " key " (re-attest with " tool "); cited at:" (key in cites ? cites[key] : " nowhere")
    }' "$WORK/citations" "$WORK/fresh" "$lockf"
  awk 'FILENAME == ARGV[1] { produced[$0] = 1; next }
       FNR > 1 && !($0 in produced) { print "lock row not produced by the lock tool: " $0 }' \
    "$WORK/fresh" "$lockf"
}

report() {
  printf '%s\n' "$1" | while IFS= read -r line; do
    [ -n "$line" ] && echo "FAIL: anchors: $line"
  done
}

expect() {
  got=$(problems "$1")
  printf '%s\n' "$got" | grep -qF -- "$2" || fail "control: $3 was not reported (wanted '$2')"
}

copy_tree() {
  rm -rf "$2"
  cp -R "$1" "$2"
}

replace_line() {
  OLD_LINE="$2" NEW_LINE="$3" awk '$0 == ENVIRON["OLD_LINE"] { if (ENVIRON["NEW_LINE"] != "") print ENVIRON["NEW_LINE"]; next } { print }' "$1" > "$1.tmp" \
    && mv "$1.tmp" "$1"
}

copy_tracked "$WORK/real"
real=$(problems "$WORK/real")
if [ -n "$real" ]; then
  report "$real"
  status=1
fi

set -- $QUESTIONS
Q_FIRST=$1
Q_OTHER=$2
FX=smith-anchor-fixture
CITER=smith-anchor-citer
OTHER=smith-anchor-other
A_FIRST='<a name="first-topic-v1"></a>'
A_SECOND='<a name="second-topic-v1"></a>'
FX_DESC='description: Anchor fixture. Use when testing anchors.'

build_fixture() {
  d=$1
  mkdir -p "$d/smith-ctx-claude/scripts" "$d/$FX" "$d/$CITER" "$d/$OTHER"
  [ -f "$REPO/$LOCK_TOOL" ] && cp "$REPO/$LOCK_TOOL" "$d/$LOCK_TOOL"
  [ -f "$REPO/$GRAMMAR" ] && cp "$REPO/$GRAMMAR" "$d/$GRAMMAR"
  cat > "$d/$FX/SKILL.md" <<EOF
---
name: $FX
$FX_DESC
metadata:
  smith-question: $Q_FIRST
---

# Anchor Fixture

$A_FIRST
## First Topic

Body of the first topic.

$A_SECOND
## Second Topic

Body of the second topic.
EOF
  cat > "$d/$OTHER/SKILL.md" <<EOF
---
name: $OTHER
description: Other question fixture. Use when testing anchors.
metadata:
  smith-question: $Q_OTHER
---

# Other Question Fixture
EOF
  cat > "$d/$CITER/SKILL.md" <<EOF
---
name: $CITER
description: Citing fixture. Use when testing anchors.
---

# Citing Fixture

- See \`@$FX/SKILL.md#first-topic-v1\` for the first topic.
EOF
}

move_second_topic() {
  awk -v a="$A_SECOND" '$0 == a { exit } { print }' "$1/$FX/SKILL.md" > "$1/x"
  awk -v a="$A_SECOND" '$0 == a { on = 1 } on { print }' "$1/$FX/SKILL.md" > "$1/moved"
  mv "$1/x" "$1/$FX/SKILL.md"
  { printf '\n'; cat "$1/moved"; } >> "$1/$OTHER/SKILL.md"
  rm "$1/moved"
}

F0="$WORK/fixture"
build_fixture "$F0"
if [ ! -f "$F0/$LOCK_TOOL" ]; then
  fail "control: $LOCK_TOOL is missing, so no planted control can run"
elif ! sh "$F0/$LOCK_TOOL" --accept-new "$F0" > /dev/null 2> "$WORK/lock.err"; then
  fail "control: $LOCK_TOOL --accept-new failed on the fixture: $(cat "$WORK/lock.err")"
else
  base=$(problems "$F0")
  if [ -n "$base" ]; then
    fail "control: the fixture baseline is not clean"
    report "$base"
  fi

  C="$WORK/control"

  copy_tree "$F0" "$C"
  replace_line "$C/$FX/SKILL.md" "$A_FIRST" ""
  expect "$C" "unresolved citation: $CITER/SKILL.md:" "a deleted anchor (citation)"
  expect "$C" "lock row without an anchor: $FX/SKILL.md#first-topic-v1" "a deleted anchor (lock row)"

  copy_tree "$F0" "$C"
  replace_line "$C/$FX/SKILL.md" "Body of the first topic." "Body of the first topia."
  expect "$C" "section changed: $FX/SKILL.md#first-topic-v1" "a one-character section change"
  expect "$C" "$CITER/SKILL.md:" "the citing location of a changed section"

  copy_tree "$F0" "$C"
  printf 'orphan-v1\t%s/SKILL.md\t%s\t%s\n' "$FX" "$Q_FIRST" "$(printf 'orphan\n' | git hash-object --stdin)" >> "$C/$LOCK"
  expect "$C" "lock row without an anchor: $FX/SKILL.md#orphan-v1" "an orphan lock row"

  copy_tree "$F0" "$C"
  tail -n 1 "$C/$LOCK" >> "$C/$LOCK"
  expect "$C" "duplicate lock row: " "a duplicated lock row"

  copy_tree "$F0" "$C"
  last=$(tail -n 1 "$C/$LOCK")
  replace_line "$C/$LOCK" "$last" "$last${TAB}planted"
  expect "$C" "lock row not produced by the lock tool: $last${TAB}planted" "a lock row the lock tool does not produce"

  copy_tree "$F0" "$C"
  printf '\n<a name="third-topic-v1"></a>\n## Third Topic\n\nBody of the third topic.\n' >> "$C/$FX/SKILL.md"
  expect "$C" "anchor without a lock row: $FX/SKILL.md#third-topic-v1" "an anchor without a lock row"
  cp "$C/$LOCK" "$WORK/lock.before"
  if sh "$C/$LOCK_TOOL" "$C" > /dev/null 2>&1; then
    fail "control: $LOCK_TOOL attested a new label without --accept-new"
  fi
  cmp -s "$WORK/lock.before" "$C/$LOCK" || fail "control: $LOCK_TOOL changed the lock while refusing a new label"
  sh "$C/$LOCK_TOOL" --accept-new "$C" > "$WORK/accepted" 2>&1
  grep -qF "third-topic-v1${TAB}$FX/SKILL.md${TAB}$Q_FIRST" "$WORK/accepted" \
    || fail "control: $LOCK_TOOL --accept-new did not print the new row"

  copy_tree "$F0" "$C"
  move_second_topic "$C"
  if sh "$C/$LOCK_TOOL" "$C" > /dev/null 2> "$WORK/move.err"; then
    expect "$C" "question differs: $OTHER/SKILL.md#second-topic-v1 is locked as $Q_FIRST" "a section moved to a skill with another question and re-attested"
  else
    fail "control: $LOCK_TOOL refused to re-attest a moved label: $(cat "$WORK/move.err")"
  fi

  copy_tree "$F0" "$C"
  replace_line "$C/$FX/SKILL.md" "  smith-question: $Q_FIRST" "  smith-question: $Q_OTHER"
  replace_line "$C/$OTHER/SKILL.md" "  smith-question: $Q_OTHER" "  smith-question: $Q_FIRST"
  expect "$C" "question differs: $FX/SKILL.md#first-topic-v1" "a question changed without re-attestation"
  sh "$C/$LOCK_TOOL" "$C" > /dev/null 2>&1
  expect "$C" "question differs: $FX/SKILL.md#first-topic-v1" "a question changed and re-attested"

  copy_tree "$F0" "$C"
  replace_line "$C/$FX/SKILL.md" "$FX_DESC" "description: A different description. Use when debugging."
  expect "$C" "description changed: $FX/SKILL.md" "a changed description"

  copy_tree "$F0" "$C"
  grep -vF "$DESC${TAB}$FX/SKILL.md${TAB}" "$C/$LOCK" > "$C/x" && mv "$C/x" "$C/$LOCK"
  expect "$C" "skill without a description row: $FX/SKILL.md" "a missing description row"

  copy_tree "$F0" "$C"
  printf '%s\t%s/SKILL.md\t-\t%s\n' "$DESC" "$CITER" "$(printf 'x\n' | git hash-object --stdin)" >> "$C/$LOCK"
  expect "$C" "description row for a skill that declares no question: $CITER/SKILL.md" "a description row for a skill without a question"

  copy_tree "$F0" "$C"
  replace_line "$C/$CITER/SKILL.md" "description: Citing fixture. Use when testing anchors." \
    "$(printf 'description: Citing fixture. Use when testing anchors.\nmetadata:\n  smith-question: %s' "$Q_FIRST")"
  expect "$C" "question claimed by more than one skill: $Q_FIRST" "a question claimed twice"

  copy_tree "$F0" "$C"
  replace_line "$C/$FX/SKILL.md" "  smith-question: $Q_FIRST" "  smith-question: planted"
  expect "$C" "unknown question: $FX/SKILL.md declares planted" "an unknown question"

  copy_tree "$F0" "$C"
  printf '\n## Bare Topic\n\nBody without an anchor.\n' >> "$C/$FX/SKILL.md"
  expect "$C" "section without an anchor: $FX/SKILL.md:" "an unanchored section"

  copy_tree "$F0" "$C"
  printf -- '- See `@%s/SKILL.md` First Topic for more.\n' "$FX" >> "$C/$CITER/SKILL.md"
  expect "$C" "heading-text citation of $FX/SKILL.md#first-topic-v1" "a heading-text citation"

  copy_tree "$F0" "$C"
  printf -- '- `@%s/SKILL.md` - Second\n  Topic for more.\n' "$FX" >> "$C/$CITER/SKILL.md"
  expect "$C" "heading-text citation of $FX/SKILL.md#second-topic-v1" "a heading-text citation split over lines"

  copy_tree "$F0" "$C"
  printf '\n<a name="long-topic-v1"></a>\n## Long Topic of Findings\n\nBody of the long topic.\n' >> "$C/$FX/SKILL.md"
  sh "$C/$LOCK_TOOL" --accept-new "$C" > /dev/null 2>&1
  printf -- '- `@%s/SKILL.md` - "Long Topic" for more.\n' "$FX" >> "$C/$CITER/SKILL.md"
  expect "$C" "heading-text citation of $FX/SKILL.md#long-topic-v1" "an abbreviated heading prefix"

  copy_tree "$F0" "$C"
  printf -- '- See `@%s/SKILL.md#first-topic` for more.\n' "$FX" >> "$C/$CITER/SKILL.md"
  expect "$C" "heading-text citation of $FX/SKILL.md#first-topic-v1" "an unversioned heading-slug citation"

  copy_tree "$F0" "$C"
  printf -- '- See `@%s/SKILL.md#first-topic-v1x` for more.\n' "$FX" >> "$C/$CITER/SKILL.md"
  expect "$C" "malformed citation: $CITER/SKILL.md:" "a citation with a character after its version"
  list_citations "$C" exact | grep -qF "$CITER/SKILL.md:9${TAB}" \
    && fail "control: a malformed citation was read as a citation of its versioned prefix"

  copy_tree "$F0" "$C"
  printf -- '- `@%s/SKILL.md` - First Topic notes of another skill\n' "$CITER" >> "$C/$CITER/SKILL.md"
  printf -- '- If mentions "First Topic" → Load `@%s/SKILL.md`\n' "$FX" >> "$C/$CITER/SKILL.md"
  got=$(problems "$C")
  [ -z "$got" ] || { fail "control: a description of another skill or heading text before the token was reported"; report "$got"; }

  copy_tree "$F0" "$C"
  awk -v a="$A_FIRST" '{ print } $0 == a { print "" }' "$C/$FX/SKILL.md" > "$C/x" && mv "$C/x" "$C/$FX/SKILL.md"
  expect "$C" "anchor not directly above a heading: $FX/SKILL.md:" "an anchor not directly above a heading"

  copy_tree "$F0" "$C"
  replace_line "$C/$FX/SKILL.md" "$A_SECOND" "$A_FIRST"
  expect "$C" "duplicate anchor: $FX/SKILL.md#first-topic-v1" "a duplicate anchor label"

  copy_tree "$F0" "$C"
  rm "$C/$LOCK"
  expect "$C" "missing lock: $LOCK" "a missing lock"

  copy_tree "$F0" "$C"
  rm "$C/$GRAMMAR"
  expect "$C" "missing anchor grammar: $GRAMMAR" "a missing anchor grammar"

  copy_tree "$F0" "$C"
  { printf 'label\tfile\tblob\n'; tail -n +2 "$F0/$LOCK"; } > "$C/$LOCK"
  expect "$C" "lock header is not label, file, question, blob: $LOCK" "a wrong lock header"

  copy_tree "$F0" "$C"
  rm "$C/$LOCK_TOOL"
  expect "$C" "missing lock tool: $LOCK_TOOL" "a missing lock tool"

  copy_tree "$F0" "$C"
  printf 'echo planted lock tool failure >&2\nexit 1\n' > "$C/$LOCK_TOOL"
  expect "$C" "lock tool failed: planted lock tool failure" "a failing lock tool"

  copy_tree "$F0" "$C"
  printf '\n<a name="Not A Label"></a>\n## Fourth Topic\n' >> "$C/$FX/SKILL.md"
  expect "$C" "malformed anchor: $FX/SKILL.md:" "a malformed anchor"

  R0="$WORK/real"
  real_row=$(awk -F "$TAB" -v desc="$DESC" 'NR > 1 && $1 != desc { print; exit }' "$R0/$LOCK" 2> /dev/null)
  if [ -n "$real_row" ]; then
    label=$(printf '%s\n' "$real_row" | cut -f1)
    file=$(printf '%s\n' "$real_row" | cut -f2)
    anchor="<a name=\"$label\"></a>"
    R="$WORK/real-control"

    copy_tree "$R0" "$R"
    replace_line "$R/$file" "$anchor" ""
    expect "$R" "lock row without an anchor: $file#$label" "a deleted real anchor"

    copy_tree "$R0" "$R"
    awk -v a="$anchor" 'hit { $0 = $0 "x"; hit = 0 } $0 == a { hit = 1 } { print }' "$R/$file" > "$R/x" && mv "$R/x" "$R/$file"
    expect "$R" "section changed: $file#$label" "a one-character change of a real section"

    copy_tree "$R0" "$R"
    printf 'orphan-v1\t%s\t-\t%s\n' "$file" "$(printf 'orphan\n' | git hash-object --stdin)" >> "$R/$LOCK"
    expect "$R" "lock row without an anchor: $file#orphan-v1" "an orphan row beside the real lock"
  fi
fi

[ "$status" = 0 ] && echo "PASS: anchors"
exit "$status"
