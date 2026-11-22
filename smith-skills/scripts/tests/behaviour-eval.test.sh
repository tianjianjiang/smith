#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
RUNNER="$HERE/../behaviour-eval.mjs"
EGRESS="$HERE/../behaviour-eval-egress.sh"
LEAK_SCAN="$HERE/../behaviour-eval-leak-scan.mjs"
NODE="$(command -v node)"

TMPD="$(mktemp -d)" && [ -n "$TMPD" ] && [ -d "$TMPD" ] && [ -z "$(ls -A "$TMPD")" ] && TMPD="$(cd "$TMPD" && pwd -P)" && [ -n "$TMPD" ] \
  || { echo "FAIL: mktemp -d did not create a new empty folder"; exit 1; }
trap 'chmod -R u+rwx "$TMPD" 2>/dev/null' EXIT
fail() { echo "FAIL: $1"; exit 1; }
[ "${BEHAVIOUR_EVAL_TEST_STOP_AFTER_TEMP_FOLDER:-}" != 1 ] || exit 0

[ -f "$RUNNER" ] || fail "the script under test does not exist: $RUNNER"
[ -f "$EGRESS" ] || fail "the sibling egress script does not exist: $EGRESS"
[ -f "$LEAK_SCAN" ] || fail "the sibling leak scan does not exist: $LEAK_SCAN"
[ -n "$NODE" ] || fail "node must be on PATH"

probe_temp_folder_guard() {
  probe="$TMPD/temp-folder-guard-$1"
  mkdir -p "$probe/bin" "$probe/caller"
  printf '#!/bin/sh\n%s\n' "$2" > "$probe/bin/mktemp"
  chmod +x "$probe/bin/mktemp"
  : > "$probe/caller/canary"
  (cd "$probe/caller" && PATH="$probe/bin:$PATH" BEHAVIOUR_EVAL_TEST_STOP_AFTER_TEMP_FOLDER=1 sh "$HERE/behaviour-eval.test.sh" > "$probe/out" 2>&1)
  probe_status=$?
  [ -e "$probe/caller/canary" ] || fail "temp folder guard, $1: the test must never delete the folder it was started from"
}
probe_temp_folder_guard failing 'exit 1'
[ "$probe_status" != 0 ] || fail "temp folder guard, failing: a failed mktemp must make the test exit non-zero"
probe_temp_folder_guard existing-folder 'echo .'
[ "$probe_status" != 0 ] || fail "temp folder guard, existing-folder: a mktemp that names an existing folder with files must make the test exit non-zero"
probe_temp_folder_guard working "exec $(command -v mktemp) \"\$@\""
[ "$probe_status" = 0 ] || fail "temp folder guard, working: the guard must accept a folder mktemp created, got status $probe_status: $(cat "$probe/out")"

for git_variable in $(git rev-parse --local-env-vars); do unset "$git_variable"; done
unset GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM DOCKER_HOST
git -C "$TMPD" rev-parse --is-inside-work-tree >/dev/null 2>&1 && fail "the temp folder of this test must not be inside a git work tree"

random_word() { head -c 45 /dev/urandom | base64 | tr -d '=+/\n'; }

KEY_VENDOR="sk-"
KEY_KIND="ant-"
KEY="${KEY_VENDOR}${KEY_KIND}$(random_word | cut -c1-24)"

CONTROL="$TMPD/control"
BIN="$TMPD/bin"
SKILLED_DIR="$TMPD/skilled-bin"
SKILLED="$SKILLED_DIR/skilled"
CALLS="$CONTROL/skilled-calls"
FAKE_LOG="$CONTROL/invocations.log"
OUTS="$TMPD/outs"
CALLER_HOME="$TMPD/caller-home"
FIXTURE="$TMPD/fixture"
PLACE="$TMPD/placement-repo"
mkdir -p "$CONTROL" "$BIN" "$SKILLED_DIR" "$OUTS" "$CALLER_HOME/.skilled"
printf 'api_key: planted-credentials\n' > "$CALLER_HOME/.skilled/credentials.yaml"

install_fake() {
  sed "s|@CONTROL@|$CONTROL|g" > "$1"
  chmod +x "$1"
}

install_fake "$BIN/docker" <<'FAKE'
#!/bin/sh
CONTROL=@CONTROL@
echo "docker $*" >> "$CONTROL/invocations.log"
case "$*" in
  "context show")
    echo rancher-desktop
    ;;
  "context inspect "*)
    echo "$HOME" > "$CONTROL/context-inspect-home"
    case "$(cat "$CONTROL/docker-context-mode")" in
      fail)
        echo "error: no such context" >&2
        exit 1
        ;;
      empty)
        ;;
      *)
        cat "$CONTROL/docker-context-host"
        ;;
    esac
    ;;
  *"network inspect bridge"*)
    cat "$CONTROL/bridge-ipv6"
    ;;
  ps*"network=bridge"*)
    cat "$CONTROL/bridge-containers"
    ;;
  ps*)
    cat "$CONTROL/containers-now"
    ;;
  "rm -f "*)
    if [ -e "$CONTROL/hang-rm" ]; then
      mv "$CONTROL/hang-rm" "$(mktemp -d)"
      echo $$ > "$CONTROL/rm-started"
      exec sleep 60
    fi
    shift 2
    for name in "$@"; do
      grep -vxF "$name" "$CONTROL/containers-now" > "$CONTROL/containers-now.next"
      mv "$CONTROL/containers-now.next" "$CONTROL/containers-now"
    done
    ;;
  run*getent*)
    cat "$CONTROL/resolved.txt"
    ;;
  run*)
    cat "$CONTROL/probe.txt"
    ;;
esac
exit 0
FAKE

install_fake "$BIN/rdctl" <<'FAKE'
#!/bin/sh
CONTROL=@CONTROL@
echo "rdctl $*" >> "$CONTROL/invocations.log"
chain=SMITH-EGRESS
if [ -s "$CONTROL/block-path" ]; then
  mkdir -p "$(cat "$CONTROL/block-path")"
  mv "$CONTROL/block-path" "$(mktemp -d)"
fi
case "$*" in
  *"cat /etc/resolv.conf"*)
    echo "nameserver $(cat "$CONTROL/resolver")"
    ;;
  *"iptables"*"-L $chain"*)
    if [ -e "$CONTROL/hang-chain-check" ]; then
      mv "$CONTROL/hang-chain-check" "$(mktemp -d)"
      : > "$CONTROL/run-started"
      exec sleep 60
    fi
    [ -f "$CONTROL/state/chain" ] || exit 1
    echo "-N $chain"
    ;;
  *"iptables"*"-C DOCKER-USER"*)
    [ -f "$CONTROL/state/jump" ] || exit 1
    ;;
  *"iptables"*"-D DOCKER-USER"*)
    [ ! -e "$CONTROL/state/jump" ] || mv "$CONTROL/state/jump" "$(mktemp -d)"
    ;;
  *"iptables"*"-I DOCKER-USER"*)
    touch "$CONTROL/state/jump"
    ;;
  *"iptables"*"-N $chain"*)
    touch "$CONTROL/state/chain"
    ;;
  *"iptables"*"-X $chain"*)
    [ ! -e "$CONTROL/state/chain" ] || mv "$CONTROL/state/chain" "$(mktemp -d)"
    ;;
  *"iptables"*"-L $chain"*|*"iptables"*"-S $chain"*)
    [ -f "$CONTROL/state/chain" ] || exit 1
    echo "-N $chain"
    ;;
esac
exit 0
FAKE

install_fake "$BIN/trash" <<'FAKE'
#!/bin/sh
CONTROL=@CONTROL@
echo "trash $*" >> "$CONTROL/invocations.log"
mkdir -p "$CONTROL/trashed"
for target in "$@"; do
  mv "$target" "$CONTROL/trashed/$(basename "$target").$$"
done
exit 0
FAKE

install_fake "$SKILLED" <<'FAKE'
#!/bin/sh
CONTROL=@CONTROL@
. "$CONTROL/skilled.conf"
CALLS="$CONTROL/skilled-calls"
number=$(( $(cat "$CALLS/count") + 1 ))
echo "$number" > "$CALLS/count"
printf '%s\n' "$*" > "$CALLS/$number.args"
pwd -P > "$CALLS/$number.cwd"
env > "$CALLS/$number.env"
if [ -e "$CONTROL/state/jump" ]; then echo up; else echo down; fi > "$CALLS/$number.chain"
if [ -d "$HOME" ]; then echo yes; else echo no; fi > "$CALLS/$number.home-exists"
if [ -d "$TMPDIR" ]; then echo yes; else echo no; fi > "$CALLS/$number.tmpdir-exists"
if [ -e "$HOME/.skilled/credentials.yaml" ]; then echo yes; else echo no; fi > "$CALLS/$number.credentials-visible"
cat SKILL.md > "$CALLS/$number.skill-text" 2>/dev/null
cat ../tree-marker.txt > "$CALLS/$number.marker" 2>/dev/null
ls .. > "$CALLS/$number.siblings" 2>/dev/null
ls evals > "$CALLS/$number.evals-list" 2>/dev/null
cat evals/fixtures/repos/tree/tree-marker.txt > "$CALLS/$number.fixture-marker" 2>/dev/null
ls evals/fixtures/repos/tree/smith-second > "$CALLS/$number.fixture-skill-list" 2>/dev/null
case "$1" in
  validate | run)
    if [ -f "$2" ]; then cat "$2" > "$CALLS/$number.evalfile"; fi
    ;;
