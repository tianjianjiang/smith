#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/isolated-worker.sh"
require_live_probe_opt_in
OUT="${1:?usage: detached-job-survives-call.probe.sh output.json}"
MODEL="${SMITH_LIVE_CONTEXT_RESET_MODEL:-haiku}"
JOB_SECONDS="${SMITH_LIVE_JOB_SECONDS:-60}"
run_variant() {
  local name="$1" launch="$2"
  local work
  work=$(mktemp -d "${TMPDIR:-/tmp}/detached-job.XXXXXX")
  printf '#!/bin/bash\necho $$ > "%s/job.pid"\nsleep %s\necho done > "%s/job.done"\n' "$work" "$JOB_SECONDS" "$work" > "$work/job.sh"
  printf '#!/bin/bash\n%s\nfor _ in $(seq 1 50); do [ -s "%s/job.pid" ] && break; sleep 0.1; done\necho started\n' "$launch" "$work" > "$work/start.sh"
  printf '#!/bin/bash\nif kill -0 "$(cat "%s/job.pid")" 2> /dev/null; then echo job-alive; else echo job-gone; fi\n' "$work" > "$work/check.sh"
  chmod +x "$work/job.sh" "$work/start.sh" "$work/check.sh"
  build_isolated_worker_argv "$MODEL" "Bash(./start.sh) Bash(./check.sh)" "Glob Grep" json \
    "Use the Bash tool to run exactly ./start.sh in the foreground. After it returns, use the Bash tool again to run exactly ./check.sh. Reply with both outputs verbatim." \
    --setting-sources "" --tools Bash
  (cd "$work" && timeout 180 "${ISOLATED_WORKER_ARGV[@]}" > "$work/reply.json" 2> "$work/reply.err")
  local status=$?
  local alive_after_session=false
  is_live_pid "$(cat "$work/job.pid" 2> /dev/null)" && alive_after_session=true
  local waited=0
  while [ ! -e "$work/job.done" ] && [ "$waited" -lt $(( JOB_SECONDS + 30 )) ]; do
    /bin/sleep 1
    waited=$(( waited + 1 ))
  done
  local finished=false
  [ -e "$work/job.done" ] && finished=true
  jq -n --arg name "$name" --argjson status "$status" --argjson aliveAfterSession "$alive_after_session" \
    --argjson finished "$finished" --arg reply "$(jq -r '.result // ""' "$work/reply.json" 2> /dev/null)" \
    '{variant: $name, exitStatus: $status,
      jobAliveAtSecondToolCall: ($reply | contains("job-alive")),
      jobAliveAfterSessionExit: $aliveAfterSession, jobFinished: $finished,
      pass: (($reply | contains("job-alive")) and $finished)}'
}
{
  run_variant plain-background './job.sh > /dev/null 2>&1 &'
  run_variant nohup-background 'nohup ./job.sh > /dev/null 2>&1 &'
  run_variant own-process-group "perl -e 'setpgrp(0, 0); exec @ARGV' ./job.sh > /dev/null 2>&1 < /dev/null &"
} | jq -s --arg recordedAt "$(probe_timestamp)" --arg version "$(claude --version 2>/dev/null)" \
  --arg profile "$(profile_label)" --arg model "$MODEL" --argjson jobSeconds "$JOB_SECONDS" \
  '{recordedAt: $recordedAt, claudeCodeVersion: $version, profile: $profile, model: $model, jobSeconds: $jobSeconds,
    variants: ., survivingVariants: [.[] | select(.pass) | .variant]}' > "$OUT"
cat "$OUT"
