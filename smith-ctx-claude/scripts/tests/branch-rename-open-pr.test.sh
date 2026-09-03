#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../branch-rename-open-pr.mjs"

SHIM="$(mktemp -d)"
trap 'rm -rf "$SHIM"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

cat > "$SHIM/gh" <<'EOF'
#!/bin/sh
[ "${GH_STUB_FAIL:-0}" = "1" ] && exit 1
head=""
state=""
while [ $# -gt 0 ]; do
  case "$1" in
    --head) head="$2"; shift 2 ;;
    --state) state="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ "${GH_STUB_OPEN:-0}" = "1" ] && [ -n "$head" ] && [ "$state" = "open" ] \
   && { [ -z "${EXPECT_HEAD:-}" ] || [ "$head" = "$EXPECT_HEAD" ]; }; then
  echo '[{"number":42}]'
else
  echo '[]'
fi
EOF
cat > "$SHIM/git" <<'EOF'
#!/bin/sh
case "$*" in
  *"rev-parse --abbrev-ref HEAD"*)
    [ "${GIT_REVPARSE_FAIL:-0}" = "1" ] && exit 1
    echo "${GIT_STUB_BRANCH:-feature}" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$SHIM/gh" "$SHIM/git"
export PATH="$SHIM:$PATH"

GIT_ONLY="$(mktemp -d)"
cp "$SHIM/git" "$GIT_ONLY/git"
chmod +x "$GIT_ONLY/git"
NODE="$(command -v node)"

assert_exit() {
  printf '%s' "$2" | node "$HOOK" >/dev/null 2>&1
  got=$?
  [ "$got" = "$3" ] || fail "$1 (expected exit $3, got $got)"
}

assert_asks() {
  out=$(printf '%s' "$2" | node "$HOOK") || fail "$1: hook crashed"
  echo "$out" | grep -q '"permissionDecision":"ask"' || fail "$1: expected ask, got: $out"
}

GH_STUB_OPEN=1 EXPECT_HEAD=feature assert_exit "rename current branch with open PR blocks" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -m newname"}}' 2
GH_STUB_OPEN=1 EXPECT_HEAD=oldname assert_exit "rename old to new queries the old head and blocks" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -m oldname newname"}}' 2
GH_STUB_OPEN=1 EXPECT_HEAD=feature assert_exit "git -C before branch still blocks" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C /repo branch -m newname"}}' 2
GH_STUB_OPEN=1 EXPECT_HEAD=feature assert_exit "git -c option before branch still blocks" \
  '{"tool_name":"Bash","tool_input":{"command":"git -c user.name=x branch -m newname"}}' 2
GH_STUB_OPEN=1 EXPECT_HEAD=oldname assert_exit "quoted branch names strip quotes and block" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -m \"oldname\" \"newname\""}}' 2
GH_STUB_OPEN=1 EXPECT_HEAD=oldname assert_exit "rename after earlier non-rename branch blocks" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -a; git branch -m oldname newname"}}' 2
GH_STUB_OPEN=1 EXPECT_HEAD=feature assert_exit "chained rename blocks" \
  '{"tool_name":"Bash","tool_input":{"command":"cd /repo && git branch -m newname"}}' 2
GH_STUB_OPEN=1 EXPECT_HEAD=feature assert_exit "force rename -M blocks" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -M newname"}}' 2
GH_STUB_OPEN=1 EXPECT_HEAD=feature assert_exit "long-form --move blocks" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch --move newname"}}' 2
GH_STUB_OPEN=1 EXPECT_HEAD=feature assert_exit "newline-joined multiline rename blocks" \
  '{"tool_name":"Bash","tool_input":{"command":"git add -A\ngit commit -m wip\ngit branch -m newname"}}' 2
GH_STUB_OPEN=1 EXPECT_HEAD=feature assert_exit "env-prefixed rename blocks" \
  '{"tool_name":"Bash","tool_input":{"command":"GIT_EDITOR=true git branch -m newname"}}' 2
GH_STUB_OPEN=1 EXPECT_HEAD=feature assert_exit "git -C with quoted path containing spaces blocks" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C \"/repo with spaces\" branch -m newname"}}' 2

GH_STUB_OPEN=0 assert_exit "rename without open PR allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -m newname"}}' 0

GH_STUB_FAIL=1 assert_asks "unverifiable PR state on rename asks" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -m newname"}}'

GH_STUB_OPEN=1 GIT_REVPARSE_FAIL=1 assert_asks "unverifiable current branch asks" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -m newname"}}'

GIT_STUB_BRANCH=HEAD assert_exit "detached HEAD rename is skipped" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -m newname"}}' 0

assert_exit "null stdin allowed" 'null' 0

unset GH_STUB_FAIL GIT_REVPARSE_FAIL GIT_STUB_BRANCH

out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git branch -m newname"}}' | PATH="$GIT_ONLY" "$NODE" "$HOOK") \
  || fail "gh missing: hook crashed"
[ -z "$out" ] || fail "gh missing (ENOENT) should allow silently, got: $out"

GH_STUB_OPEN=1 assert_exit "create branch allowed even when an open PR exists" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch newname"}}' 0
GH_STUB_OPEN=1 assert_exit "git status allowed even when an open PR exists" \
  '{"tool_name":"Bash","tool_input":{"command":"git status"}}' 0
GH_STUB_OPEN=1 assert_exit "echoed git branch is not a rename" \
  '{"tool_name":"Bash","tool_input":{"command":"echo git branch -m x"}}' 0
GH_STUB_OPEN=1 assert_exit "non-Bash tool allowed" \
  '{"tool_name":"Read","tool_input":{"file_path":"/x"}}' 0
GH_STUB_OPEN=1 assert_exit "malformed stdin allowed" 'not json' 0

echo "PASS: branch-rename-open-pr"
