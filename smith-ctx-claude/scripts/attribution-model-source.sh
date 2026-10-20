#!/usr/bin/env bash

source "$(dirname "$0")/attribution-lib.sh"

model=$(attribution_session_model "${1:-}") || exit 1
printf 'Claude:%s\n' "$model"
