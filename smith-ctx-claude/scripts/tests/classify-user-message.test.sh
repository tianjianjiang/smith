#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../classify-user-message.mjs"

TMPD="$(mktemp -d)"
export CLAUDE_CONFIG_DIR="$TMPD"
STATE_FILE="$TMPD/state/exit-plan-mode-message-classification.json"

trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

run() {
  printf '{"user_message":"%s"}' "$1" | node "$HOOK"
}

check_classification() {
  msg="$1"
  expected="$2"
  desc="$3"

  run "$msg"
  [ -f "$STATE_FILE" ] || fail "$desc: state file not created"

  actual=$(node -p "JSON.parse(require('fs').readFileSync('$STATE_FILE', 'utf8')).classification")
  [ "$actual" = "$expected" ] || fail "$desc: expected '$expected', got '$actual'"
}

check_classification "go" "approval" "short approval: go"
check_classification "yes" "approval" "short approval: yes"
check_classification "ok" "approval" "short approval: ok"
check_classification "proceed" "approval" "short approval: proceed"
check_classification "繼續" "approval" "short approval: Chinese 繼續"
check_classification "好" "approval" "short approval: Chinese 好"
check_classification "go ahead" "approval" "approval with modifier: go ahead"
check_classification "yes please" "approval" "approval with modifier: yes please"
check_classification "繼續吧" "approval" "approval with modifier: Chinese 繼續吧"

check_classification "This is a longer explanation that should be classified as elaboration." "elaboration" "long message is elaboration"
check_classification "Let me explain the approach" "elaboration" "even short non-approval is elaboration"
check_classification "Yes, that's a bug" "elaboration" "yes in different context"

run ""
[ -f "$STATE_FILE" ] || fail "empty message: state file not created"
actual=$(node -p "JSON.parse(require('fs').readFileSync('$STATE_FILE', 'utf8')).classification")
[ "$actual" = "unknown" ] || fail "empty message: expected 'unknown', got '$actual'"

echo "PASS"
