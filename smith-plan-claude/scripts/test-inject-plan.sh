#!/bin/bash
#
# test-inject-plan.sh - Tests for inject-plan.sh and enforce-clear.sh
#
# Runs 21 scenarios covering:
#   1. Flag reload -> directive with "context clear"
#   2. Trigger words -> no directive, plan content present
#   3. Fresh session (state exists, small transcript) -> directive with "context clear"
#   4. Context threshold -> CONTEXT CRITICAL, no ACTION REQUIRED
#   5. No plan file -> silent exit or message, no crash
#   6. Ralph iter 2+ -> silent exit (empty output)
#   7. Stop hook: first block -> flag file created + block JSON
#   8. Stop hook: second attempt -> exit 0 (no block output)
#   9. CWD isolation: on-plan-exit creates flag keyed to CWD (worktree A)
#  10. CWD isolation: worktree B ignores worktree A's flag
#  11. CWD isolation: worktree A consumes its own flag after /clear
#  12. Full lifecycle: parallel worktrees create+consume flags independently
#  13. Bug repro: after /clear, each worktree loads its own plan (not the other's)
#  14. State file: created after plan injection
#  15. State file: same session + large transcript -> no re-injection (debounce)
#  16. State file: new CWD (no state, no flag) -> no auto-load
#  17. State file: stale state (>3 min) -> re-injection via "refresh"
#  18. State file: transcript shrank by >50% -> re-injection
#  19. State-based reload uses plan from CWD state file, not most-recent globally
#  20. Same CWD + different session_id -> flag found (validates /clear fix)
#  21. Different CWDs -> independent flags (validates worktree isolation)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INJECT_SCRIPT="$SCRIPT_DIR/scripts/inject-plan.sh"
ENFORCE_SCRIPT="$SCRIPT_DIR/scripts/enforce-clear.sh"
PLAN_EXIT_SCRIPT="$SCRIPT_DIR/scripts/on-plan-exit.sh"

# Use temp directory for isolation
TEST_DIR=$(mktemp -d)
PLANS_DIR="$TEST_DIR/plans"
mkdir -p "$PLANS_DIR"

PASS=0
FAIL=0
TOTAL=21

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Compute CWD key (same logic as scripts — state and flag files both keyed by CWD)
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

