#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

VALID_BODY="Test comment

Assisted-by: Claude:claude-sonnet-4-5-20250929"

test_with_json() {
    local desc="$1"
    local json="$2"
    local should_pass="$3"

    echo -n "$desc... "
    printf '%s' "$json" | ./enforce-attribution.sh >/dev/null 2>&1
    exit_code=$?

    if [[ "$should_pass" == "true" ]]; then
        if [[ $exit_code -eq 0 ]]; then
            echo "PASS"
            ((PASS++))
        else
            echo "FAIL (expected pass, got exit $exit_code)"
            ((FAIL++))
        fi
    else
        if [[ $exit_code -ne 0 ]]; then
            echo "PASS"
            ((PASS++))
        else
            echo "FAIL (expected fail, got exit 0)"
            ((FAIL++))
        fi
    fi
}

echo "Testing enforce-attribution.sh"
echo

echo "=== Bug Fix Tests ==="

test_with_json "Empty stdin" '{}' true

test_with_json "Body with trailing flag (bug 1 fix)" \
    "$(jq -n --arg b "$VALID_BODY" '{tool_name: "Bash", tool_input: {command: ("gh pr comment 123 -b \"" + $b + "\" --edit-last")}}')" \
    true

echo -n "File with spaces (bug 2 fix)... "
echo "$VALID_BODY" > "/tmp/test with spaces.txt"
test_json=$(jq -n '{tool_name: "Bash", tool_input: {command: "gh pr comment 123 -F \"/tmp/test with spaces.txt\""}}')
printf '%s' "$test_json" | ./enforce-attribution.sh >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
    echo "PASS"
    ((PASS++))
else
    echo "FAIL"
    ((FAIL++))
fi
rm -f "/tmp/test with spaces.txt"

echo
echo "=== Functional Tests ==="

test_with_json "Valid attribution" \
    "$(jq -n --arg b "$VALID_BODY" '{tool_name: "Bash", tool_input: {command: ("gh pr comment 123 -b \"" + $b + "\"")}}')" \
    true

test_with_json "Missing attribution" \
    '{"tool_name": "Bash", "tool_input": {"command": "gh pr comment 123 -b \"Missing attribution\""}}' \
    false

FORBIDDEN_BODY="Test

Assisted-by: Claude:claude-sonnet-4-5-20250929

on behalf of Mike"

test_with_json "Forbidden pattern" \
    "$(jq -n --arg b "$FORBIDDEN_BODY" '{tool_name: "Bash", tool_input: {command: ("gh pr comment 123 -b \"" + $b + "\"")}}')" \
    false

test_with_json "Non-gh command" \
    '{"tool_name": "Bash", "tool_input": {"command": "git status"}}' \
    true

test_with_json "gh non-pr command" \
    '{"tool_name": "Bash", "tool_input": {"command": "gh repo view"}}' \
    true

test_with_json "--body= equals form" \
    "$(jq -n --arg b "$VALID_BODY" '{tool_name: "Bash", tool_input: {command: ("gh pr comment 123 --body=\"" + $b + "\"")}}')" \
    true

echo -n "--body-file= equals form... "
echo "$VALID_BODY" > "/tmp/test-body.txt"
test_json=$(jq -n '{tool_name: "Bash", tool_input: {command: "gh pr comment 123 --body-file=/tmp/test-body.txt"}}')
printf '%s' "$test_json" | ./enforce-attribution.sh >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
    echo "PASS"
    ((PASS++))
else
    echo "FAIL"
    ((FAIL++))
fi
rm -f "/tmp/test-body.txt"

echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

[[ $FAIL -eq 0 ]] && exit 0
exit 1
