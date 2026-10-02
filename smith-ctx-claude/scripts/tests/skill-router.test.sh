#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../skill-router.mjs"
TABLE="$HERE/../../skill-triggers.json"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

NOTHING_LOADED="$TMPD/nothing-loaded.jsonl"
printf '%s\n' '{"type":"user","message":{"content":"go"}}' > "$NOTHING_LOADED"

GH_PR_LOADED="$TMPD/gh-pr-loaded.jsonl"
for skill in smith-gh-pr smith-gh-cli smith-style; do
  printf '%s\n' \
    "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"id\":\"call-$skill\",\"name\":\"Skill\",\"input\":{\"skill\":\"$skill\"}}]}}" \
    "{\"type\":\"user\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"call-$skill\",\"content\":\"Launching skill\"}]}}"
done > "$GH_PR_LOADED"

route() {
  node -e '
    process.stdout.write(JSON.stringify({ prompt: process.argv[1], transcript_path: process.argv[2] }));
  ' "$1" "$2" | node "$HOOK"
}
suggests() {
  out=$(route "$2" "$3") || fail "$1: hook crashed"
  echo "$out" | grep -q "@$4" || fail "$1: expected @$4, got: $out"
}
does_not_suggest() {
  out=$(route "$2" "$3") || fail "$1: hook crashed"
  echo "$out" | grep -q "@$4" && fail "$1: @$4 should not be suggested, got: $out"
  return 0
}
silent() {
  out=$(route "$2" "$3") || fail "$1: hook crashed"
  [ -z "$out" ] || fail "$1: expected silence, got: $out"
}

suggests "owner prompt about a pull request" \
  "open a pull request for this" "$NOTHING_LOADED" smith-gh-pr
suggests "owner prompt with no transcript yet" \
  "review this pull request" "$TMPD/does-not-exist.jsonl" smith-gh-pr
suggests "slash command typed by the owner" \
  "/smith-ship stack" "$NOTHING_LOADED" smith-gh-pr
does_not_suggest "skill the prompt already names" \
  "/smith-ship stack" "$NOTHING_LOADED" smith-ship

silent "task notification after leading whitespace" \
  "  <task-notification> the pull request review finished" "$NOTHING_LOADED"
silent "task notification" \
  "<task-notification> the pull request review finished" "$NOTHING_LOADED"
silent "message from another session" \
  "Another Claude session sent a message: please review the pull request" "$NOTHING_LOADED"

does_not_suggest "skill already loaded in the session" \
  "open a pull request for this" "$GH_PR_LOADED" smith-gh-pr
silent "every matching skill already loaded and no note" \
  "look at the pull request" "$GH_PR_LOADED"

out=$(route "create stacked PRs for this" "$GH_PR_LOADED")
echo "$out" | grep -q "note: retarget every child" || fail "a note is still emitted when a matching skill is loaded"

for prompt in "fix it" "merge it" "improve this" "that is solid" "access denied" "a recurring problem" \
  "commit to the idea" "implement it" "modify that" "spawn one" "delegate it" "the classifier" \
  "ask permission" "debug it" "the architecture" "squash them" "develop further" "refactor it"; do
  silent "single common word: $prompt" "$prompt" "$NOTHING_LOADED"
done

suggests "narrowed pattern: git commit" "write the git commit message" "$NOTHING_LOADED" smith-git
suggests "narrowed pattern: fix the bug" "please fix the bug in the parser" "$NOTHING_LOADED" smith-validation
suggests "narrowed pattern: permission denied" "I got permission denied again" "$NOTHING_LOADED" smith-ctx-claude-mode-auto
suggests "narrowed pattern: denied by the hook" "it was denied by the hook" "$NOTHING_LOADED" smith-ctx-claude-mode-auto
suggests "narrowed pattern: subagents" "use subagents for this" "$NOTHING_LOADED" smith-subagents
suggests "narrowed pattern: software architecture" "sketch the software architecture" "$NOTHING_LOADED" smith-design
suggests "narrowed pattern: poll for" "poll for the result" "$NOTHING_LOADED" smith-automation
suggests "narrowed pattern: allowlist" "add it to the allowlist" "$NOTHING_LOADED" smith-settings
suggests "narrowed pattern: add a feature" "add a feature flag for this" "$NOTHING_LOADED" smith-dev

footer=$(route "open a pull request for this" "$NOTHING_LOADED")
echo "$footer" | grep -q "Skill tool" || fail "footer should say to load with the Skill tool"
echo "$footer" | grep -qi "read its SKILL.md" && fail "footer must not offer reading the SKILL.md"

node -e '
  const table = JSON.parse(require("fs").readFileSync(process.argv[1], "utf-8"));
  const broken = table.rules.filter((rule) => {
    try { new RegExp(rule.pattern, "i"); return false; } catch { return true; }
  });
  if (broken.length > 0) { console.log(broken.map((rule) => rule.why).join("; ")); process.exit(1); }
' "$TABLE" || fail "a pattern of skill-triggers.json does not compile"

COPY="$TMPD/copy"
mkdir -p "$COPY/smith-ctx-claude" "$COPY/smith-git/scripts"
cp -R "$HERE/.." "$COPY/smith-ctx-claude/scripts"
cp "$HERE/../../skill-gate.json" "$COPY/smith-ctx-claude/"
cp -R "$HERE/../../../smith-git/scripts/lib" "$COPY/smith-git/scripts/lib"
printf '%s\n' '{"rules":[{"pattern":"pull request","skills":["Smith-GH-PR"],"why":"mixed case"}]}' \
  > "$COPY/smith-ctx-claude/skill-triggers.json"
route_copy() {
  node -e '
    process.stdout.write(JSON.stringify({ prompt: "open a pull request", transcript_path: process.argv[1] }));
  ' "$1" | node "$COPY/smith-ctx-claude/scripts/skill-router.mjs"
}
out=$(route_copy "$NOTHING_LOADED") || fail "mixed-case table: hook crashed"
echo "$out" | grep -q "@Smith-GH-PR" || fail "the copied router should suggest its table's skill, got: $out"
out=$(route_copy "$GH_PR_LOADED") || fail "mixed-case table: hook crashed"
[ -z "$out" ] || fail "a loaded skill named in another case should not be suggested, got: $out"

silent "empty prompt" "   " "$NOTHING_LOADED"
out=$(printf 'not json' | node "$HOOK") || fail "malformed stdin: hook crashed"
[ -z "$out" ] || fail "malformed stdin should be silent"

echo "PASS: skill-router"
