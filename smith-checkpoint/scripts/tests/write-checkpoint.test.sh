#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../write-checkpoint.sh"

SHIM="$(mktemp -d)"
trap 'rm -rf "$SHIM"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

cat > "$SHIM/uvx" <<'EOF'
#!/bin/sh
argv="$*"

value_after() {
  token="$1"; shift
  found=0
  for arg in "$@"; do
    if [ "$found" = "1" ]; then
      printf '%s' "$arg"
      return 0
    fi
    [ "$arg" = "$token" ] && found=1
  done
}

store_key() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'
}

case "$argv" in
  *"serena memories read"*)
    label=$(value_after read "$@")
    printf '%s\n' "$argv" >> "$UVX_LOG_DIR/serena_read.argv"
    store="$UVX_LOG_DIR/store_serena_$(store_key "$label")"
    if [ "${SERENA_READ_BROKEN:-0}" = "1" ]; then
      echo "connection reset by peer" >&2
      exit 1
    fi
    if [ -f "$store" ]; then
      [ "${SERENA_READ_NOISE:-0}" = "1" ] && echo "Resolved 1 package in 3ms" >&2
      cat "$store"
      exit 0
    fi
    echo "Memory named '$label' not found" >&2
    exit 1
    ;;
  *"serena memories write"*)
    label=$(value_after write "$@")
    content=$(value_after --content "$@")
    store="$UVX_LOG_DIR/store_serena_$(store_key "$label")"
    printf '%s\n' "$argv" > "$UVX_LOG_DIR/serena.argv"
    printf '%s' "$content" > "$UVX_LOG_DIR/serena.content"
    [ "${SERENA_FAIL:-0}" = "1" ] && { echo "serena write failed" >&2; exit 1; }
    printf '%s' "$content" > "$store"
    exit 0
    ;;
  *"basic-memory tool read-note"*)
    title=$(value_after read-note "$@")
    store="$UVX_LOG_DIR/store_bm_$(store_key "$title")"
    printf '%s\n' "$argv" >> "$UVX_LOG_DIR/bm_read.argv"
    if [ "${BM_READ_BROKEN:-0}" = "1" ]; then
      echo "connection reset by peer" >&2
      exit 1
    fi
    if [ -f "$store" ]; then
      jq -Rs --arg title "$title" --arg permalink "projects/$(basename "$PWD")/$(store_key "$title")" '{title: $title, permalink: $permalink, content: .}' < "$store"
    else
      printf '{"title": null, "content": null}\n'
    fi
    exit 0
    ;;
  *"basic-memory tool write-note"*)
    title=$(value_after --title "$@")
    content=$(value_after --content "$@")
    store="$UVX_LOG_DIR/store_bm_$(store_key "$title")"
    printf '%s\n' "$argv" > "$UVX_LOG_DIR/bm.argv"
    printf '%s' "$content" > "$UVX_LOG_DIR/bm.content"
    [ "${BM_FAIL:-0}" = "1" ] && { echo "write-note failed" >&2; exit 1; }
    printf '%s' "$content" > "$store"
    printf '{"permalink": "projects/%s/%s"}\n' "$(basename "$PWD")" "$(store_key "$title")"
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$SHIM/uvx"
export PATH="$SHIM:$PATH"
export UVX_LOG_DIR="$SHIM"

run_script() {
  label="$1"; shift
  (cd "$SHIM" && bash "$SCRIPT" "$label" "$@")
}

reset_logs() {
  rm -f "$SHIM/serena.argv" "$SHIM/serena.content" "$SHIM/bm.argv" "$SHIM/bm.content" "$SHIM/serena_read.argv" "$SHIM/bm_read.argv"
}

reset_logs
out=$(run_script test_label_success "plan=/tmp/plan.md" 2>"$SHIM/stderr") || fail "success path: script exited non-zero: $(cat "$SHIM/stderr")"
grep -q -- '--overwrite' "$SHIM/bm.argv" || fail "write-note argv must pass --overwrite so it succeeds whether or not the note already exists: $(cat "$SHIM/bm.argv")"
grep -q 'write-note' "$SHIM/bm.argv" || fail "checkpoint must write via write-note: $(cat "$SHIM/bm.argv")"
cmp -s "$SHIM/serena.content" "$SHIM/bm.content" || fail "fresh checkpoint: Serena and Basic-Memory must receive identical content"
[ -s "$SHIM/serena.content" ] || fail "content passed to backends is empty"
[ "$(grep -c '^# test_label_success$' "$SHIM/serena.content")" = 1 ] || fail "fresh checkpoint must carry exactly one title line"
echo "$out" | grep -qF -- "Basic-Memory: projects/$(basename "$SHIM")/Test_Label_Success" || fail "reload block missing permalink: $out"

