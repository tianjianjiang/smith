#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../erase-guard.mjs"
CASES="$HERE/fixtures/erase-guard/commands.tsv"
DEEP_CASES="$HERE/fixtures/erase-guard/deeply-wrapped.tsv"
WORK="$(mktemp -d)" || { echo "FAIL: setup: mktemp"; exit 2; }
TAB="$(printf '\t')"
. "$HERE/lib/json-string.sh"

failures=0
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

decide_on() {
  printf '%s' "$1" > "$WORK/input" || { echo "FAIL: setup: could not record the hook input"; exit 2; }
  out=$(node "$HOOK" < "$WORK/input" 2> "$WORK/stderr") || fail "$2: the hook exited non-zero"
  if [ "$3" = notes-unreadable-input ]; then
    grep -q '^hook input unreadable' "$WORK/stderr" || fail "$2: the hook must note that it could not read the input, got: $(cat "$WORK/stderr")"
    grep -v '^hook input unreadable' "$WORK/stderr" | grep -q . && fail "$2: the hook wrote more than the unreadable-input note: $(cat "$WORK/stderr")"
  elif [ -s "$WORK/stderr" ]; then
    fail "$2: the hook wrote to standard error, so it did not check the command: $(cat "$WORK/stderr")"
  fi
}

bash_input() {
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":%s}}' "$(json_string "$1")"
}

wrapped_too_deeply() {
  wrapped="$1"
  for level in 1 2 3 4 5 6 7 8 9 10; do wrapped="sh -c \"$(printf '%s' "$wrapped" | sed 's/\\/\\\\/g; s/"/\\"/g')\""; done
  printf '%s' "$wrapped"
}

with_newlines() { printf '%s' "$1" | awk '{ gsub(/<NL>/, "\n"); printf "%s", $0 }'; }

expect_denial() {
  echo "$2" | grep -q '"permissionDecision":"deny"' || { fail "$1: expected a denial, got: $2"; return; }
  echo "$2" | grep -q '/usr/bin/trash' || fail "$1: the reason must name /usr/bin/trash, got: $2"
  echo "$2" | grep -q 'mktemp -d' || fail "$1: the reason must name a move into a mktemp -d folder, got: $2"
  echo "$2" | grep -q 'use type «name» or which «name»' || fail "$1: the reason must name the lookup workaround, got: $2"
}

denied=0
allowed=0
labelled=0
while IFS="$TAB" read -r expectation name command label; do
  case "$expectation" in
    '' | '#'*) continue ;;
  esac
  decide_on "$(bash_input "$(with_newlines "$command")")" "$name"
  case "$expectation" in
    deny)
      denied=$((denied + 1))
      expect_denial "$name: $command" "$out"
      if [ -n "$label" ]; then
        labelled=$((labelled + 1))
        echo "$out" | grep -qF "erase-guard: $label erases" || fail "$name: the reason must name $label, got: $out"
      fi
      ;;
    allow)
      allowed=$((allowed + 1))
      [ -z "$out" ] || fail "$name: expected silence for $command, got: $out"
      ;;
    *) fail "unknown expectation in $CASES: $expectation" ;;
  esac
done < "$CASES"
[ "$denied" -gt 0 ] && [ "$allowed" -gt 0 ] && [ "$labelled" -gt 0 ] || fail "no deny, no allow or no labelled deny case was read from $CASES"

FIRST_DENIED="$(awk -F "$TAB" '$1 == "deny" { print $3; exit }' "$CASES")"
FIRST_PROGRAM="${FIRST_DENIED%% *}"
decide_on "$(bash_input "$FIRST_DENIED")" reason
echo "$out" | grep -q 'judges the command' || fail "the reason must say the hook judges the command, not whether the content survives elsewhere, got: $out"
echo "$out" | grep -q "erase-guard: $FIRST_PROGRAM erases" || fail "the reason must name what it denied, $FIRST_PROGRAM, got: $out"

deep_denied=0
deep_allowed=0
while IFS="$TAB" read -r expectation name command; do
  case "$expectation" in
    '' | '#'*) continue ;;
    deep-deny)
      deep_denied=$((deep_denied + 1))
      decide_on "$(bash_input "$(wrapped_too_deeply "$command")")" "$name"
      echo "$out" | grep -q '"permissionDecision":"deny"' || fail "$name: a command wrapped too deeply to scan that names an erasing command must be denied, got: $out"
      echo "$out" | grep -q 'too deeply' || fail "$name: the denial of an unscannable command must say why, got: $out"
      ;;
    deep-allow)
      deep_allowed=$((deep_allowed + 1))
      decide_on "$(bash_input "$(wrapped_too_deeply "$command")")" "$name"
      [ -z "$out" ] || fail "$name: a command wrapped too deeply to scan that names no eraser must stay allowed, got: $out"
      ;;
    *) fail "unknown expectation in $DEEP_CASES: $expectation" ;;
  esac
done < "$DEEP_CASES"
[ "$deep_denied" -gt 0 ] && [ "$deep_allowed" -gt 0 ] || fail "no deep-deny or no deep-allow case was read from $DEEP_CASES"

for input in \
  "{\"tool_name\":\"Edit\",\"tool_input\":{\"command\":$(json_string "$FIRST_DENIED")}}" \
  '{"tool_name":"Bash","tool_input":{}}' \
  '{"tool_name":"Bash","tool_input":{"command":42}}' \
  '{"tool_name":"Bash"}' \
  'null'; do
  decide_on "$input" "input $input"
  [ -z "$out" ] || fail "expected silence on: $input, got: $out"
done
decide_on 'not json' "input that is not JSON" notes-unreadable-input
[ -z "$out" ] || fail "expected silence on input that is not JSON, got: $out"

if [ "$failures" -gt 0 ]; then
  echo "erase-guard: $failures failure(s)"
  exit 1
fi
echo "erase-guard: PASS ($denied denied, $allowed allowed, $deep_denied denied and $deep_allowed allowed when wrapped too deeply)"
