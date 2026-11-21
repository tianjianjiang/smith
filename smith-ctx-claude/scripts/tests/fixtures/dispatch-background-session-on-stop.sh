#!/bin/sh
arm_file=$1
model=$2
readable_folder=$3
prompt_file=$4
[ -n "$arm_file" ] && [ -f "$arm_file" ] || exit 0
. "$(dirname "$0")/../lib/set-aside.sh"
set_aside "$arm_file"
{
  echo "probe_variable=${SMITH_PROBE_PASSED_VARIABLE:-absent}"
  echo "job=${CLAUDE_JOB_DIR:+set}"
  claude --bg --model "$model" --add-dir "$readable_folder" -- "$(cat "$prompt_file")" < /dev/null
} > "$arm_file.sent" 2>&1
