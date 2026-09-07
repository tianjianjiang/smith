#!/bin/bash
#
# list-plans.sh - List available plan files with progress
#

source "$(dirname "$0")/../ctx-claude/scripts/lib-plan.sh"
OWN_SCOPE=$(scope_key "${PWD:-}")

if [[ ! -d "$PLANS_DIR" ]]; then
    echo "No plans directory found at $PLANS_DIR"
    echo "Create one with: mkdir -p $PLANS_DIR"
    exit 1
fi

echo "Available Plans"
echo "=================="
echo ""

# Check if any plans exist
if [[ -z "$(ls -A "$PLANS_DIR"/*.md 2>/dev/null)" ]]; then
    echo "No plan files found."
    echo ""
    echo "Create a plan using:"
    echo "  1. Plan mode in Claude Code (Shift+Tab)"
    echo "  2. Manually: echo '# My Plan' > $PLANS_DIR/my-plan.md"
    exit 0
fi

# List plans with details
VISIBLE=0
WITHHELD=0
while IFS= read -r file; do
    if ! classify_plan_scope "$file" "" "$OWN_SCOPE"; then
        WITHHELD=$((WITHHELD + 1))
        continue
    fi
    VISIBLE=$((VISIBLE + 1))
    name=$(basename "$file" .md)

    mtime_human "$file"
    modified="${_MTIME_HUMAN:0:16}"

  
    total=$(grep -c '^[[:space:]]*- \[.\]' "$file" 2>/dev/null || echo "0")
    done=$(grep -c '^[[:space:]]*- \[x\]' "$file" 2>/dev/null || echo "0")

    if [[ $total -gt 0 ]]; then
        percent=$((done * 100 / total))
        progress="${done}/${total} (${percent}%)"
    else
        progress="no tasks"
    fi

  
    title=$(grep -m1 "^#" "$file" | sed 's/^#* *//')
    title="${title:-(untitled)}"

    printf "%-20s %s\n" "$name" "$title"
    printf "  Modified: %s | Progress: %s\n" "$modified" "$progress"
    echo ""
done < <(ls -t "$PLANS_DIR"/*.md 2>/dev/null)

echo "----------------"
echo "Total: $VISIBLE plan(s)"
if [[ $WITHHELD -gt 0 ]]; then
    echo "Withheld: $WITHHELD plan(s) claimed by another or unverifiable scope"
fi
