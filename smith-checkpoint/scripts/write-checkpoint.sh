#!/usr/bin/env bash
set -euo pipefail

readonly LABEL="${1:?Error: label required}"
shift
readonly -a EXTRA_ARGS=("$@")

RELOAD_STATUS=""
RELOAD_FLAG_PATH=""
RELOAD_SUPERSEDED=0
BM_FOLDER=""
RELOCATED_MOVED=0
RELOCATED_REMOVED=0
RELOCATED_RENAMED=0
AUDIT_STATUS=""
SERENA_ENTRIES=""
BM_ENTRIES=""
SERENA_BACKUP=""
SERENA_PRIOR=""
BM_BACKUP=""
BM_WRITE_RESULT=""
readonly BACKUPS_KEPT=5
readonly ENTRY_HEADING_PATTERN='^## [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$'

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
    if [[ -n "$plan_path" && -f "$plan_path" ]]; then
        printf '%s\n' "$plan_path"
    fi
    return 0
}

write_reload_flag() {
    local reload_script="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../smith-ctx-claude/scripts" 2>/dev/null && pwd)/write-reload-flag.sh"
    if [[ ! -e "$reload_script" ]]; then
        RELOAD_STATUS="unavailable"
        return 0
    fi
    if [[ ! -x "$reload_script" ]]; then
        echo "Warning: reload-flag script found but not executable: ${reload_script}" >&2
        RELOAD_STATUS="failed"
        return 0
    fi

    local output
    if output=$("$reload_script" "$LABEL" 2>&1); then
        RELOAD_FLAG_PATH=$(sed -n 's/^Wrote reload flag: //p' <<<"$output" | tail -1)
        RELOAD_STATUS="written"
        supersede_earlier_reload_flags
    else
        echo "Warning: reload-flag write failed: ${output}" >&2
        RELOAD_STATUS="failed"
    fi
    return 0
}

supersede_earlier_reload_flags() {
    [[ -n "$RELOAD_FLAG_PATH" && -f "$RELOAD_FLAG_PATH" && ! -L "$RELOAD_FLAG_PATH" ]] || return 0
    [[ -n "$(sed -n '5p' "$RELOAD_FLAG_PATH" 2>/dev/null)" ]] || return 0
    local identity old_flag
    identity=$(sed -n '3,5p' "$RELOAD_FLAG_PATH" 2>/dev/null) || return 0
    for old_flag in "$(dirname "$RELOAD_FLAG_PATH")"/.pending-memory-restore-*; do
        [[ "$old_flag" != "$RELOAD_FLAG_PATH" && -f "$old_flag" && ! -L "$old_flag" ]] || continue
        [[ "$(sed -n '3,5p' "$old_flag" 2>/dev/null)" == "$identity" ]] || continue
        rm -f "$old_flag" 2>/dev/null && RELOAD_SUPERSEDED=$((RELOAD_SUPERSEDED + 1))
    done
    return 0
}

physical_path() {
    (cd "$1" 2>/dev/null && pwd -P)
}

inside_git_work_tree() {
    command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null
}

resolve_primary_checkout() {
    inside_git_work_tree || return 0
    local common_dir
    common_dir=$(physical_path "$(git rev-parse --git-common-dir)") || return 0
    [[ -n "$common_dir" ]] && dirname "$common_dir"
}

resolve_worktree() {
    inside_git_work_tree || return 0
    local git_dir common_dir
    git_dir=$(physical_path "$(git rev-parse --git-dir)") || return 0
    common_dir=$(physical_path "$(git rev-parse --git-common-dir)") || return 0
    [[ "$git_dir" != "$common_dir" ]] || return 0
    physical_path "$(git rev-parse --show-toplevel)"
}

