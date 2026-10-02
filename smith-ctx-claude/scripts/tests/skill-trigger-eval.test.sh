#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
EVAL="$HERE/../skill-trigger-eval.mjs"
PROMPTS="$HERE/../../evals/skill-trigger/smith-nuxt.json"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

mkdir -p "$TMPD/bin"
cat > "$TMPD/bin/claude" <<'FAKE'
#!/bin/sh
skill_call() {
  echo '{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"tool_use","name":"Skill"}}}'
  echo "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"$1\"}}}"
  echo "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"$2\"}}}"
  echo '{"type":"stream_event","event":{"type":"content_block_stop"}}'
}
other_tool_call() {
  echo '{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"tool_use","name":"Bash"}}}'
  echo '{"type":"stream_event","event":{"type":"content_block_stop"}}'
}
[ "$FAKE_CLAUDE" = crash ] && { echo "no login" >&2; exit 3; }
[ "$SLASH_COMMAND_TOOL_CHAR_BUDGET" = 60000 ] || exit 4
grep -q '^description: ' .claude/skills/smith-nuxt/SKILL.md || exit 5
case "$*" in *"--setting-sources project"*) ;; *) exit 6 ;; esac
grep -q 'The rules of this skill are now loaded' .claude/skills/smith-nuxt/SKILL.md || exit 7
grep -q 'Auto-Import' .claude/skills/smith-nuxt/SKILL.md && exit 8
[ -z "$CLAUDECODE" ] || exit 9
case "$*" in *"--no-session-persistence"*) ;; *) exit 10 ;; esac
if [ -n "$FAKE_EXPECTED_DESCRIPTION" ]; then
  grep -q "^description: $FAKE_EXPECTED_DESCRIPTION" .claude/skills/smith-nuxt/SKILL.md || exit 11
fi
if [ "$FAKE_CLAUDE" = unlisted ]; then
  echo '{"type":"system","subtype":"init","skills":["smith-git"]}'
else
  echo '{"type":"system","subtype":"init","skills":["smith-git","smith-nuxt"]}'
fi
[ "$FAKE_CLAUDE" = died ] && exit 1
[ "$FAKE_CLAUDE" = hang ] && exec sleep 30
[ "$FAKE_CLAUDE" = api-error ] && { echo '{"type":"result","subtype":"success","is_error":true}'; exit 0; }
[ "$FAKE_CLAUDE" = no-model-turn ] && { echo '{"type":"result","subtype":"success"}'; exit 0; }
echo '{"type":"stream_event","event":{"type":"message_start"}}'
case "$FAKE_CLAUDE" in
  skill)
    skill_call '{\"skill\": \"smith-' 'nuxt\"}'
    echo '{"type":"stream_event","event":{"type":"message_stop"}}'
    echo '{"type":"stream_event","event":{"type":"message_start"}}'
    other_tool_call
    echo '{"type":"stream_event","event":{"type":"message_stop"}}'
    exec sleep 30
    ;;
  other)
    skill_call '{\"skill\": \"smith-' 'git\"}'
    ;;
  tool-then-skill)
    other_tool_call
    skill_call '{\"skill\": \"smith-' 'nuxt\"}'
    echo '{"type":"stream_event","event":{"type":"message_stop"}}'
    exec sleep 30
    ;;
  tool-only)
    other_tool_call
    echo '{"type":"stream_event","event":{"type":"message_stop"}}'
    exec sleep 30
    ;;
  unreadable-skill)
    skill_call '{\"skill\": 4' '2}'
    ;;
  garbled)
    echo 'this line is not JSON'
    ;;
  failed-result)
    echo '{"type":"result","subtype":"error_during_execution"}'
    exit 0
    ;;
esac
echo '{"type":"result","subtype":"success","is_error":false}'
FAKE
chmod +x "$TMPD/bin/claude"
PATH="$TMPD/bin:$PATH"
CLAUDECODE=1
export PATH CLAUDECODE

