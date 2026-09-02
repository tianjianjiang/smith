#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../write-checkpoint.sh"

SHIM="$(mktemp -d)"
trap 'rm -rf "$SHIM"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

cat > "$SHIM/uvx" <<'EOF'
#!/bin/sh
argv="$*"
content=""
while [ $# -gt 0 ]; do
  case "$1" in
    --content) content="$2"; shift ;;
  esac
  shift
done
case "$argv" in
  *"serena memories write"*)
    printf '%s\n' "$argv" > "$UVX_LOG_DIR/serena.argv"
    printf '%s' "$content" > "$UVX_LOG_DIR/serena.content" ;;
  *"basic-memory tool write-note"*)
    printf '%s\n' "$argv" > "$UVX_LOG_DIR/bm.argv"
    printf '%s' "$content" > "$UVX_LOG_DIR/bm.content"
    [ "${BM_FAIL:-0}" = "1" ] && { echo "NOTE_ALREADY_EXISTS" >&2; exit 1; }
    echo '{"permalink": "smith/projects/smith/test-label"}' ;;
esac
exit 0
EOF
chmod +x "$SHIM/uvx"
export PATH="$SHIM:$PATH"
export UVX_LOG_DIR="$SHIM"

run_script() {
  (cd "$SHIM" && bash "$SCRIPT" test_label "plan=/tmp/plan.md")
}

out=$(run_script 2>"$SHIM/stderr") || fail "success path: script exited non-zero: $(cat "$SHIM/stderr")"
grep -q -- '--overwrite' "$SHIM/bm.argv" || fail "write-note argv missing --overwrite: $(cat "$SHIM/bm.argv")"
cmp -s "$SHIM/serena.content" "$SHIM/bm.content" || fail "Serena and Basic-Memory received different content"
[ -s "$SHIM/serena.content" ] || fail "content passed to backends is empty"
echo "$out" | grep -q 'Basic-Memory: smith/projects/smith/test-label' || fail "reload block missing permalink: $out"

BM_FAIL=1 run_script >/dev/null 2>"$SHIM/stderr" && fail "failure path: script exited zero when write-note failed"
grep -q 'Basic-Memory write failed' "$SHIM/stderr" || fail "failure path: missing error message: $(cat "$SHIM/stderr")"

grep -q -- 'serena memories write test_label --content' "$SHIM/serena.argv" || fail "outside git: serena argv should carry no project: $(cat "$SHIM/serena.argv")"
grep -q -- '--folder projects/smith' "$SHIM/bm.argv" || fail "outside git: folder should default to projects/smith: $(cat "$SHIM/bm.argv")"

REPO="$SHIM/primary-repo"
git init -q "$REPO" && (cd "$REPO" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init)
git -C "$REPO" worktree add -q "$REPO/.claude/worktrees/wt" -b wt
PRIMARY="$(cd "$REPO" && pwd -P)"
wt_out=$(cd "$REPO/.claude/worktrees/wt" && BM_FAIL=0 bash "$SCRIPT" test_label "plan=/tmp/plan.md" 2>"$SHIM/stderr") || fail "worktree path: script exited non-zero: $(cat "$SHIM/stderr")"
echo "$wt_out" | grep -q 'Serena: test_label (primary-repo project)' || fail "reload block must name the resolved Serena project: $wt_out"
grep -qF -- "serena memories write test_label $PRIMARY --content" "$SHIM/serena.argv" || fail "worktree: serena argv should name the primary checkout: $(cat "$SHIM/serena.argv")"
grep -q -- '--folder projects/primary-repo' "$SHIM/bm.argv" || fail "worktree: folder should use the primary checkout name: $(cat "$SHIM/bm.argv")"