reset_logs
( export BM_FAIL=1; run_script test_label_failure >/dev/null 2>"$SHIM/stderr" ) && fail "failure path: script exited zero when write-note failed"
grep -q 'Basic-Memory write failed' "$SHIM/stderr" || fail "failure path: missing error message: $(cat "$SHIM/stderr")"

reset_logs
printf '## Completed\n- [x] first session thing\n' > "$SHIM/body1.md"
run_script test_label_accumulate "body=$SHIM/body1.md" >/dev/null 2>"$SHIM/stderr1" || fail "accumulate first call: script exited non-zero: $(cat "$SHIM/stderr1")"
grep -q 'write-note' "$SHIM/bm.argv" || fail "accumulate first call must write via write-note: $(cat "$SHIM/bm.argv")"

printf '## Completed\n- [x] second session thing\n' > "$SHIM/body2.md"
run_script test_label_accumulate "body=$SHIM/body2.md" >/dev/null 2>"$SHIM/stderr2" || fail "accumulate second call: script exited non-zero: $(cat "$SHIM/stderr2")"
grep -q -- '--overwrite' "$SHIM/bm.argv" || fail "second checkpoint must still pass --overwrite to write-note: $(cat "$SHIM/bm.argv")"
grep -qF -- 'first session thing' "$SHIM/serena.content" || fail "accumulation must not drop the first checkpoint's facts from Serena: $(cat "$SHIM/serena.content")"
grep -qF -- 'second session thing' "$SHIM/serena.content" || fail "accumulation must include the new checkpoint's facts in Serena"
[ "$(grep -c '^# test_label_accumulate$' "$SHIM/serena.content")" = 1 ] || fail "accumulated Serena document must carry exactly one title line, not one per checkpoint: $(cat "$SHIM/serena.content")"
newest_line=$(grep -n 'second session thing' "$SHIM/serena.content" | cut -d: -f1)
oldest_line=$(grep -n 'first session thing' "$SHIM/serena.content" | cut -d: -f1)
[ "$newest_line" -lt "$oldest_line" ] || fail "most recent checkpoint must be prepended (newest first) in Serena: $(cat "$SHIM/serena.content")"
grep -qF -- 'first session thing' "$SHIM/bm.content" || fail "accumulation must not drop the first checkpoint's facts from Basic-Memory: $(cat "$SHIM/bm.content")"
grep -qF -- 'second session thing' "$SHIM/bm.content" || fail "accumulation must include the new checkpoint's facts in Basic-Memory"
[ "$(grep -c '^# test_label_accumulate$' "$SHIM/bm.content")" = 1 ] || fail "accumulated Basic-Memory document must carry exactly one title line, not have it pushed down by the new entry: $(cat "$SHIM/bm.content")"
bm_newest_line=$(grep -n 'second session thing' "$SHIM/bm.content" | cut -d: -f1)
bm_oldest_line=$(grep -n 'first session thing' "$SHIM/bm.content" | cut -d: -f1)
[ "$bm_newest_line" -lt "$bm_oldest_line" ] || fail "most recent checkpoint must be prepended (newest first) in Basic-Memory: $(cat "$SHIM/bm.content")"
cmp -s "$SHIM/serena.content" "$SHIM/bm.content" || fail "accumulate second call: Serena and Basic-Memory must receive identical merged content"
[ "$(wc -l < "$SHIM/serena_read.argv" | tr -d ' ')" = 2 ] || fail "each checkpoint must read Serena before writing: $(cat "$SHIM/serena_read.argv")"
[ "$(wc -l < "$SHIM/bm_read.argv" | tr -d ' ')" = 2 ] || fail "each checkpoint must read Basic-Memory before writing: $(cat "$SHIM/bm_read.argv")"

reset_logs
printf '# test_label_titleonly\n' > "$SHIM/store_serena_test_label_titleonly"
printf '# test_label_titleonly\n' > "$SHIM/store_bm_Test_Label_Titleonly"
printf '## Completed\n- [x] after a title-only prior memory\n' > "$SHIM/body_titleonly.md"
run_script test_label_titleonly "body=$SHIM/body_titleonly.md" >/dev/null 2>"$SHIM/stderr" || fail "title-only prior memory: script exited non-zero: $(cat "$SHIM/stderr")"
[ "$(grep -c '^# test_label_titleonly$' "$SHIM/serena.content")" = 1 ] || fail "a prior memory containing only the title line must not be duplicated into the merged document: $(cat "$SHIM/serena.content")"
[ "$(grep -c '^# test_label_titleonly$' "$SHIM/bm.content")" = 1 ] || fail "a prior Basic-Memory note containing only the title line must not be duplicated into the merged document: $(cat "$SHIM/bm.content")"

