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

echo "PASS: write-checkpoint"
