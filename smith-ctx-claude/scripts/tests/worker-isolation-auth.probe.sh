#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/isolated-worker.sh"
require_live_probe_opt_in
OUT="${1:?usage: worker-isolation-auth.probe.sh output.json}"
MODEL="${SMITH_LIVE_CONTEXT_RESET_MODEL:-haiku}"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/worker-auth-probe.XXXXXX")
WORD="probe$RANDOM$RANDOM"
build_isolated_worker_argv "$MODEL" Read "Bash Glob Grep" json \
  "Reply with exactly this word and nothing else: $WORD"
started=$(date +%s)
(cd "$WORK" && timeout 120 "${ISOLATED_WORKER_ARGV[@]}" > "$WORK/out.json" 2> "$WORK/err.txt")
status=$?
elapsed=$(( $(date +%s) - started ))
jq -c . "$WORK/out.json" > "$WORK/reply.json" 2> /dev/null || echo '{}' > "$WORK/reply.json"
jq -n --arg recordedAt "$(probe_timestamp)" --arg version "$(claude --version 2>/dev/null)" \
  --arg profile "$(profile_label)" --arg model "$MODEL" --arg word "$WORD" \
  --argjson status "$status" --argjson elapsed "$elapsed" \
  --slurpfile reply "$WORK/reply.json" \
  '$reply[0] as $r
   | (($r.result // "") | gsub("\\s"; "") == $word) as $matches
   | {recordedAt: $recordedAt, claudeCodeVersion: $version, profile: $profile, model: $model,
      flags: ["--strict-mcp-config", "--no-session-persistence", "--output-format json",
              "--allowedTools", "--disallowedTools", "env -u CLAUDE_JOB_DIR", "CTX_AUTO_RESET_DISPATCH=0"],
      exitStatus: $status, elapsedSeconds: $elapsed,
      isError: $r.is_error, subtype: ($r.subtype // null), replyMatches: $matches,
      pass: ($status == 0 and $r.is_error == false and $matches)}' > "$OUT"
cat "$OUT"
