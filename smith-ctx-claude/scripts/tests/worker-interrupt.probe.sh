#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/isolated-worker.sh"
require_live_probe_opt_in
OUT="${1:?usage: worker-interrupt.probe.sh output.json}"
MODEL="${SMITH_LIVE_CONTEXT_RESET_MODEL:-haiku}"
SIGNAL="${SMITH_LIVE_WORKER_SIGNAL:-TERM}"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/worker-interrupt-probe.XXXXXX")
SECONDS_MARK=$(( 200 + RANDOM % 600 ))
SLEEP_CMD="sleep $SECONDS_MARK"
printf '#!/bin/bash\n%s\n' "$SLEEP_CMD" > "$WORK/hold.sh"
chmod +x "$WORK/hold.sh"
cat > "$WORK/runner.sh" <<EOF
#!/bin/bash
. "$HERE/lib/isolated-worker.sh"
trap 'trap - INT TERM; kill -TERM -\$\$ 2> /dev/null; exit 130' INT TERM
for name in first second; do
  build_isolated_worker_argv "$MODEL" "Bash(./hold.sh)" "Glob Grep" json \
    "Run exactly this command with the Bash tool in the foreground, with timeout 600000: ./hold.sh. Then reply done."
  "\${ISOLATED_WORKER_ARGV[@]}" > "$WORK/\$name.json" 2> "$WORK/\$name.err" &
  echo "\$!" >> "$WORK/workers.pids"
done
wait
EOF
chmod +x "$WORK/runner.sh"
sleepers() { pgrep -f "^$SLEEP_CMD\$" || true; }
(cd "$WORK" && exec perl -e 'setpgrp(0, 0); $SIG{INT} = "DEFAULT"; exec @ARGV' "$WORK/runner.sh") &
RUNNER=$!
waited=0
while [ "$(sleepers | wc -l | tr -d ' ')" -lt 2 ] && [ "$waited" -lt 120 ]; do
  /bin/sleep 1
  waited=$(( waited + 1 ))
done
before_sleepers=$(sleepers | tr '\n' ' ')
runner_pgid=$(ps -o pgid= -p "$RUNNER" | tr -d ' ')
runner_pgid=${runner_pgid:-0}
workers_before=$(for pid in $(cat "$WORK/workers.pids" 2> /dev/null); do kill -0 "$pid" 2> /dev/null && echo "$pid"; done | tr '\n' ' ')
sleeper_pgids=$(for pid in $before_sleepers; do ps -o pgid= -p "$pid"; done | tr -d ' ' | sort -u | tr '\n' ' ')
kill -"$SIGNAL" "$RUNNER"
runner_exited=false
for _ in $(seq 1 30); do
  kill -0 "$RUNNER" 2> /dev/null || { runner_exited=true; break; }
  /bin/sleep 1
done
if [ "$runner_exited" = true ]; then
  wait "$RUNNER" 2> /dev/null
  runner_status=$?
else
  runner_status=-1
  kill -TERM "$RUNNER" 2> /dev/null
fi
/bin/sleep 5
after_sleepers=$(sleepers | tr '\n' ' ')
workers_after=$(for pid in $workers_before; do kill -0 "$pid" 2> /dev/null && echo "$pid"; done | tr '\n' ' ')
for pid in $after_sleepers; do kill -TERM "$pid" 2> /dev/null; done
to_array() { printf '%s\n' "$1" | jq -R 'split(" ") | map(select(length > 0) | tonumber)'; }
jq -n --arg recordedAt "$(probe_timestamp)" --arg version "$(claude --version 2>/dev/null)" \
  --arg profile "$(profile_label)" --arg model "$MODEL" --arg signal "$SIGNAL" \
  --argjson waited "$waited" --argjson runnerStatus "$runner_status" --argjson runnerPgid "$runner_pgid" \
  --argjson workersBefore "$(to_array "$workers_before")" --argjson workersAfter "$(to_array "$workers_after")" \
  --argjson sleepersBefore "$(to_array "$before_sleepers")" --argjson sleepersAfter "$(to_array "$after_sleepers")" \
  --argjson sleeperPgids "$(to_array "$sleeper_pgids")" \
  '{recordedAt: $recordedAt, claudeCodeVersion: $version, profile: $profile, model: $model, signal: $signal,
    secondsUntilBothToolCallsRan: $waited, runnerExitStatus: $runnerStatus,
    runnerExitedWithin30Seconds: ($runnerStatus != -1),
    workersBefore: ($workersBefore | length), workersAliveAfter: ($workersAfter | length),
    toolProcessesBefore: ($sleepersBefore | length), toolProcessesAliveAfter: ($sleepersAfter | length),
    toolProcessesShareRunnerGroup: (($sleeperPgids | length) > 0 and all($sleeperPgids[]; . == $runnerPgid)),
    pass: ($runnerStatus != -1 and ($workersBefore | length) == 2 and ($sleepersBefore | length) == 2
           and ($workersAfter | length) == 0 and ($sleepersAfter | length) == 0)}' > "$OUT"
cat "$OUT"
