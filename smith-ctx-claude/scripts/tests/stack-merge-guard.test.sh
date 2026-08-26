#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../stack-merge-guard.mjs"

SHIM="$(mktemp -d)"
trap 'rm -rf "$SHIM"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

cat > "$SHIM/gh" <<'EOF'
#!/bin/sh
[ "${GH_STUB_FAIL:-0}" = "1" ] && exit 1
if [ -n "${EXPECT_REPO:-}" ]; then
  case " $* " in
    *" -R $EXPECT_REPO "*) : ;;
    *) echo "FORWARDING-MISSED: $*" >&2; exit 1 ;;
  esac
fi
case "$*" in
  *"pr view"*"headRefName"*)
    [ "${GH_STUB_FAIL_VIEW:-0}" = "1" ] && exit 1
    if [ -n "${EXPECT_TARGET:-}" ]; then
      case " $* " in
        *" $EXPECT_TARGET "*) : ;;
        *) echo "TARGET-MISMATCH: $*" >&2; exit 1 ;;
      esac
    fi
    if [ -n "${REJECT_TARGET:-}" ]; then
      case " $* " in
        *" $REJECT_TARGET "*) echo "LEAKED-TARGET: $*" >&2; exit 1 ;;
      esac
    fi
    is_second_target=0
    if [ -n "${GH_STUB_SECOND_TARGET:-}" ]; then
      case " $* " in *" $GH_STUB_SECOND_TARGET "*) is_second_target=1 ;; esac
    fi
    if [ -n "${GH_STUB_VIEW_RAW:-}" ]; then
      printf '%s' "$GH_STUB_VIEW_RAW"
    elif [ "$is_second_target" = "1" ]; then
      echo '{"headRefName":"feat/second"}'
    else
      echo "{\"headRefName\":\"${GH_STUB_HEAD_REF:-feat/parent}\"}"
    fi ;;
  *"pr list"*)
    [ "${GH_STUB_FAIL_LIST:-0}" = "1" ] && exit 1
    if [ -n "${GH_STUB_LIST_RAW:-}" ]; then
      printf '%s' "$GH_STUB_LIST_RAW"
    elif [ -n "${GH_STUB_SECOND_TARGET:-}" ]; then
      case "$*" in *"--base feat/second"*) echo '[{"number":91}]' ;; *) echo '[]' ;; esac
    elif [ "${GH_STUB_CHILDREN:-0}" = "1" ]; then
      echo '[{"number":91}]'
    else
      echo '[]'
    fi ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$SHIM/gh"
export PATH="$SHIM:$PATH"

reset_stubs() {
  unset GH_STUB_FAIL GH_STUB_FAIL_VIEW GH_STUB_FAIL_LIST GH_STUB_CHILDREN \
    GH_STUB_HEAD_REF GH_STUB_VIEW_RAW GH_STUB_LIST_RAW EXPECT_REPO EXPECT_TARGET REJECT_TARGET \
    GH_STUB_SECOND_TARGET
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

GH_STUB_CHILDREN=1 assert_asks \
  "merge --delete-branch with an open child PR asks" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --squash --delete-branch"}}'

GH_STUB_CHILDREN=1 assert_reason_includes \
  "reason names the child PR number" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --squash --delete-branch"}}' \
  "#91"

GH_STUB_CHILDREN=1 assert_asks \
  "short -d flag detected" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 -sd"}}'

GH_STUB_CHILDREN=1 assert_silent \
  "short cluster without d is not treated as delete-branch" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 -s"}}'

GH_STUB_CHILDREN=1 assert_asks \
  "-d clustered before a value-taking short flag is still detected (-dt)" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge -dt subject 42"}}'

GH_STUB_CHILDREN=1 assert_silent \
  "-d clustered after a value-taking short flag is consumed as its value, not detected (-td)" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge -td 42"}}'

GH_STUB_CHILDREN=1 EXPECT_REPO=owner/repo EXPECT_TARGET=123 assert_reason_includes \
  "-d clustered with -R (-dR owner/repo) forwards the repo and does not misread the repo as the target" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge -dR owner/repo 123"}}' \
  "are based on it"

GH_STUB_CHILDREN=1 assert_asks \
  "current-branch merge (no positional target) checked" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --squash --delete-branch"}}'

GH_STUB_CHILDREN=0 assert_silent \
  "merge --delete-branch with no child PRs allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --squash --delete-branch"}}'

GH_STUB_CHILDREN=0 assert_silent \
  "merge without --delete-branch allowed regardless of children" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --squash"}}'

GH_STUB_CHILDREN=1 assert_silent \
  "non-merge gh pr command allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr view 42"}}'

GH_STUB_CHILDREN=1 GH_STUB_HEAD_REF=feat/parent assert_asks \
  "-R repo flag before target does not break target detection" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge -R owner/repo 42 --delete-branch"}}'

GH_STUB_CHILDREN=1 EXPECT_REPO=owner/repo assert_reason_includes \
  "-R repo flag is forwarded to the hook's own verification calls" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge -R owner/repo 42 --delete-branch"}}' \
  "are based on it"

GH_STUB_CHILDREN=1 EXPECT_REPO=owner/repo assert_reason_includes \
  "attached --repo=value form is split and forwarded" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --repo=owner/repo 42 --delete-branch"}}' \
  "are based on it"

GH_STUB_CHILDREN=1 EXPECT_REPO=owner/repo assert_reason_includes \
  "attached -Rowner/repo short form after pr merge is split and forwarded" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge -Rowner/repo 42 --delete-branch"}}' \
  "are based on it"

