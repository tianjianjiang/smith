#!/usr/bin/env bash

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SMITH_ROOT="$(dirname "$(dirname "$SCRIPTS_DIR")")"
MODEL_SOURCES="$SCRIPTS_DIR/attribution-model-sources.txt"
ATTRIBUTION_VALUE_FORMAT='^[A-Za-z][A-Za-z0-9_-]*:[A-Za-z0-9]([A-Za-z0-9._@:/-]*[A-Za-z0-9])?$'

attribution_value() {
    local source value
    while IFS= read -r source || [[ -n "$source" ]]; do
        [[ -n "$source" ]] || continue
        value=$("$SMITH_ROOT/$source" "$@" 2>/dev/null) || continue
        if [[ "$value" =~ $ATTRIBUTION_VALUE_FORMAT ]]; then
            printf '%s' "$value"
            return 0
        fi
    done < "$MODEL_SOURCES"
    return 1
}

mode="line"
if [[ "${1:-}" == "value" || "${1:-}" == "line" ]]; then
    mode="$1"
    shift
fi

value=$(attribution_value "$@") || exit 1

case "$mode" in
    value) printf '%s\n' "$value" ;;
    *)     printf 'Assisted-by: %s\n' "$value" ;;
esac