esac
echo "skilled $number: $*" >> "$CONTROL/invocations.log"
case "$*" in
  "validate --skill .") kind=validate-skill ;;
  validate\ *) kind=validate-eval ;;
  *--dry-run) kind=dry-run ;;
  run\ *) kind=run ;;
esac
[ "$FAIL_ON" != "$kind" ] || exit "$FAIL_STATUS"
if [ "$kind" = run ] && [ "$HANG_ON_RUN" = 1 ]; then
  : > "$CONTROL/run-started"
  exec sleep 30
fi
if [ "$kind" = run ] && [ "$HANG_ON_RUN" = ignore-term ]; then
  trap '' TERM
  : > "$CONTROL/run-started"
  while :; do sleep 1; done
fi
if [ "$kind" = run ] && [ "$HANG_ON_RUN" = escaped-grandchild ]; then
  "$GRANDCHILD_NODE" -e "const child = require('child_process').spawn('sleep', ['60'], { detached: true, stdio: ['ignore', 'inherit', 'inherit'] }); require('fs').appendFileSync(process.argv[1], child.pid + '\\n'); child.unref();" "$CONTROL/grandchild-pid"
  : > "$CONTROL/run-started"
  exec sleep 60
fi
if [ "$kind" = run ] && [ "$BLOCK_RUN_LOG" = 1 ]; then
  previous=""
  for argument in "$@"; do
    if [ "$previous" = --output-dir ]; then mkdir -p "$argument/run.txt"; fi
    previous=$argument
  done
fi
if [ "$kind" = run ]; then
  output_dir=""
  iteration_count=1
  previous=""
  for argument in "$@"; do
    if [ "$previous" = --output-dir ]; then output_dir=$argument; fi
    if [ "$previous" = --iteration ]; then iteration_count=$argument; fi
    previous=$argument
  done
  mkdir -p "$output_dir"
  case_entries=""
  every_case_passed=1
  for case_status in $CASE_STATUSES; do
    case_entries="$case_entries${case_entries:+,}{\"case_id\":\"case-$case_status\",\"status\":\"$case_status\"}"
    [ "$case_status" = PASS ] || every_case_passed=0
  done
  iteration=1
  while [ "$iteration" -le "$iteration_count" ]; do
    if [ "$iteration" != "$SKIP_RESULT_OF_ITERATION" ]; then
      mkdir -p "$output_dir/iteration-$iteration"
      printf '{"case_results":[%s]}\n' "$case_entries" > "$output_dir/iteration-$iteration/result.json"
    fi
    iteration=$((iteration + 1))
  done
  echo "report" > "$output_dir/report.html"
  echo "<testsuite/>" > "$output_dir/results.xml"
  echo "{}" > "$output_dir/events.jsonl"
  if [ "$LEAK_KEY" = 1 ]; then printf 'token=%s\n' "$ANTHROPIC_API_KEY" > "$output_dir/leaked.txt"; fi
  if [ "$LEAVE_CONTAINER" = 1 ]; then
    echo skilled-leftover >> "$CONTROL/containers-now"
    echo unrelated-new-box >> "$CONTROL/containers-now"
  fi
  if [ "$every_case_passed" = 0 ]; then
    echo "Error: one or more cases failed"
    exit 1
  fi
fi
echo "skilled fake finished $kind"
exit 0
FAKE

install_fake "$BIN/gh" <<'FAKE'
#!/bin/sh
CONTROL=@CONTROL@
echo "gh $*" >> "$CONTROL/invocations.log"
directory=""
archive_name=""
previous=""
for argument in "$@"; do
  if [ "$previous" = --dir ]; then directory=$argument; fi
  if [ "$previous" = --pattern ]; then
    case "$argument" in
      *.tar.gz) archive_name=$argument ;;
    esac
  fi
  previous=$argument
done
asset=${archive_name%.tar.gz}
staging="$(mktemp -d)" || exit 1
mkdir -p "$staging/$asset"
cp "$CONTROL/skilled-for-archive" "$staging/$asset/skilled"
tar -czf "$directory/$archive_name" -C "$staging" "$asset"
sum=$(shasum -a 256 "$directory/$archive_name" | cut -d' ' -f1)
if [ "$(cat "$CONTROL/gh-mode")" != no-sha256 ]; then
  printf '%s  %s\n' "$sum" "$archive_name" > "$directory/$archive_name.sha256"
fi
printf '%s  %s\n' "$sum" "$archive_name" > "$directory/checksums.txt"
exit 0
FAKE
cp "$SKILLED" "$CONTROL/skilled-for-archive"

CONTEXT_HOST="unix:///fixture/docker.sock"
RESOLVED_VENDOR_FIRST="203.0.113.10"
RESOLVED_VENDOR_SECOND="203.0.113.11"
RESOLVED_REGISTRY="198.51.100.7"

set_probe() {
  cat > "$CONTROL/probe.txt" <<PROBE
api.anthropic.com: $1
example.com: $2
www.google.com: $3
ipv6-literal: $4
foreign-host via $RESOLVED_VENDOR_FIRST: $5
foreign-host via $RESOLVED_VENDOR_SECOND: $5
foreign-host via $RESOLVED_REGISTRY: $5
PROBE
}

write_skilled_conf() {
  printf 'FAIL_ON=\nFAIL_STATUS=7\nLEAK_KEY=0\nLEAVE_CONTAINER=0\nCASE_STATUSES=PASS\nSKIP_RESULT_OF_ITERATION=\nHANG_ON_RUN=0\nBLOCK_RUN_LOG=0\nGRANDCHILD_NODE=%s\n%s\n' "$NODE" "$*" > "$CONTROL/skilled.conf"
}

reset_world() {
  : > "$FAKE_LOG"
  for stale in "$CONTROL/state" "$CALLS" "$CONTROL/trashed" "$CONTROL/run-started" "$CONTROL/grandchild-pid" "$CONTROL/hang-rm" "$CONTROL/rm-started" "$CONTROL/hang-chain-check" "$CONTROL/block-path" "$CONTROL/context-inspect-home"; do
    [ ! -e "$stale" ] || mv "$stale" "$(mktemp -d)" || fail "could not move away: $stale"
  done
  mkdir -p "$CONTROL/state" "$CALLS" "$CONTROL/trashed"
  echo 0 > "$CALLS/count"
  : > "$CONTROL/containers-now"
  : > "$CONTROL/bridge-containers"
  echo false > "$CONTROL/bridge-ipv6"
  echo ok > "$CONTROL/docker-context-mode"
  echo consistent > "$CONTROL/gh-mode"
  echo "$CONTEXT_HOST" > "$CONTROL/docker-context-host"
  echo 192.168.5.2 > "$CONTROL/resolver"
  printf '%s STREAM api.anthropic.com\n%s STREAM api.anthropic.com\n%s STREAM registry.npmjs.org\n' \
    "$RESOLVED_VENDOR_FIRST" "$RESOLVED_VENDOR_SECOND" "$RESOLVED_REGISTRY" > "$CONTROL/resolved.txt"
  set_probe reachable blocked blocked blocked blocked
  write_skilled_conf
  EXPECTED_DOCKER_HOST="$CONTEXT_HOST"
}

fixture_git() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git \
    -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false -C "$FIXTURE" "$@"
}
put() {
  mkdir -p "$(dirname "$FIXTURE/$1")"
  printf '%s\n' "$2" > "$FIXTURE/$1"
}

mkdir "$FIXTURE"
fixture_git init -q -b main
put smith-fixture/SKILL.md "base skill text"
put smith-fixture/evals/eval.yaml "eval file at base for smith-fixture"
put smith-fixture/evals/baseline.eval.yaml "baseline eval file at base for smith-fixture"
put smith-fixture/evals/stale.yaml "stale file at base"
put smith-second/SKILL.md "second base text"
put smith-second/evals/eval.yaml "eval file at base for smith-second"
put smith-third/SKILL.md "third base text"
put tree-marker.txt "marker base"
put README.md "readme"
fixture_git add -A
fixture_git commit -q -m "base"
fixture_git tag fixture-base
put smith-fixture/SKILL.md "changed skill text"
put smith-second/SKILL.md "second changed text"
put tree-marker.txt "marker change"
fixture_git add -A
fixture_git commit -q -m "change"
fixture_git branch fixture-change
fixture_git checkout -q -b fixture-env
put smith-fixture/.env "SECRET=dummy"
fixture_git add -A
fixture_git commit -q -m "env"
fixture_git checkout -q -b fixture-skilled-yaml fixture-change
put smith-fixture/.skilled.yaml "env: {ANTHROPIC_BASE_URL: http://example.invalid}"
fixture_git add -A
fixture_git commit -q -m "skilled yaml"
fixture_git checkout -q main
put smith-fixture/evals/eval.yaml "eval file at head for smith-fixture"
put smith-fixture/evals/baseline.eval.yaml "baseline eval file at head for smith-fixture"
put smith-second/evals/eval.yaml "eval file at head for smith-second"
put smith-second/evals/arm-tree-fixture.txt "evals/fixtures/repos/tree"
put smith-third/evals/eval.yaml "eval file at head for smith-third"
put smith-third/evals/arm-tree-fixture.txt "evals/fixtures/../../../outside"
mv "$FIXTURE/smith-fixture/evals/stale.yaml" "$(mktemp -d)"
fixture_git add -A
fixture_git commit -q -m "head evals"
COMMIT_BASE="$(fixture_git rev-parse fixture-base^{commit})"
COMMIT_CHANGE="$(fixture_git rev-parse fixture-change)"
COMMIT_HEAD="$(fixture_git rev-parse HEAD)"
fixture_git update-ref refs/remotes/origin/main "$COMMIT_BASE"
[ "$COMMIT_BASE" != "$COMMIT_CHANGE" ] || fail "the fixture must give the source and the baseline different commits"

