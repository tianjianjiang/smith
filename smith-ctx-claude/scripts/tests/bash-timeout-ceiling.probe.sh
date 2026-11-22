#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/isolated-worker.sh"
require_live_probe_opt_in
OUT="${1:?usage: bash-timeout-ceiling.probe.sh output.json}"
MODEL="${SMITH_LIVE_CONTEXT_RESET_MODEL:-haiku}"
HOLD_SECONDS="${SMITH_LIVE_HOLD_SECONDS:-660}"
REQUESTED_MS="${SMITH_LIVE_REQUESTED_TIMEOUT_MS:-900000}"
CEILING_MS="${SMITH_LIVE_CEILING_MS:-1200000}"
run_variant() {
  local name="$1"
  shift
  local work
  work=$(mktemp -d "${TMPDIR:-/tmp}/bash-ceiling.XXXXXX")
  local mark="holdfinished$RANDOM$RANDOM"
  printf '#!/bin/bash\nsleep %s\necho %s\n' "$HOLD_SECONDS" "$mark" > "$work/hold.sh"
  chmod +x "$work/hold.sh"
  build_isolated_worker_argv "$MODEL" "Bash(./hold.sh)" "Glob Grep" stream-json \
    "Run exactly ./hold.sh with the Bash tool in the foreground, with the timeout parameter set to $REQUESTED_MS, and do not set run_in_background. Then reply with the tool result verbatim." \
    --verbose --setting-sources "" --tools Bash "$@"
  local started
  started=$(date +%s)
  (cd "$work" && timeout "$(( HOLD_SECONDS + 300 ))" "${ISOLATED_WORKER_ARGV[@]}" > "$work/stream.jsonl" 2> "$work/stream.err")
  local status=$?
  local elapsed=$(( $(date +%s) - started ))
  jq -s --arg name "$name" --argjson status "$status" --argjson elapsed "$elapsed" --arg mark "$mark" '
    [.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | .input] as $inputs
    | [.[] | select(.type == "user") | .message.content[]? | select(.type == "tool_result")
       | (if (.content | type) == "string" then .content else ([.content[]? | .text? // ""] | join("")) end)] as $texts
    | {variant: $name, exitStatus: $status, elapsedSeconds: $elapsed,
       requestedTimeouts: [$inputs[] | .timeout // null], runInBackgroundRequested: [$inputs[] | .run_in_background // false],
       firstToolResultSaysBackground: (($texts[0] // "") | test("background"; "i")),
       holdFinishedInForeground: (($texts[0] // "") | contains($mark)),
       firstToolResultHead: (($texts[0] // "") | .[0:200] | gsub("/[^ ]+"; "«path»"))}' "$work/stream.jsonl" || stream_parse_error_variant "$name" "$status"
}
RESULTS=$(mktemp -d "${TMPDIR:-/tmp}/bash-ceiling-results.XXXXXX")
{
  (unset BASH_MAX_TIMEOUT_MS; run_variant no-ceiling-change) > "$RESULTS/a.json" &
  BASH_MAX_TIMEOUT_MS="$CEILING_MS" run_variant ceiling-in-process-environment > "$RESULTS/b.json" &
  (unset BASH_MAX_TIMEOUT_MS; run_variant ceiling-in-settings-env --settings "{\"env\":{\"BASH_MAX_TIMEOUT_MS\":\"$CEILING_MS\"}}") > "$RESULTS/c.json" &
  wait
}
jq -s --arg recordedAt "$(probe_timestamp)" --arg version "$(claude --version 2>/dev/null)" \
  --arg profile "$(profile_label)" --arg model "$MODEL" \
  --argjson hold "$HOLD_SECONDS" --argjson requested "$REQUESTED_MS" --argjson ceiling "$CEILING_MS" \
  '{recordedAt: $recordedAt, claudeCodeVersion: $version, profile: $profile, model: $model,
    holdSeconds: $hold, requestedTimeoutMs: $requested, ceilingMs: $ceiling,
    variants: ., foregroundVariants: [.[] | select(.holdFinishedInForeground) | .variant]}' \
  "$RESULTS/a.json" "$RESULTS/b.json" "$RESULTS/c.json" > "$OUT"
cat "$OUT"
