#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../exit-plan-mode-guard.mjs"
RUNS="${SMITH_LIVE_CLASSIFIER_EVAL_RUNS:-5}"

if [ "$SMITH_LIVE_CLASSIFIER_EVAL" != 1 ]; then
  echo "SKIP: set SMITH_LIVE_CLASSIFIER_EVAL=1 to run the live approval classifier eval"
  exit 0
fi
unset SMITH_APPROVAL_CLASSIFIER_BIN SMITH_APPROVAL_CLASSIFIER SMITH_APPROVAL_CLASSIFIER_MODEL

fail() { echo "FAIL: $1"; exit 1; }
case "$RUNS" in
  "" | *[!0-9]* | 0*) fail "SMITH_LIVE_CLASSIFIER_EVAL_RUNS must be a positive integer, got '$RUNS'" ;;
esac
TMPD="$(mktemp -d)" || fail "mktemp failed"
trap 'rm -rf "$TMPD"' EXIT
TRANSCRIPT="$TMPD/transcript.jsonl"
misses=0

verdict_for() {
  if ! printf '{"type":"user","message":{"content":"%s"}}\n' "$1" > "$TRANSCRIPT"; then
    echo "error: cannot write $TRANSCRIPT" >&2
    echo error
    return
  fi
  out=$(printf '{"transcript_path":"%s"}' "$TRANSCRIPT" | node "$HOOK" 2>&1)
  case "$?:$out" in
    0:) echo approval ;;
    "2:Blocked: ExitPlanMode"*) echo elaboration ;;
    *) printf 'error for "%s": %s\n' "$1" "$out" >&2; echo error ;;
  esac
}

expect() {
  case "$2" in
    *'"'* | *'\'*) fail "case '$2' needs JSON escaping; keep cases free of quotes and backslashes" ;;
  esac
  hits=0
  i=0
  while [ "$i" -lt "$RUNS" ]; do
    [ "$(verdict_for "$2")" = "$1" ] && hits=$((hits + 1))
    i=$((i + 1))
  done
  echo "$hits/$RUNS $1: $2"
  [ "$hits" = "$RUNS" ] || misses=$((misses + 1))
}

for reply in "go" "ok" "yes" "lgtm" "好" "可以" \
  "approve the plan" "sounds good" "ship it" "proceed" "行" "沒問題"; do
  expect approval "$reply"
done
for reply in "go, but rename X first" "why not regex?" "好，但先改測試" \
  "rename it first, then go" "does this handle Windows paths?" "可以，不過測試要改"; do
  expect elaboration "$reply"
done

[ "$misses" = 0 ] || fail "$misses case(s) misclassified at least once"
echo "PASS: exit-plan-mode-guard classifier eval (model haiku${ANTHROPIC_DEFAULT_HAIKU_MODEL:+ = $ANTHROPIC_DEFAULT_HAIKU_MODEL})"