# Create transcript of given size (in KB)
# Optional second arg: name suffix for isolated transcript files
create_transcript() {
    local size_kb=$1
    local name="${2:-default}"
    local path="$TEST_DIR/transcript-${name}.jsonl"
    dd if=/dev/zero bs=1024 count="$size_kb" of="$path" 2>/dev/null
    echo "$path"
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

# Initialize patched scripts
create_patched_scripts

# Compute CWD key for tests 1-8 (all share $PWD as their CWD)
CWD_DEFAULT_KEY=$(compute_cwd_key "$PWD")

# --- Test 1: Flag reload ---
echo "Test 1: Flag reload -> directive with 'context clear'"
create_test_plan
printf '%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_test" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" > "$PLANS_DIR/.pending-reload-${CWD_DEFAULT_KEY}"
TRANSCRIPT=$(create_transcript 5)
OUTPUT=$(echo '{"prompt":"hi","session_id":"sess_new","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_contains "1" "$OUTPUT" "ACTION REQUIRED" && \
   assert_contains "1" "$OUTPUT" "context clear" && \
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
TRANSCRIPT=$(create_transcript 50)
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

# --- Test 3: Same session, small transcript (post-/clear) ---
echo "Test 3: Same session, small transcript -> directive with 'context clear'"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-*
TRANSCRIPT=$(create_transcript 5)
# State file exists from test 2 with sess_test and large size -> transcript shrank
OUTPUT=$(echo '{"prompt":"hi","session_id":"sess_test","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_contains "3" "$OUTPUT" "ACTION REQUIRED" && \
   assert_contains "3" "$OUTPUT" "context clear" && \
   assert_contains "3" "$OUTPUT" "Task 2"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 4: Context threshold ---
echo "Test 4: Context threshold -> CONTEXT CRITICAL, no ACTION REQUIRED"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-*
TRANSCRIPT=$(create_transcript 900)
# Update state so we're in an active session (CWD-keyed state, same transcript)
printf '%s\n%s\n%s\n%s\n%s\n' "sess_test" "$TRANSCRIPT" "921600" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_DEFAULT_KEY}"
OUTPUT=$(echo '{"prompt":"do something","session_id":"sess_test","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_contains "4" "$OUTPUT" "CONTEXT CRITICAL" && \
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
TRANSCRIPT=$(create_transcript 5)
OUTPUT=$(echo '{"prompt":"hi","session_id":"sess_test","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh" 2>&1)
EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (exit code: $EXIT_CODE)"
    FAIL=$((FAIL + 1))
fi

# --- Test 6: Ralph iter 2+ ---
echo "Test 6: Ralph iter 2+ (large transcript, generic prompt) -> silent exit"
create_test_plan
TRANSCRIPT=$(create_transcript 20)
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

# --- Test 7: Stop hook first block ---
echo "Test 7: Stop hook: first block -> CWD-specific flag file created + block JSON"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*
TRANSCRIPT=$(create_transcript 900)
# enforce-clear needs a CWD-keyed state file to find the active plan (no ls -t fallback)
printf '%s\n%s\n%s\n%s\n%s\n' "sess_test" "$TRANSCRIPT" "921600" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_DEFAULT_KEY}"
OUTPUT=$(echo '{"transcript_path":"'"$TRANSCRIPT"'","session_id":"sess_test","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/enforce-clear.sh")
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

# --- Test 8: Stop hook second attempt ---
echo "Test 8: Stop hook: second attempt (flag exists) -> exit 0, no block"
# Flag should still exist from test 7
OUTPUT=$(echo '{"transcript_path":"'"$TRANSCRIPT"'","session_id":"sess_test","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/enforce-clear.sh")
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
   assert_contains "9" "$OUTPUT" "flagged for auto-reload"; then
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
TRANSCRIPT=$(create_transcript 5)
# Session B has a state file so it can detect small transcript
printf '%s\n%s\n%s\n%s\n%s\n' "sess_b" "$TRANSCRIPT" "51200" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_B_KEY}"
OUTPUT=$(echo '{"prompt":"hi","session_id":"sess_b","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$WORKTREE_B"'"}' | bash "$TEST_DIR/inject-plan.sh")
# Session B detects its own /clear (transcript shrank) but A's flag is untouched
if assert_contains "10" "$OUTPUT" "context clear" && \
   assert_contains "10" "$OUTPUT" "ACTION REQUIRED" && \
   [[ -f "$PLANS_DIR/.pending-reload-${CWD_A_KEY}" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    [[ ! -f "$PLANS_DIR/.pending-reload-${CWD_A_KEY}" ]] && echo "  Worktree A's flag was consumed by worktree B"
    FAIL=$((FAIL + 1))
fi

# --- Test 11: Worktree A sees and consumes its own flag ---
echo "Test 11: inject-plan.sh from worktree A consumes its own flag after /clear"
TRANSCRIPT=$(create_transcript 5)
# Run inject-plan.sh with worktree A's CWD (simulates post-/clear prompt)
OUTPUT=$(echo '{"prompt":"hi","session_id":"sess_a","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$WORKTREE_A"'"}' | bash "$TEST_DIR/inject-plan.sh")
# Should get flag-based "context clear" load, flag should be consumed
if assert_contains "11" "$OUTPUT" "context clear" && \
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
TRANSCRIPT_SMALL=$(create_transcript 5)
TRANSCRIPT_LARGE=$(create_transcript 900)

# Set up state files so context threshold detection works
printf '%s\n%s\n%s\n%s\n%s\n' "sess_a" "$TRANSCRIPT_LARGE" "921600" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_A_KEY}"
printf '%s\n%s\n%s\n%s\n%s\n' "sess_b" "$TRANSCRIPT_LARGE" "921600" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_B_KEY}"

# Step 1: Worktree A hits context threshold -> flag created for A's CWD
OUTPUT_A1=$(echo '{"prompt":"do something","session_id":"sess_a","transcript_path":"'"$TRANSCRIPT_LARGE"'","cwd":"'"$WORKTREE_A"'"}' | bash "$TEST_DIR/inject-plan.sh")
FLAG_A_EXISTS_1=$([[ -f "$PLANS_DIR/.pending-reload-${CWD_A_KEY}" ]] && echo "yes" || echo "no")

# Step 2: Worktree B hits context threshold -> flag created for B's CWD
OUTPUT_B1=$(echo '{"prompt":"do something","session_id":"sess_b","transcript_path":"'"$TRANSCRIPT_LARGE"'","cwd":"'"$WORKTREE_B"'"}' | bash "$TEST_DIR/inject-plan.sh")
FLAG_B_EXISTS_1=$([[ -f "$PLANS_DIR/.pending-reload-${CWD_B_KEY}" ]] && echo "yes" || echo "no")

# Step 3: Worktree A does /clear and reloads -> A's flag consumed, B's untouched
OUTPUT_A2=$(echo '{"prompt":"hi","session_id":"sess_a","transcript_path":"'"$TRANSCRIPT_SMALL"'","cwd":"'"$WORKTREE_A"'"}' | bash "$TEST_DIR/inject-plan.sh")
FLAG_A_EXISTS_2=$([[ -f "$PLANS_DIR/.pending-reload-${CWD_A_KEY}" ]] && echo "no" || echo "yes")
FLAG_B_EXISTS_2=$([[ -f "$PLANS_DIR/.pending-reload-${CWD_B_KEY}" ]] && echo "yes" || echo "no")

# Step 4: Worktree B does /clear and reloads -> B's flag consumed
OUTPUT_B2=$(echo '{"prompt":"hi","session_id":"sess_b","transcript_path":"'"$TRANSCRIPT_SMALL"'","cwd":"'"$WORKTREE_B"'"}' | bash "$TEST_DIR/inject-plan.sh")
FLAG_B_EXISTS_3=$([[ -f "$PLANS_DIR/.pending-reload-${CWD_B_KEY}" ]] && echo "no" || echo "yes")

if [[ "$FLAG_A_EXISTS_1" == "yes" ]] && \
   [[ "$FLAG_B_EXISTS_1" == "yes" ]] && \
   [[ "$FLAG_A_EXISTS_2" == "yes" ]] && \
   [[ "$FLAG_B_EXISTS_2" == "yes" ]] && \
   [[ "$FLAG_B_EXISTS_3" == "yes" ]] && \
   assert_contains "12-a1" "$OUTPUT_A1" "CONTEXT CRITICAL" && \
   assert_contains "12-b1" "$OUTPUT_B1" "CONTEXT CRITICAL" && \
   assert_contains "12-a2" "$OUTPUT_A2" "context clear" && \
   assert_contains "12-b2" "$OUTPUT_B2" "context clear"; then
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
# This is the exact scenario that was broken before CWD-based isolation:
#   Worktree A works on plan-a.md, Worktree B works on plan-b.md
#   Both trigger ExitPlanMode (on-plan-exit.sh creates flags)
#   After /clear, Worktree A must get plan-a, Worktree B must get plan-b
echo "Test 13: Bug repro - after /clear, each worktree loads its own plan (not the other's)"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*
TRANSCRIPT_SMALL=$(create_transcript 5)

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
if ! assert_contains "13" "$OUTPUT_RELOAD_A" "context clear"; then
    echo "  Worktree A did not get flag-based reload"
    T13_PASS=false
fi
if ! assert_contains "13" "$OUTPUT_RELOAD_B" "context clear"; then
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

# --- Tests 14-18: State-based detection (post-/clear without flag) ---
# These test the .plan-state-<cwd_key> mechanism that detects /clear
# even when the transcript file doesn't shrink.

# --- Test 14: State file created after injection ---
echo "Test 14: State file created after plan injection"
create_test_plan
rm -f "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*
TRANSCRIPT=$(create_transcript 5)
CWD_14_KEY="$CWD_DEFAULT_KEY"  # Tests 14+ use $PWD as CWD
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

# --- Test 15: Same session + large transcript -> no re-injection (debounce) ---
echo "Test 15: Same session + large transcript -> silent (debounced by state)"
# State file from test 14 still exists with sess_14
TRANSCRIPT_LARGE=$(create_transcript 50)
CWD_15_KEY="$CWD_DEFAULT_KEY"
# Create state to record the large transcript
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

# --- Test 17: Stale state (simulated >3 min) -> re-injection via "refresh" ---
echo "Test 17: Stale state file -> re-injection with 'context clear' (Signal 4)"
create_test_plan
CWD_17_KEY="$CWD_DEFAULT_KEY"
rm -f "$PLANS_DIR/.plan-state-${CWD_17_KEY}"
# Create a state file and backdate it by 5 minutes
printf '%s\n%s\n%s\n%s\n%s\n' "sess_17" "$TRANSCRIPT_LARGE" "51200" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_17_KEY}"
# Backdate the state file to 5 minutes ago
touch -t "$(date -v-5M +%Y%m%d%H%M.%S 2>/dev/null || date -d '5 minutes ago' +%Y%m%d%H%M.%S 2>/dev/null)" "$PLANS_DIR/.plan-state-${CWD_17_KEY}"
# Same session_id, same transcript -> but stale state triggers refresh
OUTPUT=$(PLAN_REFRESH_STALE_MIN=3 bash -c 'echo '"'"'{"prompt":"continue","session_id":"sess_17","transcript_path":"'"$TRANSCRIPT_LARGE"'","cwd":"'"$PWD"'"}'"'"' | bash "'"$TEST_DIR/inject-plan.sh"'"')
if assert_contains "17" "$OUTPUT" "ACTION REQUIRED" && \
   assert_contains "17" "$OUTPUT" "context clear" && \
   assert_contains "17" "$OUTPUT" "Task 2"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 18: Transcript shrank by >50% -> re-injection (signal 4) ---
echo "Test 18: Transcript shrank by >50% -> re-injection (signal 4)"
create_test_plan
CWD_18_KEY="$CWD_DEFAULT_KEY"
TRANSCRIPT_SHRUNK=$(create_transcript 5)
# Create state recording a large transcript (100KB)
printf '%s\n%s\n%s\n%s\n%s\n' "sess_18" "$TRANSCRIPT_SHRUNK" "102400" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_18_KEY}"
# Now send with same session, same path, but the size on disk is 5KB vs recorded 100KB
OUTPUT=$(echo '{"prompt":"hi","session_id":"sess_18","transcript_path":"'"$TRANSCRIPT_SHRUNK"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_contains "18" "$OUTPUT" "ACTION REQUIRED" && \
   assert_contains "18" "$OUTPUT" "Task 2"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 19: State-based reload loads CWD's own plan, not most-recent globally ---
# This is the exact real-world bug: Worktree A works on plan-a, Worktree B
# modifies plan-b (making it newer). Worktree A does /clear -> state-based detection
# must reload plan-a (from CWD state file), NOT plan-b (most recent globally).
echo "Test 19: State-based reload uses plan from state file, not most-recent globally"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*

WORKTREE_A19="$TEST_DIR/worktree-a19"
WORKTREE_B19="$TEST_DIR/worktree-b19"
mkdir -p "$WORKTREE_A19" "$WORKTREE_B19"
CWD_A19_KEY=$(compute_cwd_key "$WORKTREE_A19")
_CWD_B19_KEY=$(compute_cwd_key "$WORKTREE_B19")  # reserved for future assertions

# Create plan-a and plan-b
cat > "$PLANS_DIR/plan-a.md" <<'PLAN'
# Plan A
## Tasks
- [x] Task A1: Done
- [ ] Task A2: Session A work
PLAN

cat > "$PLANS_DIR/plan-b.md" <<'PLAN'
# Plan B
## Tasks
- [x] Task B1: Done
- [ ] Task B2: Session B work
PLAN

TRANSCRIPT_A=$(create_transcript 5 "t19a")
TRANSCRIPT_B=$(create_transcript 5 "t19b")

# Step 1: Worktree A loads plan-a (trigger word)
sleep 1 && touch "$PLANS_DIR/plan-a.md"  # ensure plan-a is most recent
OUTPUT_A1=$(echo '{"prompt":"execute the plan","session_id":"sess_a19","transcript_path":"'"$TRANSCRIPT_A"'","cwd":"'"$WORKTREE_A19"'"}' | bash "$TEST_DIR/inject-plan.sh")

# Step 2: Worktree B loads plan-b (we make plan-b most recent)
sleep 1 && touch "$PLANS_DIR/plan-b.md"  # plan-b is now most recent
OUTPUT_B1=$(echo '{"prompt":"execute the plan","session_id":"sess_b19","transcript_path":"'"$TRANSCRIPT_B"'","cwd":"'"$WORKTREE_B19"'"}' | bash "$TEST_DIR/inject-plan.sh")

# Verify: plan-b is now the most-recently-modified .md file
MOST_RECENT=$(ls -t "$PLANS_DIR"/*.md | head -1)

# Step 3: Worktree A after /clear (small transcript) -> state-based detection should
# load plan-a (from CWD state file), NOT plan-b (most recent globally)
OUTPUT_A2=$(echo '{"prompt":"hi","session_id":"sess_a19","transcript_path":"'"$TRANSCRIPT_A"'","cwd":"'"$WORKTREE_A19"'"}' | bash "$TEST_DIR/inject-plan.sh")

T19_PASS=true
# Worktree A must get plan-a content
if ! echo "$OUTPUT_A2" | grep -q "Task A2"; then
    echo "  Worktree A did NOT get plan-a content after /clear"
    T19_PASS=false
fi
# Worktree A must NOT get plan-b content
if echo "$OUTPUT_A2" | grep -q "Task B2"; then
    echo "  Worktree A got plan-b content (WRONG PLAN - loaded most-recent instead of state-recorded)"
    T19_PASS=false
fi
if ! echo "$OUTPUT_A2" | grep -q "ACTION REQUIRED"; then
    echo "  Missing ACTION REQUIRED directive"
    T19_PASS=false
fi

if [[ "$T19_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    echo "  Most recent plan: $(basename "$MOST_RECENT")"
    echo "  State file plan (line 5): $(sed -n '5p' "$PLANS_DIR/.plan-state-${CWD_A19_KEY}" 2>/dev/null || echo 'MISSING')"
    FAIL=$((FAIL + 1))
fi

# (Test 20 removed: was duplicate of Test 16)

# --- Test 20: Same CWD + different session_id -> flag found (validates /clear fix) ---
# This is the core bug fix: /clear creates a NEW session_id, but CWD stays the same.
# The flag (keyed by CWD) must be found by the new session.
echo "Test 20: Same CWD + different session_id -> flag found (validates /clear fix)"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*
TRANSCRIPT=$(create_transcript 5)
# Session "sess_old" creates the flag before /clear
CWD_20_KEY=$(compute_cwd_key "$PWD")
printf '%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_old" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" > "$PLANS_DIR/.pending-reload-${CWD_20_KEY}"
# After /clear, a NEW session_id "sess_new_after_clear" arrives, same CWD
OUTPUT=$(echo '{"prompt":"continue","session_id":"sess_new_after_clear","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_contains "20" "$OUTPUT" "ACTION REQUIRED" && \
   assert_contains "20" "$OUTPUT" "context clear" && \
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
# Parallel sessions in different CWDs must NOT see each other's flags.
echo "Test 21: Different CWDs -> independent flags (validates worktree isolation)"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*
TRANSCRIPT=$(create_transcript 5)
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
T22_PASS=true
# CWD Y should get nothing (no flag, no state)
if [[ -n "$OUTPUT_Y" ]]; then
    echo "  CWD Y got unexpected output (should see nothing)"
    T22_PASS=false
fi
# CWD X should get flag-based reload
if ! assert_contains "21" "$OUTPUT_X" "ACTION REQUIRED"; then
    echo "  CWD X did NOT get flag-based reload"
    T22_PASS=false
fi
# CWD X flag should be consumed, CWD Y should have no flag
if [[ -f "$PLANS_DIR/.pending-reload-${CWD_X_KEY}" ]]; then
    echo "  CWD X flag was NOT consumed"
    T22_PASS=false
fi
if [[ -f "$PLANS_DIR/.pending-reload-${CWD_Y_KEY}" ]]; then
    echo "  Unexpected flag created for CWD Y"
    T22_PASS=false
fi
if [[ "$T22_PASS" == "true" ]]; then
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
