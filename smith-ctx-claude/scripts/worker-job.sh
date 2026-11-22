#!/bin/bash
set -u
HEARTBEAT="${SMITH_JOB_HEARTBEAT_SECONDS:-5}"
LEASE="${SMITH_JOB_LEASE_SECONDS:-600}"
GRACE="${SMITH_JOB_GRACE_SECONDS:-10}"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

usage() {
  echo "usage: worker-job.sh start --deadline SECONDS -- COMMAND [ARGUMENT...]" >&2
  echo "       worker-job.sh join FOLDER --max SECONDS" >&2
  exit 64
}

is_whole_number() { case "$1" in '' | *[!0-9]*) return 1 ;; esac; }
now() { date +%s; }
first_line() { head -n 1 "$1" 2> /dev/null; }

write_atomically() {
  local next
  next=$(mktemp "$1.XXXXXX") || return 1
  printf '%s\n' "$2" > "$next" && mv "$next" "$1"
}

is_terminal() {
  case "$1" in
    SMITH_JOB_DONE | SMITH_JOB_COMMAND_FAILED | SMITH_JOB_DEADLINE_EXCEEDED | SMITH_JOB_WAITER_LEASE_EXPIRED | SMITH_JOB_CANCELLED | SMITH_JOB_SUPERVISOR_LOST) return 0 ;;
  esac
  return 1
}

stored_tunable() {
  local value
  value=$(first_line "$1/$2")
  if is_whole_number "$value"; then printf '%s\n' "$value"; else printf '%s\n' "$3"; fi
}

load_tunables() {
  HEARTBEAT=$(stored_tunable "$1" heartbeat-seconds "$HEARTBEAT")
  LEASE=$(stored_tunable "$1" lease-seconds "$LEASE")
  GRACE=$(stored_tunable "$1" grace-seconds "$GRACE")
}

settle() {
  local waited=0
  if mkdir "$1/settled" 2> /dev/null; then
    write_atomically "$1/state" "$2"
    return
  fi
  until is_terminal "$(first_line "$1/state")" || [ "$waited" -ge 5 ]; do
    sleep 1
    waited=$((waited + 1))
  done
}

exit_outcome() {
  if [ "$(first_line "$1/exit-status")" = 0 ]; then echo SMITH_JOB_DONE; else echo SMITH_JOB_COMMAND_FAILED; fi
}

end_command() {
  local group waited=0
  group=$(first_line "$1/command.pgid")
  is_whole_number "$group" || return 0
  kill -TERM -"$group" 2> /dev/null
  while kill -0 -"$group" 2> /dev/null && [ "$waited" -lt "$GRACE" ]; do
    sleep 1
    waited=$((waited + 1))
  done
  kill -KILL -"$group" 2> /dev/null
  return 0
}

finish() {
  ending="$2"
  end_command "$1"
  settle "$1" "$ending"
  exit 0
}

supervise() {
  local dir="$1" deadline_at="$2" waiter
  shift 2
  load_tunables "$dir"
  ending=SMITH_JOB_CANCELLED
  write_atomically "$dir/supervisor.pid" "$$"
  trap 'end_command "$dir"; settle "$dir" "$ending"; exit 0' TERM INT HUP
  (
    cd "$dir" || exit 70
    perl -e 'setpgrp(0, 0); my $final = shift; open(my $out, ">", "$final.next") or exit 70; print $out "$$\n"; close($out) or exit 70; rename("$final.next", $final) or exit 70; exec @ARGV or exit 127' \
      "$dir/command.pgid" "$@" > "$dir/stdout" 2> "$dir/stderr" < /dev/null &
    command_pid=$!
    wait "$command_pid"
    write_atomically "$dir/exit-status" "$?"
  ) &
  until [ -s "$dir/command.pgid" ] || [ -e "$dir/exit-status" ]; do
    sleep 0.2
  done
  while :; do
    write_atomically "$dir/heartbeat" "$(now)"
    [ -e "$dir/exit-status" ] && finish "$dir" "$(exit_outcome "$dir")"
    [ -e "$dir/cancel" ] && finish "$dir" SMITH_JOB_CANCELLED
    [ "$(now)" -ge "$deadline_at" ] && finish "$dir" SMITH_JOB_DEADLINE_EXCEEDED
    waiter=$(first_line "$dir/waiter")
    is_whole_number "$waiter" || waiter=$(now)
    [ $(( $(now) - waiter )) -ge "$LEASE" ] && finish "$dir" SMITH_JOB_WAITER_LEASE_EXPIRED
    sleep "$HEARTBEAT"
  done
}

