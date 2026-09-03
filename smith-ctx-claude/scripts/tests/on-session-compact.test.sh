#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../on-session-compact.sh"
source "$HERE/../lib-context.sh"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: on-session-compact - $1"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/plans"
export CLAUDE_CONFIG_DIR="$TMP"
export _SMITH_PPID=12345

MYCWD="$TMP/repo"
mkdir -p "$MYCWD"
MYKEY=$(session_key "$_SMITH_PPID" "$MYCWD")

run() {
    printf '{"cwd":"%s"}' "$MYCWD" | bash "$HOOK"
}

printf 'sess1\n2026-09-04T00:00:00+09:00\n%s\nmy_checkpoint_label\n%s\n' "$MYCWD" "$MYKEY" \
    > "$TMP/plans/.pending-memory-restore-20260904T000000-1"

out=$(run) || fail "hook crashed on matching flag"
echo "$out" | grep -q '"hookEventName": "SessionStart"' || fail "expected SessionStart output, got: $out"
echo "$out" | grep -q 'my_checkpoint_label' || fail "expected checkpoint label in reminder, got: $out"
echo "$out" | grep -q 'pending-memory-restore-20260904T000000-1' || fail "expected flag path in reminder, got: $out"
pass "reminds when a flag matches this session's own key"

[ -f "$TMP/plans/.pending-memory-restore-20260904T000000-1" ] || fail "flag must NOT be deleted"
pass "does not consume the flag"

out2=$(run) || fail "hook crashed on second run"
echo "$out2" | grep -q 'my_checkpoint_label' || fail "expected reminder again on a second compact, got: $out2"
pass "reminds again on a repeated compaction (accepted, not suppressed)"

rm -f "$TMP/plans/.pending-memory-restore-20260904T000000-1"
printf 'sess2\n2026-09-04T00:00:00+09:00\n%s\nother_session_label\nnotmykey12345678\n' "$MYCWD" \
    > "$TMP/plans/.pending-memory-restore-20260904T000000-2"
out3=$(run) || fail "hook crashed on foreign-session flag"
[ -z "$out3" ] || fail "must stay silent on a flag belonging to a different session, got: $out3"
pass "silent on another session's flag (never offers it)"

rm -f "$TMP/plans/.pending-memory-restore-20260904T000000-2"
out4=$(run) || fail "hook crashed with no flags present"
[ -z "$out4" ] || fail "must stay silent when no flag exists, got: $out4"
pass "silent when no flag exists"

out5=$(echo 'not json' | bash "$HOOK") || fail "hook crashed on malformed stdin"
[ -z "$out5" ] || fail "must stay silent on malformed stdin, got: $out5"
pass "silent on malformed stdin"

echo "PASS: on-session-compact"
