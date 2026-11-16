#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
EVALS="$HERE/../../evals"
JUDGE="$EVALS/fixtures/scripts/check-anchor.sh"
EVAL_FILE="$EVALS/eval.yaml"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

[ -f "$JUDGE" ] || fail "the judge under test does not exist: $JUDGE"
IMAGE="$(sed -n 's/^  image: *//p' "$EVAL_FILE")"
[ -n "$IMAGE" ] || fail "$EVAL_FILE names no image"
docker info >/dev/null 2>&1 || fail "the judge runs inside $IMAGE during an eval, so this test needs a container runtime that answers"

LABEL="conflicting-rules-v1"
BLOB="0123456789abcdef0123456789abcdef01234567"

make_workspace() {
  WORKSPACE="$TMPD/$1"
  mkdir -p "$WORKSPACE/smith-guidance" "$WORKSPACE/smith-review" "$WORKSPACE/smith-ctx-claude"
  printf '%s\n' '# Guidance' '' "<a name=\"$LABEL\"></a>" '## Conflicting Rules' '' 'List both rules.' > "$WORKSPACE/smith-guidance/SKILL.md"
  printf '%s\n' '# Review' '' "See @smith-guidance/SKILL.md#$LABEL for conflicts." > "$WORKSPACE/smith-review/SKILL.md"
  printf 'label\tfile\tquestion\tblob\n%s\tsmith-guidance/SKILL.md\t-\t%s\n' "$LABEL" "$2" > "$WORKSPACE/smith-ctx-claude/anchors.lock"
  cp "$JUDGE" "$WORKSPACE/check-anchor.sh"
}

judge_on_host() { (cd "$WORKSPACE" && sh check-anchor.sh) >/dev/null 2>&1; }
judge_in_image() {
  tar -C "$WORKSPACE" -cf - . | docker run --rm -i --network none "$IMAGE" \
    sh -c 'mkdir /judged && tar -xf - -C /judged && cd /judged && sh check-anchor.sh' >/dev/null 2>&1
}
expect() {
  judge_on_host
  STATUS=$?
  [ "$STATUS" = "$1" ] || fail "$2: the judge must exit $1 on the host, got $STATUS"
  judge_in_image
  STATUS=$?
  [ "$STATUS" = "$1" ] || fail "$2: the judge must exit $1 in $IMAGE, got $STATUS"
}

make_workspace followed "$BLOB"
expect 0 "an anchor above the heading, a citation by fragment and a lock row"

make_workspace no-row "$BLOB"
printf 'label\tfile\tquestion\tblob\n' > "$WORKSPACE/smith-ctx-claude/anchors.lock"
expect 1 "a lock without the row"

make_workspace short-blob "0123456789abcdef"
expect 1 "a lock row whose blob is not forty hexadecimal characters"

make_workspace long-blob "${BLOB}0"
expect 1 "a lock row whose blob is longer than forty characters"

make_workspace heading-text "$BLOB"
printf '%s\n' '# Review' '' 'See the Conflicting Rules section of smith-guidance.' > "$WORKSPACE/smith-review/SKILL.md"
expect 1 "a citation by heading text"

make_workspace anchor-apart "$BLOB"
printf '%s\n' '# Guidance' '' "<a name=\"$LABEL\"></a>" '' '## Conflicting Rules' > "$WORKSPACE/smith-guidance/SKILL.md"
expect 1 "an anchor that is not on the line above a heading"

docker run --rm --network none "$IMAGE" sh -c 'command -v git' >/dev/null 2>&1 \
  || fail "$IMAGE must hold git: the lock tool the skill names hashes a section with it"

echo "PASS: check-anchor"
