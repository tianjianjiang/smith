#!/usr/bin/env bash
set -euo pipefail

readonly BODY_PATH="${1:?Error: body path required}"
shift
readonly -a EXTRA_ARGS=("$@")

FAILURES=0
WARNINGS=0

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

report_fail() {
    echo "FAIL: $1"
    FAILURES=$((FAILURES + 1))
}

report_warn() {
    echo "WARN: $1"
    WARNINGS=$((WARNINGS + 1))
}

git_toplevel_of() {
    git -C "$1" rev-parse --show-toplevel 2>/dev/null || true
}

primary_checkout_of() {
    local common
    common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
    dirname "$common"
}

search_roots() {
    local plan_path="$1" extra_roots="$2" root
    {
        git_toplevel_of "$PWD"
        primary_checkout_of "$PWD"
        [[ -n "$plan_path" ]] && dirname "$plan_path"
        if [[ -n "$extra_roots" ]]; then
            tr ':' '\n' <<<"$extra_roots"
        fi
        echo "$PWD"
    } | while IFS= read -r root; do
        [[ -n "$root" && -d "$root" ]] && (cd "$root" && pwd -P)
    done | awk '!seen[$0]++'
}

anchor_tokens() {
    { grep -o '`[^`]*`' "$BODY_PATH" || true; } \
        | tr -d '`' \
        | grep -E '^[^[:space:]]+:[0-9]+(-[0-9]+)?$' \
        | grep -v '://' \
        | grep -vE '^[0-9.]+:' \
        | grep -E '^[^:]*[./][^:]*:' \
        | awk '!seen[$0]++' || true
}

expand_home() {
    local path="$1"
    if [[ "$path" == "~/"* ]]; then
        printf '%s' "${HOME}/${path#\~/}"
    else
        printf '%s' "$path"
    fi
}