reset_logs
printf '## Completed\n- [x] before the broken read\n' > "$SHIM/body_beforebreak.md"
run_script test_label_readbroken "body=$SHIM/body_beforebreak.md" >/dev/null 2>"$SHIM/stderr" || fail "readbroken seed: script exited non-zero: $(cat "$SHIM/stderr")"
rm -f "$SHIM/serena.argv" "$SHIM/serena.content"
( export SERENA_READ_BROKEN=1; run_script test_label_readbroken "body=$SHIM/body_beforebreak.md" >/dev/null 2>"$SHIM/stderr" ) && fail "a genuine Serena read failure must abort the checkpoint, not silently drop prior history"
grep -qi 'could not read existing Serena memory' "$SHIM/stderr" || fail "a genuine Serena read failure must be reported: $(cat "$SHIM/stderr")"
[ ! -e "$SHIM/serena.content" ] || fail "a genuine Serena read failure must not proceed to overwrite the memory"
grep -qF -- 'before the broken read' "$SHIM/store_serena_test_label_readbroken" || fail "a genuine Serena read failure must leave prior history intact"

reset_logs
printf '## Completed\n- [x] before the broken bm read\n' > "$SHIM/body_bmbeforebreak.md"
run_script test_label_bmreadbroken "body=$SHIM/body_bmbeforebreak.md" >/dev/null 2>"$SHIM/stderr" || fail "bm-readbroken seed: script exited non-zero: $(cat "$SHIM/stderr")"
rm -f "$SHIM/bm.argv" "$SHIM/bm.content"
( export BM_READ_BROKEN=1; run_script test_label_bmreadbroken "body=$SHIM/body_bmbeforebreak.md" >/dev/null 2>"$SHIM/stderr" ) && fail "a genuine Basic-Memory read failure must abort the checkpoint, not silently drop prior history"
grep -qi 'could not read existing Basic-Memory note' "$SHIM/stderr" || fail "a genuine Basic-Memory read failure must be reported: $(cat "$SHIM/stderr")"
[ ! -e "$SHIM/bm.content" ] || fail "a genuine Basic-Memory read failure must not proceed to overwrite the note"
grep -qF -- 'before the broken bm read' "$SHIM/store_bm_Test_Label_Bmreadbroken" || fail "a genuine Basic-Memory read failure must leave prior history intact"

reset_logs
printf '## Completed\n- [x] before the noisy read\n' > "$SHIM/body_beforenoise.md"
run_script test_label_readnoise "body=$SHIM/body_beforenoise.md" >/dev/null 2>"$SHIM/stderr" || fail "readnoise seed: script exited non-zero: $(cat "$SHIM/stderr")"
printf '## Completed\n- [x] after the noisy read\n' > "$SHIM/body_afternoise.md"
( export SERENA_READ_NOISE=1; run_script test_label_readnoise "body=$SHIM/body_afternoise.md" >/dev/null 2>"$SHIM/stderr" ) || fail "readnoise second call: script exited non-zero: $(cat "$SHIM/stderr")"
grep -qi 'Resolved 1 package' "$SHIM/serena.content" && fail "stderr noise from a successful uvx read must not be merged into the memory content: $(cat "$SHIM/serena.content")"
[ "$(grep -c '^# test_label_readnoise$' "$SHIM/serena.content")" = 1 ] || fail "stderr noise on a successful read must not corrupt the title line: $(cat "$SHIM/serena.content")"

reset_logs
BASH_BIN="$(command -v bash)"
FAKE_PATH_NO_JQ="$SHIM/no-jq-path"
mkdir -p "$FAKE_PATH_NO_JQ"
ln -s "$SHIM/uvx" "$FAKE_PATH_NO_JQ/uvx"
(PATH="$FAKE_PATH_NO_JQ" "$BASH_BIN" "$SCRIPT" test_label_nojq "body=$BODY") >/dev/null 2>"$SHIM/stderr" && fail "a missing jq dependency must make the script exit non-zero"
grep -qi 'jq is required' "$SHIM/stderr" || fail "a missing jq dependency must be reported: $(cat "$SHIM/stderr")"

