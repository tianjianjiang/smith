#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../subagent-contract-guard.mjs"
SKILL="$HERE/../../../smith-subagents/SKILL.md"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CLAUDE_CONFIG_DIR="$TMP/config"
export CLAUDE_CONFIG_DIR

REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" -c user.name=smith-test -c user.email=smith-test@example.invalid \
  commit -q --allow-empty -m init

fail() { echo "FAIL: $1"; exit 1; }

contract_fixture() {
  node -e 'import(process.argv[1]).then((m) => {
      const lines = m.REQUIRED_CONTRACT.split(/\.\s+/).filter(Boolean);
      process.stdout.write(lines.map(l => l + ".").join("\n") + "\n");
    });' "$HERE/../lib/contract-template.mjs" "${1:-}"
}
contract_fixture > "$TMP/contract.txt"
[ -s "$TMP/contract.txt" ] || fail "could not extract the contract from $SKILL"
grep -q 'describe it for the main thread instead of doing it' "$TMP/contract.txt" \
  || fail "extracted contract is missing the mutation-describe clause"
grep -q 'do not summarize them away' "$TMP/contract.txt" \
  || fail "extracted contract is missing the exact-values clause"

payload() {
  node -e 'const fs=require("node:fs");
    process.stdout.write(JSON.stringify({
      tool_name: process.argv[1], cwd: process.argv[2], session_id: "test-session",
      tool_input: { subagent_type: process.argv[3],
                    prompt: fs.readFileSync(process.argv[4], "utf-8") },
    }));' "$1" "$2" "$3" "$4"
}

reset_ledger() { rm -rf "$CLAUDE_CONFIG_DIR/plans"; }
ledger() { cat "$CLAUDE_CONFIG_DIR"/plans/.spawn-ledger-* 2>/dev/null; }

expect_allowed() {
  name="$1"; verdict="$2"; prompt_file="$3"; type="${4:-general-purpose}"
  reset_ledger
  if ! payload Agent "$REPO" "$type" "$prompt_file" \
    | node "$HOOK" >"$TMP/out" 2>"$TMP/err"; then
    fail "$name: expected the spawn to be allowed"
  fi
  ledger | grep -q "\"verdict\":\"$verdict\"" \
    || fail "$name: expected ledger verdict $verdict, got: $(ledger)"
}

expect_blocked() {
  name="$1"; prompt_file="$2"; type="${3:-general-purpose}"
  reset_ledger
  payload Agent "$REPO" "$type" "$prompt_file" | node "$HOOK" >"$TMP/out" 2>"$TMP/err"
  [ "$?" = 2 ] || fail "$name: expected exit 2 (blocked)"
  grep -q 'describe it for the main thread instead of doing it' "$TMP/err" \
    || fail "$name: the block message must contain the contract to paste"
  ledger | grep -q '"verdict":"blocked"' \
    || fail "$name: expected ledger verdict blocked, got: $(ledger)"
}

cp "$TMP/contract.txt" "$TMP/verbatim.txt"
printf '\nFind every call site of parseConfig() and report file:line.\n' >> "$TMP/verbatim.txt"
expect_allowed "verbatim paste" contract-pasted "$TMP/verbatim.txt"

tr '\n' ' ' < "$TMP/contract.txt" | tr -s ' ' > "$TMP/reflowed.txt"
printf '\n\nReport file:line facts only.\n' >> "$TMP/reflowed.txt"
expect_allowed "reflowed paste (whitespace-normalized)" contract-pasted "$TMP/reflowed.txt"

sed -e 's/READ-ONLY/read-only/' -e 's/FINDINGS ONLY/findings only/' \
  -e 's/do NOT/do not/' < "$TMP/verbatim.txt" > "$TMP/lowercased.txt"
cmp -s "$TMP/verbatim.txt" "$TMP/lowercased.txt" \
  && fail "lowercased fixture is identical to the verbatim one"
expect_allowed "paste with the emphasis casing flattened" contract-pasted \
  "$TMP/lowercased.txt"

{ printf 'Context: auditing pull request 123 before it ships.\n\n'; \
  cat "$TMP/contract.txt"; } > "$TMP/preambled.txt"
expect_allowed "contract preceded by the task's own preamble" contract-pasted \
  "$TMP/preambled.txt"

