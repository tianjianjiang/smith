#!/bin/bash
#
# test-inject-plan.sh - Tests for inject-plan.sh, enforce-clear.sh, and on-session-clear.sh
#
# Runs 31 scenarios covering:
#   1. Flag reload -> directive with "POST-CLEAR RESUME"
#   2. Trigger words -> no directive, plan content present
#   3. on-session-clear with state file -> POST-CLEAR RESUME directive
#   4. Context threshold -> CONTEXT WARNING (percentage-based, 50%)
#   5. No plan file -> silent exit or message, no crash
#   6. Generic prompt (no trigger, no flag, low context) -> silent exit
#   7. Stop hook: context >= 60% + plan pending -> block JSON
#   8. Stop hook: stop_hook_active=true -> exit 0 (no block)
#   9. CWD isolation: on-plan-exit creates flag keyed to CWD (worktree A)
#  10. CWD isolation: worktree B ignores worktree A's flag
#  11. CWD isolation: worktree A consumes its own flag after /clear
#  12. Full lifecycle: parallel worktrees create+consume flags independently
#  13. Bug repro: after /clear, each worktree loads its own plan (not the other's)
#  14. State file: created after plan injection
#  15. State file: same session + moderate transcript -> no re-injection (debounce)
#  16. State file: new CWD (no state, no flag) -> no auto-load
#  17. on-session-clear without state file -> Serena memory restore directive
#  18. on-session-clear with unreadable plan -> Serena fallback directive
#  19. State-based reload uses plan from CWD state file, not most-recent globally
#  20. Same CWD + different session_id -> flag found (validates /clear fix)
#  21. Different CWDs -> independent flags (validates worktree isolation)
#  22. Ralph active + context < 50% -> no interference, state unchanged
#  23. Ralph active + context 50% -> advisory output, resume file created
#  24. Ralph active + context 60% -> critical output, resume file, max_iterations = iteration
#  25. enforce-clear + Ralph state file active -> exit 0 (no block)
#  26. enforce-clear + Ralph resume file only -> exit 0 (no block)
#  27. on-session-clear + resume file -> plan + Ralph restart in output
#  28. on-session-clear + resume, no plan -> Ralph restart only in output
#  29. on-session-clear + ralph state (inactive, no resume) + plan -> RALPH LOOP PHASE RESUME
#  30. on-session-clear + ralph state (no resume) + no plan -> RALPH LOOP PHASE RESUME
#  31. inject-plan flag reload + ralph state (inactive, no resume) -> RALPH LOOP PHASE RESUME
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INJECT_SCRIPT="$SCRIPT_DIR/scripts/inject-plan.sh"
ENFORCE_SCRIPT="$SCRIPT_DIR/scripts/enforce-clear.sh"
PLAN_EXIT_SCRIPT="$SCRIPT_DIR/scripts/on-plan-exit.sh"
SESSION_CLEAR_SCRIPT="$SCRIPT_DIR/scripts/on-session-clear.sh"

# Use temp directory for isolation
TEST_DIR=$(mktemp -d)
PLANS_DIR="$TEST_DIR/plans"
mkdir -p "$PLANS_DIR"

PASS=0
FAIL=0
TOTAL=31

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Compute CWD key (same logic as scripts -- state and flag files both keyed by CWD)
compute_cwd_key() {
    local cwd="$1"
    local hash
    hash=$(printf '%s' "$cwd" | md5 -q 2>/dev/null) || \
    hash=$(printf '%s' "$cwd" | md5sum 2>/dev/null | cut -d' ' -f1) || \
    hash="00000000"
    printf '%s' "${hash:0:8}"
}

# Create patched copies of scripts that use our test PLANS_DIR
# Only patches PLANS_DIR; flag/state files are computed dynamically from CWD/session key
# Also patches lib-common.sh (shared library sourced by all hook scripts)
create_patched_scripts() {
    # Patch lib-common.sh first (scripts source it from their own directory)
    LIB_COMMON="$SCRIPT_DIR/scripts/lib-common.sh"
    sed \
        -e 's|PLANS_DIR="\${HOME}/.claude/plans"|PLANS_DIR="'"$PLANS_DIR"'"|' \
        "$LIB_COMMON" > "$TEST_DIR/lib-common.sh"
    chmod +x "$TEST_DIR/lib-common.sh"

    # Patch hook scripts (they no longer set PLANS_DIR directly; it comes from lib-common.sh)
    cp "$INJECT_SCRIPT" "$TEST_DIR/inject-plan.sh"
    chmod +x "$TEST_DIR/inject-plan.sh"

    cp "$ENFORCE_SCRIPT" "$TEST_DIR/enforce-clear.sh"
    chmod +x "$TEST_DIR/enforce-clear.sh"

    cp "$PLAN_EXIT_SCRIPT" "$TEST_DIR/on-plan-exit.sh"
    chmod +x "$TEST_DIR/on-plan-exit.sh"

    cp "$SESSION_CLEAR_SCRIPT" "$TEST_DIR/on-session-clear.sh"
    chmod +x "$TEST_DIR/on-session-clear.sh"
}

# Create a test plan with pending tasks
create_test_plan() {
    cat > "$PLANS_DIR/test-plan.md" <<'PLAN'
# Test Plan

## Tasks

- [x] Task 1: Done
- [ ] Task 2: Pending
- [ ] Task 3: Pending
PLAN
}

# Create transcript JSONL that returns approximately the given percentage.
# Uses CONTEXT_WINDOW_TOKENS=200000 (the default).
# Args: $1 = percentage (0-100), $2 = optional name suffix
# Returns: path to the transcript file
create_transcript_pct() {
    local pct=$1
    local name="${2:-default}"
    local path="$TEST_DIR/transcript-${name}.jsonl"
    local tokens=$(( pct * 200000 / 100 ))
    # Write a valid JSONL line that get_context_percentage() can parse
    printf '{"type":"assistant","message":{"usage":{"input_tokens":%d,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$tokens" > "$path"
    echo "$path"
}

# Legacy helper: create transcript of given size in KB (for tests that only need a file to exist)
# NOTE: These transcripts have NO valid JSONL, so get_context_percentage returns 0%.
# Use create_transcript_pct for percentage-based tests.
create_transcript() {
    local size_kb=$1
    local name="${2:-default}"
    local path="$TEST_DIR/transcript-${name}.jsonl"
    dd if=/dev/zero bs=1024 count="$size_kb" of="$path" 2>/dev/null
    echo "$path"
}

# Create a Ralph state file (.claude/ralph-loop.local.md) in the given CWD
# Args: $1=CWD, $2=active(true/false), $3=iteration, $4=max_iterations,
#       $5=completion_promise, $6=prompt text
create_ralph_state() {
    local cwd="$1"
    local active="${2:-true}"
    local iteration="${3:-1}"
    local max_iter="${4:-20}"
    local promise="${5:-TASK DONE}"
    local prompt="${6:-Execute the plan and fix all bugs.}"
    mkdir -p "${cwd}/.claude"
    cat > "${cwd}/.claude/ralph-loop.local.md" <<RALPH
---
active: ${active}
iteration: ${iteration}
max_iterations: ${max_iter}
completion_promise: "${promise}"
started_at: "2026-02-10T14:30:45Z"
---

${prompt}
RALPH
}

assert_contains() {
    local _label="$1"  # used at call sites for readability
    local haystack="$2"
    local needle="$3"
    if echo "$haystack" | grep -q "$needle"; then
        return 0
    else
        echo "  ASSERT FAILED: expected output to contain '$needle'"
        echo "  Got: $(echo "$haystack" | head -5)"
        return 1
    fi
}

