#!/bin/bash
#
# load-plan.sh - Load and output a plan file
#
# Usage: ./load-plan.sh [plan-name]
#        If no name given, loads most recent plan
#

PLANS_DIR="${HOME}/.claude/plans"
PLAN_NAME="$1"

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
        find "$PLANS_DIR" -maxdepth 1 -name '*.md' -exec basename {} .md \; >&2
        exit 1
    fi
else
    PLAN_FILE=$(ls -t "$PLANS_DIR"/*.md 2>/dev/null | head -1)
    
    if [[ -z "$PLAN_FILE" ]]; then
        echo "Error: No plan files found in $PLANS_DIR" >&2
        exit 1
    fi
fi

# Get metadata
BASENAME=$(basename "$PLAN_FILE")
if stat -c %y "$PLAN_FILE" &>/dev/null; then
    MODIFIED=$(stat -c %y "$PLAN_FILE" | cut -d'.' -f1)
else
    MODIFIED=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$PLAN_FILE" 2>/dev/null || echo "unknown")
fi

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
