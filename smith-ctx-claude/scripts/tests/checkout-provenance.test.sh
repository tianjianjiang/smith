#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib/checkout-provenance.mjs"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
export GIT_CEILING_DIRECTORIES="$TMP"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: checkout-provenance - $1"; }

provenance() {
  node --input-type=module -e 'const { checkoutProvenance, provenanceWasRead } = await import(process.argv[1]); const found = checkoutProvenance(process.argv[2], process.argv[3]); console.log(JSON.stringify({ ...found, wasRead: provenanceWasRead(found) }));' "$LIB" "$1" "$2"
}

expect() {
  local description=$1 output=$2 filter=$3
  jq -e "$filter" <<<"$output" >/dev/null || fail "$description: $filter does not hold for $output"
}

REPO="$TMP/repo"
mkdir -p "$REPO/scripts"
git -C "$REPO" init -q || fail "the fixture repository could not be created"
printf 'echo hook\n' > "$REPO/scripts/hook.sh"
git -C "$REPO" add scripts/hook.sh || fail "the fixture hook could not be staged"
git -C "$REPO" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m fixture || fail "the fixture commit failed"
COMMIT=$(git -C "$REPO" rev-parse HEAD)
HOOK_SHA=$(shasum -a 256 "$REPO/scripts/hook.sh" | cut -d' ' -f1)

OUT=$(provenance "$REPO" "$REPO/scripts/hook.sh")
expect "a clean checkout" "$OUT" ".commit == \"$COMMIT\""
expect "a clean checkout" "$OUT" '.treeIsDirty == false'
expect "a clean checkout" "$OUT" ".hookSha256 == \"$HOOK_SHA\""
expect "a clean checkout" "$OUT" '.wasRead == true'
pass "a clean checkout names its commit, a clean tree and the hook's SHA-256"

OTHER="$TMP/other"
mkdir -p "$OTHER"
git -C "$OTHER" init -q || fail "the second fixture repository could not be created"
git -C "$OTHER" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q --allow-empty -m other || fail "the second fixture commit failed"
printf 'note\n' > "$OTHER/untracked.txt"
OUT=$(GIT_DIR="$OTHER/.git" GIT_WORK_TREE="$OTHER" GIT_INDEX_FILE="$OTHER/.git/index" provenance "$REPO" "$REPO/scripts/hook.sh")
expect "inherited repository overrides" "$OUT" ".commit == \"$COMMIT\""
expect "inherited repository overrides" "$OUT" '.treeIsDirty == false'
pass "inherited GIT_DIR, GIT_WORK_TREE and GIT_INDEX_FILE do not move the reads to another repository"

for OVERRIDE in "GIT_COMMON_DIR=$OTHER/.git" "GIT_OBJECT_DIRECTORY=$OTHER/.git/objects"; do
  OUT=$(export "$OVERRIDE"; provenance "$REPO" "$REPO/scripts/hook.sh")
  expect "inherited ${OVERRIDE%%=*}" "$OUT" '.treeIsDirty == false'
  expect "inherited ${OVERRIDE%%=*}" "$OUT" '.wasRead == true'
done
pass "inherited GIT_COMMON_DIR and GIT_OBJECT_DIRECTORY do not make the status read fail"

printf 'note\n' > "$REPO/untracked.txt"
OUT=$(provenance "$REPO" "$REPO/scripts/hook.sh")
expect "an untracked file" "$OUT" '.treeIsDirty == true'
pass "an untracked file marks the tree dirty"
rm "$REPO/untracked.txt"

printf 'echo changed\n' > "$REPO/scripts/hook.sh"
CHANGED_SHA=$(shasum -a 256 "$REPO/scripts/hook.sh" | cut -d' ' -f1)
OUT=$(provenance "$REPO" "$REPO/scripts/hook.sh")
expect "a changed hook" "$OUT" '.treeIsDirty == true'
expect "a changed hook" "$OUT" ".hookSha256 == \"$CHANGED_SHA\""
pass "a changed hook marks the tree dirty and hashes the file as it is on disk"

NOT_A_REPO="$TMP/plain"
mkdir -p "$NOT_A_REPO"
git -C "$NOT_A_REPO" rev-parse 2>/dev/null && fail "the folder outside a repository is inside one"
OUT=$(provenance "$NOT_A_REPO" "$NOT_A_REPO/missing.sh")
expect "outside a repository" "$OUT" '.commit == "unknown"'
expect "outside a repository" "$OUT" '.treeIsDirty == null'
expect "a missing hook" "$OUT" '.hookSha256 == "unknown"'
expect "outside a repository" "$OUT" '.wasRead == false'
pass "outside a repository and with a missing hook nothing counts as read"
