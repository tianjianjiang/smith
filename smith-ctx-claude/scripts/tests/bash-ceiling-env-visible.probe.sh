#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/isolated-worker.sh"
require_live_probe_opt_in
OUT="${1:?usage: bash-ceiling-env-visible.probe.sh output.json}"
MODEL="${SMITH_LIVE_CONTEXT_RESET_MODEL:-haiku}"
CEILING_MS="${SMITH_LIVE_CEILING_MS:-1200000}"
run_variant() {
  local name="$1"
  shift
  local work
  work=$(mktemp -d "${TMPDIR:-/tmp}/bash-ceiling-env.XXXXXX")
  printf '#!/bin/bash\necho "ceiling=${BASH_MAX_TIMEOUT_MS:-unset}"\n' > "$work/show.sh"
  chmod +x "$work/show.sh"
  build_isolated_worker_argv "$MODEL" "Bash(./show.sh)" "Glob Grep" stream-json \
    "Run exactly ./show.sh with the Bash tool, then reply with its output verbatim." \
    --verbose --setting-sources "" --tools Bash "$@"
  (cd "$work" && timeout 180 env -u BASH_MAX_TIMEOUT_MS "${ISOLATED_WORKER_ARGV[@]}" > "$work/stream.jsonl" 2> "$work/stream.err")
  local status=$?
  jq -s --arg name "$name" --argjson status "$status" '
    [.[] | select(.type == "user") | .message.content[]? | select(.type == "tool_result")
     | (if (.content | type) == "string" then .content else ([.content[]? | .text? // ""] | join("")) end)] as $texts
    | {variant: $name, exitStatus: $status,
       seenByBashChild: ([$texts[] | capture("ceiling=(?<v>[^\\s]+)") | .v] | first // null)}' "$work/stream.jsonl"
}
{
  run_variant no-setting
  run_variant settings-env --settings "{\"env\":{\"BASH_MAX_TIMEOUT_MS\":\"$CEILING_MS\"}}"
} | jq -s --arg recordedAt "$(probe_timestamp)" --arg version "$(claude --version 2>/dev/null)" \
  --arg profile "$(profile_label)" --arg model "$MODEL" --arg ceiling "$CEILING_MS" \
  '{recordedAt: $recordedAt, claudeCodeVersion: $version, profile: $profile, model: $model, ceilingMs: $ceiling,
    variants: .,
    pass: ((.[0].seenByBashChild == "unset") and (.[1].seenByBashChild == $ceiling))}' > "$OUT"
cat "$OUT"
