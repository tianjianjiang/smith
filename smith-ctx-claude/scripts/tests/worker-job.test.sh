#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
JOB="$HERE/../worker-job.sh"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: worker-job - $1"; }

export SMITH_JOB_HEARTBEAT_SECONDS=1
export SMITH_JOB_LEASE_SECONDS=4
export SMITH_JOB_GRACE_SECONDS=2

eventually() {
  local limit="$1"
  shift
  local waited=0
  until "$@"; do
    [ "$waited" -ge "$limit" ] && return 1
    sleep 1
    waited=$((waited + 1))
  done
}

alive() { kill -0 "$1" 2> /dev/null; }
gone() { ! kill -0 "$1" 2> /dev/null; }
state_is() { [ "$(head -n 1 "$1/state" 2> /dev/null)" = "$2" ]; }

join_until_terminal() {
  local dir="$1" out code
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    out=$("$JOB" join "$dir" --max 2)
    code=$?
    [ "$code" -ne 3 ] && { printf '%s\n' "$out"; return "$code"; }
  done
  printf '%s\n' "$out"
  return "$code"
}

[ -x "$JOB" ] || fail "worker-job.sh is missing or not executable"

"$JOB" start --deadline 30 > /dev/null 2>&1
[ $? -eq 64 ] || fail "start without a command must exit 64"
"$JOB" join > /dev/null 2>&1
[ $? -eq 64 ] || fail "join without a job folder must exit 64"
pass "usage errors exit 64"

dir=$("$JOB" start --deadline 30 -- bash -c 'echo hello-from-job')
[ -d "$dir" ] || fail "start must print an existing job folder, got: $dir"
out=$(join_until_terminal "$dir")
code=$?
[ "$code" -eq 0 ] || fail "a successful command must join with exit 0, got $code: $out"
[ "$(printf '%s\n' "$out" | head -n 1)" = "SMITH_JOB_DONE" ] || fail "first line must be SMITH_JOB_DONE, got: $out"
grep -qx 'hello-from-job' "$dir/stdout" || fail "the command's standard output must be kept in the job folder"
pass "successful command joins as SMITH_JOB_DONE"

dir=$("$JOB" start --deadline 30 -- bash -c 'exit 7')
out=$(join_until_terminal "$dir")
code=$?
[ "$code" -eq 2 ] || fail "a failing command must join with exit 2, got $code"
[ "$(printf '%s\n' "$out" | head -n 1)" = "SMITH_JOB_COMMAND_FAILED" ] || fail "failing command must report SMITH_JOB_COMMAND_FAILED, got: $out"
[ "$(cat "$dir/exit-status")" = "7" ] || fail "the command's exit status must be recorded"
pass "failing command joins as SMITH_JOB_COMMAND_FAILED with its status"

dir=$("$JOB" start --deadline 30 -- bash -c 'sleep 5; echo late')
started=$(date +%s)
out=$("$JOB" join "$dir" --max 1)
code=$?
elapsed=$(( $(date +%s) - started ))
[ "$code" -eq 3 ] || fail "join must return exit 3 while the job runs, got $code"
[ "$(printf '%s\n' "$out" | head -n 1)" = "SMITH_JOB_RUNNING" ] || fail "running job must report SMITH_JOB_RUNNING, got: $out"
[ "$elapsed" -le 3 ] || fail "join must return within its --max bound, took ${elapsed}s"
out=$(join_until_terminal "$dir")
[ "$(printf '%s\n' "$out" | head -n 1)" = "SMITH_JOB_DONE" ] || fail "a later join must see SMITH_JOB_DONE, got: $out"
pass "bounded join returns SMITH_JOB_RUNNING and a later join sees SMITH_JOB_DONE"

dir=$("$JOB" start --deadline 2 -- bash -c 'sleep 300 & echo $! > child.pid; wait')
eventually 5 test -s "$dir/child.pid" || fail "command did not start"
child=$(cat "$dir/child.pid")
out=$(join_until_terminal "$dir")
[ "$(printf '%s\n' "$out" | head -n 1)" = "SMITH_JOB_DEADLINE_EXCEEDED" ] || fail "an overdue job must report SMITH_JOB_DEADLINE_EXCEEDED, got: $out"
eventually 5 gone "$child" || fail "the overdue command's child must be ended"
pass "deadline ends the command and its children"

dir=$("$JOB" start --deadline 60 -- bash -c 'sleep 300 & echo $! > child.pid; wait')
eventually 5 test -s "$dir/child.pid" || fail "command did not start"
child=$(cat "$dir/child.pid")
eventually 15 state_is "$dir" SMITH_JOB_WAITER_LEASE_EXPIRED || fail "a job nobody joins must end as SMITH_JOB_WAITER_LEASE_EXPIRED, state: $(cat "$dir/state")"
eventually 5 gone "$child" || fail "an unjoined job's children must be ended"
pass "waiter lease ends a job nobody joins"

dir=$("$JOB" start --deadline 60 -- bash -c 'sleep 300 & echo $! > child.pid; wait')
eventually 5 test -s "$dir/child.pid" || fail "command did not start"
child=$(cat "$dir/child.pid")
"$JOB" join "$dir" --max 30 > "$dir/join.out" &
joiner=$!
sleep 2
kill -TERM "$joiner"
wait "$joiner"
code=$?
[ "$code" -eq 2 ] || fail "a cancelled join must exit 2, got $code"
[ "$(head -n 1 "$dir/join.out")" = "SMITH_JOB_CANCELLED" ] || fail "TERM to join must cancel the job, got: $(cat "$dir/join.out")"
eventually 5 gone "$child" || fail "a cancelled job's children must be ended"
pass "TERM to join cancels the job and its children"

dir=$("$JOB" start --deadline 60 -- bash -c 'sleep 300 & echo $! > child.pid; wait')
eventually 5 test -s "$dir/child.pid" || fail "command did not start"
child=$(cat "$dir/child.pid")
kill -KILL "$(cat "$dir/supervisor.pid")"
out=$(join_until_terminal "$dir")
[ "$(printf '%s\n' "$out" | head -n 1)" = "SMITH_JOB_SUPERVISOR_LOST" ] || fail "a dead supervisor must report SMITH_JOB_SUPERVISOR_LOST, got: $out"
eventually 5 gone "$child" || fail "join must end the command of a lost supervisor"
pass "lost supervisor is detected and its command ended"

echo "PASS: worker-job"
