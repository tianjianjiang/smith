#!/usr/bin/env bash

source "$(dirname "$0")/attribution-lib.sh"
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat) || exit 0
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null) || exit 0
[[ -n "$session_id" && -n "$transcript" ]] || exit 0

model=$(attribution_model_from_transcript "$transcript")
attribution_model_is_well_formed "$model" || exit 0

model_file=$(attribution_model_file "$session_id") || exit 0
mkdir -p "$ATTRIBUTION_PLANS_DIR" 2>/dev/null || exit 0
printf '%s\n' "$model" > "$model_file" 2>/dev/null || exit 0
exit 0
