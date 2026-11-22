#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/isolated-worker.sh"
require_live_probe_opt_in
OUT="${1:?usage: foreground-runner-interrupt.probe.sh output.json}"
MODEL="${SMITH_LIVE_CONTEXT_RESET_MODEL:-haiku}"
run_variant() {
  local name="$1"
  local work
  work=$(mktemp -d "${TMPDIR:-/tmp}/foreground-interrupt.XXXXXX")
  local hold_seconds=$(( 300 + RANDOM % 500 ))
  cat > "$work/runner.sh" <<EOF
#!/bin/bash
for signal in INT TERM HUP QUIT; do
  trap "echo \$signal >> '$work/signals.log'; kill \\\$(jobs -p) 2> /dev/null; exit 1" "\$signal"
done
echo \$\$ > "$work/runner.pid"
sleep $hold_seconds &
echo \$! > "$work/child.pid"
wait
echo wait-returned >> "$work/signals.log"
EOF
  chmod +x "$work/runner.sh"
  mkfifo "$work/in.fifo"
  (cd "$work" && exec env -u CLAUDE_JOB_DIR CTX_AUTO_RESET_DISPATCH=0 claude -p \
    --input-format stream-json --output-format stream-json --verbose \
    --setting-sources "" --strict-mcp-config --no-session-persistence \
    --model "$MODEL" --tools Bash --allowedTools "Bash(./runner.sh)" \
    < "$work/in.fifo" > "$work/out.jsonl" 2> "$work/err.txt") &
  local outer=$!
  exec 3> "$work/in.fifo"
  jq -cn --arg text "Run exactly ./runner.sh with the Bash tool in the foreground, with timeout 600000, then reply done." \
    '{type: "user", message: {role: "user", content: [{type: "text", text: $text}]}}' >&3
  local waited=0
  while ! is_live_pid "$(cat "$work/child.pid" 2> /dev/null)" && [ "$waited" -lt 120 ]; do
    /bin/sleep 1
    waited=$(( waited + 1 ))
  done
  local runner_pid child_pid
  runner_pid=$(cat "$work/runner.pid" 2> /dev/null)
  child_pid=$(cat "$work/child.pid" 2> /dev/null)
  local started=false
  is_live_pid "$child_pid" && started=true
  if [ "$name" = control-request-interrupt ]; then
    jq -cn '{type: "control_request", request_id: "probe-interrupt", request: {subtype: "interrupt"}}' >&3
  else
    kill -INT "$outer"
  fi
  /bin/sleep 8
  local runner_alive=false child_alive=false outer_alive=false
  is_live_pid "$runner_pid" && runner_alive=true
  is_live_pid "$child_pid" && child_alive=true
  kill -0 "$outer" 2> /dev/null && outer_alive=true
  exec 3>&-
  for _ in $(seq 1 20); do kill -0 "$outer" 2> /dev/null || break; /bin/sleep 1; done
  local leftover
  for leftover in "$outer" "$runner_pid" "$child_pid"; do
    is_live_pid "$leftover" && kill -TERM "$leftover" 2> /dev/null
  done
  local signals
  signals=$(jq -R -s 'split("\n") | map(select(length > 0))' "$work/signals.log" 2> /dev/null || echo '[]')
  jq -n --arg name "$name" --argjson waited "$waited" --argjson started "$started" \
    --argjson signals "$signals" --argjson runnerAlive "$runner_alive" --argjson childAlive "$child_alive" \
    --argjson outerAlive "$outer_alive" \
    --argjson controlResponse "$(jq -c 'select(.type == "control_response") | .response.subtype' "$work/out.jsonl" 2> /dev/null | jq -s . 2> /dev/null || echo '[]')" \
    '{variant: $name, secondsUntilRunnerStarted: $waited, runnerStarted: $started,
      signalsTheRunnerTrapped: $signals, runnerAliveAfter: $runnerAlive, runnerChildAliveAfter: $childAlive,
      outerClaudeAliveAfter: $outerAlive, controlResponses: $controlResponse,
      runnerSawSignal: (($signals | map(select(. != "wait-returned")) | length) > 0),
      pass: ($started and ($runnerAlive | not) and ($childAlive | not))}'
}
{
  run_variant control-request-interrupt
  run_variant sigint-to-outer-claude
} | jq -s --arg recordedAt "$(probe_timestamp)" --arg version "$(claude --version 2>/dev/null)" \
  --arg profile "$(profile_label)" --arg model "$MODEL" \
  '{recordedAt: $recordedAt, claudeCodeVersion: $version, profile: $profile, model: $model,
    setup: "outer claude -p in stream-json mode runs ./runner.sh in its foreground Bash tool; runner traps INT TERM HUP QUIT, logs the signal and kills its background sleep",
    variants: ., passingVariants: [.[] | select(.pass) | .variant]}' > "$OUT"
cat "$OUT"
