#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../volatile-artifact-guard.mjs"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
run() { printf '{"transcript_path":"%s"}' "$2" | node "$HOOK"; }

write_transcript() {
  printf '%s\n' "$2" > "$1"
}

expect_lists() {
  run "$1" "$2" | grep -q "$3" || fail "$1: expected '$3' listed"
}

expect_silent() {
  out=$(run "$1" "$2") || fail "$1: hook crashed"
  [ -z "$out" ] || fail "$1: expected silent, got: $out"
}

write_to_tmp="$TMPD/write-to-tmp.jsonl"
write_transcript "$write_to_tmp" '{"message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/tmp/foo.txt"}}]}}'
expect_lists "write to /tmp listed" "$write_to_tmp" '/tmp/foo.txt'

bash_write_to_tmp="$TMPD/bash-write-to-tmp.jsonl"
write_transcript "$bash_write_to_tmp" '{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo hi > /tmp/bar.log"}}]}}'
expect_lists "bash write to /tmp listed" "$bash_write_to_tmp" '/tmp/bar.log'

bash_read_of_tmp="$TMPD/bash-read-of-tmp.jsonl"
write_transcript "$bash_read_of_tmp" '{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cat /tmp/foo.txt"}}]}}'
expect_silent "bash read of /tmp is silent" "$bash_read_of_tmp"

write_to_durable_path="$TMPD/write-to-durable-path.jsonl"
write_transcript "$write_to_durable_path" '{"message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/Users/me/project/src/x.ts"}}]}}'
expect_silent "durable write is silent" "$write_to_durable_path"

write_to_project_tmp="$TMPD/write-to-project-tmp.jsonl"
write_transcript "$write_to_project_tmp" '{"message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/Users/me/project/tmp/build.log"}}]}}'
expect_silent "project-local tmp path is silent" "$write_to_project_tmp"

bash_write_to_private_tmp="$TMPD/bash-write-to-private-tmp.jsonl"
write_transcript "$bash_write_to_private_tmp" '{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo x > /private/tmp/foo.log"}}]}}'
expect_lists "private tmp path listed" "$bash_write_to_private_tmp" '/private/tmp/foo.log'
run "private tmp counted once" "$bash_write_to_private_tmp" | grep -q '1 file(s)' || fail "private tmp should count exactly 1"

job_dir="$TMPD/job"
write_to_job_tmp="$TMPD/write-to-job-tmp.jsonl"
write_transcript "$write_to_job_tmp" '{"message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"'"$job_dir"'/tmp/x.txt"}}]}}'
CLAUDE_JOB_DIR="$job_dir" expect_lists "job tmp write listed" "$write_to_job_tmp" '/tmp/x.txt'

bash_write_to_job_tmp="$TMPD/bash-write-to-job-tmp.jsonl"
write_transcript "$bash_write_to_job_tmp" '{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo x > $CLAUDE_JOB_DIR/tmp/log"}}]}}'
CLAUDE_JOB_DIR="$job_dir" expect_lists "job tmp literal listed" "$bash_write_to_job_tmp" 'CLAUDE_JOB_DIR/tmp/log'

write_to_downloads="$TMPD/write-to-downloads.jsonl"
write_transcript "$write_to_downloads" '{"message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"'"$HOME"'/Downloads/report.pdf"}}]}}'
expect_lists "downloads write listed" "$write_to_downloads" 'Downloads/report.pdf'

bash_copy_to_downloads="$TMPD/bash-copy-to-downloads.jsonl"
write_transcript "$bash_copy_to_downloads" '{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cp a.txt ~/Downloads/"}}]}}'
expect_lists "downloads copy listed" "$bash_copy_to_downloads" 'Downloads/'

expect_silent "missing transcript is silent" "$TMPD/does-not-exist.jsonl"

out=$(printf '{}' | node "$HOOK") || fail "no transcript_path: hook crashed"
[ -z "$out" ] || fail "no transcript_path should be silent"

echo "PASS: volatile-artifact-guard"
