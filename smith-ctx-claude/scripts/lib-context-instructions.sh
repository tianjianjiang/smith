#!/bin/bash

TEMPLATES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../templates" && pwd)"
TEMPLATE_FILE="${TEMPLATES_DIR}/context-instructions.md"

extract_template_section() {
    local section_heading="$1"
    awk -v heading="$section_heading" '
        $0 == heading { found=1; next }
        found && /^## / { exit }
        found { print }
    ' "$TEMPLATE_FILE"
}

substitute_vars() {
    local text="$1"
    local plan_path="${2:-}"
    local pending_count="${3:-0}"
    local iteration="${4:-?}"
    local critical_pct="${5:-60}"
    local context_pct="${6:-?}"
    local warning_pct="${7:-50}"

    echo "$text" \
        | sed "s|{{PLAN_PATH}}|${plan_path}|g" \
        | sed "s|{{PENDING_COUNT}}|${pending_count}|g" \
        | sed "s|{{ITERATION}}|${iteration}|g" \
        | sed "s|{{CRITICAL_PCT}}|${critical_pct}|g" \
        | sed "s|{{CONTEXT_PCT}}|${context_pct}|g" \
        | sed "s|{{WARNING_PCT}}|${warning_pct}|g"
}

render_warning_generic() {
    local plan_path="${1:-}"
    local pending_count="${2:-0}"
    local critical_pct="${3:-60}"
    local context_pct="${4:-?}"
    local warning_pct="${5:-50}"

    local template=$(extract_template_section "## 50% Warning (Generic)")
    substitute_vars "$template" "$plan_path" "$pending_count" "" "$critical_pct" "$context_pct" "$warning_pct"
}

render_warning_ralph() {
    local iteration="${1:-?}"
    local plan_path="${2:-}"
    local pending_count="${3:-0}"
    local critical_pct="${4:-60}"

    local template=$(extract_template_section "## 50% Warning (Ralph Active)")
    substitute_vars "$template" "$plan_path" "$pending_count" "$iteration" "$critical_pct"
}

render_warning_orchestrator() {
    local iteration="${1:-?}"
    local plan_path="${2:-}"
    local pending_count="${3:-0}"

    local template=$(extract_template_section "## 50% Warning (Orchestrator Active)")
    substitute_vars "$template" "$plan_path" "$pending_count" "$iteration"
}

render_critical_generic() {
    extract_template_section "## 60% Critical (Generic)"
}

render_critical_ralph() {
    extract_template_section "## 60% Critical (Ralph Active)"
}

render_critical_orchestrator() {
    local iteration="${1:-?}"

    local template=$(extract_template_section "## 60% Critical (Orchestrator Active)")
    substitute_vars "$template" "" "" "$iteration"
}