PLAN="$SHIM/groovy-greeting-pearl.md"
printf '# Fix checkpoint body — Plan\n\n- [x] done item\n- [ ] first pending\n- [ ] second pending\n' > "$PLAN"
BODY="$SHIM/body.md"
printf '## Completed\n- [x] resolved primary checkout (`write-checkpoint.sh:13`)\n\n## Related\n- Serena: `sibling_memory_name`\n' > "$BODY"

(cd "$SHIM" && BM_FAIL=0 bash "$SCRIPT" test_label "plan=$PLAN" "body=$BODY") >/dev/null 2>"$SHIM/stderr" || fail "body path: script exited non-zero: $(cat "$SHIM/stderr")"
grep -qF -- '- [x] resolved primary checkout (`write-checkpoint.sh:13`)' "$SHIM/serena.content" || fail "body file content missing from Serena payload: $(cat "$SHIM/serena.content")"
grep -q 'sibling_memory_name' "$SHIM/bm.content" || fail "body Related entries missing from Basic-Memory payload"
grep -qF -- "- Plan: $PLAN" "$SHIM/serena.content" || fail "plan path must still be listed under Related"
[ "$(grep -c '^## Related' "$SHIM/serena.content")" = 1 ] || fail "Related heading must appear exactly once: $(cat "$SHIM/serena.content")"
grep -qi 'zero tokens' "$SHIM/serena.content" && fail "placeholder sentence must not appear when a body is given"
cmp -s "$SHIM/serena.content" "$SHIM/bm.content" || fail "body path: Serena and Basic-Memory received different content"

(cd "$SHIM" && BM_FAIL=0 bash "$SCRIPT" test_label "plan=$PLAN") >/dev/null 2>"$SHIM/stderr" || fail "no-body path: script exited non-zero: $(cat "$SHIM/stderr")"
grep -q 'Fix checkpoint body' "$SHIM/serena.content" || fail "no-body fallback must carry the plan title: $(cat "$SHIM/serena.content")"
grep -qF -- '- [ ] first pending' "$SHIM/serena.content" || fail "no-body fallback must list pending plan items"
grep -qF -- '- [x] done item' "$SHIM/serena.content" && fail "no-body fallback must not list completed plan items"
grep -qi 'zero tokens' "$SHIM/serena.content" && fail "placeholder sentence must not appear in the fallback body"
grep -qi 'Load context from plan file' "$SHIM/serena.content" && fail "placeholder next-step sentence must not appear in the fallback body"

BODY_MID="$SHIM/body-related-mid.md"
printf '## Completed\n- [x] thing\n\n## Related\n- Serena: `sibling`\n\n## Next\nresume here\n' > "$BODY_MID"
(cd "$SHIM" && BM_FAIL=0 bash "$SCRIPT" test_label "plan=$PLAN" "body=$BODY_MID") >/dev/null 2>"$SHIM/stderr" || fail "related-mid path: script exited non-zero: $(cat "$SHIM/stderr")"
plan_line_no=$(grep -n -F -- "- Plan: $PLAN" "$SHIM/serena.content" | cut -d: -f1)
next_line_no=$(grep -n '^## Next' "$SHIM/serena.content" | cut -d: -f1)
[ -n "$plan_line_no" ] && [ -n "$next_line_no" ] && [ "$plan_line_no" -lt "$next_line_no" ] || fail "plan line must be filed under Related, not after the last section: $(cat "$SHIM/serena.content")"
[ "$(grep -c '^## Related' "$SHIM/serena.content")" = 1 ] || fail "related-mid: Related heading must appear exactly once"

rm -f "$SHIM/serena.content" "$SHIM/bm.content"
(cd "$SHIM" && BM_FAIL=0 bash "$SCRIPT" test_label "plan=$PLAN" "body=$SHIM/does-not-exist.md") >/dev/null 2>"$SHIM/stderr" && fail "missing body file must make the script exit non-zero"
grep -q 'body file not found' "$SHIM/stderr" || fail "missing body file must be reported: $(cat "$SHIM/stderr")"
[ ! -e "$SHIM/serena.content" ] || fail "missing body file must not write to Serena"
[ ! -e "$SHIM/bm.content" ] || fail "missing body file must not write to Basic-Memory"