candidate_files() {
    local path="$1" roots="$2" root
    path=$(expand_home "$path")
    if [[ "$path" == /* ]]; then
        [[ -f "$path" ]] && echo "$path"
        return 0
    fi
    while IFS= read -r root; do
        if [[ -f "${root}/${path}" ]]; then
            echo "${root}/${path}"
            return 0
        fi
    done <<<"$roots"
    local toplevel matches
    while IFS= read -r root; do
        toplevel=$(git_toplevel_of "$root")
        [[ -n "$toplevel" ]] || continue
        matches=$(git -C "$toplevel" ls-files 2>/dev/null \
            | awk -v p="$path" -v top="$toplevel" \
                '$0 == p || substr($0, length($0) - length(p)) == "/" p { print top "/" $0 }')
        if [[ -n "$matches" ]]; then
            echo "$matches"
            return 0
        fi
    done <<<"$roots"
}

line_count() {
    awk 'END { print NR }' "$1"
}

short_list() {
    awk 'NR <= 3 { printf "%s%s", (NR > 1 ? ", " : ""), $0 } END { if (NR > 3) printf " and %d more", NR - 3 }'
}

check_anchor() {
    local anchor="$1" roots="$2"
    local path="${anchor%:*}" range="${anchor##*:}"
    local last_line=$((10#${range##*-})) candidates candidate count fitting=0
    candidates=$(candidate_files "$path" "$roots")
    if [[ -z "$candidates" ]]; then
        report_fail "anchor \`${anchor}\`: no file \`${path}\` under $(short_list <<<"$roots") or tracked by git there; write the path relative to one of these roots, as an absolute path, or pass roots=«dir»"
        return 0
    fi
    while IFS= read -r candidate; do
        (( last_line <= $(line_count "$candidate") )) && fitting=$((fitting + 1))
    done <<<"$candidates"
    count=$(wc -l <<<"$candidates" | tr -d ' ')
    if (( fitting == 0 )); then
        report_fail "anchor \`${anchor}\`: line ${last_line} is past the end of $(short_list <<<"$candidates"); the anchor is stale, re-read the file and fix the line"
    elif (( count > 1 )); then
        report_warn "anchor \`${anchor}\` is ambiguous: ${count} tracked files end in \`${path}\` ($(short_list <<<"$candidates")); write the path from the repository root"
    fi
}

check_anchors() {
    local roots="$1" anchor
    while IFS= read -r anchor; do
        [[ -n "$anchor" ]] && check_anchor "$anchor" "$roots"
    done < <(anchor_tokens)
    return 0
}

commit_tokens() {
    { grep -oE '(commit|SHA)[[:space:]]*`?[0-9a-f]{7,40}\b' "$BODY_PATH" || true; } \
        | grep -oE '[0-9a-f]{7,40}$' | awk '!seen[$0]++' || true
}

check_commits() {
    local roots="$1" sha root resolved checked
    while IFS= read -r sha; do
        [[ -n "$sha" ]] || continue
        resolved=0
        checked=0
        while IFS= read -r root; do
            git -C "$root" rev-parse --is-inside-work-tree &>/dev/null || continue
            checked=1
            if git -C "$root" cat-file -e "${sha}^{commit}" 2>/dev/null; then
                resolved=1
                break
            fi
        done <<<"$roots"
        if (( ! checked )); then
            report_warn "commit \`${sha}\` was not verified: no git repository among the roots searched; pass roots=«repo» to check it"
        elif (( ! resolved )); then
            report_fail "commit \`${sha}\` does not resolve in any git root searched; fix the SHA or name the repository it belongs to with roots=«dir»"
        fi
    done < <(commit_tokens)
    return 0
}

check_plan() {
    local plan_path="$1"
    [[ -n "$plan_path" ]] || return 0
    if [[ ! -f "$plan_path" ]]; then
        report_warn "plan file not found: ${plan_path}; pass the live plan with plan=«path» or drop plan="
        return 0
    fi
    grep -q '^# ' "$plan_path" || report_warn "plan file has no '# ' heading, so the label falls back to the filename: ${plan_path}"
    return 0
}

heading_pattern() {
    printf '^## %s[[:space:]]*$' "$1"
}

body_section() {
    awk -v h="$(heading_pattern "$1")" '
        $0 ~ h { inside = 1; next }
        inside && /^## / { exit }
        inside { print }
    ' "$BODY_PATH"
}

check_plan_against_next() {
    local plan_path="$1" pending next
    [[ -n "$plan_path" && -f "$plan_path" ]] || return 0
    pending=$({ grep -c '^[[:space:]]*- \[ \]' "$plan_path" || true; })
    next=$(body_section Next | grep -c '[^[:space:]]' || true)
    if (( pending == 0 && next > 0 )); then
        report_warn "plan has no open '- [ ]' task but the body's '## Next' is not empty; tick the plan or drop the stale Next items"
    elif (( pending > 0 && next == 0 )); then
        report_warn "plan has ${pending} open '- [ ]' task(s) but the body's '## Next' is missing or empty; say what comes next"
    fi
}

check_sections() {
    local heading
    for heading in Completed Decisions Next Related; do
        grep -qE "$(heading_pattern "$heading")" "$BODY_PATH" || report_warn "body has no '## ${heading}' section"
    done
}

check_placeholders() {
    local hits
    hits=$({ grep -nE '«[^»]*»|\bTODO\b|\bTBD\b' "$BODY_PATH" || true; } | head -5)
    [[ -z "$hits" ]] || report_warn "body still holds a placeholder or TODO/TBD: $(tr '\n' ' ' <<<"$hits")"
}

main() {
    if [[ ! -f "$BODY_PATH" || ! -r "$BODY_PATH" ]]; then
        echo "FAIL: body is not a readable file: ${BODY_PATH}"
        exit 1
    fi
    local plan_path extra_roots roots
    plan_path=$(extract_arg plan || true)
    extra_roots=$(extract_arg roots || true)
    roots=$(search_roots "$plan_path" "$extra_roots")
    check_plan "$plan_path"
    check_anchors "$roots"
    check_commits "$roots"
    check_plan_against_next "$plan_path"
    check_sections
    check_placeholders
    echo "Audit: ${FAILURES} failure(s), ${WARNINGS} warning(s)"
    (( FAILURES == 0 ))
}

main
