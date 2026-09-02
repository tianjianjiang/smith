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

echo "PASS: write-checkpoint"
