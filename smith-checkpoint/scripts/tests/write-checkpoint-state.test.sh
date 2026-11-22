#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../write-checkpoint.sh"
STATE_SCRIPT="$HERE/../../../smith-ctx-claude/scripts/ctx-reset-state.sh"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: write-checkpoint-state - $1"; }

install_fake_stores() {
  cat > "$1/uvx" <<'EOF'
#!/bin/bash
value_after() {
  local token="$1" found=0 arg
  shift
  for arg in "$@"; do
    [ "$found" = 1 ] && { printf '%s' "$arg"; return 0; }
    [ "$arg" = "$token" ] && found=1
  done
}
store_of() { printf '%s/store_%s_%s' "$FAKE_STORE_DIR" "$1" "$(printf '%s' "$2" | tr -c 'A-Za-z0-9_.-' '_')"; }
argv="$(basename "$0") $*"
case "$argv" in
  *"serena memories read"*)
    label=$(value_after read "$@")
    store=$(store_of serena "$label")
    [ -f "$store" ] || { echo "Memory named '$label' not found" >&2; exit 1; }
    cat "$store"
    ;;
  *"serena memories write"*)
    value_after --content "$@" > "$(store_of serena "$(value_after write "$@")")"
    ;;
  *"basic-memory tool read --help"*) ;;
  *"basic-memory tool read "*)
    title=$(value_after read "$@")
    title="${title##*/}"
    store=$(store_of bm "$title")
    [ -f "$store" ] || { printf 'Error: {"error": "NOT_FOUND", "message": "No note matches %s"}\n' "$title" >&2; exit 1; }
    jq -Rs --arg title "$title" --arg file_path "$(cat "$store.folder")/$title.md" '{title: $title, file_path: $file_path, content: .}' < "$store"
    ;;
  *"basic-memory tool write "*)
    title=$(value_after --title "$@")
    folder=$(value_after --directory "$@")
    store=$(store_of bm "$title")
    value_after --content "$@" > "$store"
    printf '%s' "$folder" > "$store.folder"
    printf '{"action": "updated", "permalink": "%s/%s"}\n' "$folder" "$title"
    ;;
esac
exit 0
EOF
  chmod +x "$1/uvx"
  ln -s uvx "$1/basic-memory"
}

new_sandbox() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/claude-home/plans" "$TMP/bin" "$TMP/stores" "$TMP/work"
  install_fake_stores "$TMP/bin"
  export PATH="$TMP/bin:$ORIGINAL_PATH"
  export FAKE_STORE_DIR="$TMP/stores"
  export CLAUDE_CONFIG_DIR="$TMP/claude-home"
  export _SMITH_PPID=12345
  unset BASIC_MEMORY_CONFIG_DIR BASIC_MEMORY_HOME BASIC_MEMORY_MCP_PROJECT CLAUDE_CODE_SESSION_ID
}

checkpoint() {
  (cd "$TMP/work" && bash "$1" "$2" 2>"$TMP/stderr")
}

ORIGINAL_PATH="$PATH"

new_sandbox
OUT=$(CLAUDE_CODE_SESSION_ID=s1 checkpoint "$SCRIPT" test_label_state) || fail "the checkpoint should succeed: $(cat "$TMP/stderr")"
RESTORE_FLAG=$(find "$CLAUDE_CONFIG_DIR/plans" -name '.pending-memory-restore-*')
[ -n "$RESTORE_FLAG" ] || fail "the checkpoint should write a restore flag: $OUT"
[ "$("$STATE_SCRIPT" s1 show)" = "state=checkpointed" ] || fail "a checkpoint written with no recorded start should record the session as checkpointed, got $("$STATE_SCRIPT" s1 show)"
[ "$("$STATE_SCRIPT" s1 show-field label)" = test_label_state ] || fail "the record should carry the checkpoint label, got $("$STATE_SCRIPT" s1 show-field label)"
[ "$("$STATE_SCRIPT" s1 show-field flag)" = "$RESTORE_FLAG" ] || fail "the record should carry the restore flag path $RESTORE_FLAG, got $("$STATE_SCRIPT" s1 show-field flag)"
pass "a checkpoint written with no recorded start records the session as checkpointed with its label and restore flag"

new_sandbox
checkpoint "$SCRIPT" test_label_nosession > /dev/null || fail "a checkpoint without a session id should succeed: $(cat "$TMP/stderr")"
[ -z "$(find "$CLAUDE_CONFIG_DIR/plans" -name '.ctx-reset-state-*')" ] || fail "a checkpoint without a session id should record no state"
pass "a checkpoint without a session id succeeds and records no state"

