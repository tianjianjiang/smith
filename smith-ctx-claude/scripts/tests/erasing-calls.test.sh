#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR; git -C "$HERE" rev-parse --show-toplevel)" || { echo "FAIL: setup: no checkout around $HERE"; exit 2; }
ALLOWLIST="$HERE/erasing-calls.allowlist"
ERASING='(^|[^A-Za-z0-9_.-])rm([^A-Za-z0-9_-]|$)|\\nrm([^A-Za-z0-9_-]|$)|--rm([^A-Za-z0-9_-]|$)|(^|[^A-Za-z0-9_])(rmdir|unlink)([^A-Za-z0-9_]|$)|-delete([^A-Za-z0-9_-]|$)|rmSync|rmdirSync|unlinkSync|(^|[^A-Za-z0-9_])(rm|unlink|rmdir)[[:space:]]*\(|os\.(remove|unlink|rmdir|removedirs)|rmtree|rimraf|(^|[^A-Za-z0-9_-])clean["'"'"'[:space:],]([^;&|]*["'"'"'[:space:],])?(-[A-Za-z]*[fi]|--force|--interactive)|worktree["'"'"'[:space:],]+remove|branch[^;&|]*["'"'"'[:space:],]-[A-Za-z]*D|branch[^;&|]*["'"'"'[:space:],]-[A-Za-z]*(d[A-Za-z]*f|f[A-Za-z]*d)|branch[^;&|]*["'"'"'[:space:],](-d|--delete)[^;&|]*["'"'"'[:space:],](-f|--force)|branch[^;&|]*["'"'"'[:space:],](-f|--force)[^;&|]*["'"'"'[:space:],](-d|--delete)|(^|[^A-Za-z0-9_-])reset[^;&|]*["'"'"'[:space:],]--hard|stash["'"'"'[:space:],]+(-[^;&|]*["'"'"'[:space:],]+)?(drop|clear)|checkout[^;&|]*["'"'"'[:space:],]--(["'"'"'[:space:],]|$)'

failures=0
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

is_code() {
  case "$1" in
    *.sh | *.bash | *.mjs | *.js | *.cjs | *.py) return 0 ;;
  esac
  [ "$(head -c 2 "$2" 2>/dev/null)" = '#!' ]
}

erasing_lines() (
  checkout=$1
  git -C "$checkout" ls-files -z | tr '\0' '\n' | while IFS= read -r path; do
    [ -f "$checkout/$path" ] || continue
    is_code "$path" "$checkout/$path" || continue
    hits=$(grep -naE -e "$ERASING" "$checkout/$path")
    if [ "$?" -gt 1 ]; then
      printf '%s\t0:grep could not read this file, so it was not scanned\n' "$path"
      continue
    fi
    [ -n "$hits" ] || continue
    printf '%s\n' "$hits" | while IFS= read -r hit; do
      printf '%s\t%s\n' "$path" "$hit"
    done
  done
)

judge() {
  ERASING="$ERASING" awk -F '\t' -v allowlist="$1" '
    BEGIN {
      while ((status = (getline line < allowlist)) > 0) {
        number += 1
        if (line == "" || substr(line, 1, 1) == "#") continue
        fields = split(line, field, "\t")
        if (fields != 4 || field[1] == "" || field[2] == "" || field[4] == "" || (field[3] != "mention" && field[3] != "rebuildable")) {
          print "MALFORMED allowlist line " number ": " line
          continue
        }
        entries += 1
        file[entries] = field[1]; text[entries] = field[2]; uses[entries] = 0
      }
      if (status < 0) print "UNREADABLE allowlist: " allowlist
    }
    {
      path = $1
      rest = substr($0, length(path) + 2)
      remainder = substr(rest, index(rest, ":") + 1)
      covered = 0
      for (entry = 1; entry <= entries; entry += 1) {
        at = index(remainder, text[entry])
        if (file[entry] == path && at > 0) {
          uses[entry] += 1
          covered = 1
          remainder = substr(remainder, 1, at - 1) " " substr(remainder, at + length(text[entry]))
        }
      }
      if (!covered) print "UNALLOWED " path ":" rest
      else if (remainder ~ ENVIRON["ERASING"]) print "UNALLOWED beyond its allowlist entry " path ":" rest
      hits += 1
    }
    END {
      for (entry = 1; entry <= entries; entry += 1) {
        if (uses[entry] == 0) print "STALE allowlist entry: " file[entry] "\t" text[entry]
        if (uses[entry] > 1) print "AMBIGUOUS allowlist entry matches " uses[entry] " lines: " file[entry] "\t" text[entry]
      }
      print "HITS " hits + 0
    }
  ' "$2"
}