reject_retired_store_variables() {
    local var
    for var in BASIC_MEMORY_CONFIG_DIR BASIC_MEMORY_HOME; do
        [[ -n "${!var:-}" ]] || continue
        cat >&2 <<EOF
Error: ${var}=${!var} is set; this variable is retired, Basic-Memory projects are selected by name (basicMemory.primaryProject in .claude/settings.local.json). Nothing was written.
Likely sources: a repository .claude/settings.local.json env block not yet migrated, a profile launcher script not yet migrated, a long-lived claude daemon started before the migration (claude daemon stop --any), or a stale shell export (unset ${var} and retry).
EOF
        exit 1
    done
}

primary_project_from_settings() {
    local root="$1" file value error_output
    for file in "$root/.claude/settings.local.json" "$root/.claude/settings.json"; do
        [[ -f "$file" ]] || continue
        if ! value=$(jq -r '.basicMemory.primaryProject | if . == null then "" elif type == "string" then . else error("basicMemory.primaryProject must be a string") end' "$file" 2>&1); then
            echo "Error: cannot read basicMemory.primaryProject from ${file}: ${value}. Nothing was written." >&2
            exit 1
        fi
        if [[ -n "$value" ]]; then
            printf '%s\t%s' "$value" "$file"
            return 0
        fi
    done
    return 0
}

resolve_bm_project() {
    local root="$1"
    local configured configured_file settings_result lock="${BASIC_MEMORY_MCP_PROJECT:-}"
    settings_result=$(primary_project_from_settings "$root") || exit 1
    IFS=$'\t' read -r configured configured_file <<<"$settings_result"
    if [[ -n "$lock" && -n "$configured" && "$lock" != "$configured" ]]; then
        echo "Error: BASIC_MEMORY_MCP_PROJECT=${lock} conflicts with basicMemory.primaryProject ${configured} (${configured_file}); this repository is open in the wrong profile, or the lock must be removed. Nothing was written." >&2
        exit 1
    fi
    [[ -n "$lock" ]] && return 0
    printf '%s' "$configured"
}

describe_bm_project() {
    local bm_project="$1" lock="${BASIC_MEMORY_MCP_PROJECT:-}"
    if [[ -n "$lock" ]]; then
        printf '%s (locked by BASIC_MEMORY_MCP_PROJECT)' "$lock"
    elif [[ -n "$bm_project" ]]; then
        printf '%s' "$bm_project"
    else
        printf '(default)'
    fi
}

resolve_serena_project() {
    local primary_checkout="$1" requested
    if requested=$(extract_arg serena); then
        local resolved
        if ! resolved=$(physical_path "$requested") || [[ ! -f "$resolved/.serena/project.yml" ]]; then
            echo "Error: serena=${requested} is not a Serena project (.serena/project.yml missing). Nothing was written." >&2
            exit 1
        fi
        printf '%s' "$resolved"
        return 0
    fi
    printf '%s' "$primary_checkout"
}

warn_serena_divergence() {
    local chosen="$1" cwd
    extract_arg serena >/dev/null && return 0
    cwd=$(pwd -P)
    [[ -n "$chosen" && "$cwd" != "$chosen" && -f "$cwd/.serena/project.yml" ]] || return 0
    echo "Warning: cwd ${cwd} is itself a Serena project; this checkpoint is written to ${chosen}. MCP tools bound to ${cwd} will not list it; pass serena=${cwd} to write there instead." >&2
}

serena_memory_location() {
    local serena_project="$1"
    if [[ -n "$serena_project" ]]; then
        printf '%s/.serena/memories/%s.md' "$serena_project" "$LABEL"
    else
        printf '%s (Serena default project)' "$LABEL"
    fi
}

