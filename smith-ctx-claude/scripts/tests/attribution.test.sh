#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
CMD="$HERE/../../../smith-style/scripts/attribution.sh"
STAMP="$HERE/../attribution-model-stamp.sh"

fail() { echo "FAIL: $1"; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: attribution (jq not installed)"; exit 0; }

TMP=$(mktemp -d) || fail "mktemp"
trap 'rm -rf "$TMP"' EXIT
CLAUDE_CONFIG_DIR="$TMP/config"
export CLAUDE_CONFIG_DIR
unset CLAUDE_CODE_SESSION_ID
mkdir -p "$CLAUDE_CONFIG_DIR/plans"
WORK="$TMP/work"
mkdir -p "$WORK"

stamp() { printf '{"session_id":"s1","cwd":"%s","transcript_path":"%s"}' "$WORK" "$1" | "$STAMP"; }
run()   { ( cd "$WORK" && CLAUDE_CODE_SESSION_ID=s1 "$CMD" "$@" ); }

TR="$TMP/t.jsonl"
printf '%s\n' '{"type":"user","message":{"role":"user"}}' > "$TR"
printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-4-8"}}' >> "$TR"

out=$(run 2>/dev/null); rc=$?
[ "$rc" = 1 ] || fail "no model file: expected exit 1, got $rc"
[ -z "$out" ] || fail "no model file: expected no output, got: $out"

stamp "$TR" || fail "stamper crashed"

out=$(run); rc=$?
[ "$rc" = 0 ] || fail "full line: expected exit 0, got $rc"
[ "$out" = "Assisted-by: Claude:claude-opus-4-8" ] || fail "full line: got: $out"

out=$(run value)
[ "$out" = "Claude:claude-opus-4-8" ] || fail "value mode: got: $out"

EMPTY="$TMP/empty.jsonl"
printf '%s\n' '{"type":"user"}' > "$EMPTY"
stamp "$EMPTY" || fail "empty-transcript stamp crashed"
out=$(run)
[ "$out" = "Assisted-by: Claude:claude-opus-4-8" ] || fail "empty transcript must not clobber: got: $out"

SWITCH="$TMP/switch.jsonl"
printf '%s\n' '{"type":"assistant","message":{"model":"claude-sonnet-5"}}' > "$SWITCH"
stamp "$SWITCH" || fail "switch stamp crashed"
out=$(run)
[ "$out" = "Assisted-by: Claude:claude-sonnet-5" ] || fail "model switch not tracked: got: $out"

SENT="$TMP/sentinel.jsonl"
printf '%s\n' '{"type":"assistant","message":{"model":"<synthetic>"}}' > "$SENT"
stamp "$SENT" || fail "sentinel stamp crashed"
out=$(run)
[ "$out" = "Assisted-by: Claude:claude-sonnet-5" ] || fail "sentinel <synthetic> must not clobber: got: $out"

USERLINE="$TMP/userline.jsonl"
printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-4-8"}}' > "$USERLINE"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"the word assistant here"}}' >> "$USERLINE"
stamp "$USERLINE" || fail "userline stamp crashed"
out=$(run)
[ "$out" = "Assisted-by: Claude:claude-opus-4-8" ] || fail "user line quoting assistant must be skipped: got: $out"

SIDE="$TMP/side.jsonl"
printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-4-8"}}' > "$SIDE"
printf '%s\n' '{"type":"assistant","isSidechain":true,"message":{"model":"claude-haiku-4-5"}}' >> "$SIDE"
stamp "$SIDE" || fail "sidechain stamp crashed"
out=$(run)
[ "$out" = "Assisted-by: Claude:claude-opus-4-8" ] || fail "sidechain model must be excluded: got: $out"

MF=$(ls "$CLAUDE_CONFIG_DIR/plans/".assisted-model-* 2>/dev/null | head -1)
[ -n "$MF" ] || fail "model file not found for direct-write cases"

printf '%s\n' '<synthetic>' > "$MF"
out=$(run 2>/dev/null); rc=$?
[ "$rc" = 1 ] || fail "garbage model file: expected exit 1, got $rc"
[ -z "$out" ] || fail "garbage model file: expected no output, got: $out"

printf '   \n' > "$MF"
out=$(run 2>/dev/null); rc=$?
[ "$rc" = 1 ] || fail "whitespace-only model file: expected exit 1, got $rc"
[ -z "$out" ] || fail "whitespace-only: expected no output, got: $out"

printf 'claude-opus-4-8\r\n' > "$MF"
out=$(run)
[ "$out" = "Assisted-by: Claude:claude-opus-4-8" ] || fail "CRLF not stripped: got: $out"

BEDROCK="$TMP/bedrock.jsonl"
printf '%s\n' '{"type":"assistant","message":{"model":"us.anthropic.claude-opus-4-8"}}' > "$BEDROCK"
stamp "$BEDROCK" || fail "bedrock stamp crashed"
out=$(run)
[ "$out" = "Assisted-by: Claude:us.anthropic.claude-opus-4-8" ] || fail "provider-prefixed id: got: $out"

out=$(cd "$TMP" && CLAUDE_CODE_SESSION_ID=s1 "$CMD")
[ "$out" = "Assisted-by: Claude:us.anthropic.claude-opus-4-8" ] || fail "the session key must not depend on the directory: got: $out"
out=$(cd "$WORK" && CLAUDE_CODE_SESSION_ID=s2 "$CMD" 2>/dev/null); rc=$?
[ "$rc" = 1 ] || fail "another session must not read this session's model: got exit $rc"
out=$(cd "$WORK" && "$CMD" 2>/dev/null); rc=$?
[ "$rc" = 1 ] || fail "no session id must give no model: got exit $rc"
printf '{"session_id":"../escape","transcript_path":"%s"}' "$TR" | "$STAMP" || fail "unsafe session id stamp crashed"
[ ! -e "$CLAUDE_CONFIG_DIR/escape" ] || fail "an unsafe session id must not choose the file path"

printf 'not json at all' | "$STAMP" || fail "malformed stdin must not crash stamper"

LIB="$HERE/../attribution-lib.sh"
in_lib() { bash -c '. "$1"; shift; "$@"' _ "$LIB" "$@"; }

for id in claude-opus-5-5 claude-sonnet-4-5-20250929 us.anthropic.claude-opus-4-8 \
  us.anthropic.claude-opus-4-1-20250805-v1:0 claude-opus-4-1@20250805 claude-3-5-sonnet-20241022; do
  in_lib attribution_model_is_well_formed "$id" || fail "well-formed id rejected: $id"
done
for id in claude-- xclaude-. claude-: claude-@@ ...claude-... "<synthetic>" "claude-opus-4-8[1m]" "claude opus" ""; do
  in_lib attribution_model_is_well_formed "$id" && fail "malformed id accepted: $id"
done
XWORK="x1"
in_lib attribution_session_model "$XWORK" >/dev/null && fail "no model file must give no session model"
bash -c '. "$1"; printf "claude-opus-4-8\n" > "$(attribution_model_file "$2")"' _ "$LIB" "$XWORK" || fail "seed model file"
out=$(in_lib attribution_session_model "$XWORK")
[ "$out" = "claude-opus-4-8" ] || fail "session model from the model file: got: $out"
before=$(run)
for id in "claude-opus-4-8[1m]" "anthropic/claude-sonnet-4-5"; do
  printf '{"type":"assistant","message":{"model":"%s"}}\n' "$id" > "$TMP/malformed.jsonl"
  stamp "$TMP/malformed.jsonl" || fail "malformed-id stamp crashed"
  out=$(run)
  [ "$out" = "$before" ] || fail "malformed id $id must not be stamped: got: $out"
done

echo "PASS: attribution"
