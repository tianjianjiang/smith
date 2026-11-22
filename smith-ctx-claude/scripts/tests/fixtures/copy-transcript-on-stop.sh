#!/usr/bin/env bash
set -euo pipefail
COPY_PATH="$1"
TRANSCRIPT_PATH=$(jq -r '.transcript_path // empty')
[[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" && ! -e "$COPY_PATH" ]] || exit 0
cp "$TRANSCRIPT_PATH" "$COPY_PATH"