relocate_worktree_memories() {
    local worktree="$1" primary_checkout="$2"
    [[ -n "$worktree" && -n "$primary_checkout" && -d "$worktree/.serena/memories" ]] || return 0
    local source_dir="$worktree/.serena/memories" dest_dir="$primary_checkout/.serena/memories"
    [[ "$source_dir" -ef "$dest_dir" ]] && return 0
    local -a files=()
    local file
    for file in "$source_dir"/*.md; do
        [[ -f "$file" ]] && files+=("$file")
    done
    (( ${#files[@]} > 0 )) || return 0
    if [[ ! -f "$primary_checkout/.serena/project.yml" ]]; then
        echo "Warning: primary checkout ${primary_checkout} is not a Serena project; ${#files[@]} worktree memories left in place under ${source_dir}" >&2
        return 0
    fi
    local unrelocated_outcome="${#files[@]} worktree memories left in place under ${source_dir}; no backend was written."
    if [[ -L "$dest_dir" && ! -e "$dest_dir" ]]; then
        echo "Error: ${dest_dir} is a symbolic link to $(readlink "$dest_dir"), which does not exist or cannot be reached; ${unrelocated_outcome}" >&2
        exit 1
    fi
    if [[ -e "$dest_dir" && ! -d "$dest_dir" ]]; then
        echo "Error: ${dest_dir} exists and is not a directory; ${unrelocated_outcome}" >&2
        exit 1
    fi
    local source_physical
    if ! source_physical=$(physical_path "$source_dir"); then
        echo "Warning: could not resolve ${source_dir} to a physical path; ${#files[@]} memories left in place, not relocated" >&2
        return 0
    fi
    if [[ "$source_physical" != "$source_dir" ]]; then
        echo "Warning: ${source_dir} resolves to ${source_physical}, which is not the memories directory of worktree ${worktree}; ${#files[@]} memories left in place, not relocated" >&2
        return 0
    fi
    if ! mkdir -p "$dest_dir"; then
        echo "Error: could not create ${dest_dir}; ${unrelocated_outcome}" >&2
        exit 1
    fi
    local name dest renamed compare_status
    for file in "${files[@]}"; do
        name=$(basename "$file")
        dest="$dest_dir/$name"
        if [[ ! -e "$dest" ]]; then
            mv "$file" "$dest"
            RELOCATED_MOVED=$((RELOCATED_MOVED + 1))
            echo "Relocated worktree memory: ${name} -> ${dest}" >&2
            continue
        fi
        compare_status=0
        cmp -s "$file" "$dest" || compare_status=$?
        case "$compare_status" in
            0)
                rm -f "$file"
                RELOCATED_REMOVED=$((RELOCATED_REMOVED + 1))
                echo "Removed duplicate worktree memory: ${name} (identical copy already in ${dest_dir})" >&2
                ;;
            1)
                renamed=$(unused_worktree_copy_name "$dest_dir" "${name%.md}__from_worktree_$(basename "$worktree")")
                mv "$file" "$dest_dir/$renamed"
                RELOCATED_RENAMED=$((RELOCATED_RENAMED + 1))
                echo "Warning: worktree memory ${name} differs from the primary copy; kept both, worktree copy saved as ${dest_dir}/${renamed}" >&2
                ;;
            *)
                echo "Error: could not compare worktree memory ${file} with ${dest} (cmp exit ${compare_status}); relocation stopped after moving ${RELOCATED_MOVED}, removing ${RELOCATED_REMOVED}, renaming ${RELOCATED_RENAMED} (see the lines above); no backend was written." >&2
                exit 1
                ;;
        esac
    done
}

unused_worktree_copy_name() {
    local dest_dir="$1" stem="$2" index=2
    local candidate="${stem}.md"
    while [[ -e "$dest_dir/$candidate" ]]; do
        candidate="${stem}_${index}.md"
        index=$((index + 1))
    done
    printf '%s' "$candidate"
}

relocation_summary() {
    (( RELOCATED_MOVED + RELOCATED_REMOVED + RELOCATED_RENAMED > 0 )) || return 0
    printf 'moved %d, removed %d, renamed %d' "$RELOCATED_MOVED" "$RELOCATED_REMOVED" "$RELOCATED_RENAMED"
}

detect_project_name() {
    basename "${1:-$PWD}"
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

current_branch() {
    git branch --show-current 2>/dev/null
}

git_state_line() {
    git rev-parse --is-inside-work-tree &>/dev/null || return 0
    local branch dirty
    branch=$(current_branch)
    dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    echo "**Git**: ${branch:-detached} @ $(git rev-parse --short HEAD 2>/dev/null), ${dirty} uncommitted file(s)"
}

worktree_header_lines() {
    local worktree="$1" primary_checkout="$2"
    [[ -n "$worktree" ]] || return 0
    local branch
    branch=$(current_branch)
    echo "**Worktree**: \`${worktree}\`"
    echo "**Branch**: ${branch:-detached}"
    echo "**Primary**: \`${primary_checkout}\`"
    echo "**Resume**: EnterWorktree path=${worktree} before any file edit"
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
        echo "Note: body is ${bytes} bytes (guideline ~1600); trim only non-durable content" >&2
    fi
}

generate_entry() {
    local plan_path="$1"
    local timestamp="$2"
    local body_path="$3"
    local worktree="$4"
    local primary_checkout="$5"
    local session_id=$(basename "${CLAUDE_JOB_DIR:-bg-job-unknown}")
    local body

    if [[ -n "$body_path" ]]; then
        warn_if_body_exceeds_budget "$body_path"
        body=$(cat "$body_path") || return 1
    else
        body=$(generate_fallback_body "$plan_path") || return 1
    fi

    echo "## ${timestamp}"
    echo
    [[ -n "$plan_path" ]] && echo "**Plan**: \`${plan_path}\`"
    echo "**Session**: ${session_id}"
    git_state_line
    worktree_header_lines "$worktree" "$primary_checkout"
    echo
    append_plan_to_related "$body" "$plan_path"
}

strip_title_line() {
    local content="$1"
    local title="# ${LABEL}"
    while [[ "$content" == $'\n'* ]]; do
        content="${content#$'\n'}"
    done
    local first_line="${content%%$'\n'*}"
    if [[ "$first_line" == "$title" ]]; then
        if [[ "$content" == "$title" ]]; then
            content=""
        else
            content="${content#*$'\n'}"
            content="${content#$'\n'}"
        fi
    fi
    printf '%s' "$content"
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

build_merged_document() {
    local entry="$1"
    local existing="$2"
    local document="# ${LABEL}"$'\n\n'"${entry}"
    local prior
    if [[ -n "$existing" ]]; then
        prior=$(strip_title_line "$existing")
        [[ -n "$prior" ]] && document="${document}"$'\n\n'"${prior}"
    fi
    printf '%s' "$document"
}

serena_memories() {
    uvx --from git+https://github.com/oraios/serena serena memories "$@"
}

basic_memory_tool() {
    uvx --prerelease=allow basic-memory tool "$@"
}

read_serena_memory() {
    local serena_project="$1"
    local output error_file error_output
    error_file=$(mktemp)
    if output=$(serena_memories read "${LABEL}" ${serena_project:+"$serena_project"} 2>"$error_file"); then
        rm -f "$error_file"
        printf '%s' "$output"
        return 0
    fi
    error_output=$(cat "$error_file")
    rm -f "$error_file"
    if grep -qiE "Memory named '.*' not found" <<<"$error_output"; then
        return 0
    fi
    echo "Error: could not read existing Serena memory for ${LABEL}: ${error_output}" >&2
    return 1
}

count_entries() {
    grep -cE "$ENTRY_HEADING_PATTERN" <<<"$1" || true
}

first_entry_heading() {
    grep -m1 -E "$ENTRY_HEADING_PATTERN" <<<"$1" || true
}

verify_readback() {
    local backend="$1" timestamp="$2" prior="$3" stored="$4"
    local expected actual top
    expected=$(( $(count_entries "$prior") + 1 ))
    actual=$(count_entries "$stored")
    top=$(first_entry_heading "$stored")
    if [[ "$top" != "## ${timestamp}" ]]; then
        echo "Error: ${backend} readback: newest entry is '${top:-none}', expected '## ${timestamp}'" >&2
        return 1
    fi
    if (( actual != expected )); then
        echo "Error: ${backend} readback: ${actual} entries stored, expected ${expected} (prior entries lost or duplicated)" >&2
        return 1
    fi
    printf '%s' "$actual"
}

without_leading_newlines() {
    local text="$1"
    while [[ "$text" == $'\n'* ]]; do
        text="${text#$'\n'}"
    done
    printf '%s' "$text"
}

same_text() {
    [[ "$(without_leading_newlines "$1")" == "$(without_leading_newlines "$2")" ]]
}

verify_exact_readback() {
    local backend="$1" document="$2" stored="$3"
    same_text "$stored" "$document" && return 0
    echo "Error: ${backend} readback: the stored document differs from what was written" >&2
    return 1
}

backup_directory() {
    printf '%s/checkpoint-backups/%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "$LABEL"
}

prune_backups() {
    local directory="$1" backend="$2" keep="$3" stale_file
    find "$directory" -maxdepth 1 -type f -name "*-${backend}.md" \
        | sort -r \
        | tail -n +$((BACKUPS_KEPT + 1)) \
        | while IFS= read -r stale_file; do
            [[ "$stale_file" == "$keep" ]] && continue
            rm -f "$stale_file" || echo "Warning: could not prune old backup ${stale_file}" >&2
        done
}

backup_prior() {
    local backend="$1" prior="$2"
    local directory backup_file
    [[ -n "$prior" ]] || return 0
    directory=$(backup_directory)
    backup_file="${directory}/$(date -u +%Y%m%dT%H%M%SZ)-$$-${backend}.md"
    if ! mkdir -p "$directory" || ! printf '%s' "$prior" > "$backup_file"; then
        echo "Error: could not back up the ${backend} document before overwriting it: ${backup_file}; nothing was written to ${backend}" >&2
        return 1
    fi
    prune_backups "$directory" "$backend" "$backup_file"
    if [[ ! -f "$backup_file" ]]; then
        echo "Error: the ${backend} backup vanished after pruning: ${backup_file}; nothing was written to ${backend}" >&2
        return 1
    fi
    printf '%s' "$backup_file"
}

protect_backup() {
    local backup_file="$1" protected="${1%.md}-restore-failed.md"
    if mv "$backup_file" "$protected" 2>/dev/null; then
        printf '%s' "$protected"
    else
        echo "Warning: could not rename ${backup_file} out of pruning; copy it somewhere safe before the next checkpoint under this label" >&2
        printf '%s' "$backup_file"
    fi
}

report_restore() {
    local backend="$1" backup_file="$2" prior="$3" restored="$4" written="$5"
    if [[ -z "$backup_file" ]]; then
        if (( written )) && [[ -z "$restored" ]]; then
            echo "Error: ${backend} held no prior document, so the one this checkpoint created was removed; this checkpoint is not in ${backend}" >&2
        else
            echo "Error: ${backend} held no prior document and the removal of the one this checkpoint may have created could not be confirmed; check ${backend} for this checkpoint's entry" >&2
        fi
    elif (( written )) && same_text "$restored" "$prior"; then
        echo "Error: ${backend} restored from ${backup_file}; this checkpoint is not in ${backend}" >&2
    else
        echo "Error: ${backend} restore failed; its prior document is preserved at $(protect_backup "$backup_file")" >&2
    fi
}

restore_serena() {
    local serena_project="$1" backup_file="$2" prior="$3" restored="" written=0
    if [[ -n "$backup_file" ]]; then
        serena_memories write "${LABEL}" ${serena_project:+"$serena_project"} --content "${prior}" >&2 && written=1
    else
        serena_memories delete "${LABEL}" ${serena_project:+"$serena_project"} >&2 && written=1
    fi
    restored=$(read_serena_memory "$serena_project") || written=0
    report_restore Serena "$backup_file" "$prior" "$restored" "$written"
}

write_to_serena() {
    local entry="$1" serena_project="$2" timestamp="$3"
    local document stored
    echo "Writing to Serena: ${LABEL}" >&2
    SERENA_PRIOR=$(read_serena_memory "$serena_project") || return 1
    SERENA_BACKUP=$(backup_prior serena "$SERENA_PRIOR") || return 1
    document=$(build_merged_document "$entry" "$SERENA_PRIOR")
    if serena_memories write "${LABEL}" ${serena_project:+"$serena_project"} --content "${document}" >&2 \
        && stored=$(read_serena_memory "$serena_project") \
        && SERENA_ENTRIES=$(verify_readback Serena "$timestamp" "$SERENA_PRIOR" "$stored") \
        && verify_exact_readback Serena "$document" "$stored"; then
        return 0
    fi
    restore_serena "$serena_project" "$SERENA_BACKUP" "$SERENA_PRIOR"
    return 1
}

restore_basic_memory() {
    local title="$1" folder="$2" bm_project="$3" backup_file="$4" prior="$5" permalink="$6"
    local restored="" written=0
    if [[ -n "$backup_file" ]]; then
        write_basic_memory_document "$title" "$folder" "$bm_project" "$prior" >/dev/null && written=1
        restored=$(read_basic_memory_content "$title" "$bm_project") || written=0
    elif [[ -z "$permalink" ]]; then
        echo "Error: Basic-Memory held no prior document and returned no permalink for this write, so nothing was deleted (deleting by title could hit a same-titled note elsewhere); check Basic-Memory for this checkpoint's entry" >&2
        return 0
    else
        basic_memory_tool delete-note "$permalink" ${bm_project:+--project "$bm_project"} >&2 && written=1
        restored=$(read_basic_memory_content "$permalink" "$bm_project") || written=0
        restored+=$(read_basic_memory_content "$title" "$bm_project") || written=0
    fi
    report_restore Basic-Memory "$backup_file" "$prior" "$restored" "$written"
}

permalink_of() {
    jq -r '.permalink // empty' <<<"$1" 2>/dev/null || true
}

write_and_verify_basic_memory() {
    local entry="$1" title="$2" prior="$3" folder="$4" bm_project="$5" timestamp="$6"
    local result="" document stored
    BM_BACKUP=$(backup_prior basic-memory "$prior") || return 1
    document=$(build_merged_document "$entry" "$prior")
    if result=$(write_basic_memory_document "$title" "$folder" "$bm_project" "$document") \
        && stored=$(read_basic_memory_content "$title" "$bm_project") \
        && BM_ENTRIES=$(verify_readback Basic-Memory "$timestamp" "$prior" "$stored") \
        && verify_exact_readback Basic-Memory "$document" "$stored"; then
        BM_WRITE_RESULT="$result"
        return 0
    fi
    restore_basic_memory "$title" "$folder" "$bm_project" "$BM_BACKUP" "$prior" "$(permalink_of "$result")"
    return 1
}

run_audit() {
    local body_path="$1" plan_path="$2"
    local audit_script skip roots
    [[ -n "$body_path" ]] || { AUDIT_STATUS="not run (no body)"; return 0; }
    skip=$(extract_arg audit || true)
    if [[ "$skip" == "skip" ]]; then
        echo "Warning: audit skipped by audit=skip" >&2
        AUDIT_STATUS="skipped by audit=skip"
        return 0
    fi
    audit_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/audit-checkpoint.sh"
    if [[ ! -x "$audit_script" ]]; then
        echo "Error: audit script missing or not executable: ${audit_script}; nothing was written" >&2
        exit 1
    fi
    roots=$(extract_arg roots || true)
    if ! "$audit_script" "$body_path" ${plan_path:+"plan=$plan_path"} ${roots:+"roots=$roots"} >&2; then
        echo "Error: checkpoint audit failed; nothing was written. Fix each FAIL above and rerun" >&2
        exit 1
    fi
    AUDIT_STATUS="passed"
}

read_basic_memory_note_json() {
    local title="$1" bm_project="$2"
    local result error_file error_output
    error_file=$(mktemp)
    if ! result=$(basic_memory_tool read-note "$title" ${bm_project:+--project "$bm_project"} 2>"$error_file"); then
        error_output=$(cat "$error_file")
        rm -f "$error_file"
        echo "Error: could not read existing Basic-Memory note for ${title}: ${error_output}" >&2
        return 1
    fi
    rm -f "$error_file"
    printf '%s' "$result"
}

extract_basic_memory_content() {
    local result="$1" title="$2" content
    if ! content=$(jq -r '.content // empty' <<<"$result" 2>&1); then
        echo "Error: could not parse Basic-Memory read-note output for ${title}: ${content}" >&2
        return 1
    fi
    printf '%s' "$content"
}

read_basic_memory_content() {
    local title="$1" bm_project="$2" read_result
    read_result=$(read_basic_memory_note_json "$title" "$bm_project") || return 1
    extract_basic_memory_content "$read_result" "$title"
}

extract_basic_memory_file_path() {
    local result="$1"
    jq -r '.file_path // empty' <<<"$result" 2>/dev/null
}

basic_memory_folder_from_file_path() {
    local file_path="$1"
    if [[ -z "$file_path" ]]; then
        return 0
    elif [[ "$file_path" == */* ]]; then
        printf '%s' "${file_path%/*}"
    else
        printf '.'
    fi
}