mkdir "$PLACE"
GIT_CONFIG_GLOBAL=/dev/null git init -q -b main "$PLACE"
printf 'ignored/\n' > "$PLACE/.gitignore"
mkdir "$PLACE/existing-out" "$PLACE/existing-out-gitdir" "$PLACE/existing-out-ceiling" "$PLACE/ignored"
ln -s "$PLACE/existing-out" "$TMPD/link-into-repo"

export PATH="$BIN:$PATH"
export HOME="$CALLER_HOME"
export SMITH_CANARY="do-not-leak"
export ANTHROPIC_API_KEY="$KEY"

FIXTURE_ARGS="--repo $FIXTURE --skilled $SKILLED --source fixture-change"
STD_ARGS="$FIXTURE_ARGS --baseline fixture-base"

invoke() {
  "$NODE" "$RUNNER" "$@" > "$TMPD/last.out" 2>&1
  echo $? > "$TMPD/last.rc"
}
last_status() { cat "$TMPD/last.rc"; }
first_line() { grep -n -e "$1" "$FAKE_LOG" | head -n 1 | cut -d: -f1; }
last_line() { grep -n -e "$1" "$FAKE_LOG" | tail -n 1 | cut -d: -f1; }
log_has() { grep -q -e "$1" "$FAKE_LOG"; }
require_line() { [ -n "$2" ] || fail "the invocation log must hold the step: $1"; }

assert_refused() {
  [ "$(last_status)" = 2 ] || fail "$1: must exit 2, got status $(last_status): $(cat "$TMPD/last.out")"
  [ -s "$TMPD/last.out" ] || fail "$1: must print a message"
  [ ! -s "$FAKE_LOG" ] || fail "$1: must start no docker, rdctl or skilled: $(cat "$FAKE_LOG")"
  [ ! -e "$2.work" ] || fail "$1: must create no work folder"
}

kind_of() {
  case "$1" in
    "validate --skill .") echo validate-skill ;;
    validate\ *) echo validate-eval ;;
    *--dry-run) echo dry-run ;;
    run\ *) echo run ;;
  esac
}