cat > "$TMP/reworded.txt" <<'EOF'
Read-only investigation. Report findings only and do not edit, write, commit
or push anything. Give me file:line facts with quoted evidence, not fixes.
EOF
expect_blocked "re-worded prose contract" "$TMP/reworded.txt"

grep -v 'describe it for the main thread' "$TMP/contract.txt" \
  | grep -v 'summarize them away' > "$TMP/two-clauses-dropped.txt"
expect_blocked "the two historically dropped clauses removed" "$TMP/two-clauses-dropped.txt"

sed 's/^/> /' "$TMP/contract.txt" > "$TMP/blockquoted.txt"
printf '\nReport file:line facts only.\n' >> "$TMP/blockquoted.txt"
expect_allowed "paste kept in SKILL.md blockquote form" contract-pasted \
  "$TMP/blockquoted.txt"

cat > "$TMP/editor.txt" <<'EOF'
EDITOR ROLE. You may change exactly one artifact: smith-ctx-claude/README.md.
The only tool granted is Edit. Everything else stays read-only.
EOF
expect_allowed "declared editor role" editor-role "$TMP/editor.txt"

for opening in '**EDITOR ROLE**' '## EDITOR ROLE' '- EDITOR ROLE' \
  '1. EDITOR ROLE' '__EDITOR ROLE__'; do
  printf '%s: change only README.md, only via Edit.\n' "$opening" \
    > "$TMP/editor-markup.txt"
  expect_allowed "editor declaration written as '$opening'" editor-role \
    "$TMP/editor-markup.txt"
done

cat > "$TMP/quoted-editor.txt" <<'EOF'
Investigate the guard. The documentation says:
> EDITOR ROLE is how you declare a bounded editor spawn.
Now go and report what it does.
EOF
expect_blocked "quoting the documentation does not declare an editor role" \
  "$TMP/quoted-editor.txt"

cat > "$TMP/mentions-editor-role.txt" <<'EOF'
Investigate the failing test. You are not in an editor role here, just report
findings back to me with file:line evidence.
EOF
expect_blocked "an incidental mention of an editor role is not a declaration" \
  "$TMP/mentions-editor-role.txt"

cat > "$TMP/lowercase-editor.txt" <<'EOF'
editor role. Change smith-ctx-claude/README.md only.
EOF
expect_blocked "the editor declaration is case-sensitive" \
  "$TMP/lowercase-editor.txt"

expect_allowed "plugin-namespaced subagent type" exempt "$TMP/reworded.txt" \
  "pr-review-toolkit:code-reviewer"
expect_allowed "configured exempt subagent type" exempt "$TMP/reworded.txt" \
  statusline-setup
expect_allowed "exempt matching ignores case" exempt "$TMP/reworded.txt" \
  STATUSLINE-SETUP
for opening in '*EDITOR ROLE*' '_EDITOR ROLE_'; do
  printf '%s: change only README.md, only via Edit.\n' "$opening" \
    > "$TMP/editor-markup.txt"
  expect_allowed "editor declaration written as '$opening'" editor-role \
    "$TMP/editor-markup.txt"
done
printf '    EDITOR ROLE, quoted inside an indented code block.\n' \
  > "$TMP/editor-indented.txt"
expect_blocked "a four-space indented mention is code, not a declaration" \
  "$TMP/editor-indented.txt"

expect_blocked "a bare colon is not a namespaced type" "$TMP/reworded.txt" ":"
expect_blocked "a trailing colon is not a namespaced type" "$TMP/reworded.txt" \
  "general-purpose:"
expect_blocked "full-tool-grant built-ins are not exempt" "$TMP/reworded.txt" Explore
expect_blocked "a fork inherits context, not an exemption" "$TMP/reworded.txt" fork

mkdir -p "$REPO/.claude"
touch "$REPO/.claude/subagent-contract-guard.disabled"
expect_allowed "per-checkout opt-out" unenforced "$TMP/reworded.txt"
grep -q 'append-only' "$TMP/out" \
  || fail "opt-out: must say the resulting preflight FAIL cannot be cleared"
expect_allowed "the opt-out outranks an editor declaration" unenforced \
  "$TMP/editor.txt"
