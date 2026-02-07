#!/usr/bin/env bash
set -euo pipefail

if ((BASH_VERSINFO[0] < 4)); then
    echo "Requires bash 4+ (found ${BASH_VERSION})"
    exit 1
fi

if [[ $# -lt 1 ]]; then
    echo "Usage: verify-stack-scope.sh <branch-pattern>"
    echo "Example: verify-stack-scope.sh 'feat/PROJ-1234-*'"
    exit 1
fi

pattern="$1"

if ! git fetch --prune origin >/dev/null 2>&1; then
    echo "WARNING: fetch failed, results may be stale"
fi

mapfile -t branches < <(
    git branch -r --list "origin/${pattern}" \
        | sed 's|^ *origin/||' \
        | grep -v '\->'
)

if [[ ${#branches[@]} -eq 0 ]]; then
    echo "No remote branches matching: ${pattern}"
    exit 0
fi

# Check gh availability once upfront
has_gh=false
if command -v gh >/dev/null 2>&1 \
    && gh auth status >/dev/null 2>&1; then
    has_gh=true
fi

# Batch-fetch all PRs once instead of per-branch
all_prs_json="[]"
if [[ "${has_gh}" == true ]]; then
    all_prs_json=$(
        gh pr list \
            --state all \
            --limit 1000 \
            --json headRefName,number,state,title \
            2>/dev/null || echo "[]"
    )
fi

echo "Stack scope: ${#branches[@]} branches" \
    "matching '${pattern}'"
echo "---"

for branch in "${branches[@]}"; do
    range="origin/main..origin/${branch}"
    ahead=$(
        git rev-list --count "${range}" \
            2>/dev/null || echo "?"
    )

    if [[ "${has_gh}" == true ]]; then
        pr_info=$(
            echo "${all_prs_json}" \
                | jq -r --arg h "${branch}" \
                    '[.[]
                      | select(.headRefName == $h)
                      | "#\(.number) [\(.state)]"]
                     | join(", ")' \
                2>/dev/null || echo ""
        )
        if [[ -z "${pr_info}" ]]; then
            pr_info="no PR"
        fi
    else
        pr_info="gh unavailable"
    fi
    printf "%-50s %4s commits  %s\n" \
        "${branch}" "${ahead}" "${pr_info}"
done

echo "---"
echo "Total: ${#branches[@]} branches"