reset_logs
run_script test_label_outside_git "plan=/tmp/plan.md" >/dev/null 2>"$SHIM/stderr" || fail "outside-git path: script exited non-zero: $(cat "$SHIM/stderr")"
grep -q -- 'serena memories write test_label_outside_git --content' "$SHIM/serena.argv" || fail "outside git: serena argv should carry no project: $(cat "$SHIM/serena.argv")"
grep -qF -- "--folder projects/$(basename "$SHIM")" "$SHIM/bm.argv" || fail "outside git: folder should default to the current directory name: $(cat "$SHIM/bm.argv")"

reset_logs
REPO="$SHIM/primary-repo"
git init -q "$REPO" && (cd "$REPO" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init)
git -C "$REPO" worktree add -q "$REPO/.claude/worktrees/wt" -b wt
PRIMARY="$(cd "$REPO" && pwd -P)"
wt_out=$(cd "$REPO/.claude/worktrees/wt" && bash "$SCRIPT" test_label_worktree "plan=/tmp/plan.md" 2>"$SHIM/stderr") || fail "worktree path: script exited non-zero: $(cat "$SHIM/stderr")"
echo "$wt_out" | grep -q 'Serena: test_label_worktree (primary-repo project)' || fail "reload block must name the resolved Serena project: $wt_out"
grep -qF -- "serena memories write test_label_worktree $PRIMARY --content" "$SHIM/serena.argv" || fail "worktree: serena argv should name the primary checkout: $(cat "$SHIM/serena.argv")"
grep -q -- '--folder projects/primary-repo' "$SHIM/bm.argv" || fail "worktree: folder should use the primary checkout name: $(cat "$SHIM/bm.argv")"

reset_logs
PLAN="$SHIM/groovy-greeting-pearl.md"
printf '# Fix checkpoint body — Plan\n\n- [x] done item\n- [ ] first pending\n- [ ] second pending\n' > "$PLAN"
BODY="$SHIM/body.md"
printf '## Completed\n- [x] resolved primary checkout (`write-checkpoint.sh:13`)\n\n## Related\n- Serena: `sibling_memory_name`\n' > "$BODY"
run_script test_label_body "plan=$PLAN" "body=$BODY" >/dev/null 2>"$SHIM/stderr" || fail "body path: script exited non-zero: $(cat "$SHIM/stderr")"
grep -qF -- '- [x] resolved primary checkout (`write-checkpoint.sh:13`)' "$SHIM/serena.content" || fail "body file content missing from Serena payload: $(cat "$SHIM/serena.content")"
grep -q 'sibling_memory_name' "$SHIM/bm.content" || fail "body Related entries missing from Basic-Memory payload"
grep -qF -- "- Plan: $PLAN" "$SHIM/serena.content" || fail "plan path must still be listed under Related"
[ "$(grep -c '^## Related' "$SHIM/serena.content")" = 1 ] || fail "Related heading must appear exactly once: $(cat "$SHIM/serena.content")"
grep -qi 'zero tokens' "$SHIM/serena.content" && fail "placeholder sentence must not appear when a body is given"
cmp -s "$SHIM/serena.content" "$SHIM/bm.content" || fail "body path: fresh checkpoint, Serena and Basic-Memory must receive identical content"

reset_logs
run_script test_label_nobody "plan=$PLAN" >/dev/null 2>"$SHIM/stderr" || fail "no-body path: script exited non-zero: $(cat "$SHIM/stderr")"
grep -q 'Fix checkpoint body' "$SHIM/serena.content" || fail "no-body fallback must carry the plan title: $(cat "$SHIM/serena.content")"
grep -qF -- '- [ ] first pending' "$SHIM/serena.content" || fail "no-body fallback must list pending plan items"
grep -qF -- '- [x] done item' "$SHIM/serena.content" && fail "no-body fallback must not list completed plan items"
grep -qi 'zero tokens' "$SHIM/serena.content" && fail "placeholder sentence must not appear in the fallback body"
grep -qi 'Load context from plan file' "$SHIM/serena.content" && fail "placeholder next-step sentence must not appear in the fallback body"