resolve_basic_memory_folder() {
    local result="$1" project="$2"
    local file_path existing_folder
    file_path=$(extract_basic_memory_file_path "$result")
    existing_folder=$(basic_memory_folder_from_file_path "$file_path")
    printf '%s' "${existing_folder:-projects/${project}}"
}

write_basic_memory_document() {
    local title="$1"
    local folder="$2"
    local bm_project="$3"
    local document="$4"
    basic_memory_tool write-note \
        --title "${title}" \
        --folder "${folder}" \
        --type guide \
        --tags checkpoint \
        --overwrite \
        ${bm_project:+--project "$bm_project"} \
        --content "${document}"
}

generate_reload_block() {
    local permalink="$1"
    local plan_path="$2"
    local timestamp="$3"
    local reload_status="$4"
    local serena_location="$5"
    local bm_project_label="$6"
    local worktree="$7"
    local relocation

    cat <<EOF

Checkpoint: ${LABEL} (${timestamp})
Manual resume: /smith-recon "resume my work thread on ${LABEL}"
State locations:
- Serena: ${serena_location}
- Basic-Memory: ${permalink} (project: ${bm_project_label}, folder: ${BM_FOLDER})
EOF

    [[ -n "$plan_path" ]] && echo "- Plan: ${plan_path}"
    if [[ -n "$worktree" ]]; then
        local branch
        branch=$(current_branch)
        echo "- Worktree: ${worktree} (branch ${branch:-detached}) — resume with EnterWorktree path=${worktree}"
    fi
    relocation=$(relocation_summary)
    [[ -n "$relocation" ]] && echo "- Relocated worktree memories: ${relocation}"
    echo "- Audit: ${AUDIT_STATUS}"
    echo "- Verified: serena ${SERENA_ENTRIES} entries, basic-memory ${BM_ENTRIES} entries"
    [[ -n "${SERENA_BACKUP}${BM_BACKUP}" ]] && echo "- Prior documents backed up: $(backup_directory) (last ${BACKUPS_KEPT} per backend kept)"
    [[ -n "$RELOAD_FLAG_PATH" ]] && echo "- Reload flag: ${RELOAD_FLAG_PATH}"
    [[ "$RELOAD_SUPERSEDED" -gt 0 ]] && echo "- Superseded reload flags: ${RELOAD_SUPERSEDED} earlier flag(s) of this session for this directory and label"

    case "$reload_status" in
        written)
            echo "Auto-reload: flag written (restore not guaranteed; a live /clear proves it)"
            ;;
        failed)
            echo "Auto-reload: flag write failed — use manual resume above"
            ;;
        *)
            echo "Auto-reload: unavailable (no Claude Code reload-flag script found)"
            ;;
    esac
}