prompt_count() {
  node -e 'process.stdout.write(String(require(process.argv[1])[process.argv[2]].length))' "$PROMPTS" "$1"
}
WANTED=$(prompt_count should_trigger)
UNWANTED=$(prompt_count should_not_trigger)
ALL=$((WANTED + UNWANTED))
count() { grep -c "$2" "$1"; }
line_count() { wc -l < "$1" | tr -d ' '; }
run_as() {
  fake_mode="$1"
  shift
  FAKE_CLAUDE="$fake_mode" node "$EVAL" run --source worktree --only smith-nuxt "$@" 2>"$TMPD/err"
}
records() {
  [ "$(count "$TMPD/$1.jsonl" "$2")" = "$ALL" ] || fail "$1: expected $ALL records matching $2, got: $(head -2 "$TMPD/$1.jsonl")"
}

OUT="$TMPD/skill.jsonl"
run_as skill --out "$OUT" || fail "a run whose prompts all complete must exit zero: $(cat "$TMPD/err")"
[ "$(line_count "$OUT")" = "$ALL" ] || fail "one record per prompt, got: $(line_count "$OUT")"
records skill '"model":"sonnet","status":"ok","loaded":\["smith-nuxt"\],"triggered":true'
records skill '"source":"worktree@[0-9a-f]\{12\}"'
[ "$(count "$OUT" '"expected":true')" = "$WANTED" ] || fail "the prompts that should trigger keep their flag"
grep -q '"detail"' "$OUT" && fail "a completed prompt carries no failure detail"

run_as skill --out "$OUT"
grep -q "0 of $ALL prompts to run" "$TMPD/err" || fail "completed prompts must not run again: $(cat "$TMPD/err")"
[ "$(line_count "$OUT")" = "$ALL" ] || fail "a resumed run must not append records"

run_as skill --out "$OUT" --model haiku && fail "a file of another model must be refused"
grep -q 'holds records of source worktree@[0-9a-f]* and model sonnet' "$TMPD/err" || fail "the refusal must name what the file holds: $(cat "$TMPD/err")"
FAKE_CLAUDE=skill node "$EVAL" run --source HEAD --only smith-nuxt --out "$OUT" 2>"$TMPD/err" && fail "a file of another source must be refused"
sed 's/"source":"worktree@[0-9a-f]*"/"source":"worktree@000000000000"/' "$OUT" > "$TMPD/other-listing.jsonl"
run_as skill --out "$TMPD/other-listing.jsonl" && fail "a file measured on other descriptions must be refused"

sed 's/"prompt":"[0-9a-f]*"/"prompt":"000000000000"/' "$OUT" > "$TMPD/stale.jsonl"
run_as skill --out "$TMPD/stale.jsonl"
grep -q "$ALL of $ALL prompts to run" "$TMPD/err" || fail "a record of an edited prompt must not count as completed: $(cat "$TMPD/err")"

QUIET="$TMPD/none.jsonl"
run_as none --out "$QUIET" || fail "a run without any Skill call still completes"
records none '"status":"ok","loaded":\[\],"triggered":false'

run_as other --out "$TMPD/other.jsonl" || fail "a run that loads another skill still completes"
records other '"status":"ok","loaded":\["smith-git"\],"triggered":false'

run_as tool-then-skill --out "$TMPD/tool-then-skill.jsonl" || fail "a Skill call after another tool in one message still completes"
records tool-then-skill '"status":"ok","loaded":\["smith-nuxt"\],"triggered":true'

run_as tool-only --out "$TMPD/tool-only.jsonl" || fail "a message that only calls another tool ends the run"
records tool-only '"status":"ok","loaded":\[\],"triggered":false'

