#!/usr/bin/env bash
set -euo pipefail

readonly LABEL="${1:?Error: label required}"
shift
readonly -a EXTRA_ARGS=("$@")

extract_arg() {
    local key="$1" arg
    for arg in ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}; do
        if [[ "$arg" =~ ^${key}=(.*)$ ]]; then
            echo "${BASH_REMATCH[1]}"
            return 0
        fi
    done
    return 1
}

detect_active_plan() {
    local lib_context="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../smith-ctx-claude/scripts" 2>/dev/null && pwd)/lib-context.sh"
    [[ -f "$lib_context" ]] || return 0
    source "$lib_context"

    local cwd_key
    cwd_key=$(session_key) || return 0
    local state_file="${CTX_FLAGS_DIR}/.plan-state-${cwd_key}"
    [[ -f "$state_file" ]] || return 0

    local plan_path
    plan_path=$(sed -n '5p' "$state_file" 2>/dev/null)
    [[ -n "$plan_path" && -f "$plan_path" ]] && printf '%s\n' "$plan_path"
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

plan_title() {
    local plan_path="$1"
    [[ -f "$plan_path" ]] || return 0
    { grep -m1 '^# ' "$plan_path" || true; } | sed 's/^# *//'
}

plan_pending_items() {
    local plan_path="$1"
    [[ -f "$plan_path" ]] || return 0
    { grep '^[[:space:]]*- \[ \]' "$plan_path" || true; } | head -10
}

warn_if_plan_missing() {
    local plan_path="$1"
    [[ -z "$plan_path" || -f "$plan_path" ]] && return 0
    echo "Warning: plan file not found: ${plan_path}" >&2
}

git_state_line() {
    git rev-parse --is-inside-work-tree &>/dev/null || return 0
    local branch dirty
    branch=$(git branch --show-current 2>/dev/null)
    dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    echo "**Git**: ${branch:-detached} @ $(git rev-parse --short HEAD 2>/dev/null), ${dirty} uncommitted file(s)"
}

generate_fallback_body() {
    local plan_path="$1"
    local title pending
    title=$(plan_title "$plan_path")
    pending=$(plan_pending_items "$plan_path")

    echo "## Status"
    echo
    echo "No session body was supplied; only the facts below were recorded."
    [[ -n "$title" ]] && echo "**Plan title**: ${title}"
    git_state_line
    if [[ -n "$pending" ]]; then
        echo
        echo "## Pending"
        echo
        echo "$pending"
    fi
}

warn_if_body_exceeds_budget() {
    local body_path="$1"
    local bytes
    bytes=$(wc -c < "$body_path" | tr -d ' ')
    if (( bytes > 1600 )); then
        echo "Warning: body is ${bytes} bytes; target is <400 tokens (about 1600 bytes)" >&2
    fi
}

generate_checkpoint_content() {
    local plan_path="$1"
    local timestamp="$2"
    local body_path="$3"
    local session_id=$(basename "${CLAUDE_JOB_DIR:-bg-job-unknown}")
    local body

    if [[ -n "$body_path" ]]; then
        warn_if_body_exceeds_budget "$body_path"
        body=$(cat "$body_path") || return 1
    else
        body=$(generate_fallback_body "$plan_path") || return 1
    fi

    echo "# ${LABEL}"
    echo
    echo "**Date**: ${timestamp}"
    [[ -n "$plan_path" ]] && echo "**Plan**: \`${plan_path}\`"
    echo "**Session**: ${session_id}"
    echo
    append_plan_to_related "$body" "$plan_path"
}

append_plan_to_related() {
    local body="$1"
    local plan_path="$2"
    local plan_line="- Plan: ${plan_path}"
    if [[ -z "$plan_path" ]]; then
        printf '%s\n' "$body"
    elif grep -q '^## Related[[:space:]]*$' <<<"$body"; then
        awk -v plan="$plan_line" '
            pending && /^$/ { print; print plan; pending = 0; next }
            pending { print plan; pending = 0 }
            { print }
            /^## Related[[:space:]]*$/ { pending = 1 }
            END { if (pending) print plan }
        ' <<<"$body"
    else
        printf '%s\n\n## Related\n\n%s\n' "$body" "$plan_line"
    fi
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
Checkpoint written to both backends
  Serena: ${LABEL}
  Basic-Memory: ${permalink}
  Timestamp: ${timestamp}
EOF
}

require_readable_body() {
    local body_path="$1"
    if [[ -z "$body_path" || ! -f "$body_path" || ! -r "$body_path" ]]; then
        echo "Error: body file not found or unreadable: '${body_path}'" >&2
        exit 1
    fi
    if ! grep -q '[^[:space:]]' "$body_path"; then
        echo "Error: body file is empty: '${body_path}'" >&2
        exit 1
    fi
}

main() {
    local plan_path=$(extract_arg plan)
    [[ -z "$plan_path" ]] && plan_path=$(detect_active_plan)
    local body_path=""
    if body_path=$(extract_arg body); then
        require_readable_body "$body_path"
    fi
    warn_if_plan_missing "$plan_path"
    local primary_checkout=$(resolve_primary_checkout)
    local project=$(detect_project_name "$primary_checkout")
    local timestamp=$(generate_timestamp)
    local content
    content=$(generate_checkpoint_content "$plan_path" "$timestamp" "$body_path") || {
        echo "Error: could not generate checkpoint content" >&2
        exit 1
    }
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