(cd "$SHIM" && BM_FAIL=0 bash "$SCRIPT" test_label "plan=$PLAN" "body=") >/dev/null 2>"$SHIM/stderr" && fail "empty body= value must make the script exit non-zero"
grep -q 'body file not found' "$SHIM/stderr" || fail "empty body= value must be reported: $(cat "$SHIM/stderr")"
[ ! -e "$SHIM/serena.content" ] || fail "empty body= value must not write to Serena"

printf '\n  \n' > "$SHIM/blank-body.md"
(cd "$SHIM" && BM_FAIL=0 bash "$SCRIPT" test_label "plan=$PLAN" "body=$SHIM/blank-body.md") >/dev/null 2>"$SHIM/stderr" && fail "blank body file must make the script exit non-zero"
grep -q 'body file is empty' "$SHIM/stderr" || fail "blank body file must be reported: $(cat "$SHIM/stderr")"
[ ! -e "$SHIM/serena.content" ] || fail "blank body file must not write to Serena"

(cd "$SHIM" && BM_FAIL=0 bash "$SCRIPT" test_label "body=$BODY") >/dev/null 2>"$SHIM/stderr" || fail "no-plan path: script exited non-zero: $(cat "$SHIM/stderr")"
grep -q -- '^- Plan:' "$SHIM/serena.content" && fail "without plan= no Plan line may be emitted: $(cat "$SHIM/serena.content")"
grep -q '^\*\*Plan\*\*' "$SHIM/serena.content" && fail "without plan= the header must not carry an empty Plan line"
grep -q 'sibling_memory_name' "$SHIM/serena.content" || fail "no-plan path must still carry the body"

DONE_PLAN="$SHIM/all-done.md"
printf 'no heading\n- [x] everything done\n' > "$DONE_PLAN"
(cd "$SHIM" && BM_FAIL=0 bash "$SCRIPT" test_label "plan=$DONE_PLAN") >/dev/null 2>"$SHIM/stderr" || fail "fallback with no heading and no pending items must still succeed: $(cat "$SHIM/stderr")"
grep -q 'No session body was supplied' "$SHIM/serena.content" || fail "completed-plan fallback must carry the status sentence"
grep -q '^## Pending' "$SHIM/serena.content" && fail "completed plan must not emit a Pending section"

(cd "$SHIM" && BM_FAIL=0 bash "$SCRIPT" test_label "plan=$SHIM/missing-plan.md" "body=$BODY") >/dev/null 2>"$SHIM/stderr" || fail "missing plan= must not be fatal: $(cat "$SHIM/stderr")"
grep -q 'plan file not found' "$SHIM/stderr" || fail "missing plan= must be reported on stderr: $(cat "$SHIM/stderr")"

mkdir -p "$SHIM/body-dir"
(cd "$SHIM" && BM_FAIL=0 bash "$SCRIPT" test_label "plan=$PLAN" "body=$SHIM/body-dir") >/dev/null 2>"$SHIM/stderr" && fail "a directory passed as body= must fail"
grep -q 'not found or unreadable' "$SHIM/stderr" || fail "directory body= must be reported as not a readable file: $(cat "$SHIM/stderr")"

printf '## Related Work\n- other\n' > "$SHIM/body-related-work.md"
(cd "$SHIM" && BM_FAIL=0 bash "$SCRIPT" test_label "plan=$PLAN" "body=$SHIM/body-related-work.md") >/dev/null 2>"$SHIM/stderr" || fail "Related Work body: script exited non-zero: $(cat "$SHIM/stderr")"
[ "$(grep -c '^## Related$' "$SHIM/serena.content")" = 1 ] || fail "a heading that merely starts with Related must not absorb the Plan line: $(cat "$SHIM/serena.content")"

echo "PASS: write-checkpoint"
