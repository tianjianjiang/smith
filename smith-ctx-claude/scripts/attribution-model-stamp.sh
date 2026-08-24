#!/usr/bin/env bash

source "$(dirname "$0")/attribution-lib.sh"
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat) || exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null) || exit 0
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null) || exit 0
[[ -n "$cwd" && -n "$transcript" ]] || exit 0

model=$(attribution_model_from_transcript "$transcript")
[[ -n "$model" ]] || exit 0

model_file=$(attribution_model_file "$cwd") || exit 0
mkdir -p "$ATTRIBUTION_PLANS_DIR" 2>/dev/null || exit 0
printf '%s\n' "$model" > "$model_file" 2>/dev/null || exit 0
exit 0
