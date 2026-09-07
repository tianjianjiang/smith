#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

VALID_BODY="Test comment

Assisted-by: Claude:claude-sonnet-4-5-20250929"

echo "Testing enforce-attribution.sh"
echo

echo "=== Bug Fix Tests ==="

echo -n "Zero arguments (bug 3 fix)... "
if ./enforce-attribution.sh >/dev/null 2>&1; then
    echo "✓ PASS"
    ((PASS++))
else
    echo "✗ FAIL"
    ((FAIL++))
fi

echo -n "Body with trailing flag (bug 1 fix)... "
if ./enforce-attribution.sh gh pr comment 123 -b "$VALID_BODY" --edit-last >/dev/null 2>&1; then
    echo "✓ PASS"
    ((PASS++))
else
    echo "✗ FAIL"
    ((FAIL++))
fi

echo -n "File with spaces (bug 2 fix)... "
echo "$VALID_BODY" > "/tmp/test with spaces.txt"
if ./enforce-attribution.sh gh pr comment 123 -F "/tmp/test with spaces.txt" >/dev/null 2>&1; then
    echo "✓ PASS"
    ((PASS++))
else
    echo "✗ FAIL"
    ((FAIL++))
fi
rm -f "/tmp/test with spaces.txt"

echo
echo "=== Functional Tests ==="

echo -n "Valid attribution... "
if ./enforce-attribution.sh gh pr comment 123 -b "$VALID_BODY" >/dev/null 2>&1; then
    echo "✓ PASS"
    ((PASS++))
else
    echo "✗ FAIL"
    ((FAIL++))
fi

echo -n "Missing attribution... "
if ! ./enforce-attribution.sh gh pr comment 123 -b "Missing attribution" >/dev/null 2>&1; then
    echo "✓ PASS"
    ((PASS++))
else
    echo "✗ FAIL"
    ((FAIL++))
fi

echo -n "Forbidden pattern... "
if ! ./enforce-attribution.sh gh pr comment 123 -b "Test

Assisted-by: Claude on behalf of Mike" >/dev/null 2>&1; then
    echo "✓ PASS"
    ((PASS++))
else
    echo "✗ FAIL"
    ((FAIL++))
fi

echo -n "Non-gh command... "
if ./enforce-attribution.sh git status >/dev/null 2>&1; then
    echo "✓ PASS"
    ((PASS++))
else
    echo "✗ FAIL"
    ((FAIL++))
fi

echo -n "gh non-pr command... "
if ./enforce-attribution.sh gh repo view >/dev/null 2>&1; then
    echo "✓ PASS"
    ((PASS++))
else
    echo "✗ FAIL"
    ((FAIL++))
fi

echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

[[ $FAIL -eq 0 ]] && echo "All tests passed!" && exit 0
echo "Some tests failed" && exit 1