for mode in crash:not-started died:error failed-result:error api-error:error no-model-turn:error \
  unlisted:skill-not-listed unreadable-skill:error garbled:unparsable-output; do
  name="${mode%%:*}"
  run_as "$name" --out "$TMPD/$name.jsonl" && fail "$name: a run that did not complete must exit non-zero"
  records "$name" "\"status\":\"${mode##*:}\""
  [ "$(count "$TMPD/$name.jsonl" '"detail":"')" = "$ALL" ] || fail "$name: a failed prompt must say why"
done
grep -q 'no login' "$TMPD/crash.jsonl" || fail "the failure detail must carry the error output"

run_as crash --out "$TMPD/storm.jsonl" --runs 3 --concurrency 1 && fail "a run that keeps failing must exit non-zero"
[ "$(line_count "$TMPD/storm.jsonl")" = 25 ] || fail "a run must stop after 25 failures in a row, got: $(line_count "$TMPD/storm.jsonl")"
grep -q "stopped after 25 prompts in a row did not complete; $((ALL * 3 - 25)) were not tried" "$TMPD/err" || fail "the early stop must be reported: $(cat "$TMPD/err")"

run_as hang --out "$TMPD/hang.jsonl" --timeout 1 && fail "a run whose prompts time out must exit non-zero"
records hang '"status":"timeout"'

CRASHED="$TMPD/crash.jsonl"
out=$(node "$EVAL" compare --only smith-nuxt "$CRASHED" "$CRASHED") && fail "files holding only failed prompts must exit non-zero"
printf '%s\n' "$out" | grep -q "incomplete: 0 and 0 of $ALL prompt runs completed$" || fail "a skill whose prompts all failed must be reported incomplete, got: $out"
run_as none --out "$CRASHED"
grep -q "$ALL of $ALL prompts to run" "$TMPD/err" || fail "prompts that did not complete must run again"

FAKE_CLAUDE=none node "$EVAL" run --source HEAD --out "$TMPD/from-ref.jsonl" --only smith-nuxt 2>/dev/null \
  || fail "a git ref must be readable as a source"
grep -q '"source":"[0-9a-f]\{40\}"' "$TMPD/from-ref.jsonl" || fail "a git ref must be recorded as its commit"

COPY="$TMPD/copy"
mkdir -p "$COPY/smith-ctx-claude/scripts" "$COPY/smith-ctx-claude/evals/skill-trigger" "$COPY/smith-nuxt"
cp "$EVAL" "$COPY/smith-ctx-claude/scripts/"
cp "$PROMPTS" "$COPY/smith-ctx-claude/evals/skill-trigger/"
printf -- '---\nname: smith-nuxt\ndescription: Committed words. Use when testing.\n---\n' > "$COPY/smith-nuxt/SKILL.md"
git -C "$COPY" init -q
git -C "$COPY" add -A
git -C "$COPY" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false \
  -c core.hooksPath=/dev/null commit -q -m "fixture" || fail "the fixture repository must take a commit"
printf -- '---\nname: smith-nuxt\ndescription: Edited words. Use when testing.\n---\n' > "$COPY/smith-nuxt/SKILL.md"
run_copy() {
  FAKE_CLAUDE=none FAKE_EXPECTED_DESCRIPTION="$2" node "$COPY/smith-ctx-claude/scripts/skill-trigger-eval.mjs" \
    run --source "$1" --out "$TMPD/copy-$3.jsonl" 2>"$TMPD/err"
}
run_copy HEAD "Committed words" ref || fail "a git ref must be measured on the descriptions of that commit: $(cat "$TMPD/err")"
run_copy worktree "Edited words" tree || fail "the working tree must be measured on its own descriptions: $(cat "$TMPD/err")"
run_copy HEAD "Edited words" ref-wrong && fail "a git ref must not be measured on the working tree's descriptions"

ROSE="^smith-nuxt	0/$WANTED	$WANTED/$WANTED	0/$UNWANTED	$UNWANTED/$UNWANTED	over-triggers$"
out=$(node "$EVAL" compare --only smith-nuxt "$QUIET" "$OUT") && fail "a near miss that started to trigger must exit non-zero"
printf '%s\n' "$out" | grep -q "$ROSE" || fail "compare must count both columns, got: $out"
out=$(node "$EVAL" compare --only smith-nuxt "$OUT" "$QUIET") && fail "a rate that fell must exit non-zero"
printf '%s\n' "$out" | grep -q '	fell$' || fail "compare must name the skill whose rate fell, got: $out"
printf '%s\n' "$out" | grep -q "^total	$WANTED/$WANTED	0/$WANTED	$UNWANTED/$UNWANTED	0/$UNWANTED	1 fell, 0 over-triggers, 0 incomplete$" \
  || fail "compare must total the rows, got: $out"
out=$(node "$EVAL" compare --only smith-nuxt "$OUT" "$OUT") || fail "an unchanged rate must exit zero"
printf '%s\n' "$out" | grep -q '	same$' || fail "an unchanged rate must be reported as same, got: $out"
grep -v 'near-miss' "$OUT" > "$TMPD/wanted-hits.jsonl"
grep 'near-miss' "$QUIET" >> "$TMPD/wanted-hits.jsonl"
out=$(node "$EVAL" compare --only smith-nuxt "$QUIET" "$TMPD/wanted-hits.jsonl") || fail "a rate that rose must exit zero, got: $out"
printf '%s\n' "$out" | grep -q '	rose$' || fail "a rate that rose must be reported as rose, got: $out"
grep -v 'trigger/0' "$OUT" > "$TMPD/partial.jsonl"
out=$(node "$EVAL" compare --only smith-nuxt "$OUT" "$TMPD/partial.jsonl") && fail "a file missing prompts must exit non-zero"
printf '%s\n' "$out" | grep -q "incomplete: $ALL and $((ALL - 1)) of $ALL prompt runs completed$" || fail "a skill with missing prompts must be reported with its counts, got: $out"

run_as none --out "$TMPD/repeated.jsonl" --runs 2 || fail "a prompt can be run more than once"
[ "$(line_count "$TMPD/repeated.jsonl")" = "$((ALL * 2))" ] || fail "--runs 2 must record every prompt twice"
[ "$(count "$TMPD/repeated.jsonl" '"run":1,')" = "$ALL" ] || fail "each repeat must carry its run number"
run_as none --out "$TMPD/repeated.jsonl" --runs 3
grep -q "$ALL of $((ALL * 3)) prompts to run" "$TMPD/err" || fail "a higher --runs must only add the missing repeats: $(cat "$TMPD/err")"
out=$(node "$EVAL" compare --only smith-nuxt "$TMPD/repeated.jsonl" "$TMPD/repeated.jsonl") || fail "repeated runs compare like single ones, got: $out"
printf '%s\n' "$out" | grep -q "^smith-nuxt	0/$((WANTED * 3))	0/$((WANTED * 3))	" || fail "compare must sum the repeats, got: $out"
out=$(node "$EVAL" compare --only smith-nuxt "$QUIET" "$TMPD/repeated.jsonl") && fail "sides with unequal repeats must exit non-zero"
printf '%s\n' "$out" | grep -q "incomplete: $ALL and $((ALL * 3)) of $((ALL * 3)) prompt runs completed$" || fail "the side with fewer repeats must be reported incomplete, got: $out"
out=$(node "$EVAL" compare --only smith-nuxt "$OUT" "$TMPD/stale.jsonl") || fail "the completed record of the current prompt counts, got: $out"
out=$(node "$EVAL" compare --only smith-nuxt "$CRASHED" "$OUT") && fail "a near miss that started to trigger must exit non-zero"
printf '%s\n' "$out" | grep -q "$ROSE" || fail "the completed record must replace the failed one, got: $out"
grep 'run":0' "$TMPD/repeated.jsonl" > "$TMPD/lost-repeat.jsonl"
grep 'run":1' "$TMPD/repeated.jsonl" | sed 's/"status":"ok"/"status":"timeout"/' >> "$TMPD/lost-repeat.jsonl"
out=$(node "$EVAL" compare --only smith-nuxt "$TMPD/lost-repeat.jsonl" "$TMPD/lost-repeat.jsonl") && fail "a repeat that failed on both sides must exit non-zero"
printf '%s\n' "$out" | grep -q "incomplete: $ALL and $ALL of $((ALL * 2)) prompt runs completed$" || fail "failed repeats must count as expected runs, got: $out"
printf '%s\n' "$out" | grep -q '^before: source worktree@[0-9a-f]*, model sonnet$' || fail "compare must say what each file measured, got: $out"
sed 's/"model":"sonnet"/"model":"haiku"/' "$OUT" > "$TMPD/other-model.jsonl"
node "$EVAL" compare --only smith-nuxt "$OUT" "$TMPD/other-model.jsonl" >/dev/null 2>"$TMPD/err" && fail "files of two models must not be compared"
grep -q 'different models' "$TMPD/err" || fail "the model mismatch must be named: $(cat "$TMPD/err")"
cat "$OUT" "$TMPD/other-listing.jsonl" > "$TMPD/mixed.jsonl"
node "$EVAL" compare --only smith-nuxt "$TMPD/mixed.jsonl" "$OUT" >/dev/null 2>"$TMPD/err" && fail "a file mixing two sources must not be compared"
grep -q 'mixes records' "$TMPD/err" || fail "the mixed sources must be named: $(cat "$TMPD/err")"
: > "$TMPD/empty.jsonl"
node "$EVAL" compare --only smith-nuxt "$TMPD/empty.jsonl" "$TMPD/empty.jsonl" >/dev/null 2>&1 && fail "two files without a completed prompt must exit non-zero"
out=$(node "$EVAL" compare "$OUT" "$OUT") && fail "a skill missing from both files must exit non-zero"
printf '%s\n' "$out" | grep -q '^smith-git	.*incomplete: 0 and 0 of ' || fail "a skill missing from both files must be reported incomplete, got: $out"
printf '%s\n' "$out" | grep -q '^smith-nuxt	.*	same$' || fail "the skill both files hold must still be compared, got: $out"
node "$EVAL" compare --only smith-absent "$OUT" "$OUT" >/dev/null 2>&1
[ "$?" = 2 ] || fail "compare must refuse a skill name it has no prompts for"
printf '%s\n' 'not json' > "$TMPD/broken.jsonl"
node "$EVAL" compare --only smith-nuxt "$TMPD/broken.jsonl" "$OUT" >/dev/null 2>"$TMPD/err" && fail "a file that is not JSON Lines must exit non-zero"
grep -q 'broken.jsonl:1 is not valid JSON' "$TMPD/err" || fail "a broken line must be named: $(cat "$TMPD/err")"

usage_error() {
  description="$1"
  shift
  node "$EVAL" "$@" >/dev/null 2>"$TMPD/err"
  [ "$?" = 2 ] || fail "$description must exit 2"
  [ ! -s "$TMPD/misuse.jsonl" ] || fail "$description must not run a prompt"
}
usage_error "run without --out" run --source worktree
usage_error "an unknown skill" run --source worktree --out "$TMPD/misuse.jsonl" --only smith-absent
usage_error "a source that is no commit" run --source no-such-ref --out "$TMPD/misuse.jsonl"
usage_error "a concurrency of zero" run --source worktree --out "$TMPD/misuse.jsonl" --concurrency 0
usage_error "a run count of zero" run --source worktree --out "$TMPD/misuse.jsonl" --runs 0
usage_error "a timeout that is no number" run --source worktree --out "$TMPD/misuse.jsonl" --timeout soon
usage_error "an option without a value" run --source worktree --out --model
usage_error "compare with one file" compare "$OUT"
usage_error "a misspelled run option" run --source worktree --out "$TMPD/misuse.jsonl" --run 3
grep -q 'unknown option: --run' "$TMPD/err" || fail "the unknown option must be named: $(cat "$TMPD/err")"
usage_error "a misspelled compare option" compare "$OUT" "$OUT" --olny smith-nuxt
usage_error "no command"

echo "PASS: skill-trigger-eval"
