#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../amend-shared-commit-guard.mjs"

SHIM="$(mktemp -d)"
trap 'rm -rf "$SHIM"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

cat > "$SHIM/git" <<'EOF'
#!/bin/sh
case "$*" in
  *"rev-parse --abbrev-ref HEAD"*)
    [ "${GIT_REVPARSE_FAIL:-0}" = "1" ] && exit 1
    echo "${GIT_STUB_BRANCH:-feat/child}" ;;
  *"branch --points-at HEAD"*)
    [ "${GIT_POINTSAT_FAIL:-0}" = "1" ] && exit 1
    printf '%s\n' ${GIT_STUB_POINTS_AT:-${GIT_STUB_BRANCH:-feat/child}} ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$SHIM/git"
export PATH="$SHIM:$PATH"

reset_stubs() {
  unset GIT_STUB_BRANCH GIT_STUB_POINTS_AT GIT_REVPARSE_FAIL GIT_POINTSAT_FAIL
}
assert_silent() {
  out=$(printf '%s' "$2" | node "$HOOK") || { reset_stubs; fail "$1: hook crashed"; }
  reset_stubs
  [ -z "$out" ] || fail "$1: expected silent allow, got: $out"
}
assert_asks() {
  out=$(printf '%s' "$2" | node "$HOOK") || { reset_stubs; fail "$1: hook crashed"; }
  reset_stubs
  echo "$out" | grep -q '"permissionDecision":"ask"' || fail "$1: expected ask, got: $out"
}
assert_reason_includes() {
  out=$(printf '%s' "$2" | node "$HOOK") || { reset_stubs; fail "$1: hook crashed"; }
  reset_stubs
  echo "$out" | grep -q "$3" || fail "$1: expected reason to include '$3', got: $out"
}

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_asks \
  "amend on branch with no own commits (shared HEAD) asks" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit --amend"}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_reason_includes \
  "reason names the other branch" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit --amend"}}' \
  "feat/parent"

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_reason_includes \
  "single shared branch uses singular verb agreement" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit --amend"}}' \
  "'feat/parent' also points at"

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child" assert_silent \
  "amend on branch with its own commit (HEAD unique) allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit --amend"}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child" assert_silent \
  "commit without --amend allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_silent \
  "unrelated command allowed even with shared HEAD" \
  '{"tool_name":"Bash","tool_input":{"command":"git status"}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_asks \
  "git -C prefix before commit --amend does not defeat detection (evaluated against the hook's cwd, not the -C target)" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C /repo commit --amend"}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_asks \
  "amend with --no-edit still detected" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit --amend --no-edit"}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_silent \
  "a later --no-amend overrides an earlier --amend (git last-flag-wins)" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit --amend --no-amend --allow-empty -m x"}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_asks \
  "a later --amend overrides an earlier --no-amend (git last-flag-wins)" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit --no-amend --amend"}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_asks \
  "the unambiguous abbreviation --am is detected as --amend" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit --am"}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_asks \
  "the unambiguous abbreviation --amen is detected as --amend" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit --amen"}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_silent \
  "the ambiguous prefix --a is not treated as --amend" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit --a"}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_silent \
  "the unambiguous abbreviation --no-am overrides --amend (git last-flag-wins)" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit --amend --no-am --allow-empty -m x"}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_asks \
  "a commit message literally reading --no-amend is not misread as the real flag (real --amend still detected)" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit --amend -m \"--no-amend\""}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_silent \
  "a commit message literally reading --amend is not misread as the real flag (no real amend, stays silent)" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"--amend\""}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_asks \
  "amend wrapped in sh -c still detected" \
  '{"tool_name":"Bash","tool_input":{"command":"sh -c \"git commit --amend\""}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_asks \
  "a paren-wrapped amend with a quoted multi-word flag-like message does not lose its quote boundary" \
  '{"tool_name":"Bash","tool_input":{"command":"(git commit --amend -m \"flag looks --no-amend\")"}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_asks \
  "a wrapper composed with a shell (sudo sh -c ...) still detects the real amend" \
  '{"tool_name":"Bash","tool_input":{"command":"sudo sh -c \"git commit --amend\""}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_asks \
  "a subshell with a && separator still detects the real amend as its own command" \
  '{"tool_name":"Bash","tool_input":{"command":"(cd /tmp && git commit --amend)"}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent feat/other" assert_reason_includes \
  "three or more shared branches use plural verb agreement" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit --amend"}}' \
  "also point at"

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_asks \
  "qualified /usr/bin/git path still detected" \
  '{"tool_name":"Bash","tool_input":{"command":"/usr/bin/git commit --amend"}}'

GIT_STUB_BRANCH=HEAD assert_silent \
  "detached HEAD skipped" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit --amend"}}'

GIT_REVPARSE_FAIL=1 assert_asks \
  "unverifiable current branch asks" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit --amend"}}'

GIT_STUB_BRANCH=feat/child GIT_POINTSAT_FAIL=1 assert_asks \
  "unverifiable points-at asks" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit --amend"}}'

GIT_STUB_BRANCH=feat/child GIT_STUB_POINTS_AT="feat/child feat/parent" assert_asks \
  "excessively nested eval fails closed" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$(node -e 'console.log(JSON.stringify("eval \"".repeat(9) + "git commit --amend" + "\"".repeat(9)))')}}"

assert_silent "malformed stdin allowed" 'not json'
assert_silent "non-Bash tool allowed" '{"tool_name":"Read","tool_input":{"file_path":"/x"}}'

echo "PASS: amend-shared-commit-guard"
