#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
PREFLIGHT="$ROOT/smith-preflight/SKILL.md"
PROBE_MARK='smith-review/scripts/review-receipt.mjs'
FULL_RECEIPT='coderabbit ran · /code-review ran · pr-review-toolkit:review-pr ran · security-review NA:docs · code-simplifier NA:docs'

fail() { echo "FAIL: preflight-probe: $1"; exit 1; }

[ -r "$PREFLIGHT" ] || fail "cannot read smith-preflight/SKILL.md"
case "$(grep -c -F -- "$PROBE_MARK" "$PREFLIGHT")" in
  0) fail "smith-preflight/SKILL.md no longer runs $PROBE_MARK" ;;
  1) ;;
  *) fail "smith-preflight/SKILL.md runs $PROBE_MARK on more than one line" ;;
esac
probe="$(grep -F -- "$PROBE_MARK" "$PREFLIGHT" | sed -n 's/^.*!`\(.*\)`$/\1/p')"
[ -n "$probe" ] \
  || fail "the $PROBE_MARK line is not a !\`command\` live-state probe"

TMPD="$(mktemp -d)" && [ -d "$TMPD" ] || fail "mktemp could not create a fixture folder"
mkdir -p "$TMPD/config" "$TMPD/empty-home" "$TMPD/home/.claude"
ln -s "$ROOT" "$TMPD/config/skills"
ln -s "$ROOT" "$TMPD/home/.claude/skills"
REPO="$TMPD/repo"
git init -q --bare -b main "$TMPD/remote.git"
git init -q -b main "$REPO"
git -C "$REPO" remote add origin "$TMPD/remote.git"
repo_git() { git -C "$REPO" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false "$@"; }
commit_file() {
  printf '%b' "$2" > "$REPO/$1"
  repo_git add "$1"
  repo_git commit -q -m "$3"
}
commit_file base.txt 'base\n' base
repo_git push -q -u origin main
repo_git remote set-head origin main
git -C "$REPO" switch -q -c feature
commit_file feature.txt 'change\n' feature

check_probe_output() {
  [ "$status" = 0 ] \
    || fail "with $2 and $3, the probe in smith-preflight/SKILL.md exited $status, got: $out"
  printf '%s\n' "$out" | grep -q -E "^review-converged $1([: ]|\$)" \
    || fail "with $2 and $3, the probe in smith-preflight/SKILL.md printed no 'review-converged $1' line, got: $out"
}
expect_probe() {
  out="$(cd "$REPO" && HOME="$TMPD/empty-home" CLAUDE_CONFIG_DIR="$TMPD/config" sh -c "$probe")"
  status=$?
  check_probe_output "$1" "$2" "CLAUDE_CONFIG_DIR set"
  out="$(cd "$REPO" && unset CLAUDE_CONFIG_DIR && HOME="$TMPD/home" sh -c "$probe")"
  status=$?
  check_probe_output "$1" "$2" "CLAUDE_CONFIG_DIR unset"
}

expect_probe FAIL "no review receipt"
(cd "$REPO" && node "$ROOT/$PROBE_MARK" write "$FULL_RECEIPT" >/dev/null) \
  || fail "review-receipt.mjs did not write the fixture receipt"
expect_probe PASS "a written receipt"

echo "PASS: preflight-probe"