assert_not_contains() {
    local _label="$1"  # used at call sites for readability
    local haystack="$2"
    local needle="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo "  ASSERT FAILED: expected output NOT to contain '$needle'"
        return 1
    else
        return 0
    fi
}

assert_file_exists() {
    local _label="$1"
    local path="$2"
    if [[ -f "$path" ]]; then
        return 0
    else
        echo "  ASSERT FAILED: expected file to exist: $path"
        return 1
    fi
}

assert_file_not_exists() {
    local _label="$1"
    local path="$2"
    if [[ ! -f "$path" ]]; then
        return 0
    else
        echo "  ASSERT FAILED: expected file NOT to exist: $path"
        return 1
    fi
}

# Initialize patched scripts
create_patched_scripts

# Compute CWD key for tests 1-8 (all share $PWD as their CWD)
CWD_DEFAULT_KEY=$(compute_cwd_key "$PWD")

# ============================================================================
# CORE TESTS (1-21): Updated for percentage-based context detection
# ============================================================================

# --- Test 1: Flag reload ---
echo "Test 1: Flag reload -> directive with 'POST-CLEAR RESUME'"
create_test_plan
printf '%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_test" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" > "$PLANS_DIR/.pending-reload-${CWD_DEFAULT_KEY}"
TRANSCRIPT=$(create_transcript_pct 5)
OUTPUT=$(echo '{"prompt":"hi","session_id":"sess_new","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_contains "1" "$OUTPUT" "ACTION REQUIRED" && \
   assert_contains "1" "$OUTPUT" "POST-CLEAR RESUME" && \
   assert_contains "1" "$OUTPUT" "Task 2"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 2: Trigger words ---
echo "Test 2: Trigger words -> no directive, plan content present"
create_test_plan
TRANSCRIPT=$(create_transcript_pct 10)
# Need state file so it doesn't look like a fresh session (state is CWD-keyed)
printf '%s\n%s\n%s\n%s\n%s\n' "sess_test" "$TRANSCRIPT" "51200" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_DEFAULT_KEY}"
OUTPUT=$(echo '{"prompt":"execute the plan","session_id":"sess_test","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_not_contains "2" "$OUTPUT" "ACTION REQUIRED" && \
   assert_contains "2" "$OUTPUT" "Task 2"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 3: on-session-clear with state file -> POST-CLEAR RESUME ---
echo "Test 3: on-session-clear with state file -> POST-CLEAR RESUME directive"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-*
CWD_3="$TEST_DIR/worktree-3"
mkdir -p "$CWD_3"
CWD_3_KEY=$(compute_cwd_key "$CWD_3")
# Create state file pointing to test plan
printf '%s\n%s\n%s\n%s\n%s\n' "sess_3" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_3_KEY}"
OUTPUT=$(echo '{"cwd":"'"$CWD_3"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "3" "$OUTPUT" "ACTION REQUIRED" && \
   assert_contains "3" "$OUTPUT" "POST-CLEAR RESUME" && \
   assert_contains "3" "$OUTPUT" "Task 2"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 4: Context threshold (percentage-based) ---
echo "Test 4: Context threshold -> CONTEXT WARNING at 50%"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-*
# Create transcript at 55% context (above 50% warning, below 60% critical)
TRANSCRIPT=$(create_transcript_pct 55 "t4")
# Update state so we're in an active session (CWD-keyed state)
printf '%s\n%s\n%s\n%s\n%s\n' "sess_test" "$TRANSCRIPT" "1000" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_DEFAULT_KEY}"
OUTPUT=$(echo '{"prompt":"do something","session_id":"sess_test","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_contains "4" "$OUTPUT" "CONTEXT WARNING" && \
   assert_not_contains "4" "$OUTPUT" "ACTION REQUIRED"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR"/.pending-reload-*

# --- Test 5: No plan file ---
echo "Test 5: No plan file -> silent exit, no crash"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-*
TRANSCRIPT=$(create_transcript_pct 5)
OUTPUT=$(echo '{"prompt":"hi","session_id":"sess_test","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh" 2>&1)
EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (exit code: $EXIT_CODE)"
    FAIL=$((FAIL + 1))
fi

# --- Test 6: Generic prompt (no trigger, no flag, low context) -> silent ---
echo "Test 6: Generic prompt (no trigger, no flag, low context) -> silent exit"
create_test_plan
TRANSCRIPT=$(create_transcript_pct 20)
# Set state file so we are in an active session with matching parameters (CWD-keyed)
printf '%s\n%s\n%s\n%s\n%s\n' "sess_test" "$TRANSCRIPT" "20480" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_DEFAULT_KEY}"
OUTPUT=$(echo '{"prompt":"continue working","session_id":"sess_test","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if [[ -z "$OUTPUT" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (expected empty output, got: $(echo "$OUTPUT" | head -3))"
    FAIL=$((FAIL + 1))
fi

# --- Test 7: Stop hook first block (percentage-based) ---
echo "Test 7: Stop hook: context >= 60% + plan pending -> block JSON"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*
# Create transcript at 65% context (above 60% critical threshold)
TRANSCRIPT=$(create_transcript_pct 65 "t7")
# enforce-clear needs a CWD-keyed state file to find the active plan
printf '%s\n%s\n%s\n%s\n%s\n' "sess_test" "$TRANSCRIPT" "1000" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_DEFAULT_KEY}"
OUTPUT=$(echo '{"transcript_path":"'"$TRANSCRIPT"'","session_id":"sess_test","cwd":"'"$PWD"'","stop_hook_active":false}' | bash "$TEST_DIR/enforce-clear.sh")
if assert_contains "7" "$OUTPUT" '"decision"' && \
   assert_contains "7" "$OUTPUT" "block" && \
   [[ -f "$PLANS_DIR/.pending-reload-${CWD_DEFAULT_KEY}" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    if [[ ! -f "$PLANS_DIR/.pending-reload-${CWD_DEFAULT_KEY}" ]]; then
        echo "  CWD-specific flag file was NOT created (expected .pending-reload-${CWD_DEFAULT_KEY})"
    fi
    FAIL=$((FAIL + 1))
fi

# --- Test 8: Stop hook with stop_hook_active=true ---
echo "Test 8: Stop hook: stop_hook_active=true -> exit 0, no block"
TRANSCRIPT=$(create_transcript_pct 65 "t8")
OUTPUT=$(echo '{"transcript_path":"'"$TRANSCRIPT"'","session_id":"sess_test","cwd":"'"$PWD"'","stop_hook_active":true}' | bash "$TEST_DIR/enforce-clear.sh")
EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]] && [[ -z "$OUTPUT" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (exit: $EXIT_CODE, output: $OUTPUT)"
    FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR"/.pending-reload-*

# --- Tests 9-13: CWD-based isolation with simulated worktrees ---
# Worktree A uses "$TEST_DIR/worktree-a", Worktree B uses "$TEST_DIR/worktree-b"
WORKTREE_A="$TEST_DIR/worktree-a"
WORKTREE_B="$TEST_DIR/worktree-b"
mkdir -p "$WORKTREE_A" "$WORKTREE_B"
CWD_A_KEY=$(compute_cwd_key "$WORKTREE_A")
CWD_B_KEY=$(compute_cwd_key "$WORKTREE_B")

# --- Test 9: on-plan-exit creates CWD-specific flag (worktree A) ---
echo "Test 9: on-plan-exit.sh creates flag keyed to worktree A's CWD"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-*
# Run on-plan-exit.sh with worktree A's CWD
OUTPUT=$(echo '{"session_id":"sess_a","cwd":"'"$WORKTREE_A"'"}' | bash "$TEST_DIR/on-plan-exit.sh")
# Flag should exist for worktree A's CWD hash, NOT worktree B's
if [[ -f "$PLANS_DIR/.pending-reload-${CWD_A_KEY}" ]] && \
   [[ ! -f "$PLANS_DIR/.pending-reload-${CWD_B_KEY}" ]] && \
   assert_contains "9" "$OUTPUT" "PLAN EXIT"; then
    # Verify the flag content has the correct plan
    FLAG_PLAN=$(sed -n '1p' "$PLANS_DIR/.pending-reload-${CWD_A_KEY}")
    if [[ "$FLAG_PLAN" == *"test-plan.md" ]]; then
        echo "  PASS"
        PASS=$((PASS + 1))
    else
        echo "  FAIL (flag plan='$FLAG_PLAN', expected test-plan.md)"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL"
    [[ ! -f "$PLANS_DIR/.pending-reload-${CWD_A_KEY}" ]] && echo "  Flag for worktree A was NOT created"
    [[ -f "$PLANS_DIR/.pending-reload-${CWD_B_KEY}" ]] && echo "  Unexpected flag for worktree B was created"
    FAIL=$((FAIL + 1))
fi

# --- Test 10: Worktree B does NOT see worktree A's flag ---
echo "Test 10: inject-plan.sh from worktree B ignores worktree A's flag"
# Flag from test 9 should still be there (for CWD_A_KEY)
TRANSCRIPT=$(create_transcript_pct 2 "t10")
# Session B has no flag and no state -> should produce no output
OUTPUT=$(echo '{"prompt":"hi","session_id":"sess_b","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$WORKTREE_B"'"}' | bash "$TEST_DIR/inject-plan.sh")
# Session B should produce empty output (no flag for its CWD, no state, no trigger)
# A's flag must remain untouched
if [[ -z "$OUTPUT" ]] && \
   [[ -f "$PLANS_DIR/.pending-reload-${CWD_A_KEY}" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    [[ -n "$OUTPUT" ]] && echo "  Worktree B got unexpected output: $(echo "$OUTPUT" | head -3)"
    [[ ! -f "$PLANS_DIR/.pending-reload-${CWD_A_KEY}" ]] && echo "  Worktree A's flag was consumed by worktree B"
    FAIL=$((FAIL + 1))
fi

# --- Test 11: Worktree A sees and consumes its own flag ---
echo "Test 11: inject-plan.sh from worktree A consumes its own flag after /clear"
TRANSCRIPT=$(create_transcript_pct 2 "t11")
# Run inject-plan.sh with worktree A's CWD (simulates post-/clear prompt)
OUTPUT=$(echo '{"prompt":"hi","session_id":"sess_a","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$WORKTREE_A"'"}' | bash "$TEST_DIR/inject-plan.sh")
# Should get flag-based "POST-CLEAR RESUME" load, flag should be consumed
if assert_contains "11" "$OUTPUT" "POST-CLEAR RESUME" && \
   assert_contains "11" "$OUTPUT" "ACTION REQUIRED" && \
   [[ ! -f "$PLANS_DIR/.pending-reload-${CWD_A_KEY}" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    [[ -f "$PLANS_DIR/.pending-reload-${CWD_A_KEY}" ]] && echo "  Flag was NOT consumed"
    FAIL=$((FAIL + 1))
fi

# --- Test 12: Full lifecycle - both worktrees create and consume flags independently ---
echo "Test 12: Full lifecycle - parallel worktrees create+consume flags independently"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*

# Use percentage-based transcripts: 65% for context threshold, 2% for post-clear
TRANSCRIPT_HIGH=$(create_transcript_pct 65 "t12-high")
TRANSCRIPT_LOW=$(create_transcript_pct 2 "t12-low")

# Set up state files so context threshold detection works
printf '%s\n%s\n%s\n%s\n%s\n' "sess_a" "$TRANSCRIPT_HIGH" "1000" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_A_KEY}"
printf '%s\n%s\n%s\n%s\n%s\n' "sess_b" "$TRANSCRIPT_HIGH" "1000" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_B_KEY}"

# Step 1: Worktree A hits context threshold -> flag created for A's CWD
OUTPUT_A1=$(echo '{"prompt":"do something","session_id":"sess_a","transcript_path":"'"$TRANSCRIPT_HIGH"'","cwd":"'"$WORKTREE_A"'"}' | bash "$TEST_DIR/inject-plan.sh")
FLAG_A_EXISTS_1=$([[ -f "$PLANS_DIR/.pending-reload-${CWD_A_KEY}" ]] && echo "yes" || echo "no")

# Step 2: Worktree B hits context threshold -> flag created for B's CWD
OUTPUT_B1=$(echo '{"prompt":"do something","session_id":"sess_b","transcript_path":"'"$TRANSCRIPT_HIGH"'","cwd":"'"$WORKTREE_B"'"}' | bash "$TEST_DIR/inject-plan.sh")
FLAG_B_EXISTS_1=$([[ -f "$PLANS_DIR/.pending-reload-${CWD_B_KEY}" ]] && echo "yes" || echo "no")

# Step 3: Worktree A does /clear and reloads -> A's flag consumed, B's untouched
OUTPUT_A2=$(echo '{"prompt":"hi","session_id":"sess_a","transcript_path":"'"$TRANSCRIPT_LOW"'","cwd":"'"$WORKTREE_A"'"}' | bash "$TEST_DIR/inject-plan.sh")
FLAG_A_EXISTS_2=$([[ -f "$PLANS_DIR/.pending-reload-${CWD_A_KEY}" ]] && echo "no" || echo "yes")
FLAG_B_EXISTS_2=$([[ -f "$PLANS_DIR/.pending-reload-${CWD_B_KEY}" ]] && echo "yes" || echo "no")

# Step 4: Worktree B does /clear and reloads -> B's flag consumed
OUTPUT_B2=$(echo '{"prompt":"hi","session_id":"sess_b","transcript_path":"'"$TRANSCRIPT_LOW"'","cwd":"'"$WORKTREE_B"'"}' | bash "$TEST_DIR/inject-plan.sh")
FLAG_B_EXISTS_3=$([[ -f "$PLANS_DIR/.pending-reload-${CWD_B_KEY}" ]] && echo "no" || echo "yes")

if [[ "$FLAG_A_EXISTS_1" == "yes" ]] && \
   [[ "$FLAG_B_EXISTS_1" == "yes" ]] && \
   [[ "$FLAG_A_EXISTS_2" == "yes" ]] && \
   [[ "$FLAG_B_EXISTS_2" == "yes" ]] && \
   [[ "$FLAG_B_EXISTS_3" == "yes" ]] && \
   assert_contains "12-a1" "$OUTPUT_A1" "CONTEXT WARNING" && \
   assert_contains "12-b1" "$OUTPUT_B1" "CONTEXT WARNING" && \
   assert_contains "12-a2" "$OUTPUT_A2" "POST-CLEAR RESUME" && \
   assert_contains "12-b2" "$OUTPUT_B2" "POST-CLEAR RESUME"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    echo "  Flag A after step 1: $FLAG_A_EXISTS_1 (expected yes)"
    echo "  Flag B after step 2: $FLAG_B_EXISTS_1 (expected yes)"
    echo "  Flag A consumed after step 3: $FLAG_A_EXISTS_2 (expected yes=consumed)"
    echo "  Flag B untouched after step 3: $FLAG_B_EXISTS_2 (expected yes)"
    echo "  Flag B consumed after step 4: $FLAG_B_EXISTS_3 (expected yes=consumed)"
    FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR"/.pending-reload-*

# --- Test 13: Bug reproduction - after /clear, each worktree gets its OWN plan, not the other's ---
echo "Test 13: Bug repro - after /clear, each worktree loads its own plan (not the other's)"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*
TRANSCRIPT_SMALL=$(create_transcript_pct 2 "t13-small")

# Create plan-a (worktree A's plan)
cat > "$PLANS_DIR/plan-a.md" <<'PLAN'
# Plan A - Worktree A's work

## Tasks
- [x] Task A1: Done
- [ ] Task A2: Worktree A pending work
PLAN

# Create state file for session A pointing to plan-a
printf '%s\n%s\n%s\n%s\n%s\n' "sess_a" "$TRANSCRIPT_SMALL" "5120" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/plan-a.md" > "$PLANS_DIR/.plan-state-${CWD_A_KEY}"

# Worktree A triggers ExitPlanMode -> on-plan-exit flags plan-a (from state)
_OUTPUT_EXIT_A=$(echo '{"session_id":"sess_a","cwd":"'"$WORKTREE_A"'"}' | bash "$TEST_DIR/on-plan-exit.sh")  # side effect: creates flag

sleep 1  # ensure different mtime

# Now create plan-b (worktree B's plan) making it newer than plan-a
cat > "$PLANS_DIR/plan-b.md" <<'PLAN'
# Plan B - Worktree B's work

## Tasks
- [x] Task B1: Done
- [ ] Task B2: Worktree B pending work
PLAN

# Create state file for session B pointing to plan-b
printf '%s\n%s\n%s\n%s\n%s\n' "sess_b" "$TRANSCRIPT_SMALL" "5120" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/plan-b.md" > "$PLANS_DIR/.plan-state-${CWD_B_KEY}"

# Worktree B triggers ExitPlanMode -> on-plan-exit flags plan-b (from state)
_OUTPUT_EXIT_B=$(echo '{"session_id":"sess_b","cwd":"'"$WORKTREE_B"'"}' | bash "$TEST_DIR/on-plan-exit.sh")  # side effect: creates flag

# Verify both flags exist and point to different plans
FLAG_A_PLAN=$(sed -n '1p' "$PLANS_DIR/.pending-reload-${CWD_A_KEY}" 2>/dev/null || echo "MISSING")
FLAG_B_PLAN=$(sed -n '1p' "$PLANS_DIR/.pending-reload-${CWD_B_KEY}" 2>/dev/null || echo "MISSING")

# Simulate /clear in worktree A -> must get plan-a
OUTPUT_RELOAD_A=$(echo '{"prompt":"hi","session_id":"sess_a","transcript_path":"'"$TRANSCRIPT_SMALL"'","cwd":"'"$WORKTREE_A"'"}' | bash "$TEST_DIR/inject-plan.sh")

# Simulate /clear in worktree B -> must get plan-b
OUTPUT_RELOAD_B=$(echo '{"prompt":"hi","session_id":"sess_b","transcript_path":"'"$TRANSCRIPT_SMALL"'","cwd":"'"$WORKTREE_B"'"}' | bash "$TEST_DIR/inject-plan.sh")

# Verify: worktree A loaded plan-a (not plan-b), worktree B loaded plan-b (not plan-a)
T13_PASS=true
if ! assert_contains "13" "$OUTPUT_RELOAD_A" "Task A2"; then
    echo "  Worktree A did NOT get plan-a content"
    T13_PASS=false
fi
if echo "$OUTPUT_RELOAD_A" | grep -q "Task B2"; then
    echo "  Worktree A got plan-b content (WRONG PLAN)"
    T13_PASS=false
fi
if ! assert_contains "13" "$OUTPUT_RELOAD_B" "Task B2"; then
    echo "  Worktree B did NOT get plan-b content"
    T13_PASS=false
fi
if echo "$OUTPUT_RELOAD_B" | grep -q "Task A2"; then
    echo "  Worktree B got plan-a content (WRONG PLAN)"
    T13_PASS=false
fi
if ! assert_contains "13" "$OUTPUT_RELOAD_A" "POST-CLEAR RESUME"; then
    echo "  Worktree A did not get flag-based reload"
    T13_PASS=false
fi
if ! assert_contains "13" "$OUTPUT_RELOAD_B" "POST-CLEAR RESUME"; then
    echo "  Worktree B did not get flag-based reload"
    T13_PASS=false
fi
# Also verify the flags stored the correct plan paths
if [[ "$FLAG_A_PLAN" != *"plan-a.md" ]]; then
    echo "  Flag A pointed to '$FLAG_A_PLAN' (expected plan-a.md)"
    T13_PASS=false
fi
if [[ "$FLAG_B_PLAN" != *"plan-b.md" ]]; then
    echo "  Flag B pointed to '$FLAG_B_PLAN' (expected plan-b.md)"
    T13_PASS=false
fi

if [[ "$T13_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR"/.pending-reload-*

# --- Tests 14-18: State-based detection and on-session-clear ---

# --- Test 14: State file created after injection ---
echo "Test 14: State file created after plan injection"
create_test_plan
rm -f "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*
TRANSCRIPT=$(create_transcript_pct 5 "t14")
CWD_14_KEY="$CWD_DEFAULT_KEY"
# No state file for sess_14 -> new session -> no auto-load
# Use trigger word to force load
OUTPUT=$(echo '{"prompt":"execute the plan","session_id":"sess_14","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if [[ -f "$PLANS_DIR/.plan-state-${CWD_14_KEY}" ]] && \
   assert_contains "14" "$OUTPUT" "Task 2"; then
    # Verify state file content
    STATE_SESSION=$(sed -n '1p' "$PLANS_DIR/.plan-state-${CWD_14_KEY}")
    STATE_PATH=$(sed -n '2p' "$PLANS_DIR/.plan-state-${CWD_14_KEY}")
    if [[ "$STATE_SESSION" == "sess_14" ]] && [[ "$STATE_PATH" == "$TRANSCRIPT" ]]; then
        echo "  PASS"
        PASS=$((PASS + 1))
    else
        echo "  FAIL (state content: session='$STATE_SESSION' path='$STATE_PATH')"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL"
    [[ ! -f "$PLANS_DIR/.plan-state-${CWD_14_KEY}" ]] && echo "  State file was NOT created"
    FAIL=$((FAIL + 1))
fi

# --- Test 15: Same session + moderate transcript -> no re-injection (debounce) ---
echo "Test 15: Same session + moderate transcript -> silent (debounced by state)"
TRANSCRIPT_LARGE=$(create_transcript_pct 20 "t15")
CWD_15_KEY="$CWD_DEFAULT_KEY"
# Create state to record the transcript
printf '%s\n%s\n%s\n%s\n%s\n' "sess_15" "$TRANSCRIPT_LARGE" "51200" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_15_KEY}"
OUTPUT=$(echo '{"prompt":"do something","session_id":"sess_15","transcript_path":"'"$TRANSCRIPT_LARGE"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if [[ -z "$OUTPUT" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (expected empty output, got: $(echo "$OUTPUT" | head -3))"
    FAIL=$((FAIL + 1))
fi

# --- Test 16: New CWD (no state, no flag) -> no auto-load ---
echo "Test 16: New CWD (no state, no flag) -> no auto-load"
# Fresh CWD with no state file, no flag -> should NOT auto-load
CWD_16_KEY=$(compute_cwd_key "$TEST_DIR/worktree-16")
mkdir -p "$TEST_DIR/worktree-16"
rm -f "$PLANS_DIR/.plan-state-${CWD_16_KEY}"
OUTPUT=$(echo '{"prompt":"hi","session_id":"sess_16","transcript_path":"'"$TRANSCRIPT_LARGE"'","cwd":"'"$TEST_DIR/worktree-16"'"}' | bash "$TEST_DIR/inject-plan.sh")
if [[ -z "$OUTPUT" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (expected empty output for new CWD without state, got: $(echo "$OUTPUT" | head -3))"
    FAIL=$((FAIL + 1))
fi

# --- Test 17: on-session-clear without state file -> Serena memory restore ---
echo "Test 17: on-session-clear without state file -> Serena memory restore directive"
rm -f "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*
create_test_plan
CWD_17="$TEST_DIR/worktree-17"
mkdir -p "$CWD_17"
# No state file for this CWD -> on-session-clear falls through to Serena-only path
OUTPUT=$(echo '{"cwd":"'"$CWD_17"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "17" "$OUTPUT" "ACTION REQUIRED" && \
   assert_contains "17" "$OUTPUT" "POST-CLEAR RESUME" && \
   assert_contains "17" "$OUTPUT" "list_memories"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 18: on-session-clear with unreadable plan -> Serena fallback ---
echo "Test 18: on-session-clear with unreadable plan -> Serena fallback directive"
CWD_18="$TEST_DIR/worktree-18"
mkdir -p "$CWD_18"
CWD_18_KEY=$(compute_cwd_key "$CWD_18")
# Create state pointing to a plan file that does not exist
printf '%s\n%s\n%s\n%s\n%s\n' "sess_18" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/nonexistent-plan.md" > "$PLANS_DIR/.plan-state-${CWD_18_KEY}"
OUTPUT=$(echo '{"cwd":"'"$CWD_18"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "18" "$OUTPUT" "ACTION REQUIRED" && \
   assert_contains "18" "$OUTPUT" "list_memories"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 19: State-based reload loads CWD's own plan, not most-recent globally ---
# Uses on-session-clear.sh which is the primary post-/clear injection point.
echo "Test 19: State-based reload uses plan from state file, not most-recent globally"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*

WORKTREE_A19="$TEST_DIR/worktree-a19"
WORKTREE_B19="$TEST_DIR/worktree-b19"
mkdir -p "$WORKTREE_A19" "$WORKTREE_B19"
CWD_A19_KEY=$(compute_cwd_key "$WORKTREE_A19")
CWD_B19_KEY=$(compute_cwd_key "$WORKTREE_B19")

# Create plan-a and plan-b
cat > "$PLANS_DIR/plan-a.md" <<'PLAN'
# Plan A
## Tasks
- [x] Task A1: Done
- [ ] Task A2: Session A work
PLAN

sleep 1

cat > "$PLANS_DIR/plan-b.md" <<'PLAN'
# Plan B
## Tasks
- [x] Task B1: Done
- [ ] Task B2: Session B work
PLAN

# plan-b is now newer. Create state files linking each CWD to its own plan.
printf '%s\n%s\n%s\n%s\n%s\n' "sess_a19" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/plan-a.md" > "$PLANS_DIR/.plan-state-${CWD_A19_KEY}"
printf '%s\n%s\n%s\n%s\n%s\n' "sess_b19" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/plan-b.md" > "$PLANS_DIR/.plan-state-${CWD_B19_KEY}"

# Simulate /clear in worktree A -> on-session-clear should load plan-a
OUTPUT_A=$(echo '{"cwd":"'"$WORKTREE_A19"'"}' | bash "$TEST_DIR/on-session-clear.sh")

# Simulate /clear in worktree B -> on-session-clear should load plan-b
OUTPUT_B=$(echo '{"cwd":"'"$WORKTREE_B19"'"}' | bash "$TEST_DIR/on-session-clear.sh")

T19_PASS=true
# Worktree A must get plan-a content
if ! echo "$OUTPUT_A" | grep -q "Task A2"; then
    echo "  Worktree A did NOT get plan-a content after /clear"
    T19_PASS=false
fi
# Worktree A must NOT get plan-b content
if echo "$OUTPUT_A" | grep -q "Task B2"; then
    echo "  Worktree A got plan-b content (WRONG PLAN - loaded most-recent instead of state-recorded)"
    T19_PASS=false
fi
# Worktree B must get plan-b content
if ! echo "$OUTPUT_B" | grep -q "Task B2"; then
    echo "  Worktree B did NOT get plan-b content"
    T19_PASS=false
fi
# Worktree B must NOT get plan-a content
if echo "$OUTPUT_B" | grep -q "Task A2"; then
    echo "  Worktree B got plan-a content (WRONG PLAN)"
    T19_PASS=false
fi

if [[ "$T19_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    echo "  State file A plan (line 5): $(sed -n '5p' "$PLANS_DIR/.plan-state-${CWD_A19_KEY}" 2>/dev/null || echo 'MISSING')"
    echo "  State file B plan (line 5): $(sed -n '5p' "$PLANS_DIR/.plan-state-${CWD_B19_KEY}" 2>/dev/null || echo 'MISSING')"
    FAIL=$((FAIL + 1))
fi

# --- Test 20: Same CWD + different session_id -> flag found (validates /clear fix) ---
echo "Test 20: Same CWD + different session_id -> flag found (validates /clear fix)"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*
TRANSCRIPT=$(create_transcript_pct 5 "t20")
# Session "sess_old" creates the flag before /clear
CWD_20_KEY=$(compute_cwd_key "$PWD")
printf '%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_old" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" > "$PLANS_DIR/.pending-reload-${CWD_20_KEY}"
# After /clear, a NEW session_id "sess_new_after_clear" arrives, same CWD
OUTPUT=$(echo '{"prompt":"continue","session_id":"sess_new_after_clear","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_contains "20" "$OUTPUT" "ACTION REQUIRED" && \
   assert_contains "20" "$OUTPUT" "POST-CLEAR RESUME" && \
   assert_contains "20" "$OUTPUT" "Task 2" && \
   [[ ! -f "$PLANS_DIR/.pending-reload-${CWD_20_KEY}" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    [[ -f "$PLANS_DIR/.pending-reload-${CWD_20_KEY}" ]] && echo "  Flag was NOT consumed"
    FAIL=$((FAIL + 1))
fi

# --- Test 21: Different CWDs -> independent flags (validates worktree isolation) ---
echo "Test 21: Different CWDs -> independent flags (validates worktree isolation)"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*
TRANSCRIPT=$(create_transcript_pct 5 "t21")
CWD_X="$TEST_DIR/worktree-x"
CWD_Y="$TEST_DIR/worktree-y"
mkdir -p "$CWD_X" "$CWD_Y"
CWD_X_KEY=$(compute_cwd_key "$CWD_X")
CWD_Y_KEY=$(compute_cwd_key "$CWD_Y")
# Create flag for CWD X only
printf '%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_x" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_X" > "$PLANS_DIR/.pending-reload-${CWD_X_KEY}"
# Session in CWD Y must NOT consume CWD X's flag
OUTPUT_Y=$(echo '{"prompt":"hi","session_id":"sess_y","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$CWD_Y"'"}' | bash "$TEST_DIR/inject-plan.sh")
# Session in CWD X must consume its own flag
OUTPUT_X=$(echo '{"prompt":"hi","session_id":"sess_x","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$CWD_X"'"}' | bash "$TEST_DIR/inject-plan.sh")
T21_PASS=true
# CWD Y should get nothing (no flag, no state)
if [[ -n "$OUTPUT_Y" ]]; then
    echo "  CWD Y got unexpected output (should see nothing)"
    T21_PASS=false
fi
# CWD X should get flag-based reload
if ! assert_contains "21" "$OUTPUT_X" "ACTION REQUIRED"; then
    echo "  CWD X did NOT get flag-based reload"
    T21_PASS=false
fi
# CWD X flag should be consumed, CWD Y should have no flag
if [[ -f "$PLANS_DIR/.pending-reload-${CWD_X_KEY}" ]]; then
    echo "  CWD X flag was NOT consumed"
    T21_PASS=false
fi
if [[ -f "$PLANS_DIR/.pending-reload-${CWD_Y_KEY}" ]]; then
    echo "  Unexpected flag created for CWD Y"
    T21_PASS=false
fi
if [[ "$T21_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# ============================================================================
# RALPH INTEGRATION TESTS (22-28)
# ============================================================================

echo ""
echo "--- Ralph Integration Tests ---"
echo ""

# --- Test 22: Ralph active + context < 50% -> no interference ---
echo "Test 22: Ralph active + context < 50% -> no interference, state unchanged"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.ralph-resume-*

RALPH_CWD_22="$TEST_DIR/worktree-ralph-22"
mkdir -p "$RALPH_CWD_22/.claude"
CWD_22_KEY=$(compute_cwd_key "$RALPH_CWD_22")

# Create Ralph state: active, iteration 5, max 20
create_ralph_state "$RALPH_CWD_22" "true" "5" "20" "TASK DONE" "Fix all bugs in auth module."

# Create transcript at 25% (well below 50% warning)
TRANSCRIPT_22=$(create_transcript_pct 25 "t22")

# Set up state file pointing to plan
printf '%s\n%s\n%s\n%s\n%s\n' "sess_22" "$TRANSCRIPT_22" "1000" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_22_KEY}"

OUTPUT=$(echo '{"prompt":"continue working","session_id":"sess_22","transcript_path":"'"$TRANSCRIPT_22"'","cwd":"'"$RALPH_CWD_22"'"}' | bash "$TEST_DIR/inject-plan.sh")

T22_PASS=true
# No output expected (no trigger word, no context warning, no flag)
if [[ -n "$OUTPUT" ]]; then
    echo "  Got unexpected output: $(echo "$OUTPUT" | head -3)"
    T22_PASS=false
fi
# Ralph state should be unchanged (max_iterations still 20)
RALPH_MAX=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$RALPH_CWD_22/.claude/ralph-loop.local.md" | grep '^max_iterations:' | sed 's/^max_iterations:[[:space:]]*//' | tr -d '[:space:]')
if [[ "$RALPH_MAX" != "20" ]]; then
    echo "  Ralph max_iterations changed from 20 to $RALPH_MAX (should be unchanged)"
    T22_PASS=false
fi
# No resume file should exist
if [[ -f "$PLANS_DIR/.ralph-resume-${CWD_22_KEY}" ]]; then
    echo "  Unexpected ralph-resume file created"
    T22_PASS=false
fi

if [[ "$T22_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 23: Ralph active + context 50% -> advisory, resume file created ---
echo "Test 23: Ralph active + context 50% -> advisory output, resume file created"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.ralph-resume-*

RALPH_CWD_23="$TEST_DIR/worktree-ralph-23"
mkdir -p "$RALPH_CWD_23/.claude"
CWD_23_KEY=$(compute_cwd_key "$RALPH_CWD_23")

# Create Ralph state: active, iteration 5, max 20
create_ralph_state "$RALPH_CWD_23" "true" "5" "20" "ALL TESTS PASS" "Run test suite and fix failures."

# Create transcript at 52% (above 50% warning, below 60% critical)
TRANSCRIPT_23=$(create_transcript_pct 52 "t23")

# Set up state file pointing to plan
printf '%s\n%s\n%s\n%s\n%s\n' "sess_23" "$TRANSCRIPT_23" "1000" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_23_KEY}"

OUTPUT=$(echo '{"prompt":"continue working","session_id":"sess_23","transcript_path":"'"$TRANSCRIPT_23"'","cwd":"'"$RALPH_CWD_23"'"}' | bash "$TEST_DIR/inject-plan.sh")

T23_PASS=true
# Should get CONTEXT WARNING (advisory)
if ! assert_contains "23" "$OUTPUT" "CONTEXT WARNING"; then
    T23_PASS=false
fi
# Should mention Ralph loop is active
if ! assert_contains "23" "$OUTPUT" "Ralph loop active"; then
    T23_PASS=false
fi
# Should mention saving to Serena
if ! assert_contains "23" "$OUTPUT" "write_memory"; then
    T23_PASS=false
fi
# Resume file should be created (preemptive save)
if ! assert_file_exists "23" "$PLANS_DIR/.ralph-resume-${CWD_23_KEY}"; then
    T23_PASS=false
fi
# max_iterations should NOT be changed (still 20, no force-exit at warning)
RALPH_MAX=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$RALPH_CWD_23/.claude/ralph-loop.local.md" | grep '^max_iterations:' | sed 's/^max_iterations:[[:space:]]*//' | tr -d '[:space:]')
if [[ "$RALPH_MAX" != "20" ]]; then
    echo "  Ralph max_iterations changed from 20 to $RALPH_MAX (should be unchanged at warning level)"
    T23_PASS=false
fi

if [[ "$T23_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 24: Ralph active + context 60% -> critical, resume file, force exit ---
echo "Test 24: Ralph active + context 60% -> critical output, resume file, max_iterations = iteration"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.ralph-resume-*

RALPH_CWD_24="$TEST_DIR/worktree-ralph-24"
mkdir -p "$RALPH_CWD_24/.claude"
CWD_24_KEY=$(compute_cwd_key "$RALPH_CWD_24")

# Create Ralph state: active, iteration 7, max 20
create_ralph_state "$RALPH_CWD_24" "true" "7" "20" "DEPLOY SUCCESS" "Deploy and verify staging."

# Create transcript at 62% (above 60% critical)
TRANSCRIPT_24=$(create_transcript_pct 62 "t24")

# Set up state file pointing to plan
printf '%s\n%s\n%s\n%s\n%s\n' "sess_24" "$TRANSCRIPT_24" "1000" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_24_KEY}"

OUTPUT=$(echo '{"prompt":"continue working","session_id":"sess_24","transcript_path":"'"$TRANSCRIPT_24"'","cwd":"'"$RALPH_CWD_24"'"}' | bash "$TEST_DIR/inject-plan.sh")

T24_PASS=true
# Should get CONTEXT CRITICAL
if ! assert_contains "24" "$OUTPUT" "CONTEXT CRITICAL"; then
    T24_PASS=false
fi
# Should mention Ralph auto-exiting
if ! assert_contains "24" "$OUTPUT" "auto-exiting"; then
    T24_PASS=false
fi
# Should instruct to save state to Serena
if ! assert_contains "24" "$OUTPUT" "write_memory"; then
    T24_PASS=false
fi
# Should mention auto-resume after /clear
if ! assert_contains "24" "$OUTPUT" "auto-resume"; then
    T24_PASS=false
fi
# Resume file should exist
if ! assert_file_exists "24" "$PLANS_DIR/.ralph-resume-${CWD_24_KEY}"; then
    T24_PASS=false
fi
# max_iterations should now equal iteration (7) -- force_ralph_exit was called
RALPH_MAX=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$RALPH_CWD_24/.claude/ralph-loop.local.md" | grep '^max_iterations:' | sed 's/^max_iterations:[[:space:]]*//' | tr -d '[:space:]')
if [[ "$RALPH_MAX" != "7" ]]; then
    echo "  Ralph max_iterations should be 7 (= iteration), got $RALPH_MAX"
    T24_PASS=false
fi
# Prompt file should exist alongside resume file
if ! assert_file_exists "24" "$PLANS_DIR/.ralph-resume-${CWD_24_KEY}.prompt"; then
    T24_PASS=false
fi
# Verify resume file contains plan path
RESUME_PLAN=$(sed -n '4p' "$PLANS_DIR/.ralph-resume-${CWD_24_KEY}" 2>/dev/null)
if [[ "$RESUME_PLAN" != *"test-plan.md" ]]; then
    echo "  Resume file plan path expected test-plan.md, got: $RESUME_PLAN"
    T24_PASS=false
fi

if [[ "$T24_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 25: enforce-clear + Ralph state file active -> exit 0 (no block) ---
echo "Test 25: enforce-clear + Ralph state file active -> exit 0 (no block)"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.ralph-resume-*

RALPH_CWD_25="$TEST_DIR/worktree-ralph-25"
mkdir -p "$RALPH_CWD_25/.claude"
CWD_25_KEY=$(compute_cwd_key "$RALPH_CWD_25")

# Create active Ralph state file in the CWD
create_ralph_state "$RALPH_CWD_25" "true" "3" "20" "DONE" "Continue."

# Create transcript at 65% (above critical) -- normally would block
TRANSCRIPT_25=$(create_transcript_pct 65 "t25")

# State file pointing to plan (normally enforce-clear would block)
printf '%s\n%s\n%s\n%s\n%s\n' "sess_25" "$TRANSCRIPT_25" "1000" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_25_KEY}"

OUTPUT=$(echo '{"transcript_path":"'"$TRANSCRIPT_25"'","session_id":"sess_25","cwd":"'"$RALPH_CWD_25"'","stop_hook_active":false}' | bash "$TEST_DIR/enforce-clear.sh")
EXIT_CODE=$?

T25_PASS=true
# Should exit 0 with no output (Ralph defers to inject-plan.sh)
if [[ $EXIT_CODE -ne 0 ]]; then
    echo "  Expected exit 0, got $EXIT_CODE"
    T25_PASS=false
fi
if [[ -n "$OUTPUT" ]]; then
    echo "  Expected empty output, got: $(echo "$OUTPUT" | head -3)"
    T25_PASS=false
fi

if [[ "$T25_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 26: enforce-clear + Ralph resume file only -> exit 0 (no block) ---
echo "Test 26: enforce-clear + Ralph resume file only -> exit 0 (no block)"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.ralph-resume-*

RALPH_CWD_26="$TEST_DIR/worktree-ralph-26"
mkdir -p "$RALPH_CWD_26"
CWD_26_KEY=$(compute_cwd_key "$RALPH_CWD_26")

# NO Ralph state file in CWD, but a resume file exists in PLANS_DIR
# (simulates: inject-plan.sh already force-exited Ralph and saved resume)
printf '20\n7\nDONE\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "$(date +%Y-%m-%dT%H:%M:%S%z)" > "$PLANS_DIR/.ralph-resume-${CWD_26_KEY}"
printf 'Continue fixing bugs.' > "$PLANS_DIR/.ralph-resume-${CWD_26_KEY}.prompt"

# Create transcript at 65% (above critical)
TRANSCRIPT_26=$(create_transcript_pct 65 "t26")

# State file for plan context
printf '%s\n%s\n%s\n%s\n%s\n' "sess_26" "$TRANSCRIPT_26" "1000" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_26_KEY}"

OUTPUT=$(echo '{"transcript_path":"'"$TRANSCRIPT_26"'","session_id":"sess_26","cwd":"'"$RALPH_CWD_26"'","stop_hook_active":false}' | bash "$TEST_DIR/enforce-clear.sh")
EXIT_CODE=$?

T26_PASS=true
if [[ $EXIT_CODE -ne 0 ]]; then
    echo "  Expected exit 0, got $EXIT_CODE"
    T26_PASS=false
fi
if [[ -n "$OUTPUT" ]]; then
    echo "  Expected empty output (Ralph defers), got: $(echo "$OUTPUT" | head -3)"
    T26_PASS=false
fi

if [[ "$T26_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 27: on-session-clear + resume file -> plan + Ralph restart in output ---
echo "Test 27: on-session-clear + resume file -> plan + Ralph restart in output"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.ralph-resume-*

RALPH_CWD_27="$TEST_DIR/worktree-ralph-27"
mkdir -p "$RALPH_CWD_27"
CWD_27_KEY=$(compute_cwd_key "$RALPH_CWD_27")

# Create resume files (as inject-plan.sh would create them before /clear)
printf '20\n7\nALL TESTS PASS\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "$(date +%Y-%m-%dT%H:%M:%S%z)" > "$PLANS_DIR/.ralph-resume-${CWD_27_KEY}"
printf 'Run test suite and fix failures.' > "$PLANS_DIR/.ralph-resume-${CWD_27_KEY}.prompt"

# Create state file pointing to plan
printf '%s\n%s\n%s\n%s\n%s\n' "sess_27" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_27_KEY}"

OUTPUT=$(echo '{"cwd":"'"$RALPH_CWD_27"'"}' | bash "$TEST_DIR/on-session-clear.sh")

T27_PASS=true
# Should contain plan content
if ! assert_contains "27" "$OUTPUT" "Task 2"; then
    T27_PASS=false
fi
# Should contain POST-CLEAR RESUME directive
if ! assert_contains "27" "$OUTPUT" "POST-CLEAR RESUME"; then
    T27_PASS=false
fi
# Should contain Ralph auto-resume directive
if ! assert_contains "27" "$OUTPUT" "RALPH LOOP AUTO-RESUME"; then
    T27_PASS=false
fi
# Should contain the Skill tool invocation with ralph-loop
if ! assert_contains "27" "$OUTPUT" "ralph-loop"; then
    T27_PASS=false
fi
# Should contain the prompt text
if ! assert_contains "27" "$OUTPUT" "Run test suite"; then
    T27_PASS=false
fi
# Should contain max-iterations (remaining: 20-7=13, min 10 -> 13)
if ! assert_contains "27" "$OUTPUT" "max-iterations 13"; then
    T27_PASS=false
fi
# Resume files should be cleaned up (consumed by on-session-clear)
if [[ -f "$PLANS_DIR/.ralph-resume-${CWD_27_KEY}" ]]; then
    echo "  Resume file was NOT cleaned up"
    T27_PASS=false
fi
if [[ -f "$PLANS_DIR/.ralph-resume-${CWD_27_KEY}.prompt" ]]; then
    echo "  Resume prompt file was NOT cleaned up"
    T27_PASS=false
fi

if [[ "$T27_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 28: on-session-clear + resume, no plan -> Ralph restart only ---
echo "Test 28: on-session-clear + resume, no plan -> Ralph restart only in output"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.ralph-resume-*

RALPH_CWD_28="$TEST_DIR/worktree-ralph-28"
mkdir -p "$RALPH_CWD_28"
CWD_28_KEY=$(compute_cwd_key "$RALPH_CWD_28")

# Create resume files but NO plan and NO state file
printf '15\n3\nDEPLOY SUCCESS\n\n%s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" > "$PLANS_DIR/.ralph-resume-${CWD_28_KEY}"
printf 'Deploy and verify staging.' > "$PLANS_DIR/.ralph-resume-${CWD_28_KEY}.prompt"

OUTPUT=$(echo '{"cwd":"'"$RALPH_CWD_28"'"}' | bash "$TEST_DIR/on-session-clear.sh")

T28_PASS=true
# Should contain Ralph auto-resume directive
if ! assert_contains "28" "$OUTPUT" "RALPH LOOP AUTO-RESUME"; then
    T28_PASS=false
fi
# Should contain the Skill tool invocation
if ! assert_contains "28" "$OUTPUT" "ralph-loop"; then
    T28_PASS=false
fi
# Should contain the prompt text
if ! assert_contains "28" "$OUTPUT" "Deploy and verify staging"; then
    T28_PASS=false
fi
# Should contain completion promise
if ! assert_contains "28" "$OUTPUT" "DEPLOY SUCCESS"; then
    T28_PASS=false
fi
# Should NOT contain plan task content (no plan exists)
if echo "$OUTPUT" | grep -q "Task 2"; then
    echo "  Output contains plan task content but no plan should exist"
    T28_PASS=false
fi
# Should have Serena/memory instructions (no-plan path includes these)
if ! assert_contains "28" "$OUTPUT" "list_memories"; then
    T28_PASS=false
fi
# max-iterations should be 12 (15-3=12, >= 10 so not clamped)
if ! assert_contains "28" "$OUTPUT" "max-iterations 12"; then
    T28_PASS=false
fi
# Resume files should be cleaned up
if [[ -f "$PLANS_DIR/.ralph-resume-${CWD_28_KEY}" ]]; then
    echo "  Resume file was NOT cleaned up"
    T28_PASS=false
fi

if [[ "$T28_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# ============================================================================
# PROACTIVE PHASE RESUME TESTS (29-31)
# ============================================================================

echo ""
echo "--- Proactive Phase Resume Tests ---"
echo ""

# --- Test 29: on-session-clear + ralph state file (no resume) + plan -> phase resume hint ---
echo "Test 29: on-session-clear + ralph state (inactive, no resume) + plan -> RALPH LOOP PHASE RESUME"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.ralph-resume-*

RALPH_CWD_29="$TEST_DIR/worktree-ralph-29"
mkdir -p "$RALPH_CWD_29/.claude"
CWD_29_KEY=$(compute_cwd_key "$RALPH_CWD_29")

# Ralph state: active=false (phase completed, Ralph exited via promise)
create_ralph_state "$RALPH_CWD_29" "false" "5" "20" "PHASE_COMPLETE" "Execute the plan tasks."

# State file pointing to plan (simulates previous session had a plan)
printf '%s\n%s\n%s\n%s\n%s\n' "sess_29" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_29_KEY}"

# No resume files -- this is the proactive path
OUTPUT=$(echo '{"cwd":"'"$RALPH_CWD_29"'"}' | bash "$TEST_DIR/on-session-clear.sh")

T29_PASS=true
# Should contain plan content
if ! assert_contains "29" "$OUTPUT" "Task 2"; then
    T29_PASS=false
fi
# Should contain POST-CLEAR RESUME
if ! assert_contains "29" "$OUTPUT" "POST-CLEAR RESUME"; then
    T29_PASS=false
fi
# Should contain RALPH LOOP PHASE RESUME (proactive path)
if ! assert_contains "29" "$OUTPUT" "RALPH LOOP PHASE RESUME"; then
    T29_PASS=false
fi
# Should instruct to read Serena memory for ralph state
if ! assert_contains "29" "$OUTPUT" "ralph_.*state"; then
    T29_PASS=false
fi
# Should instruct to auto-invoke ralph-loop
if ! assert_contains "29" "$OUTPUT" "ralph-loop"; then
    T29_PASS=false
fi
# Should NOT contain RALPH LOOP AUTO-RESUME (that's the reactive path)
if echo "$OUTPUT" | grep -q "AUTO-RESUME"; then
    echo "  Got AUTO-RESUME directive (reactive path) instead of PHASE RESUME (proactive path)"
    T29_PASS=false
fi

if [[ "$T29_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 30: on-session-clear + ralph state (no resume) + no plan -> phase resume hint ---
echo "Test 30: on-session-clear + ralph state (no resume) + no plan -> RALPH LOOP PHASE RESUME"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.ralph-resume-*

RALPH_CWD_30="$TEST_DIR/worktree-ralph-30"
mkdir -p "$RALPH_CWD_30/.claude"

# Ralph state: active=false, no plan, no resume files
create_ralph_state "$RALPH_CWD_30" "false" "3" "15" "DONE" "Fix all bugs."

OUTPUT=$(echo '{"cwd":"'"$RALPH_CWD_30"'"}' | bash "$TEST_DIR/on-session-clear.sh")

T30_PASS=true
# Should contain RALPH LOOP PHASE RESUME
if ! assert_contains "30" "$OUTPUT" "RALPH LOOP PHASE RESUME"; then
    T30_PASS=false
fi
# Should instruct to auto-invoke ralph-loop
if ! assert_contains "30" "$OUTPUT" "ralph-loop"; then
    T30_PASS=false
fi
# Should contain list_memories (Serena restore)
if ! assert_contains "30" "$OUTPUT" "list_memories"; then
    T30_PASS=false
fi

if [[ "$T30_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 31: inject-plan flag reload + ralph state (no resume) -> phase resume hint ---
echo "Test 31: inject-plan flag reload + ralph state (inactive, no resume) -> RALPH LOOP PHASE RESUME"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.ralph-resume-*

RALPH_CWD_31="$TEST_DIR/worktree-ralph-31"
mkdir -p "$RALPH_CWD_31/.claude"
CWD_31_KEY=$(compute_cwd_key "$RALPH_CWD_31")

# Ralph state: active=false (phase completed)
create_ralph_state "$RALPH_CWD_31" "false" "4" "20" "ALL_TESTS_PASS" "Run test suite."

# Create flag file for this CWD (simulates on-plan-exit created it)
printf '%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_31" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$RALPH_CWD_31" > "$PLANS_DIR/.pending-reload-${CWD_31_KEY}"

TRANSCRIPT_31=$(create_transcript_pct 5 "t31")
OUTPUT=$(echo '{"prompt":"continue","session_id":"sess_31_new","transcript_path":"'"$TRANSCRIPT_31"'","cwd":"'"$RALPH_CWD_31"'"}' | bash "$TEST_DIR/inject-plan.sh")

T31_PASS=true
# Should contain POST-CLEAR RESUME (flag-based reload)
if ! assert_contains "31" "$OUTPUT" "POST-CLEAR RESUME"; then
    T31_PASS=false
fi
# Should contain plan content
if ! assert_contains "31" "$OUTPUT" "Task 2"; then
    T31_PASS=false
fi
# Should contain RALPH LOOP PHASE RESUME (proactive path)
if ! assert_contains "31" "$OUTPUT" "RALPH LOOP PHASE RESUME"; then
    T31_PASS=false
fi
# Should instruct to auto-invoke ralph-loop
if ! assert_contains "31" "$OUTPUT" "ralph-loop"; then
    T31_PASS=false
fi
# Flag should be consumed
if [[ -f "$PLANS_DIR/.pending-reload-${CWD_31_KEY}" ]]; then
    echo "  Flag was NOT consumed"
    T31_PASS=false
fi

if [[ "$T31_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Summary ---
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