expect_allowed "an exemption is non-applicability, not a waived check" exempt \
  "$TMP/reworded.txt" "pr-review-toolkit:code-reviewer"
expect_allowed "a configured exemption survives the opt-out too" exempt \
  "$TMP/reworded.txt" statusline-setup
rm -rf "$REPO/.claude"

ledger_path_for() {
  node -e 'import(process.argv[1]).then(m =>
    process.stdout.write(m.ledgerPath(m.checkoutRoot(process.argv[2]) || process.argv[2])));' \
    "$HERE/../lib/spawn-ledger.mjs" "$1"
}
OUTSIDE="$TMP/outside-any-repo"
mkdir -p "$OUTSIDE"
REPO_LEDGER=$(ledger_path_for "$REPO")
OUTSIDE_LEDGER=$(ledger_path_for "$OUTSIDE")
[ "$REPO_LEDGER" != "$OUTSIDE_LEDGER" ] || fail "ledger key setup: the two paths must differ"
reset_ledger
if ! payload Agent "$OUTSIDE" general-purpose "$TMP/verbatim.txt" \
  | GIT_DIR="$REPO/.git" GIT_WORK_TREE="$REPO" node "$HOOK" \
    >"$TMP/out" 2>"$TMP/err"; then
  fail "inherited GIT_DIR: the spawn must still be allowed"
fi
[ -f "$OUTSIDE_LEDGER" ] \
  || fail "inherited GIT_DIR: the entry must be keyed to the real working directory"
[ -f "$REPO_LEDGER" ] \
  && fail "inherited GIT_DIR hijacked the ledger key into an unrelated repository"
grep -q '"branch":""' "$OUTSIDE_LEDGER" \
  || fail "inherited GIT_DIR leaked a branch name into a non-repository spawn"

reset_ledger
node -e 'const fs=require("node:fs");
  process.stdout.write(JSON.stringify({
    tool_name:"Agent", session_id:"no-cwd",
    tool_input:{subagent_type:"general-purpose",
                prompt:fs.readFileSync(process.argv[1],"utf-8")},
  }));' "$TMP/verbatim.txt" | node "$HOOK" >"$TMP/out" 2>"$TMP/err" \
  || fail "no cwd: the spawn must still be allowed"
grep -q 'could not be written to the ledger' "$TMP/out" \
  || fail "no cwd: an unrecordable spawn must warn; got: $(cat "$TMP/out")"

UNWRITABLE="$TMP/config-is-a-regular-file"
: > "$UNWRITABLE"
if ! payload Agent "$REPO" general-purpose "$TMP/verbatim.txt" \
  | CLAUDE_CONFIG_DIR="$UNWRITABLE" node "$HOOK" >"$TMP/out" 2>"$TMP/err"; then
  fail "unwritable ledger: the spawn must still be allowed"
fi
grep -q 'could not be written to the ledger' "$TMP/out" \
  || fail "unwritable ledger: must warn loudly, not vanish; got: $(cat "$TMP/out")"

scratch_tree() {
  root="$TMP/$1"
  mkdir -p "$root/smith-ctx-claude/scripts/lib" "$root/smith-subagents"
  cp "$HOOK" "$root/smith-ctx-claude/scripts/subagent-contract-guard.mjs"
  cp "$HERE/../lib/spawn-ledger.mjs" "$root/smith-ctx-claude/scripts/lib/"
  cp "$HERE/../lib/contract-template.mjs" "$root/smith-ctx-claude/scripts/lib/"
  cp "$SKILL" "$root/smith-subagents/SKILL.md"
  cp "$HERE/../../subagent-contract-config.json" "$root/smith-ctx-claude/"
  printf '%s' "$root/smith-ctx-claude/scripts/subagent-contract-guard.mjs"
}

CFG_TREE=$(scratch_tree config-honoured)
printf '{"exemptSubagentTypes":["a-type-not-in-the-code"]}\n' \
  > "$TMP/config-honoured/smith-ctx-claude/subagent-contract-config.json"
reset_ledger
payload Agent "$REPO" a-type-not-in-the-code "$TMP/reworded.txt" \
  | node "$CFG_TREE" >"$TMP/out" 2>"$TMP/err" \
  || fail "config-only exemption: the spawn must be allowed"