new_sandbox
LONE_TREE="$TMP/lone-tree"
mkdir -p "$LONE_TREE/smith-checkpoint/scripts"
cp "$SCRIPT" "$HERE/../audit-checkpoint.sh" "$LONE_TREE/smith-checkpoint/scripts/"
CLAUDE_CODE_SESSION_ID=s1 checkpoint "$LONE_TREE/smith-checkpoint/scripts/write-checkpoint.sh" test_label_nostatescript > /dev/null || fail "a missing state script should not fail the checkpoint: $(cat "$TMP/stderr")"
grep -q 'not recorded in the session state' "$TMP/stderr" || fail "a missing state script should be reported on stderr: $(cat "$TMP/stderr")"
pass "a missing state script is reported and does not fail the checkpoint"

new_sandbox
TREE="$TMP/tree"
mkdir -p "$TREE/smith-checkpoint/scripts" "$TREE/smith-ctx-claude/scripts"
cp "$SCRIPT" "$HERE/../audit-checkpoint.sh" "$TREE/smith-checkpoint/scripts/"
printf '#!/bin/bash\necho "state script broken" >&2\nexit 1\n' > "$TREE/smith-ctx-claude/scripts/ctx-reset-state.sh"
chmod +x "$TREE/smith-ctx-claude/scripts/ctx-reset-state.sh"
CLAUDE_CODE_SESSION_ID=s1 checkpoint "$TREE/smith-checkpoint/scripts/write-checkpoint.sh" test_label_brokenstate > /dev/null || fail "a failing state script should not fail the checkpoint: $(cat "$TMP/stderr")"
grep -q 'state script broken' "$TMP/stderr" || fail "a failing state script should be reported on stderr: $(cat "$TMP/stderr")"
[ -s "$FAKE_STORE_DIR/store_serena_test_label_brokenstate" ] || fail "a failing state script should leave the Serena entry written"
pass "a failing state script is reported and does not fail the checkpoint"

new_sandbox
"$STATE_SCRIPT" s1 checkpoint-started > /dev/null
CLAUDE_CODE_SESSION_ID=s1 checkpoint "$SCRIPT" test_label_started > /dev/null || fail "the checkpoint after its start was recorded should succeed: $(cat "$TMP/stderr")"
RESTORE_FLAG=$(find "$CLAUDE_CONFIG_DIR/plans" -name '.pending-memory-restore-*')
[ "$("$STATE_SCRIPT" s1 show)" = "state=checkpointed" ] || fail "a checkpoint written during its recorded procedure should record checkpointed, got $("$STATE_SCRIPT" s1 show)"
[ "$("$STATE_SCRIPT" s1 show-field label)" = test_label_started ] || fail "the record should carry the label, got $("$STATE_SCRIPT" s1 show-field label)"
[ "$("$STATE_SCRIPT" s1 show-field flag)" = "$RESTORE_FLAG" ] || fail "the record should carry the restore flag $RESTORE_FLAG, got $("$STATE_SCRIPT" s1 show-field flag)"
[ -n "$("$STATE_SCRIPT" s1 show-field written_at)" ] || fail "the record should carry the write time"
pass "a checkpoint written after its start was recorded records the label, the restore flag and the write time"

new_sandbox
"$STATE_SCRIPT" s1 checkpoint-written label=test_label_handed_on flag= > /dev/null
"$STATE_SCRIPT" s1 stop high=1 active=0 dispatch=on worked=0 > /dev/null
CLAUDE_CODE_SESSION_ID=s1 checkpoint "$SCRIPT" test_label_unrecorded > /dev/null || fail "a checkpoint the state does not record should still succeed: $(cat "$TMP/stderr")"
grep -q 'unspecified - continued' "$TMP/stderr" || fail "a state answer other than the recorded checkpoint should be reported on stderr: $(cat "$TMP/stderr")"
pass "a state answer that does not record the checkpoint is reported and does not fail the checkpoint"

new_sandbox
CLAUDE_CODE_SESSION_ID=s1 checkpoint "$SCRIPT" test_label_first > /dev/null || fail "the first checkpoint should succeed: $(cat "$TMP/stderr")"
CLAUDE_CODE_SESSION_ID=s1 checkpoint "$SCRIPT" test_label_second > /dev/null || fail "the second checkpoint should succeed: $(cat "$TMP/stderr")"
grep -q 'did not record the checkpoint' "$TMP/stderr" && fail "the second checkpoint should be recorded: $(cat "$TMP/stderr")"
[ "$("$STATE_SCRIPT" s1 show-field label)" = test_label_second ] || fail "the record should carry the second label, got $("$STATE_SCRIPT" s1 show-field label)"
RECORDED_FLAG=$("$STATE_SCRIPT" s1 show-field flag)
[ -f "$RECORDED_FLAG" ] || fail "the recorded restore flag should exist: $RECORDED_FLAG"
[ "$(sed -n '4p' "$RECORDED_FLAG")" = test_label_second ] || fail "the recorded restore flag should name the second label: $RECORDED_FLAG"
pass "a second checkpoint written in the same session replaces the recorded label and restore flag"
