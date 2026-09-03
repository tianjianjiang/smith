#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../gh-stack-guard.mjs"

SHIM="$(mktemp -d)"
trap 'rm -rf "$SHIM"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

cat > "$SHIM/gh" <<'EOF'
#!/bin/sh
case "$*" in
  *"extension list"*)
    [ "${GH_STACK_INSTALLED:-0}" = "1" ] && printf 'gh stack\tgithub/gh-stack\tv0.1.0\n'
    ;;
  *) : ;;
esac
EOF
cat > "$SHIM/git" <<'EOF'
#!/bin/sh
[ "${GIT_NO_DEFAULT:-0}" = "1" ] && case "$*" in *symbolic-ref*|*"origin/HEAD"*) exit 1 ;; esac
case "$*" in
  *symbolic-ref*) echo "origin/${GIT_DEFAULT_BRANCH:-main}" ;;
  *"rev-parse --abbrev-ref origin/HEAD"*) echo "origin/${GIT_DEFAULT_BRANCH:-main}" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$SHIM/gh" "$SHIM/git"
export PATH="$SHIM:$PATH"

GIT_ONLY="$(mktemp -d)"
cp "$SHIM/git" "$GIT_ONLY/git"
chmod +x "$GIT_ONLY/git"
NODE="$(command -v node)"

run() { printf '%s' "$2" | node "$HOOK"; }
advises() {
  out=$(run "$1" "$2") || fail "$1: hook crashed"
  echo "$out" | grep -q 'gh-stack-guard' || fail "$1: expected advisory, got: $out"
}
silent() {
  out=$(run "$1" "$2") || fail "$1: hook crashed"
  [ -z "$out" ] || fail "$1: expected silent, got: $out"
}

GH_STACK_INSTALLED=1 advises "gh pr create with non-default base advises" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr create --base feature-x --head child"}}'
GH_STACK_INSTALLED=1 advises "gh pr create --base=form advises" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr create --base=feature-x"}}'
GH_STACK_INSTALLED=1 advises "git rebase --onto advises" \
  '{"tool_name":"Bash","tool_input":{"command":"git rebase --onto origin/main feat/parent feat/child"}}'
GH_STACK_INSTALLED=1 advises "chained gh pr create advises" \
  '{"tool_name":"Bash","tool_input":{"command":"cd /repo && gh pr create --base feature-x"}}'
GH_STACK_INSTALLED=1 advises "gh pr create -B short base flag advises" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr create -B feature-x --head child"}}'
GH_STACK_INSTALLED=1 advises "env-prefixed gh pr create advises" \
  '{"tool_name":"Bash","tool_input":{"command":"GH_HOST=github.com gh pr create --base feature-x"}}'
GH_STACK_INSTALLED=1 advises "env-prefixed git rebase --onto advises" \
  '{"tool_name":"Bash","tool_input":{"command":"GIT_EDITOR=true git rebase --onto origin/main feat/parent feat/child"}}'
GH_STACK_INSTALLED=1 advises "git -C with quoted path containing spaces advises" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C \"/repo with spaces\" rebase --onto origin/main feat/parent feat/child"}}'

GH_STACK_INSTALLED=1 silent "base equal to default branch is not stacked" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr create --base main --head child"}}'
GH_STACK_INSTALLED=1 silent "gh pr create without base is silent" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title x"}}'
GH_STACK_INSTALLED=1 silent "echoed gh pr create is not an invocation" \
  '{"tool_name":"Bash","tool_input":{"command":"echo gh pr create --base feature-x"}}'
GH_STACK_INSTALLED=1 silent "unrelated command is silent" \
  '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
GH_STACK_INSTALLED=1 silent "non-Bash tool is silent" \
  '{"tool_name":"Read","tool_input":{"file_path":"/x"}}'
GH_STACK_INSTALLED=1 silent "malformed stdin is silent" 'not json'
GH_STACK_INSTALLED=1 GIT_NO_DEFAULT=1 silent "unresolvable default branch stays silent" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr create --base feature-x"}}'
unset GIT_NO_DEFAULT

GH_STACK_INSTALLED=0 silent "no native stack extension installed stays silent" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr create --base feature-x"}}'

out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh pr create --base feature-x"}}' \
  | PATH="$GIT_ONLY" "$NODE" "$HOOK") || fail "gh missing: hook crashed"
[ -z "$out" ] || fail "gh missing (ENOENT) should stay silent, got: $out"

echo "PASS: gh-stack-guard"