ledger | grep -q '"verdict":"exempt"' \
  || fail "config-only exemption: the config file is not being honoured at all"
reset_ledger
payload Agent "$REPO" statusline-setup "$TMP/reworded.txt" \
  | node "$CFG_TREE" >"$TMP/out" 2>"$TMP/err"
[ "$?" = 2 ] \
  || fail "config-only exemption: a type absent from the config must not be exempt"

printf '{"exemptSubagentTypes":"statusline-setup"}\n' \
  > "$TMP/config-honoured/smith-ctx-claude/subagent-contract-config.json"
reset_ledger
payload Agent "$REPO" statusline-setup "$TMP/reworded.txt" \
  | node "$CFG_TREE" >"$TMP/out" 2>"$TMP/err"
[ "$?" = 2 ] \
  || fail "a non-array config must exempt nothing, not fall back to a built-in list"

rm -f "$TMP/config-honoured/smith-ctx-claude/subagent-contract-config.json"
reset_ledger
payload Agent "$REPO" statusline-setup "$TMP/reworded.txt" \
  | node "$CFG_TREE" >"$TMP/out" 2>"$TMP/err"
[ "$?" = 2 ] \
  || fail "absent config: there must be no hardcoded exemption fallback"
grep -q 'missing or does not hold an exemption array' "$TMP/out" \
  || fail "absent config: a broken config must say so, not just block silently"
reset_ledger
payload Agent "$REPO" "plug:agent" "$TMP/reworded.txt" \
  | node "$CFG_TREE" >"$TMP/out" 2>"$TMP/err" \
  || fail "absent config: the namespaced rule lives in code and must survive"

BQ_TREE=$(scratch_tree stray-blockquote)
BQ_SKILL="$TMP/stray-blockquote/smith-subagents/SKILL.md"
node -e 'const fs=require("node:fs");
  const p=process.argv[1];
  const src=fs.readFileSync(p,"utf-8");
  const at=src.indexOf("## Contract template");
  const eol=src.indexOf("\n", at) + 1;
  fs.writeFileSync(p, src.slice(0,eol) +
    "\n> Note: an editorial callout that must never become the contract.\n" +
    "> «and a placeholder, so it looks like the template too»\n\n" +
    src.slice(eol));' "$BQ_SKILL"
reset_ledger
payload Agent "$REPO" general-purpose "$TMP/verbatim.txt" \
  | node "$BQ_TREE" >"$TMP/out" 2>"$TMP/err" \
  || fail "stray blockquote: a correct paste must never be blocked"
ledger | grep -q '"verdict":"blocked"' \
  && fail "stray blockquote before the template became the contract"
grep -q 'subagent-contract-guard' "$TMP/out" \
  || fail "stray blockquote: refusing to guess must be loud, got: $(cat "$TMP/out")"

MISMATCH_TREE=$(scratch_tree display-vs-constant-mismatch)
MISMATCH_SKILL="$TMP/display-vs-constant-mismatch/smith-subagents/SKILL.md"
node -e 'const fs=require("node:fs");
  const p=process.argv[1];
  const src=fs.readFileSync(p,"utf-8");
  const before="> exact values you observed; do not summarize them away.";
  if (!src.includes(before)) { console.error("anchor not found"); process.exit(1); }
  fs.writeFileSync(p, src.replace(before,
    before + "\n> NEVER post to Slack, Jira, or GitHub under any circumstances."));' \
  "$MISMATCH_SKILL" || fail "display-constant mismatch: could not build the fixture"
reset_ledger
payload Agent "$REPO" general-purpose "$TMP/verbatim.txt" \
  | node "$MISMATCH_TREE" >"$TMP/out" 2>"$TMP/err" \
  || fail "display-constant mismatch: must fail open rather than block"
ledger | grep -q '"reason":"contract-source-unreadable"' \
  || fail "a clause added to SKILL.md without updating REQUIRED_CONTRACT must not be silently unenforced"

reset_ledger
payload Agent "$REPO" general-purpose "$TMP/reworded.txt" \
  | env -u CLAUDE_CONFIG_DIR HOME="$TMP/fake-home" node "$HOOK" \
    >"$TMP/out" 2>"$TMP/err"
