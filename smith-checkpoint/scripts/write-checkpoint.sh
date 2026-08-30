#!/usr/bin/env bash
set -euo pipefail

readonly LABEL="${1:?Error: label required}"
readonly PLAN_ARG="${2:-}"

extract_plan_path() {
    if [[ "$PLAN_ARG" =~ ^plan=(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

detect_project_name() {
    if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        basename "$(git rev-parse --show-toplevel)"
    else
        echo "smith"
    fi
}

generate_timestamp() {
    date +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/'
}

generate_checkpoint_content() {
    local plan_path="$1"
    local timestamp="$2"
    local session_id=$(basename "${CLAUDE_JOB_DIR:-bg-job-unknown}")

    cat <<EOF
# ${LABEL}

**Date**: ${timestamp}
**Plan**: \`${plan_path}\`
**Session**: ${session_id}

## Status

Checkpoint created via shell script (zero tokens).

## Next Steps

Load context from plan file.

## Related

- Plan: ${plan_path}
EOF
}

transform_label_to_basic_memory_title() {
    echo "$LABEL" | sed 's/_/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2));}1'
}

write_to_serena() {
    local content="$1"
    echo "Writing to Serena: ${LABEL}"
    uvx --from git+https://github.com/oraios/serena serena memories write "${LABEL}" --content "${content}" 2>&1
}

write_to_basic_memory() {
    local content="$1"
    local title="$2"
    local project="$3"
    local folder="projects/${project}"

    echo "Writing to Basic-Memory: ${title}"
    uvx basic-memory tool write-note \
        --title "${title}" \
        --folder "${folder}" \
        --type guide \
        --tags checkpoint \
        --content "${content}" 2>&1
}

report_success() {
    local bm_title="$1"
    local project="$2"
    local timestamp="$3"

    cat <<EOF
✓ Checkpoint written to both backends
  Serena: ${LABEL}
  Basic-Memory: ${bm_title} (project: ${project})
  Timestamp: ${timestamp}
EOF
}

main() {
    local plan_path=$(extract_plan_path)
    local project=$(detect_project_name)
    local timestamp=$(generate_timestamp)
    local content=$(generate_checkpoint_content "$plan_path" "$timestamp")
    local bm_title=$(transform_label_to_basic_memory_title)

    if ! write_to_serena "$content"; then
        echo "Error: Serena write failed" >&2
        exit 1
    fi

    if ! write_to_basic_memory "$content" "$bm_title" "$project"; then
        echo "Error: Basic-Memory write failed" >&2
        exit 1
    fi

    report_success "$bm_title" "$project" "$timestamp"
}

main
