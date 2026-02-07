#!/bin/bash
#
# plan-status.sh - Show detailed progress of a plan
#
# Usage: ./plan-status.sh [plan-name]
#        If no name given, shows most recent plan
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
else
    PLAN_FILE=$(ls -t "$PLANS_DIR"/*.md 2>/dev/null | head -1)
fi

if [[ -z "$PLAN_FILE" ]] || [[ ! -f "$PLAN_FILE" ]]; then
    echo "Error: Plan not found" >&2
    echo "Available plans:" >&2
    find "$PLANS_DIR" -maxdepth 1 -name '*.md' -exec basename {} .md \; >&2
    exit 1
fi

BASENAME=$(basename "$PLAN_FILE")
CONTENT=$(cat "$PLAN_FILE")

# Calculate stats
TOTAL=$(echo "$CONTENT" | grep -c '^[[:space:]]*- \[.\]' 2>/dev/null || true)
TOTAL=${TOTAL:-0}
DONE=$(echo "$CONTENT" | grep -c '^[[:space:]]*- \[x\]' 2>/dev/null || true)
DONE=${DONE:-0}
PENDING=$((TOTAL - DONE))

if [[ $TOTAL -gt 0 ]]; then
    PERCENT=$((DONE * 100 / TOTAL))
else
    PERCENT=0
fi

# Get modification time
if stat -c %y "$PLAN_FILE" &>/dev/null; then
    MODIFIED=$(stat -c %y "$PLAN_FILE" | cut -d'.' -f1)
else
    MODIFIED=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$PLAN_FILE" 2>/dev/null || echo "unknown")
fi

echo "╔════════════════════════════════════════════════════════════╗"
echo "║                      PLAN STATUS                            ║"
echo "╠════════════════════════════════════════════════════════════╣"
printf "║ File: %-53s ║\n" "$BASENAME"
printf "║ Path: %-53s ║\n" "$PLAN_FILE"
printf "║ Modified: %-49s ║\n" "$MODIFIED"
echo "╠════════════════════════════════════════════════════════════╣"
printf "║ Progress: %d/%d tasks (%d%%)%-30s ║\n" "$DONE" "$TOTAL" "$PERCENT" ""

# Progress bar
if [[ $TOTAL -gt 0 ]]; then
    BAR_WIDTH=40
    FILLED=$((PERCENT * BAR_WIDTH / 100))
    EMPTY=$((BAR_WIDTH - FILLED))
    BAR=$(printf '%*s' "$FILLED" '' | tr ' ' '█')
    BAR+=$(printf '%*s' "$EMPTY" '' | tr ' ' '░')
    printf "║ [%s] %-15s ║\n" "$BAR" ""
fi

echo "╠════════════════════════════════════════════════════════════╣"
echo "║ COMPLETED TASKS:                                           ║"

# List completed tasks
echo "$CONTENT" | grep '^[[:space:]]*- \[x\]' | head -5 | while read -r task; do
    task_text=$(echo "$task" | sed 's/^[[:space:]]*- \[x\] //' | cut -c1-55)
    printf "║   [x] %-52s ║\n" "$task_text"
done

DONE_COUNT=$(echo "$CONTENT" | grep -c '^[[:space:]]*- \[x\]' 2>/dev/null || true)
DONE_COUNT=${DONE_COUNT:-0}
if [[ $DONE_COUNT -gt 5 ]]; then
    printf "║   ... and %d more%-43s ║\n" "$((DONE_COUNT - 5))" ""
fi

echo "╠════════════════════════════════════════════════════════════╣"
echo "║ PENDING TASKS:                                             ║"

# List pending tasks
echo "$CONTENT" | grep '^[[:space:]]*- \[ \]' | head -5 | while read -r task; do
    task_text=$(echo "$task" | sed 's/^[[:space:]]*- \[ \] //' | cut -c1-55)
    printf "║   [ ] %-52s ║\n" "$task_text"
done

PENDING_COUNT=$(echo "$CONTENT" | grep -c '^[[:space:]]*- \[ \]' 2>/dev/null || true)
PENDING_COUNT=${PENDING_COUNT:-0}
if [[ $PENDING_COUNT -gt 5 ]]; then
    printf "║   ... and %d more%-43s ║\n" "$((PENDING_COUNT - 5))" ""
fi

echo "╚════════════════════════════════════════════════════════════╝"

# Current task highlight
CURRENT=$(echo "$CONTENT" | grep -m1 '^[[:space:]]*- \[ \]' | sed 's/^[[:space:]]*- \[ \] //')
if [[ -n "$CURRENT" ]]; then
    echo ""
    echo "▶ CURRENT TASK: $CURRENT"
fi

# Check for completion
if [[ $PENDING -eq 0 ]] && [[ $TOTAL -gt 0 ]]; then
    echo ""
    echo "PLAN COMPLETE: All tasks finished successfully."
fi