call_id_for() {
  for args_file in "$CALLS"/*.args; do
    [ -e "$args_file" ] || continue
    call_id=$(basename "$args_file" .args)
    call_cwd=$(cat "$CALLS/$call_id.cwd")
    [ "$(basename "$call_cwd")" = "$2" ] || continue
    [ "$(basename "$(dirname "$call_cwd")")" = "$3" ] || continue
    [ "$(kind_of "$(cat "$args_file")")" = "$1" ] || continue
    echo "$call_id"
    return 0
  done
  return 1
}

sorted_names() { printf '%s\n' "$@" | LC_ALL=C sort | tr '\n' ' '; }

assert_environment() {
  call=$1
  kind=$2
  label=$3
  work=$4
  names="HOME PATH TMPDIR DOCKER_HOST"
  [ "$kind" != run ] || names="$names ANTHROPIC_API_KEY"
  expected=$(sorted_names $names)
  actual=$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$CALLS/$call.env" | sed 's/=.*//' | grep -vE '^(PWD|SHLVL|_|OLDPWD)$' | LC_ALL=C sort | tr '\n' ' ')
  [ "$actual" = "$expected" ] || fail "$label: the environment of skillEd must hold exactly $expected, got: $actual"
  home=$(sed -n 's/^HOME=//p' "$CALLS/$call.env")
  scratch=$(sed -n 's/^TMPDIR=//p' "$CALLS/$call.env")
  case "$home" in "$work"/*) ;; *) fail "$label: HOME must be a fresh folder under the work folder, got: $home" ;; esac
  case "$scratch" in "$work"/*) ;; *) fail "$label: TMPDIR must be a fresh folder under the work folder, got: $scratch" ;; esac
  [ "$(cat "$CALLS/$call.home-exists")" = yes ] || fail "$label: the HOME folder must exist when skillEd starts"
  [ "$(cat "$CALLS/$call.tmpdir-exists")" = yes ] || fail "$label: the TMPDIR folder must exist when skillEd starts"
  [ "$(cat "$CALLS/$call.credentials-visible")" = no ] || fail "$label: a credentials file planted in the caller's HOME must not be visible to skillEd"
  grep -q "do-not-leak" "$CALLS/$call.env" && fail "$label: an unlisted caller variable must not reach skillEd"
  grep -qF "$CALLER_HOME" "$CALLS/$call.env" && fail "$label: the caller's HOME must not appear in the environment of skillEd"
  [ "$(sed -n 's/^DOCKER_HOST=//p' "$CALLS/$call.env")" = "$EXPECTED_DOCKER_HOST" ] || fail "$label: DOCKER_HOST must be $EXPECTED_DOCKER_HOST, got: $(sed -n 's/^DOCKER_HOST=//p' "$CALLS/$call.env")"
  if [ "$kind" = run ]; then
    [ "$(sed -n 's/^ANTHROPIC_API_KEY=//p' "$CALLS/$call.env")" = "$KEY" ] || fail "$label: the run must receive the key unchanged"
  fi
  return 0
}

assert_arm() {
  out=$1
  skill=$2
  arm=$3
  eval_file=$4
  skill_text=$5
  marker=$6
  eval_text=$7
  model=$8
  iterations=$9
  label="$skill $arm"
  work="$out.work"
  validate_skill=$(call_id_for validate-skill "$skill" "$arm") || fail "$label: skillEd must validate the skill folder from inside it"
  validate_eval=$(call_id_for validate-eval "$skill" "$arm") || fail "$label: skillEd must validate the eval file"
  dry_run=$(call_id_for dry-run "$skill" "$arm") || fail "$label: skillEd must run the eval file with --dry-run"
  real_run=$(call_id_for run "$skill" "$arm") || fail "$label: skillEd must run the eval file for real"
  [ "$validate_skill" -lt "$validate_eval" ] && [ "$validate_eval" -lt "$dry_run" ] && [ "$dry_run" -lt "$real_run" ] \
    || fail "$label: skillEd must run validate --skill, validate eval, dry run, real run in that order"
  [ "$(cat "$CALLS/$validate_skill.args")" = "validate --skill ." ] || fail "$label: the first validation must be exactly: validate --skill ."
  [ "$(cat "$CALLS/$validate_eval.args")" = "validate $eval_file" ] || fail "$label: the second validation must name $eval_file"
  [ "$(cat "$CALLS/$dry_run.args")" = "run $eval_file --dry-run" ] || fail "$label: the dry run must be exactly: run $eval_file --dry-run"
  expected_run="run $eval_file --provider anthropic --model $model --iteration $iterations --output-dir $out/$skill/$arm --format html --format junit --event-log $out/$skill/$arm/events.jsonl"
  [ "$(cat "$CALLS/$real_run.args")" = "$expected_run" ] || fail "$label: the real run must be exactly: $expected_run, got: $(cat "$CALLS/$real_run.args")"
  for early in "$validate_skill" "$validate_eval" "$dry_run"; do
    [ "$(cat "$CALLS/$early.chain")" = down ] || fail "$label: validation and the dry run must happen before the egress chain is up"
  done
  [ "$(cat "$CALLS/$real_run.chain")" = up ] || fail "$label: the real run must happen while the egress chain is up"
  for each in "$validate_skill" "$validate_eval" "$dry_run" "$real_run"; do
    [ "$(cat "$CALLS/$each.skill-text")" = "$skill_text" ] || fail "$label: the skill folder must hold the SKILL.md of its own ref"
    [ "$(cat "$CALLS/$each.marker")" = "$marker" ] || fail "$label: the arm folder must hold the whole tree of its own ref"
    grep -qx "README.md" "$CALLS/$each.siblings" || fail "$label: the arm folder must hold the whole tree, including top-level files"
    grep -qx "tree-marker.txt" "$CALLS/$each.siblings" || fail "$label: the arm folder must hold the whole tree, including top-level files"
    grep -qx "stale.yaml" "$CALLS/$each.evals-list" && fail "$label: the evals folder must be replaced by the one at HEAD, not merged with the ref's"
    grep -qx "eval.yaml" "$CALLS/$each.evals-list" || fail "$label: the evals folder at HEAD must be present"
    assert_environment "$each" "$(kind_of "$(cat "$CALLS/$each.args")")" "$label" "$work"
  done
  for each in "$validate_eval" "$dry_run" "$real_run"; do
    [ "$(cat "$CALLS/$each.evalfile")" = "$eval_text" ] || fail "$label: the eval file must come from HEAD of the repository, got: $(cat "$CALLS/$each.evalfile")"
  done
  return 0
}

arms_line_is() {
  [ -f "$1/arms.txt" ] || return 1
  grep -qxF "skill=$2 arm=$3 ref=$4 commit=$5 eval-file=$6 eval-commit=$COMMIT_HEAD" "$1/arms.txt"
}

assert_sums() {
  [ -f "$1/leak-scan.txt" ] || fail "$2: the leak scan report must be written to leak-scan.txt in the out folder"
  [ -f "$1/SHA256SUMS.txt" ] || fail "$2: SHA256SUMS.txt must be written into the out folder"
  awk '{print $2}' "$1/SHA256SUMS.txt" | sed 's|^\./||;s|^\*||' | grep -qxF "leak-scan.txt" || fail "$2: SHA256SUMS.txt must cover the leak scan report, so it is written after the report"
  (cd "$1" && shasum -a 256 -c SHA256SUMS.txt >/dev/null 2>&1) || fail "$2: SHA256SUMS.txt must verify against the files of the out folder"
  listed=$(awk '{print $2}' "$1/SHA256SUMS.txt" | sed 's|^\./||;s|^\*||' | LC_ALL=C sort)
  present=$(cd "$1" && find . -type f ! -name SHA256SUMS.txt | sed 's|^\./||' | LC_ALL=C sort)
  [ "$listed" = "$present" ] || fail "$2: SHA256SUMS.txt must list every file of the out folder and nothing else"
}

assert_no_key_in_argv() {
  grep -qF "$KEY" "$FAKE_LOG" && fail "$1: the key must never appear in the arguments of docker, rdctl, skillEd or trash"
  for args_file in "$CALLS"/*.args; do
    [ -e "$args_file" ] || continue
    grep -qF "$KEY" "$args_file" && fail "$1: the key must never appear in the arguments of skillEd"
  done
  return 0
}

assert_cleanup_done() {
  out=$1
  label=$2
  [ ! -e "$CONTROL/state/chain" ] || fail "$label: egress down must remove the chain"
  [ ! -e "$CONTROL/state/jump" ] || fail "$label: egress down must remove the jump"
  assert_sums "$out" "$label"
  assert_no_key_in_argv "$label"
}

assert_work_trashed() {
  grep -qxF "trash $1.work" "$FAKE_LOG" || fail "$2: the work folder must be moved to the Trash with: trash $1.work"
  [ ! -e "$1.work" ] || fail "$2: the work folder must be gone after the Trash call"
  [ -d "$1" ] || fail "$2: the out folder must stay"
}

reset_world
OUT="$OUTS/refuse-no-out"
invoke $STD_ARGS smith-fixture
assert_refused "a run without --out" "$OUT"

reset_world
OUT="$OUTS/refuse-no-source"
invoke --out "$OUT" --repo "$FIXTURE" --skilled "$SKILLED" --baseline fixture-base smith-fixture
assert_refused "a run without --source" "$OUT"
[ ! -e "$OUT" ] || fail "a run without --source must create no out folder"

reset_world
OUT="$OUTS/refuse-no-skill"
invoke --out "$OUT" $STD_ARGS
assert_refused "a run without a skill" "$OUT"
[ ! -e "$OUT" ] || fail "a run without a skill must create no out folder"

reset_world
OUT="$OUTS/refuse-key-unset"
( unset ANTHROPIC_API_KEY; invoke --out "$OUT" $STD_ARGS smith-fixture )
assert_refused "a run with ANTHROPIC_API_KEY unset" "$OUT"
[ ! -e "$OUT" ] || fail "a run with ANTHROPIC_API_KEY unset must create no out folder"

reset_world
OUT="$OUTS/refuse-key-empty"
( ANTHROPIC_API_KEY=""; invoke --out "$OUT" $STD_ARGS smith-fixture )
assert_refused "a run with ANTHROPIC_API_KEY empty" "$OUT"
[ ! -e "$OUT" ] || fail "a run with ANTHROPIC_API_KEY empty must create no out folder"

for override in ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN; do
  reset_world
  OUT="$OUTS/refuse-$override"
  ( export "$override=https://override.invalid"; invoke --out "$OUT" $STD_ARGS smith-fixture )
  assert_refused "a run with $override set" "$OUT"
  [ ! -e "$OUT" ] || fail "a run with $override set must create no out folder"
done

reset_world
OUT="$OUTS/refuse-non-empty"
mkdir "$OUT"
echo keep > "$OUT/earlier-result.txt"
invoke --out "$OUT" $STD_ARGS smith-fixture
assert_refused "a run into a non-empty out folder" "$OUT"
[ "$(ls -A "$OUT")" = "earlier-result.txt" ] || fail "a run into a non-empty out folder must leave it untouched"

reset_world
invoke --out "$PLACE/existing-out" $STD_ARGS smith-fixture
assert_refused "an out folder that exists inside a git work tree" "$PLACE/existing-out"

reset_world
invoke --out "$PLACE/not-yet/nested/out" $STD_ARGS smith-fixture
assert_refused "an out path that does not exist yet inside a git work tree" "$PLACE/not-yet/nested/out"
[ ! -e "$PLACE/not-yet" ] || fail "a refused out path must not leave a created folder behind"

reset_world
invoke --out "$PLACE/ignored/out" $STD_ARGS smith-fixture
assert_refused "an out path inside a gitignored folder of a git work tree" "$PLACE/ignored/out"
[ ! -e "$PLACE/ignored/out" ] || fail "a refused gitignored out path must not be created"

reset_world
invoke --out "$TMPD/link-into-repo/via-link" $STD_ARGS smith-fixture
assert_refused "an out path reached through a symlink from outside a git work tree" "$TMPD/link-into-repo/via-link"
[ ! -e "$PLACE/existing-out/via-link" ] || fail "a refused out path reached through a symlink must not be created"

reset_world
invoke --out "$PLACE/.git/eval-out" $STD_ARGS smith-fixture
assert_refused "an out path inside the .git folder of a repository" "$PLACE/.git/eval-out"
[ ! -e "$PLACE/.git/eval-out" ] || fail "a refused out path inside .git must not be created"

reset_world
( GIT_DIR="$TMPD/no-such-gitdir"; export GIT_DIR; invoke --out "$PLACE/existing-out-gitdir/run" $STD_ARGS smith-fixture )
assert_refused "an out path inside a git work tree while GIT_DIR names a nonexistent path" "$PLACE/existing-out-gitdir/run"
[ ! -e "$PLACE/existing-out-gitdir/run" ] || fail "a refused out path must not be created when GIT_DIR misleads git"

reset_world
( GIT_CEILING_DIRECTORIES="$PLACE"; export GIT_CEILING_DIRECTORIES; invoke --out "$PLACE/existing-out-ceiling/run" $STD_ARGS smith-fixture )
assert_refused "an out path inside a git work tree while GIT_CEILING_DIRECTORIES names the repository" "$PLACE/existing-out-ceiling/run"
[ ! -e "$PLACE/existing-out-ceiling/run" ] || fail "a refused out path must not be created when GIT_CEILING_DIRECTORIES misleads git"

assert_refused_for_work() {
  [ "$(last_status)" = 2 ] || fail "$1: must exit 2, got status $(last_status): $(cat "$TMPD/last.out")"
  [ -s "$TMPD/last.out" ] || fail "$1: must print a message"
  [ ! -s "$FAKE_LOG" ] || fail "$1: must start no docker, rdctl or skilled: $(cat "$FAKE_LOG")"
  [ ! -e "$2" ] || fail "$1: must create no out folder"
  [ -e "$2.work" ] || [ -L "$2.work" ] || fail "$1: the existing work path must stay as it was"
}

reset_world
OUT="$OUTS/work-is-folder"
mkdir "$OUT.work"
invoke --out "$OUT" $STD_ARGS smith-fixture
assert_refused_for_work "an existing work folder" "$OUT"

reset_world
OUT="$OUTS/work-is-file"
echo keep > "$OUT.work"
invoke --out "$OUT" $STD_ARGS smith-fixture
assert_refused_for_work "an existing file at the work path" "$OUT"
[ "$(cat "$OUT.work")" = keep ] || fail "an existing file at the work path must stay untouched"

reset_world
OUT="$OUTS/work-is-symlink"
ln -s "$TMPD/caller-home" "$OUT.work"
invoke --out "$OUT" $STD_ARGS smith-fixture
assert_refused_for_work "an existing symlink at the work path" "$OUT"

reset_world
OUT="$OUTS/work-is-dangling-symlink"
ln -s "$TMPD/no-such-target" "$OUT.work"
invoke --out "$OUT" $STD_ARGS smith-fixture
assert_refused_for_work "an existing dangling symlink at the work path" "$OUT"

reset_world
OUT="$OUTS/work-is-symlink-into-repo"
ln -s "$PLACE/existing-out" "$OUT.work"
invoke --out "$OUT" $STD_ARGS smith-fixture
assert_refused_for_work "an existing symlink from the work path into a repository" "$OUT"
[ -z "$(ls -A "$PLACE/existing-out")" ] || fail "a symlink from the work path into a repository must not be written through"

reset_world
OUT="$OUTS/refuse-no-git"
( PATH="$BIN"; export PATH; invoke --out "$OUT" $STD_ARGS smith-fixture )
assert_refused "a run when git is not on PATH" "$OUT"
[ ! -e "$OUT" ] || fail "a run without git must create no out folder"
grep -qi "git" "$TMPD/last.out" || fail "a run without git must say that git is missing, got: $(cat "$TMPD/last.out")"

reset_world
OUT="$OUTS/refuse-env-file"
invoke --out "$OUT" --repo "$FIXTURE" --skilled "$SKILLED" --source fixture-env --baseline fixture-base smith-fixture
[ "$(last_status)" = 2 ] || fail "an arm tree holding a .env file at the skill root must refuse the run with status 2, got status $(last_status): $(cat "$TMPD/last.out")"
grep -q '\.env' "$TMPD/last.out" || fail "the .env refusal must name the .env file, got: $(cat "$TMPD/last.out")"
log_has "skilled [0-9]*:" && fail "an arm tree holding a .env file must be refused before skillEd starts"
log_has "iptables.* -N SMITH-EGRESS" && fail "an arm tree holding a .env file must be refused before the egress chain is raised"

reset_world
OUT="$OUTS/refuse-skilled-yaml"
invoke --out "$OUT" --repo "$FIXTURE" --skilled "$SKILLED" --source fixture-skilled-yaml --baseline fixture-base smith-fixture
[ "$(last_status)" = 2 ] || fail "an arm tree holding a .skilled.yaml file at the skill root must refuse the run with status 2, got status $(last_status): $(cat "$TMPD/last.out")"
grep -qF '.skilled.yaml' "$TMPD/last.out" || fail "the .skilled.yaml refusal must name the .skilled.yaml file, got: $(cat "$TMPD/last.out")"
log_has "skilled [0-9]*:" && fail "an arm tree holding a .skilled.yaml file must be refused before skillEd starts"

reset_world
OUT="$OUTS/main"
invoke --out "$OUT" $STD_ARGS smith-fixture smith-second
[ "$(last_status)" = 0 ] || fail "a clean run must exit 0, got status $(last_status): $(cat "$TMPD/last.out")"
[ -d "$OUT" ] || fail "a clean run must create the out folder"
arms_line_is "$OUT" smith-fixture with-change fixture-change "$COMMIT_CHANGE" evals/eval.yaml || fail "arms.txt must hold the line: skill=smith-fixture arm=with-change ref=fixture-change commit=«resolved» eval-file=evals/eval.yaml eval-commit=«HEAD of --repo»"
arms_line_is "$OUT" smith-fixture baseline fixture-base "$COMMIT_BASE" evals/baseline.eval.yaml || fail "arms.txt must hold the smith-fixture baseline line naming evals/baseline.eval.yaml, which HEAD has"
arms_line_is "$OUT" smith-second with-change fixture-change "$COMMIT_CHANGE" evals/eval.yaml || fail "arms.txt must hold the smith-second with-change line"
arms_line_is "$OUT" smith-second baseline fixture-base "$COMMIT_BASE" evals/eval.yaml || fail "arms.txt must hold the smith-second baseline line naming evals/eval.yaml, because HEAD has no baseline eval file for it"
arms_line_is "$OUT" smith-fixture with-change fixture-change "$COMMIT_CHANGE" evals/baseline.eval.yaml && fail "the with-change arm must not use the baseline eval file"
[ "$(wc -l < "$OUT/arms.txt" | tr -d ' ')" = "$(grep -c '^skill=' "$OUT/arms.txt")" ] || fail "every line of arms.txt must be an arm line starting with skill="
assert_arm "$OUT" smith-fixture with-change evals/eval.yaml "changed skill text" "marker change" "eval file at head for smith-fixture" claude-haiku-5-5 3
assert_arm "$OUT" smith-fixture baseline evals/baseline.eval.yaml "base skill text" "marker base" "baseline eval file at head for smith-fixture" claude-haiku-5-5 3
assert_arm "$OUT" smith-second with-change evals/eval.yaml "second changed text" "marker change" "eval file at head for smith-second" claude-haiku-5-5 3
assert_arm "$OUT" smith-second baseline evals/eval.yaml "second base text" "marker base" "eval file at head for smith-second" claude-haiku-5-5 3
first_validate=$(first_line 'skilled [0-9]*: validate')
last_dry_run=$(last_line 'skilled [0-9]*: run .*--dry-run')
egress_up=$(first_line 'iptables.* -N SMITH-EGRESS')
jump_in=$(first_line 'iptables.* -I DOCKER-USER')
probe_run=$(grep -n '^docker run' "$FAKE_LOG" | grep -v getent | head -n 1 | cut -d: -f1)
first_real_run=$(first_line 'skilled [0-9]*: run .*--provider')
last_real_run=$(last_line 'skilled [0-9]*: run .*--provider')
egress_down=$(first_line 'iptables.* -D DOCKER-USER')
trash_call=$(first_line '^trash ')
require_line "the first validation" "$first_validate"
require_line "the last dry run" "$last_dry_run"
require_line "the egress chain being created" "$egress_up"
require_line "the jump being inserted" "$jump_in"
require_line "the egress probe" "$probe_run"
require_line "the first real run" "$first_real_run"
require_line "the last real run" "$last_real_run"
require_line "the egress down" "$egress_down"
require_line "the Trash call" "$trash_call"
[ "$first_validate" -lt "$last_dry_run" ] || fail "validation must start before the dry runs end"
[ "$last_dry_run" -lt "$egress_up" ] || fail "every dry run must finish before egress up"
[ "$egress_up" -lt "$jump_in" ] || fail "egress up must build the chain before it inserts the jump"
[ "$jump_in" -lt "$probe_run" ] || fail "the egress probe must run after egress up"
[ "$probe_run" -lt "$first_real_run" ] || fail "the egress probe must finish before the first real run"
[ "$last_real_run" -lt "$egress_down" ] || fail "egress down must come after the last real run"
[ "$egress_down" -lt "$trash_call" ] || fail "the work folder must be trashed after egress down"
log_has '^docker rm' && fail "a run that left no new container must remove no container"
grep -rl "chain present" "$OUT" --exclude=SHA256SUMS.txt >/dev/null 2>&1 || fail "the egress status taken before down must be recorded in the out folder"
assert_cleanup_done "$OUT" "clean run"
assert_work_trashed "$OUT" "clean run"
grep -qx 'files-read: yes' "$OUT/leak-scan.txt" || fail "clean run: leak-scan.txt must hold the full line: files-read: yes"
[ ! -e "$OUT/LEAK-FOUND" ] || fail "clean run: no LEAK-FOUND marker may exist"
[ "$(grep -c '^trash ' "$FAKE_LOG")" = 1 ] || fail "a clean run must trash only the work folder"
context_lookup=$(grep -nxF "docker context inspect --format {{.Endpoints.docker.Host}}" "$FAKE_LOG" | head -n 1 | cut -d: -f1)
require_line "the docker context lookup: docker context inspect --format {{.Endpoints.docker.Host}}" "$context_lookup"
[ "$context_lookup" -lt "$first_validate" ] || fail "the docker context lookup must happen before the first skillEd start"
[ "$(cat "$CONTROL/context-inspect-home")" = "$CALLER_HOME" ] || fail "the docker context lookup must run in the caller's own environment, so the caller's HOME"

reset_world
OUT="$OUTS/options"
( DOCKER_HOST="tcp://127.0.0.1:2375"; export DOCKER_HOST; invoke --out "$OUT" --repo "$FIXTURE" --skilled "$SKILLED" --source fixture-change --model claude-test-model --iterations 2 smith-fixture )
[ "$(last_status)" = 0 ] || fail "a run with --model, --iterations and no --baseline must exit 0, got status $(last_status): $(cat "$TMPD/last.out")"
EXPECTED_DOCKER_HOST="tcp://127.0.0.1:2375"
[ "$EXPECTED_DOCKER_HOST" != "$CONTEXT_HOST" ] || fail "the fixture must give the caller's DOCKER_HOST a value different from the docker context's"
log_has '^docker context inspect' && fail "a caller-provided DOCKER_HOST must pass through without any docker context lookup"
arms_line_is "$OUT" smith-fixture baseline origin/main "$COMMIT_BASE" evals/baseline.eval.yaml || fail "without --baseline the baseline arm must come from origin/main"
assert_arm "$OUT" smith-fixture with-change evals/eval.yaml "changed skill text" "marker change" "eval file at head for smith-fixture" claude-test-model 2
assert_arm "$OUT" smith-fixture baseline evals/baseline.eval.yaml "base skill text" "marker base" "baseline eval file at head for smith-fixture" claude-test-model 2
assert_cleanup_done "$OUT" "run with options"

reset_world
OUT="$OUTS/empty-docker-host"
( DOCKER_HOST=""; export DOCKER_HOST; invoke --out "$OUT" $STD_ARGS smith-fixture )
[ "$(last_status)" = 0 ] || fail "a run with an empty caller DOCKER_HOST must exit 0, got status $(last_status): $(cat "$TMPD/last.out")"
log_has '^docker context inspect' || fail "an empty caller DOCKER_HOST must count as none and trigger the docker context lookup"
assert_arm "$OUT" smith-fixture with-change evals/eval.yaml "changed skill text" "marker change" "eval file at head for smith-fixture" claude-haiku-5-5 3

assert_context_refusal() {
  [ "$(last_status)" = 2 ] || fail "$1: must exit 2, got status $(last_status): $(cat "$TMPD/last.out")"
  grep -qi "docker context" "$TMPD/last.out" || fail "$1: the message must name the docker context, got: $(cat "$TMPD/last.out")"
  log_has '^docker context inspect' || fail "$1: the runner must have asked docker for the context endpoint"
  log_has "skilled [0-9]*:" && fail "$1: skillEd must never start"
  log_has "iptables.* -N SMITH-EGRESS" && fail "$1: egress must never be raised"
  [ ! -e "$2/arms.txt" ] || fail "$1: the refusal must come before any arm is built"
}

reset_world
echo fail > "$CONTROL/docker-context-mode"
OUT="$OUTS/context-lookup-fails"
invoke --out "$OUT" $STD_ARGS smith-fixture
assert_context_refusal "a failing docker context lookup" "$OUT"

reset_world
echo empty > "$CONTROL/docker-context-mode"
OUT="$OUTS/context-lookup-empty"
invoke --out "$OUT" $STD_ARGS smith-fixture
assert_context_refusal "a docker context lookup that prints nothing" "$OUT"

reset_world
OUT="$OUTS/git-dir-set"
( GIT_DIR="$PLACE/.git"; export GIT_DIR; invoke --out "$OUT" $STD_ARGS smith-fixture )
[ "$(last_status)" = 0 ] || fail "a run in a plain folder must exit 0 although the caller's GIT_DIR names another repository, got status $(last_status): $(cat "$TMPD/last.out")"
arms_line_is "$OUT" smith-fixture with-change fixture-change "$COMMIT_CHANGE" evals/eval.yaml || fail "the caller's GIT_DIR must not redirect the runner's own git calls away from --repo"

for failing_step in validate-skill validate-eval dry-run; do
  reset_world
  write_skilled_conf "FAIL_ON=$failing_step"
  OUT="$OUTS/fail-$failing_step"
  invoke --out "$OUT" $STD_ARGS smith-fixture
  [ "$(last_status)" = 3 ] || fail "a failing $failing_step must exit 3, got status $(last_status): $(cat "$TMPD/last.out")"
  log_has "iptables.* -N SMITH-EGRESS" && fail "a failing $failing_step must stop before egress up"
  log_has "skilled [0-9]*: run .*--provider" && fail "a failing $failing_step must stop before any real run"
  assert_cleanup_done "$OUT" "failing $failing_step"
  assert_work_trashed "$OUT" "failing $failing_step"
  grep -rl "chain absent" "$OUT" --exclude=SHA256SUMS.txt >/dev/null 2>&1 || fail "a failing $failing_step must still record the egress status in the out folder"
done

another_run_chain() {
  touch "$CONTROL/state/chain" "$CONTROL/state/jump"
}

assert_other_chain_kept() {
  [ -e "$CONTROL/state/chain" ] || fail "$1: the chain of another run must stay in place"
  [ -e "$CONTROL/state/jump" ] || fail "$1: the jump of another run must stay in place"
  log_has "iptables.* -D DOCKER-USER" && fail "$1: a run that did not raise egress must never remove the jump"
  log_has "iptables.* -X SMITH-EGRESS" && fail "$1: a run that did not raise egress must never delete the chain"
  assert_sums "$OUT" "$1"
}

reset_world
another_run_chain
OUT="$OUTS/other-run-chain-up-refused"
invoke --out "$OUT" $STD_ARGS smith-fixture
[ "$(last_status)" = 6 ] || fail "egress up refused because another run holds the chain must exit 6, got status $(last_status): $(cat "$TMPD/last.out")"
log_has "skilled [0-9]*: run .*--provider" && fail "a refused egress up must stop before any real run"
assert_other_chain_kept "egress up refused for an existing chain"

reset_world
another_run_chain
write_skilled_conf "FAIL_ON=validate-skill" "FAIL_STATUS=1"
OUT="$OUTS/other-run-chain-validate-failed"
invoke --out "$OUT" $STD_ARGS smith-fixture
[ "$(last_status)" = 3 ] || fail "a failing validation while another run holds the chain must exit 3, got status $(last_status): $(cat "$TMPD/last.out")"
assert_other_chain_kept "a failing validation while another run holds the chain"

reset_world
OUT="$OUTS/egress-log-unwritable"
printf '%s\n' "$OUT/egress-up.txt" > "$CONTROL/block-path"
invoke --out "$OUT" $STD_ARGS smith-fixture
[ "$(last_status)" = 7 ] || fail "a run whose egress-up.txt cannot be written must exit 7, got status $(last_status): $(cat "$TMPD/last.out")"
grep -q "egress-up.txt" "$TMPD/last.out" || fail "an egress-up.txt that cannot be written must be named, got: $(cat "$TMPD/last.out")"

reset_world
write_skilled_conf "BLOCK_RUN_LOG=1"
OUT="$OUTS/run-log-unwritable"
invoke --out "$OUT" $STD_ARGS smith-fixture
[ "$(last_status)" = 7 ] || fail "a real run whose run.txt cannot be written must exit 7, got status $(last_status): $(cat "$TMPD/last.out")"
grep -q "run.txt" "$TMPD/last.out" || fail "a run.txt that cannot be written must be named, got: $(cat "$TMPD/last.out")"
grep -q "unexpected failure" "$TMPD/last.out" && fail "a run.txt that cannot be written must not end in an unexpected failure: $(cat "$TMPD/last.out")"
log_has "skilled [0-9]*: run .*smith-fixture/baseline" || fail "a run.txt that cannot be written must not stop the next arm"
assert_cleanup_done "$OUT" "run.txt that cannot be written"
grep -qx 'files-read: yes' "$OUT/leak-scan.txt" || fail "run.txt that cannot be written: the leak scan must still run"

reset_world
set_probe unreachable blocked blocked blocked blocked
OUT="$OUTS/fail-probe"
invoke --out "$OUT" $STD_ARGS smith-fixture
[ "$(last_status)" = 5 ] || fail "a failing egress probe must exit 5, got status $(last_status): $(cat "$TMPD/last.out")"
log_has "iptables.* -N SMITH-EGRESS" || fail "a failing egress probe must come after egress up"
log_has "skilled [0-9]*: run .*--provider" && fail "a failing egress probe must stop before any real run"
log_has "iptables.* -D DOCKER-USER" || fail "egress down must still run after a failing egress probe"
assert_cleanup_done "$OUT" "failing probe"
assert_work_trashed "$OUT" "failing probe"

reset_world
write_skilled_conf "FAIL_ON=run" "FAIL_STATUS=1"
OUT="$OUTS/fail-run"
invoke --out "$OUT" $STD_ARGS smith-fixture
[ "$(last_status)" = 7 ] || fail "a real run that wrote no result must exit 7, got status $(last_status): $(cat "$TMPD/last.out")"
grep -q "smith-fixture with-change" "$TMPD/last.out" || fail "a real run that wrote no result must name the skill and arm, got: $(cat "$TMPD/last.out")"
log_has "iptables.* -D DOCKER-USER" || fail "egress down must still run after a failing real run"
assert_cleanup_done "$OUT" "failing real run"
assert_work_trashed "$OUT" "failing real run"

reset_world
write_skilled_conf "CASE_STATUSES='PASS FAIL'"
OUT="$OUTS/failing-verdicts"
invoke --out "$OUT" $STD_ARGS smith-fixture
[ "$(last_status)" = 0 ] || fail "a run whose every case reached PASS or FAIL must exit 0 although skillEd exited non-zero, got status $(last_status): $(cat "$TMPD/last.out")"
grep -q '"status":"FAIL"' "$OUT/smith-fixture/baseline/iteration-1/result.json" || fail "failing verdicts: the fake must have written a FAIL case"
assert_cleanup_done "$OUT" "failing verdicts"
assert_work_trashed "$OUT" "failing verdicts"

reset_world
write_skilled_conf "CASE_STATUSES='PASS ERROR'"
OUT="$OUTS/errored-case"
invoke --out "$OUT" $STD_ARGS smith-fixture
[ "$(last_status)" = 7 ] || fail "a run with a case that reached neither PASS nor FAIL must exit 7, got status $(last_status): $(cat "$TMPD/last.out")"
grep -q "case-ERROR" "$TMPD/last.out" || fail "an errored case must be named, got: $(cat "$TMPD/last.out")"
assert_cleanup_done "$OUT" "errored case"
assert_work_trashed "$OUT" "errored case"

reset_world
write_skilled_conf "SKIP_RESULT_OF_ITERATION=2"
OUT="$OUTS/missing-iteration"
invoke --out "$OUT" $STD_ARGS --iterations 2 smith-fixture
[ "$(last_status)" = 7 ] || fail "a run that lacks the result of an iteration must exit 7 although skillEd exited 0, got status $(last_status): $(cat "$TMPD/last.out")"
grep -q "iteration-2" "$TMPD/last.out" || fail "the iteration without a result must be named, got: $(cat "$TMPD/last.out")"

reset_world
write_skilled_conf "CASE_STATUSES="
OUT="$OUTS/no-case"
invoke --out "$OUT" $STD_ARGS smith-fixture
[ "$(last_status)" = 7 ] || fail "a run whose result holds no case must exit 7, got status $(last_status): $(cat "$TMPD/last.out")"

reset_world
write_skilled_conf "LEAK_KEY=1"
OUT="$OUTS/leak-hit"
invoke --out "$OUT" $STD_ARGS smith-fixture
[ "$(last_status)" = 9 ] || fail "a scan hit must exit 9, got status $(last_status): $(cat "$TMPD/last.out")"
[ -d "$OUT.work" ] || fail "a scan hit must keep the work folder"
log_has '^trash ' && fail "a scan hit must trash nothing"
[ ! -e "$CONTROL/state/chain" ] || fail "a scan hit must not skip egress down"
[ -f "$OUT/LEAK-FOUND" ] || fail "scan hit: the scan must leave LEAK-FOUND in the out folder"
assert_sums "$OUT" "scan hit"
assert_no_key_in_argv "scan hit"

reset_world
write_skilled_conf "LEAVE_CONTAINER=1"
OUT="$OUTS/leftover"
invoke --out "$OUT" $STD_ARGS smith-fixture
[ "$(last_status)" = 0 ] || fail "a run that left a skilled- container behind must still exit 0 once it is removed, got status $(last_status): $(cat "$TMPD/last.out")"
grep -qxF "docker rm -f skilled-leftover" "$FAKE_LOG" || fail "a skilled- container created during the run must be removed with: docker rm -f skilled-leftover"
log_has "docker rm -f unrelated-new-box" && fail "only containers named skilled-* may be removed"
removal_line=$(first_line '^docker rm -f skilled-leftover')
leftover_down=$(first_line 'iptables.* -D DOCKER-USER')
require_line "the egress down" "$leftover_down"
[ "$removal_line" -lt "$leftover_down" ] || fail "leftover containers must be removed before egress down"
assert_cleanup_done "$OUT" "leftover container"
assert_work_trashed "$OUT" "leftover container"

reset_world
printf 'skilled-preexisting\nunrelated-old-box\n' > "$CONTROL/containers-now"
OUT="$OUTS/preexisting"
invoke --out "$OUT" $STD_ARGS smith-fixture
[ "$(last_status)" = 4 ] || fail "a pre-existing skilled- container must refuse the run with status 4, got status $(last_status): $(cat "$TMPD/last.out")"
grep -q "skilled-preexisting" "$TMPD/last.out" || fail "the refusal for a pre-existing container must name it, got: $(cat "$TMPD/last.out")"
log_has '^docker rm' && fail "a container that existed before the run must never be removed"
log_has "skilled [0-9]*:" && fail "a pre-existing skilled- container must refuse the run before skillEd starts"
log_has "iptables.* -N SMITH-EGRESS" && fail "a pre-existing skilled- container must refuse the run before egress up"
[ ! -e "$OUT/arms.txt" ] || fail "a pre-existing skilled- container must refuse the run before any arm is built"
grep -qx "skilled-preexisting" "$CONTROL/containers-now" || fail "a pre-existing container must stay"

reset_world
printf 'skilled-preexisting\n' > "$CONTROL/containers-now"
OUT="$OUTS/preexisting-no-key"
( unset ANTHROPIC_API_KEY; invoke --out "$OUT" $STD_ARGS smith-fixture )
[ "$(last_status)" = 2 ] || fail "the key check must come before the container check, got status $(last_status): $(cat "$TMPD/last.out")"

reset_world
printf 'skilled-preexisting\n' > "$CONTROL/containers-now"
invoke --out "$PLACE/existing-out" $STD_ARGS smith-fixture
[ "$(last_status)" = 2 ] || fail "the placement check must come before the container check, got status $(last_status): $(cat "$TMPD/last.out")"

reset_world
printf 'unrelated-old-box\n' > "$CONTROL/containers-now"
OUT="$OUTS/unrelated-container"
invoke --out "$OUT" $STD_ARGS smith-fixture
[ "$(last_status)" = 0 ] || fail "a pre-existing container whose name does not start with skilled- must not refuse the run, got status $(last_status): $(cat "$TMPD/last.out")"

reset_world
OUT="$OUTS/arm-tree-fixture"
invoke --out "$OUT" $STD_ARGS smith-second
[ "$(last_status)" = 0 ] || fail "a run of a skill with evals/arm-tree-fixture.txt must exit 0, got status $(last_status): $(cat "$TMPD/last.out")"
for arm_and_marker in "with-change:marker change" "baseline:marker base"; do
  arm=${arm_and_marker%%:*}
  marker=${arm_and_marker#*:}
  for kind in dry-run run; do
    call=$(call_id_for "$kind" smith-second "$arm") || fail "arm-tree fixture: skillEd must reach $kind for smith-second $arm"
    [ "$(cat "$CALLS/$call.fixture-marker")" = "$marker" ] || fail "arm-tree fixture: the folder named in evals/arm-tree-fixture.txt must hold the tree of the $arm ref at $kind, got: $(cat "$CALLS/$call.fixture-marker")"
    grep -qx "SKILL.md" "$CALLS/$call.fixture-skill-list" || fail "arm-tree fixture: the fixture of $arm must hold the skill's own folder"
    grep -qx "evals" "$CALLS/$call.fixture-skill-list" && fail "arm-tree fixture: the fixture of $arm must not hold the skill's evals folder"
  done
done
call=$(call_id_for run smith-fixture with-change) && fail "arm-tree fixture: only the named skill may run"

reset_world
OUT="$OUTS/arm-tree-fixture-outside"
invoke --out "$OUT" $STD_ARGS smith-third
[ "$(last_status)" = 2 ] || fail "an evals/arm-tree-fixture.txt path outside evals/fixtures/ must exit 2, got status $(last_status): $(cat "$TMPD/last.out")"
grep -q "arm-tree-fixture.txt" "$TMPD/last.out" || fail "the refusal of an arm-tree fixture path must name the file, got: $(cat "$TMPD/last.out")"
log_has "skilled [0-9]*:" && fail "an arm-tree fixture path outside evals/fixtures/ must refuse before skillEd starts"
[ ! -e "$OUT.work/smith-third/with-change/outside" ] || fail "an arm-tree fixture path outside evals/fixtures/ must write nothing there"

interrupt_during_real_run() {
  signal=$1
  "$NODE" "$RUNNER" --out "$OUT" $STD_ARGS smith-fixture > "$TMPD/last.out" 2>&1 &
  runner_pid=$!
  waited=0
  while [ ! -e "$CONTROL/run-started" ] && [ "$waited" -lt 300 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done
  [ -e "$CONTROL/run-started" ] || { kill -KILL "$runner_pid"; fail "interrupt by $signal: the real run never started: $(cat "$TMPD/last.out")"; }
  kill "-$signal" "$runner_pid"
  wait "$runner_pid"
  echo $? > "$TMPD/last.rc"
}

reset_world
write_skilled_conf "HANG_ON_RUN=1"
OUT="$OUTS/interrupt-term"
interrupt_during_real_run TERM
[ "$(last_status)" = 143 ] || fail "a run stopped by SIGTERM during a real run must exit 143, got status $(last_status): $(cat "$TMPD/last.out")"
log_has "skilled [0-9]*: run .*smith-fixture/baseline" && fail "an interrupted run must start no further arm"
assert_cleanup_done "$OUT" "interrupt by SIGTERM"
assert_work_trashed "$OUT" "interrupt by SIGTERM"

reset_world
write_skilled_conf "HANG_ON_RUN=1"
OUT="$OUTS/interrupt-int"
interrupt_during_real_run INT
[ "$(last_status)" = 130 ] || fail "a run stopped by SIGINT during a real run must exit 130, got status $(last_status): $(cat "$TMPD/last.out")"
assert_cleanup_done "$OUT" "interrupt by SIGINT"

reset_world
write_skilled_conf "HANG_ON_RUN=ignore-term"
OUT="$OUTS/interrupt-hup"
interrupt_during_real_run HUP
[ "$(last_status)" = 129 ] || fail "a run stopped by SIGHUP, as when its terminal closes, must exit 129, got status $(last_status): $(cat "$TMPD/last.out")"
pgrep -f "$SKILLED" > /dev/null && fail "interrupt-hup: skillEd must not outlive a runner stopped by SIGHUP"
assert_cleanup_done "$OUT" "interrupt by SIGHUP"

WATCHDOG_TEST_LIMIT_TENTHS=200
GRACE_TEST_LIMIT_TENTHS=400

stop_leftovers() {
  kill -KILL "$1" 2>/dev/null
  pkill -KILL -f "$SKILLED"
  stop_grandchildren
}

stop_grandchildren() {
  [ -s "$CONTROL/grandchild-pid" ] || return 0
  while read -r grandchild; do kill -KILL "$grandchild" 2>/dev/null; done < "$CONTROL/grandchild-pid"
}

stop_hanging_removal() {
  [ -s "$CONTROL/rm-started" ] || return 0
  kill -KILL "$(cat "$CONTROL/rm-started")" 2>/dev/null
}

interrupt_hanging_run() {
  signal_count=$1
  limit_tenths=$2
  shift 2
  "$NODE" "$RUNNER" "$@" > "$TMPD/last.out" 2>&1 &
  runner_pid=$!
  waited=0
  while [ ! -e "$CONTROL/run-started" ] && [ "$waited" -lt 300 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done
  [ -e "$CONTROL/run-started" ] || { stop_leftovers "$runner_pid"; fail "$OUT: the real run never started: $(cat "$TMPD/last.out")"; }
  sent=0
  while [ "$sent" -lt "$signal_count" ]; do
    kill -TERM "$runner_pid"
    sent=$((sent + 1))
    sleep 0.2
  done
  waited=0
  while kill -0 "$runner_pid" 2>/dev/null && [ "$waited" -lt "$limit_tenths" ]; do
    sleep 0.1
    waited=$((waited + 1))
  done
  if kill -0 "$runner_pid" 2>/dev/null; then
    stop_leftovers "$runner_pid"
    wait "$runner_pid"
    fail "$OUT: the runner was still alive $limit_tenths tenths of a second after $signal_count SIGTERM: $(cat "$TMPD/last.out")"
  fi
  wait "$runner_pid"
  echo $? > "$TMPD/last.rc"
}

run_unattended_with_limit() {
  limit_tenths=$1
  shift
  "$NODE" "$RUNNER" "$@" > "$TMPD/last.out" 2>&1 &
  runner_pid=$!
  (
    waited=0
    while kill -0 "$runner_pid" 2>/dev/null && [ "$waited" -lt "$limit_tenths" ]; do
      sleep 0.1
      waited=$((waited + 1))
    done
    if kill -0 "$runner_pid" 2>/dev/null; then
      : > "$CONTROL/runner-outlived-limit"
      stop_leftovers "$runner_pid"
    fi
  ) &
  watcher_pid=$!
  wait "$runner_pid"
  echo $? > "$TMPD/last.rc"
  wait "$watcher_pid"
  [ ! -e "$CONTROL/runner-outlived-limit" ] || fail "$OUT: the runner was still alive after the test's own limit, so nothing stopped the hanging run: $(cat "$TMPD/last.out")"
}

reset_world
write_skilled_conf "HANG_ON_RUN=1"
OUT="$OUTS/watchdog"
run_unattended_with_limit "$WATCHDOG_TEST_LIMIT_TENTHS" --out "$OUT" $STD_ARGS --seconds-per-iteration 1 --iterations 1 smith-fixture
[ "$(last_status)" = 7 ] || fail "a real run stopped by the watchdog must exit 7, got status $(last_status): $(cat "$TMPD/last.out")"
[ -e "$CONTROL/run-started" ] || fail "watchdog: the real run never started: $(cat "$TMPD/last.out")"
grep -q "the watchdog stopped smith-fixture with-change" "$TMPD/last.out" || fail "the watchdog must print a line with: the watchdog stopped smith-fixture with-change, got: $(cat "$TMPD/last.out")"
log_has "iptables.* -D DOCKER-USER" || fail "egress down must still run after the watchdog stopped a run"
assert_cleanup_done "$OUT" "watchdog stop"
assert_work_trashed "$OUT" "watchdog stop"
grep -qx 'files-read: yes' "$OUT/leak-scan.txt" || fail "watchdog stop: the leak scan must still run and write: files-read: yes"
[ ! -e "$OUT/LEAK-FOUND" ] || fail "watchdog stop: no LEAK-FOUND marker may exist"

reset_world
write_skilled_conf "HANG_ON_RUN=ignore-term"
OUT="$OUTS/watchdog-ignore-term"
run_unattended_with_limit "$GRACE_TEST_LIMIT_TENTHS" --out "$OUT" $STD_ARGS --seconds-per-iteration 1 --iterations 1 smith-fixture
[ "$(last_status)" = 7 ] || fail "a real run that ignores SIGTERM and is stopped by the watchdog must exit 7, got status $(last_status): $(cat "$TMPD/last.out")"
grep -q "the watchdog stopped smith-fixture with-change" "$TMPD/last.out" || fail "watchdog-ignore-term: the watchdog line must be printed, got: $(cat "$TMPD/last.out")"
pgrep -f "$SKILLED" > /dev/null && fail "watchdog-ignore-term: no process of the stopped run may outlive the runner"
assert_cleanup_done "$OUT" "watchdog stop of a run that ignores SIGTERM"

reset_world
write_skilled_conf "HANG_ON_RUN=escaped-grandchild"
OUT="$OUTS/watchdog-escaped-grandchild"
run_unattended_with_limit "$GRACE_TEST_LIMIT_TENTHS" --out "$OUT" $STD_ARGS --seconds-per-iteration 1 --iterations 1 smith-fixture
stop_grandchildren
[ "$(last_status)" = 7 ] || fail "a real run whose escaped grandchild holds the output pipe must still end with exit 7, got status $(last_status): $(cat "$TMPD/last.out")"
assert_cleanup_done "$OUT" "watchdog stop with an escaped grandchild holding the pipe"

reset_world
write_skilled_conf "HANG_ON_RUN=ignore-term"
OUT="$OUTS/interrupt-ignore-term"
interrupt_hanging_run 1 "$GRACE_TEST_LIMIT_TENTHS" --out "$OUT" $STD_ARGS smith-fixture
[ "$(last_status)" = 143 ] || fail "a run that ignores SIGTERM, stopped by one SIGTERM, must exit 143, got status $(last_status): $(cat "$TMPD/last.out")"
pgrep -f "$SKILLED" > /dev/null && fail "interrupt-ignore-term: no process of the stopped run may outlive the runner"
assert_cleanup_done "$OUT" "interrupt of a run that ignores SIGTERM"

reset_world
write_skilled_conf "HANG_ON_RUN=ignore-term"
OUT="$OUTS/interrupt-twice"
interrupt_hanging_run 2 50 --out "$OUT" $STD_ARGS smith-fixture
[ "$(last_status)" = 143 ] || fail "a second SIGTERM must force the stop and keep exit 143, got status $(last_status): $(cat "$TMPD/last.out")"
assert_cleanup_done "$OUT" "a second SIGTERM"

reset_world
write_skilled_conf "LEAVE_CONTAINER=1"
: > "$CONTROL/hang-rm"
OUT="$OUTS/cleanup-step-hangs"
"$NODE" "$RUNNER" --out "$OUT" $STD_ARGS smith-fixture > "$TMPD/last.out" 2>&1 &
runner_pid=$!
waited=0
while [ ! -e "$CONTROL/rm-started" ] && [ "$waited" -lt 300 ]; do
  sleep 0.1
  waited=$((waited + 1))
done
[ -e "$CONTROL/rm-started" ] || { kill -KILL "$runner_pid"; stop_hanging_removal; fail "cleanup-step-hangs: the container removal never started: $(cat "$TMPD/last.out")"; }
kill -TERM "$runner_pid"
sleep 0.2
kill -TERM "$runner_pid"
waited=0
while kill -0 "$runner_pid" 2>/dev/null && [ "$waited" -lt 50 ]; do
  sleep 0.1
  waited=$((waited + 1))
done
if kill -0 "$runner_pid" 2>/dev/null; then
  kill -KILL "$runner_pid"
  stop_hanging_removal
  wait "$runner_pid"
  fail "cleanup-step-hangs: a second SIGTERM must stop a cleanup step that hangs, the runner was still alive: $(cat "$TMPD/last.out")"
fi
wait "$runner_pid"
echo $? > "$TMPD/last.rc"
[ "$(last_status)" != 0 ] || fail "cleanup-step-hangs: a cleanup step stopped by a second signal must not exit 0"
assert_cleanup_done "$OUT" "a cleanup step stopped by a second SIGTERM"
grep -qx 'files-read: yes' "$OUT/leak-scan.txt" || fail "cleanup-step-hangs: the leak scan must still run after the stopped step"

reset_world
another_run_chain
: > "$CONTROL/hang-chain-check"
OUT="$OUTS/other-run-chain-up-interrupted"
interrupt_hanging_run 1 "$GRACE_TEST_LIMIT_TENTHS" --out "$OUT" $STD_ARGS smith-fixture
[ "$(last_status)" = 143 ] || fail "a run stopped by SIGTERM during egress up must exit 143, got status $(last_status): $(cat "$TMPD/last.out")"
assert_other_chain_kept "an egress up interrupted while another run holds the chain"

reset_world
OUT="$OUTS/refuse-timer-overflow"
invoke --out "$OUT" $STD_ARGS --iterations 3 --seconds-per-iteration 1000000 smith-fixture
assert_refused "--iterations 3 --seconds-per-iteration 1000000" "$OUT"
grep -q "2147483 seconds" "$TMPD/last.out" || fail "a total time above the longest timer must be refused with its limit, 2147483 seconds, got: $(cat "$TMPD/last.out")"
[ ! -e "$OUT" ] || fail "a total time above the longest timer must create no out folder"

for bad_seconds in 0 abc; do
  reset_world
  OUT="$OUTS/refuse-seconds-$bad_seconds"
  invoke --out "$OUT" $STD_ARGS --seconds-per-iteration "$bad_seconds" smith-fixture
  assert_refused "--seconds-per-iteration $bad_seconds" "$OUT"
  grep -qi "positive" "$TMPD/last.out" || fail "--seconds-per-iteration $bad_seconds: the refusal must say that a positive whole number is required, got: $(cat "$TMPD/last.out")"
  [ ! -e "$OUT" ] || fail "--seconds-per-iteration $bad_seconds must create no out folder"
done

reset_world
OUT="$OUTS/download-unpinned"
invoke --out "$OUT" --repo "$FIXTURE" --source fixture-change --baseline fixture-base smith-fixture
log_has "^gh release download v0.3.0 " || fail "a run without --skilled must download skillEd v0.3.0 with gh: $(cat "$TMPD/last.out")"
[ "$(last_status)" = 2 ] || fail "an archive whose SHA-256 differs from the pinned value must be refused with exit 2, although the release's own checksum files agree with it, got status $(last_status): $(cat "$TMPD/last.out")"
grep -qi "pinned" "$TMPD/last.out" || fail "the refusal of an archive that differs from the pinned SHA-256 must say so, got: $(cat "$TMPD/last.out")"
log_has "skilled [0-9]*:" && fail "an archive that differs from the pinned SHA-256 must never be run: $(cat "$FAKE_LOG")"

reset_world
echo no-sha256 > "$CONTROL/gh-mode"
OUT="$OUTS/download-no-sha256"
invoke --out "$OUT" --repo "$FIXTURE" --source fixture-change --baseline fixture-base smith-fixture
[ "$(last_status)" = 2 ] || fail "a release without the archive's .sha256 asset must be refused with exit 2, got status $(last_status): $(cat "$TMPD/last.out")"
grep -q "unexpected failure" "$TMPD/last.out" && fail "a missing .sha256 asset must be a refusal, not an unexpected failure: $(cat "$TMPD/last.out")"
grep -qF ".sha256" "$TMPD/last.out" || fail "the refusal of a missing .sha256 asset must name it, got: $(cat "$TMPD/last.out")"
log_has "skilled [0-9]*:" && fail "an archive without its .sha256 asset must never be run: $(cat "$FAKE_LOG")"

echo "PASS: behaviour-eval"
