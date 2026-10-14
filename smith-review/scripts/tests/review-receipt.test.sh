#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/../review-receipt.mjs"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

FULL_RECEIPT='coderabbit ran · /code-review ran · pr-review-toolkit:review-pr ran · security-review NA:docs · code-simplifier NA:docs'
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
tool() { (cd "$REPO" && node "$TOOL" "$@"); }
expect_pass() {
  out=$(tool check "$@") || fail "expected PASS, got: $out"
  echo "$out" | grep -q "^review-converged PASS" || fail "expected a PASS line, got: $out"
}
expect_fail() {
  out=$(tool check "$@") && fail "expected FAIL, got: $out"
  echo "$out" | grep -q "^review-converged FAIL" || fail "expected a FAIL line, got: $out"
}

commit_file base.txt 'base\n' base
repo_git push -q -u origin main
repo_git remote set-head origin main
git -C "$REPO" switch -q -c feature
commit_file feature.py 'def f():\n    return 1\n' feature

expect_fail
tool write 'coderabbit ran' >/dev/null 2>&1 && fail "an incomplete receipt line should be refused"
tool write "$FULL_RECEIPT · security-review NA:" >/dev/null 2>&1 && fail "an entry without a reason should be refused"
echo dirty > "$REPO/untracked.txt"
tool write "$FULL_RECEIPT" >/dev/null 2>&1 && fail "a receipt over a dirty tree should be refused"
rm "$REPO/untracked.txt"

tool write "$FULL_RECEIPT" >/dev/null || fail "a complete receipt over a clean tree should be written"
expect_pass
echo dirty > "$REPO/untracked.txt"
expect_fail
rm "$REPO/untracked.txt"

receipts="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/smith-review-receipts"
change_id="$(ls "$receipts")"
receipt_file="$receipts/$change_id"
cp "$receipt_file" "$TMPD/saved"
: > "$receipt_file"
expect_fail
printf '{"changeId":"%s","receipt":"coderabbit ran"}\n' "$change_id" > "$receipt_file"
expect_fail
printf '{"changeId":"another","receipt":"%s"}\n' "$FULL_RECEIPT" > "$receipt_file"
expect_fail
cp "$TMPD/saved" "$receipt_file"
expect_pass

repo_git commit -q --amend -m "feature, reworded"
expect_pass
commit_file feature.py 'def f():\n    return 1\n\ndef g():\n    return 2\n' "split commit"
expect_fail
repo_git reset -q --hard HEAD~1
expect_pass

git -C "$REPO" switch -q main
commit_file other.txt 'moves main\n' "moves main"
repo_git push -q origin main
git -C "$REPO" switch -q feature
repo_git rebase -q main || fail "rebase onto the new main failed"
expect_pass

printf 'def f():\n  return 1\n' > "$REPO/feature.py"
repo_git add feature.py
repo_git commit -q --amend --no-edit
expect_fail
tool write "$FULL_RECEIPT" >/dev/null || fail "re-indent receipt should be written"
expect_pass

git -C "$REPO" switch -q -c child
commit_file child.txt 'child\n' child
expect_fail --base feature
tool write "$FULL_RECEIPT" --base feature >/dev/null || fail "a stacked receipt should be written"
expect_pass --base feature
expect_fail

out=$(cd "$TMPD" && node "$TOOL" check) && fail "check outside a work tree should fail, got: $out"
echo "$out" | grep -q "^review-converged FAIL:not inside a git work tree" || fail "outside a work tree should say so, got: $out"

echo "PASS: review-receipt"