report_success() {
    local permalink="$1"
    local serena_location="$2"
    local bm_project_label="$3"
    local timestamp="$4"

    cat >&2 <<EOF
Checkpoint written to both backends
  Serena: ${serena_location}
  Basic-Memory: ${permalink} (project: ${bm_project_label}, folder: ${BM_FOLDER})
  Timestamp: ${timestamp}
EOF
}

fail_basic_memory_write() {
    local serena_project="$1"
    echo "Error: Basic-Memory write failed; rolling Serena back so both backends hold the same entries" >&2
    restore_serena "$serena_project" "$SERENA_BACKUP" "$SERENA_PRIOR"
    exit 1
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
    command -v jq &>/dev/null || {
        echo "Error: jq is required (used to parse Basic-Memory CLI output)" >&2
        exit 1
    }
    local plan_path=$(extract_arg plan)
    [[ -z "$plan_path" ]] && plan_path=$(detect_active_plan)
    local body_path=""
    if body_path=$(extract_arg body); then
        require_readable_body "$body_path"
    fi
    warn_if_plan_missing "$plan_path"
    reject_retired_store_variables
    local primary_checkout=$(resolve_primary_checkout)
    local worktree bm_project bm_project_label serena_project serena_location
    worktree=$(resolve_worktree)
    local project=$(detect_project_name "$primary_checkout")
    bm_project=$(resolve_bm_project "${primary_checkout:-$PWD}") || exit 1
    bm_project_label=$(describe_bm_project "$bm_project")
    serena_project=$(resolve_serena_project "$primary_checkout") || exit 1
    warn_serena_divergence "$serena_project"
    serena_location=$(serena_memory_location "$serena_project")
    run_audit "$body_path" "$plan_path"
    relocate_worktree_memories "$worktree" "$primary_checkout"
    local timestamp=$(generate_timestamp)
    local entry
    entry=$(generate_entry "$plan_path" "$timestamp" "$body_path" "$worktree" "$primary_checkout") || {
        echo "Error: could not generate checkpoint entry" >&2
        exit 1
    }
    local bm_title=$(transform_label_to_basic_memory_title)

    if ! write_to_serena "$entry" "$serena_project" "$timestamp"; then
        echo "Error: Serena write failed" >&2
        exit 1
    fi

    echo "Writing to Basic-Memory: ${bm_title}" >&2
    local bm_read_result bm_existing bm_result
    bm_read_result=$(read_basic_memory_note_json "$bm_title" "$bm_project") || fail_basic_memory_write "$serena_project"
    bm_existing=$(extract_basic_memory_content "$bm_read_result" "$bm_title") || fail_basic_memory_write "$serena_project"
    BM_FOLDER=$(resolve_basic_memory_folder "$bm_read_result" "$project")
    write_and_verify_basic_memory "$entry" "$bm_title" "$bm_existing" "$BM_FOLDER" "$bm_project" "$timestamp" || fail_basic_memory_write "$serena_project"
    bm_result="$BM_WRITE_RESULT"

    local permalink
    if ! permalink=$(jq -r '.permalink // empty' <<<"$bm_result" 2>&1); then
        echo "Warning: could not parse Basic-Memory permalink from write-note output: ${permalink}" >&2
        permalink=""
    fi

    write_reload_flag

    report_success "$permalink" "$serena_location" "$bm_project_label" "$timestamp"
    generate_reload_block "$permalink" "$plan_path" "$timestamp" "$RELOAD_STATUS" "$serena_location" "$bm_project_label" "$worktree"
}

main
