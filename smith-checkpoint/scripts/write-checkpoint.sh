#!/usr/bin/env bash
set -euo pipefail

readonly LABEL="${1:?Error: label required}"
readonly PLAN_ARG="${2:-}"

extract_plan_path() {
    if [[ "$PLAN_ARG" =~ ^plan=(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

resolve_primary_checkout() {
    command -v git &>/dev/null || return 0
    git rev-parse --is-inside-work-tree &>/dev/null || return 0
    local common_dir
    common_dir=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P) || return 0
    [[ -n "$common_dir" ]] && dirname "$common_dir"
}

detect_project_name() {
    basename "${1:-smith}"
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
    local primary_checkout="$2"
    echo "Writing to Serena: ${LABEL}" >&2
    uvx --from git+https://github.com/oraios/serena serena memories write "${LABEL}" ${primary_checkout:+"$primary_checkout"} --content "${content}" >&2
}

write_to_basic_memory() {
    local content="$1"
    local title="$2"
    local project="$3"
    local folder="projects/${project}"

    echo "Writing to Basic-Memory: ${title}" >&2
    uvx basic-memory tool write-note \
        --title "${title}" \
        --folder "${folder}" \
        --type guide \
        --tags checkpoint \
        --overwrite \
        --content "${content}"
}

generate_reload_block() {
    local permalink="$1"
    local plan_path="$2"
    local timestamp="$3"
    local project="$4"

    cat <<EOF

Checkpoint: ${LABEL} (${timestamp})
Manual resume: /smith-recon "resume my work thread on ${LABEL}"
State locations:
- Serena: ${LABEL} (${project} project)
- Basic-Memory: ${permalink}
EOF

    if [[ -n "$plan_path" ]]; then
        echo "- plan: ${plan_path}"
    fi
}

report_success() {
    local permalink="$1"
    local project="$2"
    local timestamp="$3"

    cat >&2 <<EOF
✓ Checkpoint written to both backends
  Serena: ${LABEL}
  Basic-Memory: ${permalink}
  Timestamp: ${timestamp}
EOF
}

main() {
    local plan_path=$(extract_plan_path)
    local primary_checkout=$(resolve_primary_checkout)
    local project=$(detect_project_name "$primary_checkout")
    local timestamp=$(generate_timestamp)
    local content=$(generate_checkpoint_content "$plan_path" "$timestamp")
    local bm_title=$(transform_label_to_basic_memory_title)

    if ! write_to_serena "$content" "$primary_checkout"; then
        echo "Error: Serena write failed" >&2
        exit 1
    fi

    local bm_result
    if ! bm_result=$(write_to_basic_memory "$content" "$bm_title" "$project"); then
        echo "Error: Basic-Memory write failed" >&2
        exit 1
    fi

    local permalink=$(echo "$bm_result" | grep -o '"permalink": "[^"]*"' | cut -d'"' -f4)

    report_success "$permalink" "$project" "$timestamp"
    generate_reload_block "$permalink" "$plan_path" "$timestamp" "$project"
}

main
