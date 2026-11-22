#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/isolated-worker.sh"
require_live_probe_opt_in
OUT="${1:?usage: stop-background-tasks.probe.sh output.json}"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/stop-probe.XXXXXX")
INPUTS="$WORK/stop-input.jsonl"
jq -n --arg cmd "cat >> '$INPUTS'; echo >> '$INPUTS'" \
    '{hooks: {Stop: [{hooks: [{type: "command", command: $cmd}]}]}}' > "$WORK/settings.json"
(cd "$WORK" && timeout 170 claude -p --model haiku --settings "$WORK/settings.json" \
    "Use the Bash tool with run_in_background set to true to run: sleep 40. Then immediately reply with the single word: started. Do not wait for it." \
    > "$WORK/out.txt" 2>&1)
STATUS=$?
if [ ! -s "$INPUTS" ]; then
  jq -n --arg status "$STATUS" --rawfile reply "$WORK/out.txt" '{exitStatus: $status, reply: $reply, stopInputsFileMissing: true, stopInputs: []}' > "$OUT"
  cat "$OUT"
  exit 1
fi
jq -s --arg version "$(claude --version 2>/dev/null)" --arg status "$STATUS" \
    --arg recordedAt "$(date +%Y-%m-%dT%H:%M:%S%z)" --rawfile reply "$WORK/out.txt" \
    '{recordedAt: $recordedAt, claudeCodeVersion: $version, exitStatus: $status, reply: $reply,
      stopInputs: map({hook_event_name, stop_hook_active, has_background_tasks: has("background_tasks"),
                       background_tasks, has_session_crons: has("session_crons")})}' \
    "$INPUTS" > "$OUT"
cat "$OUT"