reset_logs
BODY_MID="$SHIM/body-related-mid.md"
printf '## Completed\n- [x] thing\n\n## Related\n- Serena: `sibling`\n\n## Next\nresume here\n' > "$BODY_MID"
run_script test_label_relatedmid "plan=$PLAN" "body=$BODY_MID" >/dev/null 2>"$SHIM/stderr" || fail "related-mid path: script exited non-zero: $(cat "$SHIM/stderr")"
plan_line_no=$(grep -n -F -- "- Plan: $PLAN" "$SHIM/serena.content" | cut -d: -f1)
next_line_no=$(grep -n '^## Next' "$SHIM/serena.content" | cut -d: -f1)
[ -n "$plan_line_no" ] && [ -n "$next_line_no" ] && [ "$plan_line_no" -lt "$next_line_no" ] || fail "plan line must be filed under Related, not after the last section: $(cat "$SHIM/serena.content")"
[ "$(grep -c '^## Related' "$SHIM/serena.content")" = 1 ] || fail "related-mid: Related heading must appear exactly once"

reset_logs
run_script test_label_missingbody "plan=$PLAN" "body=$SHIM/does-not-exist.md" >/dev/null 2>"$SHIM/stderr" && fail "missing body file must make the script exit non-zero"
grep -q 'body file not found' "$SHIM/stderr" || fail "missing body file must be reported: $(cat "$SHIM/stderr")"
[ ! -e "$SHIM/serena.content" ] || fail "missing body file must not write to Serena"
[ ! -e "$SHIM/bm.content" ] || fail "missing body file must not write to Basic-Memory"

reset_logs
run_script test_label_emptybody "plan=$PLAN" "body=" >/dev/null 2>"$SHIM/stderr" && fail "empty body= value must make the script exit non-zero"
grep -q 'body file not found' "$SHIM/stderr" || fail "empty body= value must be reported: $(cat "$SHIM/stderr")"
[ ! -e "$SHIM/serena.content" ] || fail "empty body= value must not write to Serena"

reset_logs
printf '\n  \n' > "$SHIM/blank-body.md"
run_script test_label_blankbody "plan=$PLAN" "body=$SHIM/blank-body.md" >/dev/null 2>"$SHIM/stderr" && fail "blank body file must make the script exit non-zero"
grep -q 'body file is empty' "$SHIM/stderr" || fail "blank body file must be reported: $(cat "$SHIM/stderr")"
[ ! -e "$SHIM/serena.content" ] || fail "blank body file must not write to Serena"

reset_logs
run_script test_label_noplan "body=$BODY" >/dev/null 2>"$SHIM/stderr" || fail "no-plan path: script exited non-zero: $(cat "$SHIM/stderr")"
grep -q -- '^- Plan:' "$SHIM/serena.content" && fail "without plan= no Plan line may be emitted: $(cat "$SHIM/serena.content")"
grep -q '^\*\*Plan\*\*' "$SHIM/serena.content" && fail "without plan= the header must not carry an empty Plan line"
grep -q 'sibling_memory_name' "$SHIM/serena.content" || fail "no-plan path must still carry the body"

reset_logs
DONE_PLAN="$SHIM/all-done.md"
printf 'no heading\n- [x] everything done\n' > "$DONE_PLAN"
run_script test_label_donefallback "plan=$DONE_PLAN" >/dev/null 2>"$SHIM/stderr" || fail "fallback with no heading and no pending items must still succeed: $(cat "$SHIM/stderr")"
grep -q 'No session body was supplied' "$SHIM/serena.content" || fail "completed-plan fallback must carry the status sentence"
grep -q '^## Pending' "$SHIM/serena.content" && fail "completed plan must not emit a Pending section"

reset_logs
run_script test_label_missingplan "plan=$SHIM/missing-plan.md" "body=$BODY" >/dev/null 2>"$SHIM/stderr" || fail "missing plan= must not be fatal: $(cat "$SHIM/stderr")"
grep -q 'plan file not found' "$SHIM/stderr" || fail "missing plan= must be reported on stderr: $(cat "$SHIM/stderr")"

reset_logs
mkdir -p "$SHIM/body-dir"
run_script test_label_bodydir "plan=$PLAN" "body=$SHIM/body-dir" >/dev/null 2>"$SHIM/stderr" && fail "a directory passed as body= must fail"
grep -q 'not found or unreadable' "$SHIM/stderr" || fail "directory body= must be reported as not a readable file: $(cat "$SHIM/stderr")"

reset_logs
printf '## Related Work\n- other\n' > "$SHIM/body-related-work.md"
run_script test_label_relatedwork "plan=$PLAN" "body=$SHIM/body-related-work.md" >/dev/null 2>"$SHIM/stderr" || fail "Related Work body: script exited non-zero: $(cat "$SHIM/stderr")"
[ "$(grep -c '^## Related$' "$SHIM/serena.content")" = 1 ] || fail "a heading that merely starts with Related must not absorb the Plan line: $(cat "$SHIM/serena.content")"

echo "PASS: write-checkpoint"
