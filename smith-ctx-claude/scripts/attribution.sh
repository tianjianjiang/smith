#!/usr/bin/env bash

source "$(dirname "$0")/attribution-lib.sh"

model_file=$(attribution_model_file) || exit 1
[[ -f "$model_file" ]] || exit 1
model=$(<"$model_file")
model="${model//[$'\n\r\t ']/}"
[[ -n "$model" ]] || exit 1
[[ "$model" == *claude-* ]] || exit 1

case "${1:-}" in
    value) printf 'Claude:%s\n' "$model" ;;
    *)     printf 'Assisted-by: Claude:%s\n' "$model" ;;
esac
