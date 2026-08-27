#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
REPORT="$HERE/../spawn-ledger-report.mjs"
GUARD="$HERE/../subagent-contract-guard.mjs"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CLAUDE_CONFIG_DIR="$TMP/config"
export CLAUDE_CONFIG_DIR

REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" -c user.name=smith-test -c user.email=smith-test@example.invalid \
  commit -q --allow-empty -m init
git -C "$REPO" checkout -q -b feat/under-test
BRANCH=feat/under-test

fail() { echo "FAIL: $1"; exit 1; }

LEDGER=$(node -e 'import("'"$HERE"'/../lib/spawn-ledger.mjs").then(m =>
  process.stdout.write(m.ledgerPath(m.scopeRootFor(process.argv[1]))));' "$REPO")
[ -n "$LEDGER" ] || fail "could not derive the ledger path"

report() { node "$REPORT" "$REPO"; }
expect() {
  out=$(report) || fail "$1: reporter crashed"
  echo "$out" | grep -q "$2" || fail "$1: expected '$2', got: $out"
}

expect "no ledger at all" "SKIP:no-ledger"

mkdir -p "$CLAUDE_CONFIG_DIR/plans"
: > "$LEDGER"
expect "empty ledger" "N/A:no-spawns"

entry() {
  printf '{"ts":"2026-08-27T12:00:00.000Z","session":"s","branch":"%s","tool":"Agent","subagent_type":"general-purpose","verdict":"%s"%s}\n' \
    "$1" "$2" "$3" >> "$LEDGER"
}

entry "$BRANCH" contract-pasted ""
entry "$BRANCH" editor-role ""
entry "$BRANCH" exempt ""
entry "$BRANCH" blocked ""
expect "all spawns checked" "subagent-contract PASS"
expect "counts are reported" "contract-pasted=1"

entry other-branch contract-pasted ""
expect "another branch's CHECKED spawn is out of scope" "subagent-contract PASS"

entry other-branch unenforced ',"reason":"opt-out"'
expect "an unchecked spawn is never filtered away by branch" \
  "FAIL:unchecked-spawn(opt-out)"

: > "$LEDGER"
entry "$BRANCH" contract-pasted ""
entry 0123456789abcdef0123456789abcdef01234567 unenforced ',"reason":"opt-out"'
expect "a record written on a detached HEAD still counts" \
  "FAIL:unchecked-spawn(opt-out)"

: > "$LEDGER"
entry "$BRANCH" contract-pasted ""
entry other-branch contract-pasted ""

printf 'not json at all\n' >> "$LEDGER"
expect "a malformed line is never silently dropped" \
  "FAIL:unchecked-spawn(malformed-line)"
expect "the malformed line is counted in the summary" "malformed-line=1"

: > "$LEDGER"
entry "$BRANCH" contract-pasted ""
printf '{"branch":"%s","tool":"Agent"}\n' "$BRANCH" >> "$LEDGER"
expect "an entry with no verdict field cannot support a PASS" \
  "FAIL:unchecked-spawn(unrecognized)"

: > "$LEDGER"
entry "$BRANCH" future-verdict-nobody-knows ""
expect "an unrecognized verdict cannot support a PASS" \
  "FAIL:unchecked-spawn(future-verdict-nobody-knows)"

: > "$LEDGER"
entry "$BRANCH" contract-pasted ""
printf '{"tool":"Agent","verdict":"unenforced","reason":"opt-out"}\n' >> "$LEDGER"
expect "an entry with no branch field is not silently discarded" \
  "FAIL:unchecked-spawn(opt-out)"

: > "$LEDGER"
entry "$BRANCH" contract-pasted ""
entry "" unenforced ',"reason":"opt-out"'
expect "an entry with a blank branch is not silently discarded" \
  "FAIL:unchecked-spawn(opt-out)"

: > "$LEDGER"
printf 'garbage\n' >> "$LEDGER"
expect "a ledger of nothing but malformed lines is not no-spawns" \
  "FAIL:unchecked-spawn(malformed-line)"

: > "$LEDGER"
entry "$BRANCH" contract-pasted ""
printf 'null\n' >> "$LEDGER"
expect "a null ledger line is counted, not fatal" \
  "FAIL:unchecked-spawn(malformed-line)"