GH_STUB_CHILDREN=1 EXPECT_REPO=owner/repo assert_reason_includes \
  "attached -Rowner/repo short form before pr merge is recognized and forwarded" \
  '{"tool_name":"Bash","tool_input":{"command":"gh -Rowner/repo pr merge 42 --delete-branch"}}' \
  "are based on it"

GH_STUB_CHILDREN=1 EXPECT_REPO=owner/repo assert_reason_includes \
  "a global -R before the pr subcommand is recognized and forwarded" \
  '{"tool_name":"Bash","tool_input":{"command":"gh -R owner/repo pr merge 42 --delete-branch"}}' \
  "are based on it"

GH_STUB_CHILDREN=1 EXPECT_REPO=owner/repo assert_reason_includes \
  "a global --repo=value before the pr subcommand is recognized and forwarded" \
  '{"tool_name":"Bash","tool_input":{"command":"gh --repo=owner/repo pr merge 42 --delete-branch"}}' \
  "are based on it"

GH_STUB_CHILDREN=1 EXPECT_REPO=local/repo assert_reason_includes \
  "a local -R after pr merge overrides a global -R before it" \
  '{"tool_name":"Bash","tool_input":{"command":"gh -R global/repo pr merge -R local/repo 42 --delete-branch"}}' \
  "are based on it"

GH_STUB_CHILDREN=1 assert_reason_includes \
  "a -R value that is literally the string pr does not confuse subcommand detection" \
  '{"tool_name":"Bash","tool_input":{"command":"gh -R pr/pr pr merge 42 --delete-branch"}}' \
  "are based on it"

GH_STUB_CHILDREN=1 EXPECT_TARGET=91 assert_reason_includes \
  "a value-taking flag before the target is skipped, not misread as the target" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --body \"42 deep in the stack\" --delete-branch 91"}}' \
  "are based on it"

GH_STUB_FAIL=1 assert_asks \
  "unverifiable gh call asks" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --delete-branch"}}'

GH_STUB_FAIL_LIST=1 assert_asks \
  "the second gh call (pr list) failing alone still asks" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --delete-branch"}}'

GH_STUB_FAIL_LIST=1 assert_reason_includes \
  "the second-call failure reason names the head branch, not the PR target" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --delete-branch"}}' \
  "open PRs based on"

GH_STUB_VIEW_RAW="not valid json" assert_asks \
  "malformed (non-JSON) pr view output asks" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --delete-branch"}}'

GH_STUB_LIST_RAW="{}" assert_asks \
  "valid-JSON-but-non-array pr list output asks" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --delete-branch"}}'

GH_STUB_SECOND_TARGET=43 assert_reason_includes \
  "two chained merge --delete-branch invocations are both independently evaluated (only the second has a child PR)" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --delete-branch && gh pr merge 43 --delete-branch"}}' \
  "feat/second"

GH_STUB_CHILDREN=1 assert_silent \
  "--delete-branch=false is not treated as the flag being set" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --delete-branch=false"}}'

GH_STUB_CHILDREN=1 assert_silent \
  "--delete-branch=False (capitalized) is also recognized as negation" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --delete-branch=False"}}'

GH_STUB_CHILDREN=1 assert_silent \
  "--delete-branch=f (single-char) is also recognized as negation" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --delete-branch=f"}}'

GH_STUB_CHILDREN=1 assert_asks \
  "a later bare --delete-branch overrides an earlier --delete-branch=false (last occurrence wins)" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --delete-branch=false --delete-branch"}}'

GH_STUB_CHILDREN=1 assert_silent \
  "a later --delete-branch=false overrides an earlier bare --delete-branch (last occurrence wins)" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --delete-branch --delete-branch=false"}}'

GH_STUB_CHILDREN=1 assert_asks \
  "a -b/--body VALUE that literally reads --delete-branch=false is not misread as a real negation" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 -d -b \"--delete-branch=false\""}}'

GH_STUB_CHILDREN=1 assert_asks \
  "--delete-branch=true is treated as the flag being set" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --delete-branch=true"}}'

GH_STUB_CHILDREN=1 REJECT_TARGET=true assert_asks \
  "--delete-branch=true's split-off value is never misread as the PR target" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --delete-branch=true"}}'

GH_STUB_CHILDREN=1 assert_asks \
  "merge wrapped in bash -c still detected" \
  '{"tool_name":"Bash","tool_input":{"command":"bash -c \"gh pr merge 42 --delete-branch\""}}'

GH_STUB_CHILDREN=1 assert_asks \
  "qualified /usr/bin/gh path still detected" \
  '{"tool_name":"Bash","tool_input":{"command":"/usr/bin/gh pr merge 42 --delete-branch"}}'

GH_STUB_CHILDREN=1 assert_asks \
  "a wrapper composed with a shell (sudo sh -c ...) still detects the real merge" \
  '{"tool_name":"Bash","tool_input":{"command":"sudo sh -c \"gh pr merge 42 --delete-branch\""}}'

GH_STUB_CHILDREN=1 assert_asks \
  "a subshell with a && separator still detects the real merge as its own command" \
  '{"tool_name":"Bash","tool_input":{"command":"(cd /tmp && gh pr merge 42 --delete-branch)"}}'

GH_STUB_CHILDREN=1 assert_asks \
  "excessively nested eval fails closed" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$(node -e 'console.log(JSON.stringify("eval \"".repeat(9) + "gh pr merge 42 --delete-branch" + "\"".repeat(9)))')}}"

assert_silent "malformed stdin allowed" 'not json'
assert_silent "non-Bash tool allowed" '{"tool_name":"Read","tool_input":{"file_path":"/x"}}'

echo "PASS: stack-merge-guard"
