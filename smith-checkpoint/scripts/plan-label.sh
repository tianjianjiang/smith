#!/usr/bin/env bash
set -euo pipefail

readonly PLAN="${1:-}"
readonly MARKER='^<!-- checkpoint-label-v1: [A-Za-z0-9_][A-Za-z0-9._-]* -->[[:space:]]*$'

if [[ -z "$PLAN" ]]; then
    echo "Usage: plan-label.sh «plan file»" >&2
    exit 1
fi
if [[ ! -f "$PLAN" ]]; then
    echo "Error: plan is not a file: ${PLAN}" >&2
    exit 1
fi

source "$(dirname "${BASH_SOURCE[0]}")/../../smith-ctx-claude/scripts/lib-context.sh"

grep_status=0
hits=$(grep -a -n -E -- "$MARKER" "$PLAN") || grep_status=$?
case "$grep_status" in
    0) ;;
    1)
        label=$(checkpoint_label_from_plan "$PLAN")
        printf '%s\n' "$label"
        exit 3
        ;;
    *)
        echo "Error: could not read plan: ${PLAN}" >&2
        exit 1
        ;;
esac

if [[ "$hits" == *$'\n'* ]]; then
    echo "Error: ${PLAN} holds several checkpoint-label markers; keep exactly one:" >&2
    while IFS= read -r hit; do
        printf '  %s:%s\n' "$PLAN" "$hit" >&2
    done <<<"$hits"
    exit 1
fi
value="${hits#*: }"
printf '%s\n' "${value%% -->*}"
