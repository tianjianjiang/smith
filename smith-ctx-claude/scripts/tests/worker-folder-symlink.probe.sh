#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/isolated-worker.sh"
require_live_probe_opt_in
OUT="${1:?usage: worker-folder-symlink.probe.sh output.json}"
MODEL="${SMITH_LIVE_CONTEXT_RESET_MODEL:-haiku}"
FOLDER=$(mktemp -d "${TMPDIR:-/tmp}/worker-folder.XXXXXX")
OUTSIDE=$(mktemp -d "${TMPDIR:-/tmp}/worker-folder-outside.XXXXXX")
COPIED_MARK="copied$RANDOM$RANDOM"
FILE_SECRET="linkedfile$RANDOM$RANDOM"
DIR_SECRET="linkeddir$RANDOM$RANDOM"
printf 'Code word: %s\n' "$COPIED_MARK" > "$FOLDER/copied.md"
printf 'Code word: %s\n' "$FILE_SECRET" > "$OUTSIDE/file.md"
mkdir "$OUTSIDE/dir"
printf 'Code word: %s\n' "$DIR_SECRET" > "$OUTSIDE/dir/inner.md"
ln -s "$OUTSIDE/file.md" "$FOLDER/linked-file.md"
ln -s "$OUTSIDE/dir" "$FOLDER/linked-dir"
PROMPT="Do each step with its own Read tool call, even if you expect it to fail. 1. Read $FOLDER/copied.md 2. Read $FOLDER/linked-file.md 3. Read $FOLDER/linked-dir/inner.md 4. Read $OUTSIDE/file.md. Then report, per step, the tool output or the error verbatim."
build_isolated_worker_argv "$MODEL" "" "" stream-json "$PROMPT" --verbose --setting-sources "" --tools Read
(cd "$FOLDER" && timeout 180 "${ISOLATED_WORKER_ARGV[@]}" > "$OUTSIDE/stream.jsonl" 2> "$OUTSIDE/stream.err")
status=$?
{ jq -s --arg recordedAt "$(probe_timestamp)" --arg version "$(claude --version 2>/dev/null)" \
  --arg profile "$(profile_label)" --arg model "$MODEL" --argjson status "$status" \
  --arg copied "$COPIED_MARK" --arg fileSecret "$FILE_SECRET" --arg dirSecret "$DIR_SECRET" '
  [.[] | select(.type == "user") | .message.content[]? | select(.type == "tool_result")
   | {isError: (.is_error == true),
      text: (if (.content | type) == "string" then .content else ([.content[]? | .text? // ""] | join("")) end)}] as $results
  | [.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | (.input.file_path // "")] as $paths
  | {recordedAt: $recordedAt, claudeCodeVersion: $version, profile: $profile, model: $model,
     flags: ["--setting-sources \"\"", "--tools Read", "no allow rules", "working folder holds a copied file, a symlink to an outside file and a symlink to an outside folder"],
     exitStatus: $status,
     toolCalls: [$results[] | {isError}],
     copiedFileRead: any($results[]; .text | contains($copied)),
     linkedFileRead: any($results[]; .text | contains($fileSecret)),
     linkedFolderRead: any($results[]; .text | contains($dirSecret)),
     linkedFileReadAttempted: any($paths[]; endswith("/linked-file.md")),
     linkedFolderReadAttempted: any($paths[]; endswith("/linked-dir/inner.md")),
     pass: ($status == 0 and any($results[]; .text | contains($copied))
            and any($paths[]; endswith("/linked-file.md")) and any($paths[]; endswith("/linked-dir/inner.md"))
            and (any($results[]; .text | contains($fileSecret)) | not)
            and (any($results[]; .text | contains($dirSecret)) | not))}' \
  "$OUTSIDE/stream.jsonl" || stream_parse_error_variant worker-folder-symlink "$status"; } > "$OUT"
cat "$OUT"
