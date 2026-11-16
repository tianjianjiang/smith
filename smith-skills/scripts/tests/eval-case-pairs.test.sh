#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

without_declared_differences() {
  awk '
    /^description:/ { skipping = "description"; next }
    /^  prompt:/ { skipping = "prompt"; next }
    skipping == "description" && /^[^ ]/ { skipping = "" }
    skipping == "prompt" && /^ ? ?[^ ]/ { skipping = "" }
    skipping == "" { print }
  ' "$1"
}
description_of() {
  awk '/^description:/ { inside = 1; next } inside && /^[^ ]/ { inside = 0 } inside { print }' "$1"
}
check_pair() {
  change="$1"
  baseline="$2"
  without_declared_differences "$change" > "$TMPD/change"
  without_declared_differences "$baseline" > "$TMPD/baseline"
  cmp -s "$TMPD/change" "$TMPD/baseline" || return 1
  for file in "$change" "$baseline"; do
    description_of "$file" > "$TMPD/description"
    grep -q -E '^ +Claim: (equivalence|goal|regression)[.,]' "$TMPD/description" || return 2
    grep -q -E '^ +Experiment variable: ' "$TMPD/description" || return 3
    grep -q -E '^ +Control variables: ' "$TMPD/description" || return 4
  done
  return 0
}

mkdir "$TMPD/control"
write_case() {
  printf '%s\n' "title: A control case" 'description: >' "  Claim: goal. $2" '  Experiment variable: the prompt.' '  Control variables: the rest.' \
    'input:' '  prompt: |' "    $3" 'judge:' '  type: script' "  script_path: $4" > "$TMPD/control/$1"
}
write_case same.yaml 'First wording.' 'first prompt' judge.sh
write_case same.baseline.yaml 'Second wording.' 'second prompt' judge.sh
check_pair "$TMPD/control/same.yaml" "$TMPD/control/same.baseline.yaml" \
  || fail "control: a pair that differs only in description and prompt must be accepted"
write_case other-judge.baseline.yaml 'Second wording.' 'second prompt' other-judge.sh
check_pair "$TMPD/control/same.yaml" "$TMPD/control/other-judge.baseline.yaml" \
  && fail "control: a pair whose judges differ must be refused"
sed 's/^  Experiment variable: .*$//' "$TMPD/control/same.baseline.yaml" > "$TMPD/control/undeclared.baseline.yaml"
check_pair "$TMPD/control/same.yaml" "$TMPD/control/undeclared.baseline.yaml" \
  && fail "control: a case without a declared experiment variable must be refused"

pairs=0
for baseline in "$ROOT"/*/evals/cases/*.baseline.*.yaml; do
  [ -f "$baseline" ] || continue
  change="$(printf '%s' "$baseline" | sed 's/\.baseline\././')"
  name="${baseline#"$ROOT"/}"
  [ -f "$change" ] || fail "$name has no with-change case beside it"
  check_pair "$change" "$baseline"
  case $? in
    0) ;;
    1) fail "$name and its with-change case differ outside the description and the prompt" ;;
    *) fail "$name or its with-change case does not declare a claim, an experiment variable and control variables" ;;
  esac
  pairs=$((pairs + 1))
done
[ "$pairs" -gt 0 ] || fail "no baseline case was found, so nothing was checked"

echo "PASS: eval-case-pairs"