start() {
  [ "${1:-}" = --deadline ] && is_whole_number "${2:-}" && [ "${3:-}" = -- ] && [ "$#" -ge 4 ] || usage
  is_whole_number "$HEARTBEAT" && is_whole_number "$LEASE" && is_whole_number "$GRACE" || usage
  local seconds="$2" dir
  shift 3
  dir=$(mktemp -d "${TMPDIR:-/tmp}/worker-job.XXXXXX") || exit 70
  write_atomically "$dir/heartbeat-seconds" "$HEARTBEAT"
  write_atomically "$dir/lease-seconds" "$LEASE"
  write_atomically "$dir/grace-seconds" "$GRACE"
  write_atomically "$dir/state" RUNNING
  write_atomically "$dir/waiter" "$(now)"
  write_atomically "$dir/heartbeat" "$(now)"
  perl -e 'setpgrp(0, 0); $SIG{INT} = "DEFAULT"; exec @ARGV' "$SELF" supervise "$dir" "$(( $(now) + seconds ))" "$@" > /dev/null 2> "$dir/supervisor.err" < /dev/null &
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -s "$dir/supervisor.pid" ] && [ -s "$dir/command.pgid" ] && break
    sleep 0.5
  done
  if [ ! -s "$dir/supervisor.pid" ]; then
    echo "worker-job.sh: the supervisor did not start; see $dir/supervisor.err" >&2
    exit 70
  fi
  printf '%s\n' "$dir"
}

report() {
  local state
  state=$(first_line "$1/state")
  printf '%s\nstdout: %s\nstderr: %s\n' "$state" "$1/stdout" "$1/stderr"
  [ "$state" = SMITH_JOB_DONE ] && exit 0
  exit 2
}

supervisor_lost() {
  local pid beat
  pid=$(first_line "$1/supervisor.pid")
  beat=$(first_line "$1/heartbeat")
  is_whole_number "$pid" && [ "$pid" -gt 0 ] && kill -0 "$pid" 2> /dev/null || return 0
  is_whole_number "$beat" || return 0
  [ $(( $(now) - beat )) -gt $(( HEARTBEAT * 3 + 5 )) ]
}

cancel() {
  local dir="$1" waited=0
  write_atomically "$dir/cancel" "$(now)"
  while ! is_terminal "$(first_line "$dir/state")" && [ "$waited" -lt $(( GRACE + HEARTBEAT + 5 )) ]; do
    sleep 1
    waited=$((waited + 1))
  done
  if ! is_terminal "$(first_line "$dir/state")"; then
    end_command "$dir"
    settle "$dir" SMITH_JOB_CANCELLED
  fi
  report "$dir"
}

join() {
  local dir="${1:-}" max="${3:-}" started outcome
  [ -e "$dir/state" ] && [ "${2:-}" = --max ] && is_whole_number "$max" || usage
  load_tunables "$dir"
  started=$(now)
  trap 'cancel "$dir"' TERM INT HUP
  while :; do
    write_atomically "$dir/waiter" "$(now)"
    is_terminal "$(first_line "$dir/state")" && report "$dir"
    if supervisor_lost "$dir"; then
      outcome=SMITH_JOB_SUPERVISOR_LOST
      [ -e "$dir/exit-status" ] && outcome=$(exit_outcome "$dir")
      end_command "$dir"
      settle "$dir" "$outcome"
      report "$dir"
    fi
    if [ $(( $(now) - started )) -ge "$max" ]; then
      printf 'SMITH_JOB_RUNNING\njob: %s\n' "$dir"
      exit 3
    fi
    sleep 1
  done
}

case "${1:-}" in
  start) shift; start "$@" ;;
  join) shift; join "$@" ;;
  supervise) shift; supervise "$@" ;;
  *) usage ;;
esac