[ "$?" = 2 ] || fail "CLAUDE_CONFIG_DIR unset: the guard must still run"
[ -d "$TMP/fake-home/.claude/plans" ] \
  || fail "CLAUDE_CONFIG_DIR unset: the ledger must fall back to HOME/.claude"

NONTEXT='{"tool_name":"Agent","cwd":"'"$REPO"'","session_id":"s",
  "tool_input":{"subagent_type":"general-purpose","prompt":[{"text":"go"}]}}'
reset_ledger
printf '%s' "$NONTEXT" | node "$HOOK" >"$TMP/out" 2>"$TMP/err" \
  || fail "a non-text prompt must not block"
ledger | grep -q '"reason":"prompt-not-text"' \
  || fail "a non-text prompt must be recorded as unchecked, got: $(ledger)"
grep -q 'subagent-contract-guard' "$TMP/out" \
  || fail "a non-text prompt must also warn at the time"

RENAMED='{"tool_name":"Agent","cwd":"'"$REPO"'","session_id":"s",
  "tool_input":{"subagent_type":"general-purpose","promptText":"go and edit"}}'
reset_ledger
printf '%s' "$RENAMED" | node "$HOOK" >"$TMP/out" 2>"$TMP/err" \
  || fail "a renamed prompt field must not block"
ledger | grep -q '"reason":"prompt-not-text"' \
  || fail "a renamed prompt field must be recorded, got: $(ledger)"
grep -q 'promptText' "$TMP/out" \
  || fail "the advisory must name the fields it actually saw"

mkdir -p "$REPO/.claude"
touch "$REPO/.claude/subagent-contract-guard.disabled"
if ! payload Agent "$REPO" general-purpose "$TMP/reworded.txt" \
  | CLAUDE_CONFIG_DIR="$UNWRITABLE" node "$HOOK" >"$TMP/out" 2>"$TMP/err"; then
  fail "opt-out with an unwritable ledger is consent, and must not block"
fi
rm -rf "$REPO/.claude"

ORPHAN="$TMP/orphan/scripts"
mkdir -p "$ORPHAN/lib"
cp "$HOOK" "$ORPHAN/subagent-contract-guard.mjs"
cp "$HERE/../lib/spawn-ledger.mjs" "$ORPHAN/lib/spawn-ledger.mjs"
cp "$HERE/../lib/contract-template.mjs" "$ORPHAN/lib/contract-template.mjs"
reset_ledger
if ! payload Agent "$REPO" general-purpose "$TMP/reworded.txt" \
  | node "$ORPHAN/subagent-contract-guard.mjs" >"$TMP/out" 2>"$TMP/err"; then
  fail "unreadable contract source: must fail open, not block"
fi
grep -q 'subagent-contract-guard' "$TMP/out" \
  || fail "unreadable contract source: must emit a loud advisory, not stay silent"
ledger | grep -q '"reason":"contract-source-unreadable"' \
  || fail "unreadable contract source: expected that reason in the ledger, got: $(ledger)"

reset_ledger
printf '%s' '{"tool_name":"Read","cwd":"'"$REPO"'","tool_input":{"file_path":"/x"}}' \
  | node "$HOOK" >"$TMP/out" 2>"$TMP/err" || fail "non-spawn tool: must not block"
[ -z "$(ledger)" ] || fail "non-spawn tool: must not write a ledger entry"

for bad in 'null' 'not json' '{"tool_name":"Agent"}' \
  '{"tool_name":"Agent","cwd":"'"$REPO"'","tool_input":{"prompt":"   "}}'; do
  reset_ledger
  printf '%s' "$bad" | node "$HOOK" >"$TMP/out" 2>"$TMP/err" \
    || fail "malformed input must not block: $bad"
  [ -z "$(ledger)" ] || fail "malformed input must not be ledgered: $bad"
done

reset_ledger
payload Task "$REPO" general-purpose "$TMP/verbatim.txt" | node "$HOOK" >/dev/null 2>&1 \
  || fail "Task tool name must be handled like Agent"
ledger | grep -q '"tool":"Task"' || fail "ledger must record the spawning tool name"
ledger | grep -q '"session":"test-session"' || fail "ledger must record the session id"

echo "PASS: subagent-contract-guard"