: > "$LEDGER"
entry "$BRANCH" contract-pasted ',"reason":"has a space, and (parens)"'
expect "verdict tokens never break the single reported line" "subagent-contract PASS"
[ "$(report | wc -l | tr -d ' ')" = 1 ] || fail "the report must be exactly one line"
: > "$LEDGER"
printf '{"branch":"%s","verdict":"we broke\\nit"}\n' "$BRANCH" >> "$LEDGER"
[ "$(report | wc -l | tr -d ' ')" = 1 ] \
  || fail "an unrecognised verdict must not inject a newline into the report"

: > "$LEDGER"
printf '{"branch":"%s","verdict":"\\u001b[2K\\u001b[1Gsubagent-contract PASS"}\n' \
  "$BRANCH" >> "$LEDGER"
ESC=$(printf '\033')
report | grep -q "$ESC" \
  && fail "a control character in a verdict must not reach the report"
report | grep -q "FAIL:unchecked-spawn" \
  || fail "a forged verdict must still FAIL, got: $(report)"

: > "$LEDGER"
entry "$BRANCH" contract-pasted ""
chmod 000 "$LEDGER"
expect "a ledger that exists but cannot be read is not absence" \
  "FAIL:unchecked-spawn(unreadable-ledger)"
chmod 644 "$LEDGER"

: > "$LEDGER"
entry "$BRANCH" contract-pasted ""
entry "$BRANCH" unenforced ',"reason":"opt-out"'
expect "an unchecked spawn on this branch fails" "FAIL:unchecked-spawn(opt-out)"

rm -f "$LEDGER"
spawn() {
  node -e 'const fs=require("node:fs");
    process.stdout.write(JSON.stringify({
      tool_name:"Agent", cwd:process.argv[1], session_id:"end-to-end",
      tool_input:{subagent_type:"general-purpose",
                  prompt:fs.readFileSync(process.argv[2],"utf-8")},
    }));' "$REPO" "$1" | node "$GUARD" >/dev/null 2>&1
}
printf 'EDITOR ROLE. Only README.md may change, only via Edit.\n' > "$TMP/end-to-end.txt"
spawn "$TMP/end-to-end.txt" \
  || fail "end-to-end: the guard should have allowed a declared editor role"
expect "end-to-end guard write is readable by the reporter" "subagent-contract PASS"
report | grep -q "branch $BRANCH" || fail "end-to-end: report must name the branch"

spawn "$TMP/end-to-end.txt" \
  || fail "end-to-end: the second spawn should also have been allowed"
expect "the ledger accumulates rather than replacing" "2 spawn(s)"
[ "$(grep -c . "$LEDGER")" = 2 ] \
  || fail "two spawns must leave two ledger lines, got: $(grep -c . "$LEDGER")"

OUTSIDE="$TMP/outside-any-repo"
mkdir -p "$OUTSIDE"
OUTSIDE_LEDGER=$(node -e 'import("'"$HERE"'/../lib/spawn-ledger.mjs").then(m =>
  process.stdout.write(m.ledgerPath(process.argv[1])));' "$OUTSIDE")
rm -f "$LEDGER"
printf '{"branch":"","verdict":"unenforced","reason":"opt-out"}\n' > "$OUTSIDE_LEDGER"
out=$(node "$REPORT" "$OUTSIDE") || fail "non-repo report crashed"
echo "$out" | grep -q "FAIL:unchecked-spawn(opt-out)" \
  || fail "outside a repository the reporter must still find its ledger, got: $out"
rm -f "$OUTSIDE_LEDGER"

SUBDIR="$REPO/sub/dir"
mkdir -p "$SUBDIR"
SUBDIR_LEDGER=$(node -e 'import("'"$HERE"'/../lib/spawn-ledger.mjs").then(m =>
  process.stdout.write(m.ledgerPath(process.argv[1])));' "$SUBDIR")
rm -f "$LEDGER"
printf '{"branch":"%s","verdict":"unenforced","reason":"opt-out"}\n' "$BRANCH" \
  > "$SUBDIR_LEDGER"
out=$(node "$REPORT" "$SUBDIR") || fail "subdirectory report crashed"
echo "$out" | grep -q "FAIL:unchecked-spawn(opt-out)" \
  || fail "a record filed under the raw working directory must still be read: $out"
rm -f "$SUBDIR_LEDGER"

DETACHED=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q --detach "$DETACHED"
out=$(node "$REPORT" "$REPO") || fail "detached HEAD report crashed"
echo "$out" | grep -q "branch $DETACHED" \
  || fail "a detached HEAD must be reported by commit, not lumped under 'HEAD': $out"
git -C "$REPO" checkout -q "$BRANCH"

echo "PASS: spawn-ledger-report"