SCRATCH="$(mktemp -d)" || { echo "FAIL: setup: mktemp"; exit 2; }
FIXTURES="$HERE/fixtures/erasing-calls"
TAB="$(printf '\t')"

planted_repo() {
  repo="$SCRATCH/$1"
  mkdir -p "$repo" && git -C "$repo" init -q || { echo "FAIL: setup: git init $repo"; exit 2; }
  printf '%b\n' "$2" > "$repo/$3"
  git -C "$repo" add -A || { echo "FAIL: setup: git add in $repo"; exit 2; }
}

planted_cases=0
while IFS="$TAB" read -r expectation name file content; do
  planted_cases=$((planted_cases + 1))
  planted_repo "$name" "$content" "$file"
  erasing_lines "$SCRATCH/$name" > "$SCRATCH/$name.hits"
  case "$expectation" in
    caught)
      judge /dev/null "$SCRATCH/$name.hits" | grep -q '^UNALLOWED ' || fail "a planted erasing call must be caught: $name, $content in $file"
      ;;
    ignored)
      [ -s "$SCRATCH/$name.hits" ] && fail "a planted line must not count as an erasing call: $name, $content in $file"
      ;;
    *)
      fail "unknown expectation in $FIXTURES/planted.tsv: $expectation"
      ;;
  esac
done < "$FIXTURES/planted.tsv"
[ "$planted_cases" -gt 0 ] || fail "no planted case was read from $FIXTURES/planted.tsv"

expect_verdict() {
  planted_repo "$1" "$(cat "$FIXTURES/$2")" a.sh
  erasing_lines "$SCRATCH/$1" > "$SCRATCH/$1.hits"
  judge "$FIXTURES/$1.allowlist" "$SCRATCH/$1.hits" | grep -q "^$3 " || fail "$4"
}

expect_verdict stale no-call STALE "an allowlist entry that matches no erasing line must be reported stale"
expect_verdict ambiguous two-calls AMBIGUOUS "an allowlist entry that matches two lines must be reported ambiguous"
planted_repo unreadable "$(cat "$FIXTURES/no-call")" a.sh
chmod 000 "$SCRATCH/unreadable/a.sh"
erasing_lines "$SCRATCH/unreadable" > "$SCRATCH/unreadable.hits" 2> /dev/null
judge /dev/null "$SCRATCH/unreadable.hits" | grep -q '^UNALLOWED a.sh:0:grep could not read' || fail "a code file grep cannot read must fail the scan, not pass unscanned"

expect_verdict beyond extra-call "UNALLOWED beyond its allowlist entry" "a second erasing call on an allowlisted line must be caught"
expect_verdict other-file two-calls UNALLOWED "an allowlist entry must cover only the file it names"
expect_verdict malformed two-calls MALFORMED "an allowlist entry whose kind is neither mention nor rebuildable must be reported malformed"

erasing_lines "$ROOT" > "$SCRATCH/checkout.hits"
judge "$ALLOWLIST" "$SCRATCH/checkout.hits" > "$SCRATCH/checkout.verdict"
grep -v '^HITS ' "$SCRATCH/checkout.verdict" | while IFS= read -r problem; do
  echo "FAIL: $problem"
done
grep -qv '^HITS ' "$SCRATCH/checkout.verdict" && failures=$((failures + 1))
grep -q '^HITS [1-9]' "$SCRATCH/checkout.verdict" || fail "the scan of this checkout found no erasing line at all, so it did not run: the allowlist itself names some"

if [ "$failures" -gt 0 ]; then
  echo "erasing-calls: $failures failure(s); move the file or send it to /usr/bin/trash, or add an allowlist entry in $ALLOWLIST that says why it is rebuildable"
  exit 1
fi
echo "erasing-calls: PASS ($(sed -n 's/^HITS //p' "$SCRATCH/checkout.verdict") allowlisted lines)"
