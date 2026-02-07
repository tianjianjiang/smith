#!/bin/bash
#
# list-plans.sh - List available plan files with progress
#

PLANS_DIR="${HOME}/.claude/plans"

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
ls -t "$PLANS_DIR"/*.md 2>/dev/null | while read -r file; do
    name=$(basename "$file" .md)
    
    # Get modification time (macOS first, then Linux fallback)
    if stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$file" &>/dev/null; then
        modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$file")
    else
        modified=$(stat -c %y "$file" 2>/dev/null | cut -d'.' -f1)
        modified="${modified:-unknown}"
    fi
    
    # Calculate progress
    total=$(grep -c '^[[:space:]]*- \[.\]' "$file" 2>/dev/null || echo "0")
    done=$(grep -c '^[[:space:]]*- \[x\]' "$file" 2>/dev/null || echo "0")
    
    if [[ $total -gt 0 ]]; then
        percent=$((done * 100 / total))
        progress="${done}/${total} (${percent}%)"
    else
        progress="no tasks"
    fi
    
    # Get title (first # line)
    title=$(grep -m1 "^#" "$file" | sed 's/^#* *//')
    title="${title:-(untitled)}"
    
    printf "%-20s %s\n" "$name" "$title"
    printf "  Modified: %s | Progress: %s\n" "$modified" "$progress"
    echo ""
done

count=$(ls -1 "$PLANS_DIR"/*.md 2>/dev/null | wc -l)
echo "----------------"
echo "Total: $count plan(s)"
