#!/bin/bash
#
# load-plan.sh - Load and output a plan file
#
# Usage: ./load-plan.sh «plan-name»
#        If no name given, loads most recent plan
#

source "$(dirname "$0")/../ctx-claude/scripts/lib-plan.sh"
PLAN_NAME="$1"
OWN_SCOPE=$(scope_key "${PWD:-}")

if [[ ! -d "$PLANS_DIR" ]]; then
    echo "Error: No plans directory found at $PLANS_DIR" >&2
    exit 1
fi

# Find the plan file
PLAN_FILE=""

if [[ -n "$PLAN_NAME" ]]; then
    if [[ -f "${PLANS_DIR}/${PLAN_NAME}" ]]; then
        PLAN_FILE="${PLANS_DIR}/${PLAN_NAME}"
    elif [[ -f "${PLANS_DIR}/${PLAN_NAME}.md" ]]; then
        PLAN_FILE="${PLANS_DIR}/${PLAN_NAME}.md"
    else
        PLAN_FILE=$(find "$PLANS_DIR" -maxdepth 1 -name "*${PLAN_NAME}*.md" -type f 2>/dev/null | head -1)
    fi
    
    if [[ -z "$PLAN_FILE" ]] || [[ ! -f "$PLAN_FILE" ]]; then
        echo "Error: Plan '$PLAN_NAME' not found" >&2
        echo "Available plans:" >&2
        while IFS= read -r f; do
            classify_plan_scope "$f" "" "$OWN_SCOPE" || continue
            basename "$f" .md
        done < <(ls -t "$PLANS_DIR"/*.md 2>/dev/null) >&2
        exit 1
    fi
else
    newest_adoptable_plan "" "$OWN_SCOPE"
    PLAN_FILE="$NEWEST_ADOPTABLE"

    if [[ -z "$PLAN_FILE" ]]; then
        if [[ "${NEWEST_WITHHELD:-0}" -gt 0 ]]; then
            echo "Error: $NEWEST_WITHHELD plan(s) in $PLANS_DIR are claimed by another or unverifiable scope; none adoptable here" >&2
        else
            echo "Error: No plan files found in $PLANS_DIR" >&2
        fi
        exit 1
    fi
fi

# Get metadata
BASENAME=$(basename "$PLAN_FILE")
mtime_human "$PLAN_FILE"
MODIFIED="$_MTIME_HUMAN"

# Calculate progress
CONTENT=$(cat "$PLAN_FILE")
TOTAL=$(echo "$CONTENT" | grep -c '^[[:space:]]*- \[.\]' || echo "0")
DONE=$(echo "$CONTENT" | grep -c '^[[:space:]]*- \[x\]' || echo "0")

if [[ $TOTAL -gt 0 ]]; then
    PERCENT=$((DONE * 100 / TOTAL))
    PROGRESS="${DONE}/${TOTAL} (${PERCENT}%)"
else
    PROGRESS="no trackable tasks"
fi

CURRENT=$(echo "$CONTENT" | grep -m1 '^[[:space:]]*- \[ \]' | sed 's/^[[:space:]]*- \[ \] //')
CURRENT="${CURRENT:-None}"

# Output with header
echo "## Plan: ${BASENAME}"
echo ""
echo "**File:** \`${PLAN_FILE}\`"
echo "**Modified:** ${MODIFIED}"
echo "**Progress:** ${PROGRESS}"
echo "**Current task:** ${CURRENT}"
echo ""
echo "---"
echo ""
echo "**IMPORTANT:** After completing tasks, UPDATE this plan file to track progress."
echo ""
echo "---"
echo ""
cat "$PLAN_FILE"
