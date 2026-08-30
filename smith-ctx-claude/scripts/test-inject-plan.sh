#!/bin/bash
#
# test-inject-plan.sh - Tests for inject-plan.sh, enforce-clear.sh, and on-session-clear.sh
#
# The scenario count lives in TOTAL below, never in this prose. Covers:
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
#  32. "reload" (exact match) triggers plan load from state file
#  33. "reload plan" (substring) triggers plan load from state file
#  34. "reload the plan" (substring) triggers plan load from state file
#  35. Stale plan: state with completed plan (0 pending) + no flag -> no-plan path
#  36. Stale plan: completed plan + plan-completed flag (empty path) -> no-plan path with resume
#  37. enforce-clear + exit-marker -> exit 0 (no block)
#  ... (38-54 cover exit-marker edge cases, model auto-detection,
#       plan-completed flag consistency, and no-state-file regression)
#  57. memory-restore: 1 fresh matching flag -> restore directive, flag consumed
#  58. memory-restore: 2 matching flags -> collision directive lists both + asks, both consumed
#  59. memory-restore: fresh flag for a different cwd -> untouched, no directive
#  60. memory-restore: stale (>24h) matching flag -> consumed, no directive
#  61. memory-restore: end-to-end write-reload-flag.sh -> hook discovers by cwd match
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INJECT_SCRIPT="$SCRIPT_DIR/scripts/inject-plan.sh"
ENFORCE_SCRIPT="$SCRIPT_DIR/../smith-ctx-claude/scripts/enforce-clear.sh"
PLAN_EXIT_SCRIPT="$SCRIPT_DIR/scripts/on-plan-exit.sh"
SESSION_CLEAR_SCRIPT="$SCRIPT_DIR/scripts/on-session-clear.sh"

# Use temp directory for isolation. The template is explicit because BSD `mktemp -d`
# ignores TMPDIR without one, which made the guard below advise a fix that could not
# work on macOS — and made the guard's own failure path unreachable from a test.
# The trailing slash matters: macOS sets TMPDIR with one, and pasting a template
# straight on gives `…/T//smith-…`, a path that compares unequal to the same
# directory spelled once. Tests assert on these paths, so normalise it here.
TEST_TMPROOT="${TMPDIR:-/tmp}"; TEST_TMPROOT="${TEST_TMPROOT%/}"
TEST_DIR=$(mktemp -d "${TEST_TMPROOT}/smith-plan-claude-tests.XXXXXX")
# Every scenario below builds its own repositories, so an INHERITED git environment
# has nothing to contribute and plenty to break: rev-parse reads GIT_DIR before it
# looks at -C, so the sandbox guard below reports every directory as inside a
# repository, and the `git init` fixtures then operate on the inherited directory
# instead of their own. `git rebase --exec` and git hooks both export it, which is
# how a suite that passes by hand fails from inside a rebase. scope_key() scrubs the
# same three names per call, for the same reason.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR

PLANS_DIR="$TEST_DIR/plans"
mkdir -p "$PLANS_DIR"

# Fail closed if the sandbox landed inside a git repository. scope_key() searches
# UPWARD for a repository, so with a repo-local TMPDIR the directories these tests
# construct as belonging to different repositories would all resolve to the same
# one: the foreign-flag scenarios would stop testing what their names say, and some
# would fail for a reason that has nothing to do with the code under test.
if git -C "$TEST_DIR" rev-parse --git-common-dir >/dev/null 2>&1; then
    echo "Error: sandbox $TEST_DIR is inside a git repository (TMPDIR=${TMPDIR:-unset})." >&2
    echo "       scope_key() resolves upward, so repository-scoped scenarios would be meaningless." >&2
    echo "       Re-run with TMPDIR pointing outside any repository." >&2
  
  
    rm -rf "$TEST_DIR"
    exit 1
fi

# Export _SMITH_PPID so session_key() in hooks uses a predictable value
# (otherwise $PPID varies per subshell invocation, breaking key prediction)
export _SMITH_PPID=$$

PASS=0
FAIL=0
TOTAL=214

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Compute session key (same logic as scripts -- state/flag files keyed by PPID:CWD)
# Uses _SMITH_PPID (exported above) to match what hooks will compute.
compute_session_key() {
    local cwd="$1"
    local ppid="${_SMITH_PPID:-$$}"
    local input="${ppid}:${cwd}"
    local hash
    hash=$(printf '%s' "$input" | md5 -q 2>/dev/null) || \
    hash=$(printf '%s' "$input" | md5sum 2>/dev/null | cut -d' ' -f1) || \
    hash="0000000000000000"
    printf '%s' "${hash:0:16}"
}

# Patch a fresh copy of lib-plan.sh into $TEST_DIR with PLANS_DIR pointed
# at the test sandbox, and confirm the substitution actually took effect.
# Returns 1 (copy still written) on a mismatch so callers can fail closed --
# without this check, a PLANS_DIR line-format drift in lib-plan.sh would
# silently leave the copy pointed at the REAL ~/.claude/plans. Two call
# sites (create_patched_scripts, Test 61) need different responses to that
# failure (abort everything vs. fail just one test), so this only shares the
# patch+check mechanism, not the response.
patch_lib_common() {
    sed -e 's|^PLANS_DIR=.*|PLANS_DIR="'"$PLANS_DIR"'"|' \
        "$SCRIPT_DIR/scripts/lib-plan.sh" > "$TEST_DIR/lib-plan.sh"
    grep -q "PLANS_DIR=\"$PLANS_DIR\"" "$TEST_DIR/lib-plan.sh"
}

# Create patched copies of scripts that use our test PLANS_DIR
# Only patches PLANS_DIR; flag/state files are computed dynamically from CWD/session key
# Also patches lib-plan.sh (shared library sourced by all hook scripts)
create_patched_scripts() {
  
    LIB_COMMON="$SCRIPT_DIR/scripts/lib-plan.sh"
  
  
  
  
  
  
    if ! patch_lib_common; then
        echo "FATAL: PLANS_DIR substitution did not take effect in test lib-plan.sh" >&2
        exit 1
    fi
    chmod +x "$TEST_DIR/lib-plan.sh"

  
    cp "$INJECT_SCRIPT" "$TEST_DIR/inject-plan.sh"
    chmod +x "$TEST_DIR/inject-plan.sh"

    cp "$ENFORCE_SCRIPT" "$TEST_DIR/enforce-clear.sh"
    chmod +x "$TEST_DIR/enforce-clear.sh"

    cp "$SCRIPT_DIR/../smith-ctx-claude/scripts/lib-context.sh" "$TEST_DIR/lib-context.sh"

    export SMITH_CTX_LIB="$TEST_DIR/lib-context.sh"
    export SMITH_PLAN_LIB="$TEST_DIR/lib-plan.sh"
    export CLAUDE_CONFIG_DIR="$TEST_DIR"

    cp "$PLAN_EXIT_SCRIPT" "$TEST_DIR/on-plan-exit.sh"
    chmod +x "$TEST_DIR/on-plan-exit.sh"

    cp "$SESSION_CLEAR_SCRIPT" "$TEST_DIR/on-session-clear.sh"
    chmod +x "$TEST_DIR/on-session-clear.sh"

    cp "$SCRIPT_DIR/scripts/mark-session-restart.sh" "$TEST_DIR/mark-session-restart.sh"
    chmod +x "$TEST_DIR/mark-session-restart.sh"
}

# Create a test plan with pending tasks
create_test_plan() {
    printf '%s\n' '# Test Plan' '' '## Tasks' '' '- [x] Task 1: Done' '- [ ] Task 2: Pending' '- [ ] Task 3: Pending' > "$PLANS_DIR/test-plan.md"
}

# Create transcript JSONL that returns approximately the given percentage.
# Args: $1 = percentage (0-100), $2 = optional name suffix, $3 = optional model
# Returns: path to the transcript file
create_transcript_pct() {
    local pct=$1
    local name="${2:-default}"
    local model="${3:-claude-opus-4-6}"
    local path="$TEST_DIR/transcript-${name}.jsonl"
  
    local context_window
    context_window=$(source "$TEST_DIR/lib-plan.sh" && model_to_context_window "$model")
    local tokens=$(( pct * context_window / 100 ))
    printf '{"type":"assistant","message":{"model":"%s","usage":{"input_tokens":%d,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$model" "$tokens" > "$path"
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
    local _label="$1"
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
    local _label="$1"
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

# Compute session key for tests 1-8 (all share $PWD as their CWD)
CWD_DEFAULT_KEY=$(compute_session_key "$PWD")

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
CWD_3_KEY=$(compute_session_key "$CWD_3")
# Create state file pointing to test plan
printf '%s\n%s\n%s\n%s\n%s\n' "sess_3" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_3_KEY}"
# Create flag file (required for auto-resume gate)
printf '%s\n%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_3" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_3" "plan-pending" > "$PLANS_DIR/.pending-reload-${CWD_3_KEY}"
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
CWD_A_KEY=$(compute_session_key "$WORKTREE_A")
CWD_B_KEY=$(compute_session_key "$WORKTREE_B")

# --- Test 9: on-plan-exit creates CWD-specific flag (worktree A) ---
echo "Test 9: on-plan-exit.sh creates flag keyed to worktree A's CWD"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*
# Create state file so on-plan-exit finds the plan (ls -t fallback removed)
printf '%s\n%s\n%s\n%s\n%s\n' "sess_a" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_A_KEY}"
# Run on-plan-exit.sh with worktree A's CWD
OUTPUT=$(echo '{"session_id":"sess_a","cwd":"'"$WORKTREE_A"'"}' | bash "$TEST_DIR/on-plan-exit.sh")
# Flag should exist for worktree A's CWD hash, NOT worktree B's
if [[ -f "$PLANS_DIR/.pending-reload-${CWD_A_KEY}" ]] && \
   [[ ! -f "$PLANS_DIR/.pending-reload-${CWD_B_KEY}" ]] && \
   assert_contains "9" "$OUTPUT" "PLAN EXIT"; then
  
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
printf '%s\n' '# Plan A - Worktree A'\''s work' '' '## Tasks' '- [x] Task A1: Done' '- [ ] Task A2: Worktree A pending work' > "$PLANS_DIR/plan-a.md"

# Create state file for session A pointing to plan-a
printf '%s\n%s\n%s\n%s\n%s\n' "sess_a" "$TRANSCRIPT_SMALL" "5120" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/plan-a.md" > "$PLANS_DIR/.plan-state-${CWD_A_KEY}"

# Worktree A triggers ExitPlanMode -> on-plan-exit flags plan-a (from state)
_OUTPUT_EXIT_A=$(echo '{"session_id":"sess_a","cwd":"'"$WORKTREE_A"'"}' | bash "$TEST_DIR/on-plan-exit.sh")

sleep 1

# Now create plan-b (worktree B's plan) making it newer than plan-a
printf '%s\n' '# Plan B - Worktree B'\''s work' '' '## Tasks' '- [x] Task B1: Done' '- [ ] Task B2: Worktree B pending work' > "$PLANS_DIR/plan-b.md"

# Create state file for session B pointing to plan-b
printf '%s\n%s\n%s\n%s\n%s\n' "sess_b" "$TRANSCRIPT_SMALL" "5120" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/plan-b.md" > "$PLANS_DIR/.plan-state-${CWD_B_KEY}"

# Worktree B triggers ExitPlanMode -> on-plan-exit flags plan-b (from state)
_OUTPUT_EXIT_B=$(echo '{"session_id":"sess_b","cwd":"'"$WORKTREE_B"'"}' | bash "$TEST_DIR/on-plan-exit.sh")

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
CWD_16_KEY=$(compute_session_key "$TEST_DIR/worktree-16")
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

# --- Test 17: on-session-clear without state file -> fresh start ---
echo "Test 17: on-session-clear without state file -> fresh start directive"
rm -f "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*
create_test_plan
CWD_17="$TEST_DIR/worktree-17"
mkdir -p "$CWD_17"
# No state file for this CWD -> on-session-clear falls through to fresh start path
OUTPUT=$(echo '{"cwd":"'"$CWD_17"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "17" "$OUTPUT" "fresh-start" && \
   assert_contains "17" "$OUTPUT" "Signal"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 18: on-session-clear with missing plan file -> fresh start ---
echo "Test 18: on-session-clear with missing plan file -> fresh start directive"
CWD_18="$TEST_DIR/worktree-18"
mkdir -p "$CWD_18"
CWD_18_KEY=$(compute_session_key "$CWD_18")
# Create state pointing to a plan file that does not exist
printf '%s\n%s\n%s\n%s\n%s\n' "sess_18" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/nonexistent-plan.md" > "$PLANS_DIR/.plan-state-${CWD_18_KEY}"
OUTPUT=$(echo '{"cwd":"'"$CWD_18"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "18" "$OUTPUT" "fresh-start" && \
   assert_contains "18" "$OUTPUT" "file missing"; then
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
CWD_A19_KEY=$(compute_session_key "$WORKTREE_A19")
CWD_B19_KEY=$(compute_session_key "$WORKTREE_B19")

# Create plan-a and plan-b
printf '%s\n' '# Plan A' '## Tasks' '- [x] Task A1: Done' '- [ ] Task A2: Session A work' > "$PLANS_DIR/plan-a.md"

sleep 1

printf '%s\n' '# Plan B' '## Tasks' '- [x] Task B1: Done' '- [ ] Task B2: Session B work' > "$PLANS_DIR/plan-b.md"

# plan-b is now newer. Create state files linking each CWD to its own plan.
printf '%s\n%s\n%s\n%s\n%s\n' "sess_a19" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/plan-a.md" > "$PLANS_DIR/.plan-state-${CWD_A19_KEY}"
printf '%s\n%s\n%s\n%s\n%s\n' "sess_b19" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/plan-b.md" > "$PLANS_DIR/.plan-state-${CWD_B19_KEY}"
# Create flag files (required for auto-resume gate)
printf '%s\n%s\n%s\n%s\n%s\n' "$PLANS_DIR/plan-a.md" "sess_a19" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$WORKTREE_A19" "plan-pending" > "$PLANS_DIR/.pending-reload-${CWD_A19_KEY}"
printf '%s\n%s\n%s\n%s\n%s\n' "$PLANS_DIR/plan-b.md" "sess_b19" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$WORKTREE_B19" "plan-pending" > "$PLANS_DIR/.pending-reload-${CWD_B19_KEY}"

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
CWD_20_KEY=$(compute_session_key "$PWD")
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
CWD_X_KEY=$(compute_session_key "$CWD_X")
CWD_Y_KEY=$(compute_session_key "$CWD_Y")
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
CWD_22_KEY=$(compute_session_key "$RALPH_CWD_22")

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
CWD_23_KEY=$(compute_session_key "$RALPH_CWD_23")

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
CWD_24_KEY=$(compute_session_key "$RALPH_CWD_24")

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
CWD_25_KEY=$(compute_session_key "$RALPH_CWD_25")

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
CWD_26_KEY=$(compute_session_key "$RALPH_CWD_26")

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
CWD_27_KEY=$(compute_session_key "$RALPH_CWD_27")

# Create resume files (as inject-plan.sh would create them before /clear)
printf '20\n7\nALL TESTS PASS\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "$(date +%Y-%m-%dT%H:%M:%S%z)" > "$PLANS_DIR/.ralph-resume-${CWD_27_KEY}"
printf 'Run test suite and fix failures.' > "$PLANS_DIR/.ralph-resume-${CWD_27_KEY}.prompt"

# Create state file pointing to plan
printf '%s\n%s\n%s\n%s\n%s\n' "sess_27" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_27_KEY}"
# Create flag file (required for auto-resume gate)
printf '%s\n%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_27" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$RALPH_CWD_27" "plan-pending" > "$PLANS_DIR/.pending-reload-${CWD_27_KEY}"

OUTPUT=$(echo '{"cwd":"'"$RALPH_CWD_27"'"}' | bash "$TEST_DIR/on-session-clear.sh")

T27_PASS=true
# Should contain plan content
if ! assert_contains "27" "$OUTPUT" "Task 2"; then
    T27_PASS=false
fi
# Should contain POST-CLEAR RESUME directive (advisory Serena, not mandatory gate)
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
CWD_28_KEY=$(compute_session_key "$RALPH_CWD_28")

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
# Fresh start path should NOT include Serena memory gate (trust hook decision)
if echo "$OUTPUT" | grep -q "list_memories"; then
    echo "  ASSERT FAILED: fresh start should not include list_memories gate"
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
CWD_29_KEY=$(compute_session_key "$RALPH_CWD_29")

# Ralph state: active=false (phase completed, Ralph exited via promise)
create_ralph_state "$RALPH_CWD_29" "false" "5" "20" "PHASE_COMPLETE" "Execute the plan tasks."

# State file pointing to plan (simulates previous session had a plan)
printf '%s\n%s\n%s\n%s\n%s\n' "sess_29" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_29_KEY}"
# Create flag file (required for auto-resume gate)
printf '%s\n%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_29" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$RALPH_CWD_29" "plan-pending" > "$PLANS_DIR/.pending-reload-${CWD_29_KEY}"

# No resume files -- this is the proactive path
OUTPUT=$(echo '{"cwd":"'"$RALPH_CWD_29"'"}' | bash "$TEST_DIR/on-session-clear.sh")

T29_PASS=true
# Should contain plan content
if ! assert_contains "29" "$OUTPUT" "Task 2"; then
    T29_PASS=false
fi
# Should contain POST-CLEAR RESUME directive (advisory Serena, not mandatory gate)
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
# Fresh start path should NOT include Serena memory gate (trust hook decision)
if echo "$OUTPUT" | grep -q "list_memories"; then
    echo "  ASSERT FAILED: fresh start should not include list_memories gate"
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
CWD_31_KEY=$(compute_session_key "$RALPH_CWD_31")

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

# ============================================================================
# RELOAD TRIGGER WORD TESTS (32-34)
# ============================================================================

echo ""
echo "--- Reload Trigger Word Tests ---"
echo ""

# --- Test 32: "reload" (exact match) triggers plan load from state file ---
echo "Test 32: \"reload\" (exact match) triggers plan load from state file"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*
TRANSCRIPT=$(create_transcript_pct 5 "t32")
CWD_32="$TEST_DIR/worktree-reload-32"
mkdir -p "$CWD_32"
CWD_32_KEY=$(compute_session_key "$CWD_32")
# Create state file pointing to plan (simulates previous session)
printf '%s\n%s\n%s\n%s\n%s\n' "sess_32" "$TRANSCRIPT" "1000" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_32_KEY}"
OUTPUT=$(echo '{"prompt":"reload","session_id":"sess_32","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$CWD_32"'"}' | bash "$TEST_DIR/inject-plan.sh")
T32_PASS=true
# Should contain plan content (trigger word load)
if ! assert_contains "32" "$OUTPUT" "Task 2"; then
    T32_PASS=false
fi
# Should NOT contain POST-CLEAR RESUME (trigger word, not flag)
if echo "$OUTPUT" | grep -q "POST-CLEAR RESUME"; then
    echo "  Got POST-CLEAR RESUME directive (should be trigger-word load)"
    T32_PASS=false
fi
if [[ "$T32_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 33: "reload plan" (substring) triggers plan load from state file ---
echo "Test 33: \"reload plan\" (substring) triggers plan load from state file"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-*
CWD_33="$TEST_DIR/worktree-reload-33"
mkdir -p "$CWD_33"
CWD_33_KEY=$(compute_session_key "$CWD_33")
printf '%s\n%s\n%s\n%s\n%s\n' "sess_33" "$TRANSCRIPT" "1000" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_33_KEY}"
OUTPUT=$(echo '{"prompt":"please reload plan","session_id":"sess_33","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$CWD_33"'"}' | bash "$TEST_DIR/inject-plan.sh")
T33_PASS=true
if ! assert_contains "33" "$OUTPUT" "Task 2"; then
    T33_PASS=false
fi
if echo "$OUTPUT" | grep -q "POST-CLEAR RESUME"; then
    echo "  Got POST-CLEAR RESUME directive (should be trigger-word load)"
    T33_PASS=false
fi
if [[ "$T33_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 34: "reload the plan" (substring) triggers plan load from state file ---
echo "Test 34: \"reload the plan\" (substring) triggers plan load from state file"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-*
CWD_34="$TEST_DIR/worktree-reload-34"
mkdir -p "$CWD_34"
CWD_34_KEY=$(compute_session_key "$CWD_34")
printf '%s\n%s\n%s\n%s\n%s\n' "sess_34" "$TRANSCRIPT" "1000" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_34_KEY}"
OUTPUT=$(echo '{"prompt":"reload the plan","session_id":"sess_34","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$CWD_34"'"}' | bash "$TEST_DIR/inject-plan.sh")
T34_PASS=true
if ! assert_contains "34" "$OUTPUT" "Task 2"; then
    T34_PASS=false
fi
if echo "$OUTPUT" | grep -q "POST-CLEAR RESUME"; then
    echo "  Got POST-CLEAR RESUME directive (should be trigger-word load)"
    T34_PASS=false
fi
if [[ "$T34_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# ============================================================================
# STALE PLAN DETECTION TESTS (35-36)
# ============================================================================

echo ""
echo "--- Stale Plan Detection Tests ---"
echo ""

# --- Test 35: on-session-clear + state with completed plan + no flag -> no-plan path ---
echo "Test 35: on-session-clear + state with completed plan (0 pending) + no flag -> no-plan path"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*

CWD_35="$TEST_DIR/worktree-35"
mkdir -p "$CWD_35"
CWD_35_KEY=$(compute_session_key "$CWD_35")

# Create plan with NO pending tasks (all completed)
printf '%s\n' '# Completed Plan' '' '## Tasks' '' '- [x] Task 1: Done' '- [x] Task 2: Done' > "$PLANS_DIR/completed-plan.md"

# Create state file pointing to completed plan
printf '%s\n%s\n%s\n%s\n%s\n' "sess_35" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/completed-plan.md" > "$PLANS_DIR/.plan-state-${CWD_35_KEY}"

# No flag file
OUTPUT=$(echo '{"cwd":"'"$CWD_35"'"}' | bash "$TEST_DIR/on-session-clear.sh")

T35_PASS=true
# Should get "no plan" path (stale plan rejected) — state shows "not loaded"
if ! assert_contains "35" "$OUTPUT" "not loaded"; then
    T35_PASS=false
fi
# Should NOT show completed plan's task content
if echo "$OUTPUT" | grep -q "Completed Plan"; then
    echo "  Output contains completed plan content (should NOT be loaded)"
    T35_PASS=false
fi
# Should contain state metadata showing fresh start decision
if ! assert_contains "35" "$OUTPUT" "fresh-start"; then
    T35_PASS=false
fi
# Should contain state metadata showing 0 pending tasks
if ! assert_contains "35" "$OUTPUT" "pending: 0"; then
    T35_PASS=false
fi

if [[ "$T35_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 36: on-session-clear + state with completed plan + plan-completed flag (empty path) -> no-plan path ---
echo "Test 36: on-session-clear + completed plan + plan-completed flag (empty path) -> no-plan path with resume signal"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*

CWD_36="$TEST_DIR/worktree-36"
mkdir -p "$CWD_36"
CWD_36_KEY=$(compute_session_key "$CWD_36")

# Create plan with NO pending tasks (all completed)
printf '%s\n' '# Completed Plan 36' '' '## Tasks' '' '- [x] Task 1: Done' '- [x] Task 2: Done' > "$PLANS_DIR/completed-plan-36.md"

# Create state file pointing to completed plan
printf '%s\n%s\n%s\n%s\n%s\n' "sess_36" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/completed-plan-36.md" > "$PLANS_DIR/.plan-state-${CWD_36_KEY}"

# Create flag file with empty plan path (as enforce-clear now does for completed plans)
printf '%s\n%s\n%s\n%s\n%s\n' "" "sess_36" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_36" "plan-completed" > "$PLANS_DIR/.pending-reload-${CWD_36_KEY}"

OUTPUT=$(echo '{"cwd":"'"$CWD_36"'"}' | bash "$TEST_DIR/on-session-clear.sh")

T36_PASS=true
# Should show resume signal (flag exists = reload intent)
if ! assert_contains "36" "$OUTPUT" "resume"; then
    T36_PASS=false
fi
# Should NOT load the completed plan content (empty plan path in flag)
if echo "$OUTPUT" | grep -q "Completed Plan 36"; then
    echo "  Got plan content but should NOT load completed plan (empty path in flag)"
    T36_PASS=false
fi
# Should show state metadata
if ! assert_contains "36" "$OUTPUT" "State check"; then
    T36_PASS=false
fi

if [[ "$T36_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 37: enforce-clear + exit-marker -> exit 0 (no block) ---
echo "Test 37: enforce-clear + exit-marker -> exit 0 (no block)"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-*

# Create state file and flag file (simulate active plan at high context)
CWD_37="$TEST_DIR/worktree-37"
mkdir -p "$CWD_37"
CWD_37_KEY=$(compute_session_key "$CWD_37")
FLAG_37="$PLANS_DIR/.pending-reload-${CWD_37_KEY}"
printf '%s\n%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_37" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_37" "plan-pending" > "$FLAG_37"

# Create exit-marker (as on-plan-exit.sh would)
touch "${FLAG_37}.exit-marker"

# Create transcript at 65% context
TRANSCRIPT_37=$(create_transcript_pct 65 "t37")

OUTPUT=$(echo '{"session_id":"sess_37","transcript_path":"'"$TRANSCRIPT_37"'","cwd":"'"$CWD_37"'","stop_hook_active":false}' | bash "$TEST_DIR/enforce-clear.sh" 2>/dev/null)
EXIT_CODE=$?

T37_PASS=true
# Should exit 0 (no block) because exit-marker was present
if [[ $EXIT_CODE -ne 0 ]]; then
    echo "  Exit code was $EXIT_CODE, expected 0"
    T37_PASS=false
fi
# Output should be empty (allowed to stop)
if [[ -n "$OUTPUT" ]]; then
    echo "  Got output but expected empty (stop should be allowed)"
    T37_PASS=false
fi
# Exit-marker should be consumed (deleted)
if [[ -f "${FLAG_37}.exit-marker" ]]; then
    echo "  Exit-marker was NOT consumed"
    T37_PASS=false
fi

if [[ "$T37_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 38: enforce-clear + old exit-marker (session match) -> exit 0 (no block) ---
echo "Test 38: enforce-clear + old exit-marker (session match) -> exit 0 (no block)"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-*

CWD_38="$TEST_DIR/worktree-38"
mkdir -p "$CWD_38"
CWD_38_KEY=$(compute_session_key "$CWD_38")
FLAG_38="$PLANS_DIR/.pending-reload-${CWD_38_KEY}"
printf '%s\n%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_38" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_38" "plan-pending" > "$FLAG_38"

# Create exit-marker and backdate it to 60s ago (no longer matters — freshness removed)
touch "${FLAG_38}.exit-marker"
touch -t "$(date -v-60S +%Y%m%d%H%M.%S 2>/dev/null || date -d '60 seconds ago' +%Y%m%d%H%M.%S 2>/dev/null)" "${FLAG_38}.exit-marker"

TRANSCRIPT_38=$(create_transcript_pct 65 "t38")

OUTPUT=$(echo '{"session_id":"sess_38","transcript_path":"'"$TRANSCRIPT_38"'","cwd":"'"$CWD_38"'","stop_hook_active":false}' | bash "$TEST_DIR/enforce-clear.sh" 2>/dev/null)
EXIT_CODE=$?

T38_PASS=true
# Should exit 0 (no block) because session matches — marker age is irrelevant
if [[ $EXIT_CODE -ne 0 ]]; then
    echo "  Exit code was $EXIT_CODE, expected 0"
    T38_PASS=false
fi
if [[ -n "$OUTPUT" ]]; then
    echo "  Got output but expected empty (stop should be allowed)"
    T38_PASS=false
fi
# Exit-marker should be consumed (deleted)
if [[ -f "${FLAG_38}.exit-marker" ]]; then
    echo "  Exit-marker was NOT consumed"
    T38_PASS=false
fi

if [[ "$T38_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 39: enforce-clear + exit-marker with session mismatch -> still blocks ---
echo "Test 39: enforce-clear + exit-marker with session mismatch -> still blocks"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-*

CWD_39="$TEST_DIR/worktree-39"
mkdir -p "$CWD_39"
CWD_39_KEY=$(compute_session_key "$CWD_39")
FLAG_39="$PLANS_DIR/.pending-reload-${CWD_39_KEY}"
# Flag file has session "sess_39_other" but input will have "sess_39"
printf '%s\n%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_39_other" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_39" "plan-pending" > "$FLAG_39"

touch "${FLAG_39}.exit-marker"

TRANSCRIPT_39=$(create_transcript_pct 65 "t39")

OUTPUT=$(echo '{"session_id":"sess_39","transcript_path":"'"$TRANSCRIPT_39"'","cwd":"'"$CWD_39"'","stop_hook_active":false}' | bash "$TEST_DIR/enforce-clear.sh" 2>/dev/null)
EXIT_CODE=$?

T39_PASS=true
# Should block (output contains "block") because session doesn't match
if ! echo "$OUTPUT" | grep -q '"block"'; then
    echo "  Output missing 'block' decision (session mismatch should not bypass)"
    T39_PASS=false
fi
# Exit-marker should still be consumed
if [[ -f "${FLAG_39}.exit-marker" ]]; then
    echo "  Exit-marker was NOT consumed"
    T39_PASS=false
fi

if [[ "$T39_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 40: enforce-clear + exit-marker without flag file -> still blocks ---
echo "Test 40: enforce-clear + exit-marker without flag file -> still blocks"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-*

CWD_40="$TEST_DIR/worktree-40"
mkdir -p "$CWD_40"
CWD_40_KEY=$(compute_session_key "$CWD_40")
FLAG_40="$PLANS_DIR/.pending-reload-${CWD_40_KEY}"
# Only create exit-marker, NO flag file
touch "${FLAG_40}.exit-marker"

TRANSCRIPT_40=$(create_transcript_pct 65 "t40")

OUTPUT=$(echo '{"session_id":"sess_40","transcript_path":"'"$TRANSCRIPT_40"'","cwd":"'"$CWD_40"'","stop_hook_active":false}' | bash "$TEST_DIR/enforce-clear.sh" 2>/dev/null)
EXIT_CODE=$?

T40_PASS=true
# Should block (output contains "block") because flag file is missing (sed returns empty, won't match)
if ! echo "$OUTPUT" | grep -q '"block"'; then
    echo "  Output missing 'block' decision (missing flag file should not bypass)"
    T40_PASS=false
fi
# Exit-marker should still be consumed
if [[ -f "${FLAG_40}.exit-marker" ]]; then
    echo "  Exit-marker was NOT consumed"
    T40_PASS=false
fi

if [[ "$T40_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# ============================================================================
# MODEL AUTO-DETECTION TESTS (41-48b)
# ============================================================================

echo ""
echo "--- Model Auto-Detection Tests ---"
echo ""

# --- Test 41: Legacy Sonnet transcript at 55% -> 200K auto-detected -> returns ~55 ---
echo "Test 41: Legacy Sonnet (4.5) transcript at 55% -> 200K auto-detected -> returns ~55"
TRANSCRIPT_41=$(create_transcript_pct 55 "t41" "claude-sonnet-4-5")
# Source patched lib-plan.sh to call get_context_percentage directly
PCT_41=$(source "$TEST_DIR/lib-plan.sh" && get_context_percentage "$TRANSCRIPT_41")
if [[ $PCT_41 -ge 54 ]] && [[ $PCT_41 -le 56 ]]; then
    echo "  PASS (got ${PCT_41}%)"
    PASS=$((PASS + 1))
else
    echo "  FAIL (expected ~55%, got ${PCT_41}%)"
    FAIL=$((FAIL + 1))
fi

# --- Test 41b: Current-gen Sonnet (4.6) transcript at 55% -> 1M auto-detected -> returns ~55 ---
echo "Test 41b: Current-gen Sonnet (4.6) transcript at 55% -> 1M auto-detected -> returns ~55"
TRANSCRIPT_41B=$(create_transcript_pct 55 "t41b" "claude-sonnet-4-6")
PCT_41B=$(source "$TEST_DIR/lib-plan.sh" && get_context_percentage "$TRANSCRIPT_41B")
if [[ $PCT_41B -ge 54 ]] && [[ $PCT_41B -le 56 ]]; then
    echo "  PASS (got ${PCT_41B}%)"
    PASS=$((PASS + 1))
else
    echo "  FAIL (expected ~55%, got ${PCT_41B}%)"
    FAIL=$((FAIL + 1))
fi

# --- Test 42: Haiku transcript at 55% -> 200K auto-detected -> returns ~55 ---
echo "Test 42: Haiku transcript at 55% -> 200K auto-detected -> returns ~55"
TRANSCRIPT_42=$(create_transcript_pct 55 "t42" "claude-haiku-4-5-20251001")
PCT_42=$(source "$TEST_DIR/lib-plan.sh" && get_context_percentage "$TRANSCRIPT_42")
if [[ $PCT_42 -ge 54 ]] && [[ $PCT_42 -le 56 ]]; then
    echo "  PASS (got ${PCT_42}%)"
    PASS=$((PASS + 1))
else
    echo "  FAIL (expected ~55%, got ${PCT_42}%)"
    FAIL=$((FAIL + 1))
fi

# --- Test 43: Opus (no [1m] suffix) transcript at 55% -> maps to 1M -> returns ~55 ---
echo 'Test 43: Opus (no [1m] suffix) transcript at 55% -> 1M window -> returns ~55'
TRANSCRIPT_43=$(create_transcript_pct 55 "t43" "claude-opus-4-6")
PCT_43=$(source "$TEST_DIR/lib-plan.sh" && get_context_percentage "$TRANSCRIPT_43")
if [[ $PCT_43 -ge 54 ]] && [[ $PCT_43 -le 56 ]]; then
    echo "  PASS (got ${PCT_43}%)"
    PASS=$((PASS + 1))
else
    echo "  FAIL (expected ~55%, got ${PCT_43}%)"
    FAIL=$((FAIL + 1))
fi

# --- Test 44: Explicit $2 override bypasses auto-detection ---
echo "Test 44: Explicit context_window arg bypasses model auto-detection"
# Create a legacy Sonnet (4.5, 200K window) transcript but pass 1M explicitly -> should return ~11%
TRANSCRIPT_44=$(create_transcript_pct 55 "t44" "claude-sonnet-4-5")
PCT_44=$(source "$TEST_DIR/lib-plan.sh" && get_context_percentage "$TRANSCRIPT_44" "1000000")
# 55% of 200K = 110K tokens. 110K / 1M = 11%
if [[ $PCT_44 -ge 10 ]] && [[ $PCT_44 -le 12 ]]; then
    echo "  PASS (got ${PCT_44}%)"
    PASS=$((PASS + 1))
else
    echo "  FAIL (expected ~11%, got ${PCT_44}%)"
    FAIL=$((FAIL + 1))
fi

# --- Test 45: No model field -> falls back to CONTEXT_WINDOW_TOKENS ---
echo "Test 45: No model field in transcript -> falls back to CONTEXT_WINDOW_TOKENS"
# Create transcript without model field (old format)
TRANSCRIPT_45="$TEST_DIR/transcript-t45.jsonl"
printf '{"type":"assistant","message":{"usage":{"input_tokens":110000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$TRANSCRIPT_45"
PCT_45=$(source "$TEST_DIR/lib-plan.sh" && get_context_percentage "$TRANSCRIPT_45")
# 110K / 200K = 55%
if [[ $PCT_45 -ge 54 ]] && [[ $PCT_45 -le 56 ]]; then
    echo "  PASS (got ${PCT_45}%)"
    PASS=$((PASS + 1))
else
    echo "  FAIL (expected ~55%, got ${PCT_45}%)"
    FAIL=$((FAIL + 1))
fi

# --- Test 46: SessionStart model file used by inject-plan for context detection ---
echo "Test 46: SessionStart model file used by inject-plan for Opus[1m] context detection"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.model-*

CWD_46="$TEST_DIR/worktree-46"
mkdir -p "$CWD_46"
CWD_46_KEY=$(compute_session_key "$CWD_46")

# Create session model file (as on-session-clear.sh would)
printf 'claude-opus-4-6[1m]\n' > "$PLANS_DIR/.model-${CWD_46_KEY}"

# Create transcript with legacy Sonnet (4.5) model at 55% of 200K = 110K tokens
# But since session model has [1m], it should use 1M -> 110K/1M = 11% (below 50% warning)
TRANSCRIPT_46=$(create_transcript_pct 55 "t46" "claude-sonnet-4-5")

# Set up state file
printf '%s\n%s\n%s\n%s\n%s\n' "sess_46" "$TRANSCRIPT_46" "1000" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_46_KEY}"

# Should NOT trigger context warning (11% < 50%) because session model overrides
OUTPUT=$(echo '{"prompt":"do something","session_id":"sess_46","transcript_path":"'"$TRANSCRIPT_46"'","cwd":"'"$CWD_46"'"}' | bash "$TEST_DIR/inject-plan.sh")
if [[ -z "$OUTPUT" ]]; then
    echo "  PASS (no warning at 11%)"
    PASS=$((PASS + 1))
else
    echo "  FAIL (expected no output, got: $(echo "$OUTPUT" | head -3))"
    FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR/.model-${CWD_46_KEY}"

# --- Test 47: model_to_context_window maps [1m] suffix and current-gen Sonnet correctly ---
echo "Test 47: model_to_context_window maps [1m] suffix, current-gen Sonnet, and legacy models correctly"
T47_PASS=true
CTX_1M=$(source "$TEST_DIR/lib-plan.sh" && model_to_context_window "claude-opus-4-6[1m]")
CTX_1M_UPPER=$(source "$TEST_DIR/lib-plan.sh" && model_to_context_window "claude-opus-4-6[1M]")
CTX_SONNET_LEGACY=$(source "$TEST_DIR/lib-plan.sh" && model_to_context_window "claude-sonnet-4-5")
CTX_SONNET_4_6=$(source "$TEST_DIR/lib-plan.sh" && model_to_context_window "claude-sonnet-4-6")
CTX_SONNET_4_7=$(source "$TEST_DIR/lib-plan.sh" && model_to_context_window "claude-sonnet-4-7")
CTX_SONNET_4_DATED=$(source "$TEST_DIR/lib-plan.sh" && model_to_context_window "claude-sonnet-4-20250514")
CTX_SONNET_5=$(source "$TEST_DIR/lib-plan.sh" && model_to_context_window "claude-sonnet-5")
CTX_HAIKU=$(source "$TEST_DIR/lib-plan.sh" && model_to_context_window "claude-haiku-4-5-20251001")
CTX_OPUS=$(source "$TEST_DIR/lib-plan.sh" && model_to_context_window "claude-opus-4-6")
CTX_MYTHOS=$(source "$TEST_DIR/lib-plan.sh" && model_to_context_window "claude-mythos-1")
if [[ "$CTX_1M" != "1000000" ]]; then
    echo "  [1m] -> expected 1000000, got $CTX_1M"
    T47_PASS=false
fi
if [[ "$CTX_1M_UPPER" != "1000000" ]]; then
    echo "  [1M] -> expected 1000000, got $CTX_1M_UPPER"
    T47_PASS=false
fi
if [[ "$CTX_SONNET_LEGACY" != "200000" ]]; then
    echo "  sonnet-4-5 (legacy) -> expected 200000, got $CTX_SONNET_LEGACY"
    T47_PASS=false
fi
if [[ "$CTX_SONNET_4_6" != "1000000" ]]; then
    echo "  sonnet-4-6 (current-gen) -> expected 1000000, got $CTX_SONNET_4_6"
    T47_PASS=false
fi
if [[ "$CTX_SONNET_4_7" != "1000000" ]]; then
    echo "  sonnet-4-7 (current-gen, single-digit range) -> expected 1000000, got $CTX_SONNET_4_7"
    T47_PASS=false
fi
if [[ "$CTX_SONNET_4_DATED" != "200000" ]]; then
    echo "  sonnet-4-20250514 (dated base Sonnet 4, no minor version -- legacy) -> expected 200000, got $CTX_SONNET_4_DATED"
    T47_PASS=false
fi
if [[ "$CTX_SONNET_5" != "1000000" ]]; then
    echo "  sonnet-5 (current-gen) -> expected 1000000, got $CTX_SONNET_5"
    T47_PASS=false
fi
if [[ "$CTX_HAIKU" != "200000" ]]; then
    echo "  haiku -> expected 200000, got $CTX_HAIKU"
    T47_PASS=false
fi
if [[ "$CTX_OPUS" != "1000000" ]]; then
    echo "  opus (no suffix) -> expected 1000000, got $CTX_OPUS"
    T47_PASS=false
fi
if [[ "$CTX_MYTHOS" != "1000000" ]]; then
    echo "  mythos (flagship) -> expected 1000000, got $CTX_MYTHOS"
    T47_PASS=false
fi
if [[ "$T47_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 48: Plain legacy Sonnet session model -> 200K window -> warning at 55% ---
echo "Test 48: Plain legacy Sonnet (4.5) session model -> 200K window triggers warning at 55%"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.model-*

CWD_48="$TEST_DIR/worktree-48"
mkdir -p "$CWD_48"
CWD_48_KEY=$(compute_session_key "$CWD_48")

# Create session model file with plain legacy Sonnet (no [1m] suffix, pre-4.6)
printf 'claude-sonnet-4-5\n' > "$PLANS_DIR/.model-${CWD_48_KEY}"

# Create transcript with legacy Sonnet model at 55% of 200K = 110K tokens
TRANSCRIPT_48=$(create_transcript_pct 55 "t48" "claude-sonnet-4-5")

# Set up state file with plan
printf '%s\n%s\n%s\n%s\n%s\n' "sess_48" "$TRANSCRIPT_48" "1000" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_48_KEY}"

# Should trigger context warning (55% >= 50%) because legacy Sonnet uses 200K window
OUTPUT=$(echo '{"prompt":"do something","session_id":"sess_48","transcript_path":"'"$TRANSCRIPT_48"'","cwd":"'"$CWD_48"'"}' | bash "$TEST_DIR/inject-plan.sh")
if echo "$OUTPUT" | grep -q "CONTEXT WARNING"; then
    echo "  PASS (warning triggered at 55% of 200K)"
    PASS=$((PASS + 1))
else
    echo "  FAIL (expected CONTEXT WARNING, got: $(echo "$OUTPUT" | head -3))"
    FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR/.model-${CWD_48_KEY}"

# --- Test 48b: Plain current-gen Sonnet (4.6) session model -> 1M window -> no false warning ---
echo "Test 48b: Plain current-gen Sonnet (4.6) session model -> 1M window -> no warning at what used to be 55% of 200K"
create_test_plan
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.model-*

CWD_48B="$TEST_DIR/worktree-48b"
mkdir -p "$CWD_48B"
CWD_48B_KEY=$(compute_session_key "$CWD_48B")

# Create session model file with plain current-gen Sonnet (no [1m] suffix -- 1M is now standard)
printf 'claude-sonnet-4-6\n' > "$PLANS_DIR/.model-${CWD_48B_KEY}"

# 11% of the real 1M window = 110K -- the SAME absolute token count as Test 48's
# 55% of the old, incorrect 200K assumption. Against the correct 1M window this is
# below the warning threshold.
TRANSCRIPT_48B=$(create_transcript_pct 11 "t48b" "claude-sonnet-4-6")

# Set up state file with plan
printf '%s\n%s\n%s\n%s\n%s\n' "sess_48b" "$TRANSCRIPT_48B" "1000" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_48B_KEY}"

# Should NOT trigger context warning (110K / 1M = 11%, below 50%) now that current-gen
# Sonnet correctly resolves to its real 1M window instead of the legacy 200K assumption.
OUTPUT=$(echo '{"prompt":"do something","session_id":"sess_48b","transcript_path":"'"$TRANSCRIPT_48B"'","cwd":"'"$CWD_48B"'"}' | bash "$TEST_DIR/inject-plan.sh")
if [[ -z "$OUTPUT" ]] || ! echo "$OUTPUT" | grep -q "CONTEXT WARNING"; then
    echo "  PASS (no false warning at 11% of the real 1M window)"
    PASS=$((PASS + 1))
else
    echo "  FAIL (expected no CONTEXT WARNING, got: $(echo "$OUTPUT" | head -3))"
    FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR/.model-${CWD_48B_KEY}"

# --- Test 49: enforce-clear with completed plan writes empty plan path in flag and state ---
echo "Test 49: enforce-clear + completed plan -> empty plan path in flag and state"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*

CWD_49="$TEST_DIR/worktree-49"
mkdir -p "$CWD_49"
CWD_49_KEY=$(compute_session_key "$CWD_49")

# Create completed plan (0 pending)
printf '%s\n' '# Completed Plan 49' '' '## Tasks' '' '- [x] Task 1: Done' '- [x] Task 2: Done' > "$PLANS_DIR/completed-plan-49.md"

# Create state file with completed plan
printf '%s\n%s\n%s\n%s\n%s\n' "sess_49" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/completed-plan-49.md" > "$PLANS_DIR/.plan-state-${CWD_49_KEY}"

TRANSCRIPT_49=$(create_transcript_pct 65 "t49")

OUTPUT=$(echo '{"session_id":"sess_49","transcript_path":"'"$TRANSCRIPT_49"'","cwd":"'"$CWD_49"'","stop_hook_active":false}' | bash "$TEST_DIR/enforce-clear.sh" 2>/dev/null)

T49_PASS=true
# Flag file should have empty plan path (line 1)
FLAG_49="$PLANS_DIR/.pending-reload-${CWD_49_KEY}"
if [[ -f "$FLAG_49" ]]; then
    FLAG_PLAN_49=$(sed -n '1p' "$FLAG_49")
    if [[ -n "$FLAG_PLAN_49" ]]; then
        echo "  Flag line 1 should be empty but got: $FLAG_PLAN_49"
        T49_PASS=false
    fi
    FLAG_TYPE_49=$(sed -n '5p' "$FLAG_49")
    if [[ "$FLAG_TYPE_49" != "plan-completed" ]]; then
        echo "  Flag type should be plan-completed but got: $FLAG_TYPE_49"
        T49_PASS=false
    fi
else
    echo "  Flag file not created"
    T49_PASS=false
fi
# State file should also have empty plan path (line 5)
STATE_49="$PLANS_DIR/.plan-state-${CWD_49_KEY}"
if [[ -f "$STATE_49" ]]; then
    STATE_PLAN_49=$(sed -n '5p' "$STATE_49")
    if [[ -n "$STATE_PLAN_49" ]]; then
        echo "  State line 5 should be empty but got: $STATE_PLAN_49"
        T49_PASS=false
    fi
else
    echo "  State file not found"
    T49_PASS=false
fi

if [[ "$T49_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 50: inject-plan plan-mode with existing state file (empty plan) -> ls -t fallback should NOT fire ---
echo "Test 50: inject-plan plan-mode + state file with empty plan -> no ls -t fallback"
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*

CWD_50="$TEST_DIR/worktree-50"
mkdir -p "$CWD_50"
CWD_50_KEY=$(compute_session_key "$CWD_50")

# Create a plan that could be picked up by ls -t
printf '%s\n' '# Decoy Plan 50' '' '## Tasks' '' '- [ ] Task A: Should not be loaded' > "$PLANS_DIR/decoy-plan-50.md"

# Create state file with EMPTY plan path (simulating post-completed state)
printf '%s\n%s\n%s\n%s\n%s\n' "sess_50" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "" > "$PLANS_DIR/.plan-state-${CWD_50_KEY}"

TRANSCRIPT_50=$(create_transcript_pct 10 "t50")

# Run in plan mode (permission_mode=plan)
OUTPUT=$(echo '{"prompt":"do something","session_id":"sess_50","transcript_path":"'"$TRANSCRIPT_50"'","cwd":"'"$CWD_50"'","permission_mode":"plan"}' | bash "$TEST_DIR/inject-plan.sh")

T50_PASS=true
# State file should NOT have adopted the decoy plan
STATE_50="$PLANS_DIR/.plan-state-${CWD_50_KEY}"
if [[ -f "$STATE_50" ]]; then
    STATE_PLAN_50=$(sed -n '5p' "$STATE_50")
    if [[ "$STATE_PLAN_50" == *"decoy-plan-50"* ]]; then
        echo "  State file adopted decoy plan via ls -t fallback (should not happen)"
        T50_PASS=false
    fi
fi

if [[ "$T50_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 51: inject-plan context threshold updating flag to plan-completed writes empty plan path ---
echo "Test 51: inject-plan context threshold + 0 pending -> plan-completed flag with empty plan path"
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*

CWD_51="$TEST_DIR/worktree-51"
mkdir -p "$CWD_51"
CWD_51_KEY=$(compute_session_key "$CWD_51")

# Create completed plan
printf '%s\n' '# Completed Plan 51' '' '## Tasks' '' '- [x] Task 1: Done' > "$PLANS_DIR/completed-plan-51.md"

# Create state file with completed plan
printf '%s\n%s\n%s\n%s\n%s\n' "sess_51" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/completed-plan-51.md" > "$PLANS_DIR/.plan-state-${CWD_51_KEY}"

# Create an existing flag (plan-pending) that should be updated to plan-completed
printf '%s\n%s\n%s\n%s\n%s\n' "$PLANS_DIR/completed-plan-51.md" "sess_51" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_51" "plan-pending" > "$PLANS_DIR/.pending-reload-${CWD_51_KEY}"

TRANSCRIPT_51=$(create_transcript_pct 55 "t51")

# Use permission_mode=plan so the flag survives to the context threshold section
# (without plan mode, the auto-reload path consumes the flag first)
OUTPUT=$(echo '{"prompt":"do something","session_id":"sess_51","transcript_path":"'"$TRANSCRIPT_51"'","cwd":"'"$CWD_51"'","permission_mode":"plan"}' | bash "$TEST_DIR/inject-plan.sh")

T51_PASS=true
FLAG_51="$PLANS_DIR/.pending-reload-${CWD_51_KEY}"
if [[ -f "$FLAG_51" ]]; then
    FLAG_PLAN_51=$(sed -n '1p' "$FLAG_51")
    FLAG_TYPE_51=$(sed -n '5p' "$FLAG_51")
    if [[ -n "$FLAG_PLAN_51" ]]; then
        echo "  Flag plan path should be empty but got: $FLAG_PLAN_51"
        T51_PASS=false
    fi
    if [[ "$FLAG_TYPE_51" != "plan-completed" ]]; then
        echo "  Flag type should be plan-completed but got: $FLAG_TYPE_51"
        T51_PASS=false
    fi
else
    echo "  Flag file not found"
    T51_PASS=false
fi

if [[ "$T51_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 52: on-session-clear defense-in-depth: plan-completed flag with plan path still set -> no-plan path ---
echo "Test 52: on-session-clear defense-in-depth: plan-completed flag with plan path -> no-plan path"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*

CWD_52="$TEST_DIR/worktree-52"
mkdir -p "$CWD_52"
CWD_52_KEY=$(compute_session_key "$CWD_52")

# Create completed plan
printf '%s\n' '# Completed Plan 52' '' '## Tasks' '' '- [x] Task 1: Done' > "$PLANS_DIR/completed-plan-52.md"

# Create state file with completed plan
printf '%s\n%s\n%s\n%s\n%s\n' "sess_52" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/completed-plan-52.md" > "$PLANS_DIR/.plan-state-${CWD_52_KEY}"

# Create flag with plan-completed type BUT still has plan path (legacy or edge case)
printf '%s\n%s\n%s\n%s\n%s\n' "$PLANS_DIR/completed-plan-52.md" "sess_52" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_52" "plan-completed" > "$PLANS_DIR/.pending-reload-${CWD_52_KEY}"

OUTPUT=$(echo '{"cwd":"'"$CWD_52"'"}' | bash "$TEST_DIR/on-session-clear.sh")

T52_PASS=true
# Defense-in-depth should prevent loading the completed plan
if echo "$OUTPUT" | grep -q "Completed Plan 52"; then
    echo "  Defense-in-depth failed: loaded completed plan content"
    T52_PASS=false
fi
# Should still show resume signal (flag exists)
if ! assert_contains "52" "$OUTPUT" "resume"; then
    T52_PASS=false
fi

if [[ "$T52_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 53: on-plan-exit with completed plan writes empty plan path in flag ---
echo "Test 53: on-plan-exit.sh with completed plan writes empty plan path"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*

CWD_53="$TEST_DIR/worktree-53"
mkdir -p "$CWD_53"
CWD_53_KEY=$(compute_session_key "$CWD_53")

# Create completed plan (0 pending)
printf '%s\n' '# Completed Plan 53' '' '## Tasks' '' '- [x] Task 1: Done' '- [x] Task 2: Done' > "$PLANS_DIR/completed-plan-53.md"

# Create state file with completed plan
printf '%s\n%s\n%s\n%s\n%s\n' "sess_53" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/completed-plan-53.md" > "$PLANS_DIR/.plan-state-${CWD_53_KEY}"

OUTPUT=$(echo '{"session_id":"sess_53","cwd":"'"$CWD_53"'"}' | bash "$TEST_DIR/on-plan-exit.sh")

T53_PASS=true
FLAG_53="$PLANS_DIR/.pending-reload-${CWD_53_KEY}"
if [[ -f "$FLAG_53" ]]; then
    FLAG_PLAN_53=$(sed -n '1p' "$FLAG_53")
    if [[ -n "$FLAG_PLAN_53" ]]; then
        echo "  Flag line 1 should be empty but got: $FLAG_PLAN_53"
        T53_PASS=false
    fi
    FLAG_TYPE_53=$(sed -n '5p' "$FLAG_53")
    if [[ "$FLAG_TYPE_53" != "plan-completed" ]]; then
        echo "  Flag type should be plan-completed but got: $FLAG_TYPE_53"
        T53_PASS=false
    fi
else
    echo "  Flag file not created"
    T53_PASS=false
fi

if [[ "$T53_PASS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 54: on-plan-exit with NO state file at all -> exits without writing reload flag ---
echo 'Test 54: on-plan-exit with no state file -> no flag file created'
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*

CWD_54="$TEST_DIR/worktree-54"
mkdir -p "$CWD_54"
CWD_54_KEY=$(compute_session_key "$CWD_54")

# Create a plan file but NO state file (simulates first ExitPlanMode for brand-new plan)
printf '%s\n' '# Brand New Plan 54' '' '## Tasks' '' '- [ ] Task 1: Pending' > "$PLANS_DIR/brand-new-plan-54.md"

# No .plan-state-* file exists for this CWD

OUTPUT=$(echo '{"session_id":"sess_54","cwd":"'"$CWD_54"'"}' | bash "$TEST_DIR/on-plan-exit.sh" 2>/dev/null)

T54_PASS=true
# Flag file should NOT be created (no state file = no active plan knowledge)
FLAG_54="$PLANS_DIR/.pending-reload-${CWD_54_KEY}"
if [[ -f "$FLAG_54" ]]; then
    echo '  Flag file was created despite no state file (should not happen)'
    T54_PASS=false
fi

if [[ "$T54_PASS" == "true" ]]; then
    echo '  PASS'
    PASS=$((PASS + 1))
else
    echo '  FAIL'
    FAIL=$((FAIL + 1))
fi

# --- Test 57: memory-restore, single fresh matching flag -> directive + consumed ---
echo "Test 57: memory-restore: 1 fresh matching flag -> MEMORY RESTORE directive, flag consumed"
CWD_57="$TEST_DIR/worktree-57"
mkdir -p "$CWD_57"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_57="$PLANS_DIR/.pending-memory-restore-20260718T000000-11111"
printf '%s\n%s\n%s\n%s\n' "sess_57" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_57" "checkpoint-57" > "$MR_FLAG_57"
OUTPUT=$(echo '{"cwd":"'"$CWD_57"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "57" "$OUTPUT" "MEMORY RESTORE" && \
   assert_contains "57" "$OUTPUT" "checkpoint-57" && \
   assert_not_contains "57" "$OUTPUT" "checkpoints for this directory" && \
   assert_file_not_exists "57" "$MR_FLAG_57"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 58: memory-restore, two matching flags -> collision question, both consumed ---
echo "Test 58: memory-restore: 2 matching flags -> collision directive lists both, asks, consumes both"
CWD_58="$TEST_DIR/worktree-58"
mkdir -p "$CWD_58"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_58A="$PLANS_DIR/.pending-memory-restore-20260718T000001-22222"
MR_FLAG_58B="$PLANS_DIR/.pending-memory-restore-20260718T000002-33333"
printf '%s\n%s\n%s\n%s\n' "sess_58a" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_58" "checkpoint-58-older" > "$MR_FLAG_58A"
printf '%s\n%s\n%s\n%s\n' "sess_58b" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_58" "checkpoint-58-newer" > "$MR_FLAG_58B"
OUTPUT=$(echo '{"cwd":"'"$CWD_58"'"}' | bash "$TEST_DIR/on-session-clear.sh")
T58_CLAIMED=$(find "$PLANS_DIR" -name '.mr-claimed.*' | wc -l | tr -d ' ')
if assert_contains "58" "$OUTPUT" "checkpoints for this directory" && \
   assert_contains "58" "$OUTPUT" "checkpoint-58-older" && \
   assert_contains "58" "$OUTPUT" "checkpoint-58-newer" && \
   assert_contains "58" "$OUTPUT" "AskUserQuestion" && \
   assert_file_not_exists "58" "$MR_FLAG_58A" && \
   assert_file_not_exists "58" "$MR_FLAG_58B" && \
   [[ "$T58_CLAIMED" == "0" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 59: memory-restore, foreign-cwd flag -> untouched, no directive ---
echo "Test 59: memory-restore: fresh flag for a DIFFERENT cwd -> untouched, no directive"
CWD_59="$TEST_DIR/worktree-59"
CWD_59_OTHER="$TEST_DIR/worktree-59-other"
mkdir -p "$CWD_59" "$CWD_59_OTHER"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_59="$PLANS_DIR/.pending-memory-restore-20260718T000003-44444"
printf '%s\n%s\n%s\n%s\n' "sess_59" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_59_OTHER" "checkpoint-59" > "$MR_FLAG_59"
OUTPUT=$(echo '{"cwd":"'"$CWD_59"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_not_contains "59" "$OUTPUT" "MEMORY RESTORE" && \
   assert_file_exists "59" "$MR_FLAG_59"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$MR_FLAG_59"

# --- Test 60: memory-restore, stale matching flag -> consumed, no directive ---
echo "Test 60: memory-restore: stale (>24h) matching flag -> consumed, no directive"
CWD_60="$TEST_DIR/worktree-60"
mkdir -p "$CWD_60"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_60="$PLANS_DIR/.pending-memory-restore-20260716T000000-55555"
printf '%s\n%s\n%s\n%s\n' "sess_60" "2026-07-16T00:00:00+0900" "$CWD_60" "checkpoint-60" > "$MR_FLAG_60"
touch -t 202607160000 "$MR_FLAG_60"
OUTPUT=$(echo '{"cwd":"'"$CWD_60"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_not_contains "60" "$OUTPUT" "MEMORY RESTORE" && \
   assert_file_not_exists "60" "$MR_FLAG_60"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 61: memory-restore, writer-to-reader end-to-end via write-reload-flag.sh ---
echo "Test 61: memory-restore: real write-reload-flag.sh output is discovered by the hook"
CWD_61="$TEST_DIR/worktree-61"
mkdir -p "$CWD_61"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
# Fail-closed: without the substitution the writer would write into the
# REAL ~/.claude/plans and arm a spurious restore on the user's next /clear.
if patch_lib_common; then
    T61_SUBST_OK=true
else
    echo "  ASSERT FAILED: PLANS_DIR substitution did not take effect in test lib-plan.sh"
    T61_SUBST_OK=false
fi
cp "$SCRIPT_DIR/scripts/write-reload-flag.sh" "$TEST_DIR/write-reload-flag.sh"
chmod +x "$TEST_DIR/write-reload-flag.sh"
WRITE_OUT=""
if [[ "$T61_SUBST_OK" == "true" ]]; then
    WRITE_OUT=$(cd "$CWD_61" && bash "$TEST_DIR/write-reload-flag.sh" "checkpoint-61-e2e")
fi
T61_FLAG=$(find "$PLANS_DIR" -name '.pending-memory-restore-*' | head -1)
T61_KEY=$([[ -n "$T61_FLAG" ]] && sed -n '5p' "$T61_FLAG" || echo "MISSING")
T61_WANT=$(compute_session_key "$(cd "$CWD_61" && pwd -P)")
OUTPUT=$(echo '{"cwd":"'"$CWD_61"'"}' | bash "$TEST_DIR/on-session-clear.sh")
MR_LEFT=$(find "$PLANS_DIR" -name '.pending-memory-restore-*' | wc -l | tr -d ' ')
if [[ "$T61_SUBST_OK" == "true" ]] && \
   [[ "$T61_KEY" == "$T61_WANT" ]] && \
   assert_contains "61" "$WRITE_OUT" "Wrote reload flag" && \
   assert_contains "61" "$OUTPUT" "MEMORY RESTORE" && \
   assert_contains "61" "$OUTPUT" "checkpoint-61-e2e" && \
   [[ "$MR_LEFT" == "0" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    [[ "$T61_KEY" != "$T61_WANT" ]] && echo "  ASSERT FAILED: line 5 was '$T61_KEY', expected '$T61_WANT'"
    [[ "$MR_LEFT" != "0" ]] && echo "  ASSERT FAILED: expected 0 leftover flags, found $MR_LEFT"
    FAIL=$((FAIL + 1))
fi

# --- Test 62: memory-restore, concurrent hooks -> exactly one restore directive ---
echo "Test 62: memory-restore: two concurrent hooks, one flag -> exactly one directive (atomic claim)"
CWD_62="$TEST_DIR/worktree-62"
mkdir -p "$CWD_62"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.*
MR_FLAG_62="$PLANS_DIR/.pending-memory-restore-20260718T000004-66666"
printf '%s\n%s\n%s\n%s\n' "sess_62" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_62" "checkpoint-62" > "$MR_FLAG_62"
OUT_62A_FILE="$TEST_DIR/t62-a.out"
OUT_62B_FILE="$TEST_DIR/t62-b.out"
echo '{"cwd":"'"$CWD_62"'"}' | bash "$TEST_DIR/on-session-clear.sh" > "$OUT_62A_FILE" 2>/dev/null &
T62_PID_A=$!
echo '{"cwd":"'"$CWD_62"'"}' | bash "$TEST_DIR/on-session-clear.sh" > "$OUT_62B_FILE" 2>/dev/null &
T62_PID_B=$!
wait "$T62_PID_A"; T62_STATUS_A=$?
wait "$T62_PID_B"; T62_STATUS_B=$?
T62_DIRECTIVES=$(cat "$OUT_62A_FILE" "$OUT_62B_FILE" | grep -c "MEMORY RESTORE" || true)
T62_LEFT=$(find "$PLANS_DIR" \( -name '.pending-memory-restore-*' -o -name '.mr-claimed.*' \) | wc -l | tr -d ' ')
if [[ "$T62_STATUS_A" == "0" ]] && [[ "$T62_STATUS_B" == "0" ]] && \
   [[ "$T62_DIRECTIVES" == "1" ]] && [[ "$T62_LEFT" == "0" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    echo "  ASSERT FAILED: expected both hooks exit 0 (got $T62_STATUS_A/$T62_STATUS_B), exactly 1 directive (got $T62_DIRECTIVES), 0 leftover files (got $T62_LEFT)"
    FAIL=$((FAIL + 1))
fi

# --- Test 63: memory-restore, collision ordering -> newest first + headless newest label ---
echo "Test 63: memory-restore: collision with distinct mtimes -> newest first, headless picks newest"
CWD_63="$TEST_DIR/worktree-63"
mkdir -p "$CWD_63"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_63A="$PLANS_DIR/.pending-memory-restore-20260718T000005-77777"
MR_FLAG_63B="$PLANS_DIR/.pending-memory-restore-20260718T000006-88888"
printf '%s\n%s\n%s\n%s\n' "sess_63a" "2026-07-18T01:00:00+0900" "$CWD_63" "checkpoint-63-older" > "$MR_FLAG_63A"
printf '%s\n%s\n%s\n%s\n' "sess_63b" "2026-07-18T02:00:00+0900" "$CWD_63" "checkpoint-63-newer" > "$MR_FLAG_63B"
touch -t "$(date -v-3H +%Y%m%d%H%M 2>/dev/null || date -d '3 hours ago' +%Y%m%d%H%M)" "$MR_FLAG_63A"
touch -t "$(date -v-1H +%Y%m%d%H%M 2>/dev/null || date -d '1 hour ago' +%Y%m%d%H%M)" "$MR_FLAG_63B"
OUTPUT=$(echo '{"cwd":"'"$CWD_63"'"}' | bash "$TEST_DIR/on-session-clear.sh")
T63_AFTER_NEWER=${OUTPUT#*checkpoint-63-newer}
if assert_contains "63" "$OUTPUT" 'restore the newest (`checkpoint-63-newer`)' && \
   assert_contains "63" "$T63_AFTER_NEWER" "checkpoint-63-older"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (newest-first ordering or headless-newest label broken)"
    FAIL=$((FAIL + 1))
fi

# --- Test 64: memory-restore + plan reload flag coexist -> both directives ---
echo "Test 64: memory-restore flag + plan reload flag -> output contains BOTH directives"
create_test_plan
CWD_64="$TEST_DIR/worktree-64"
mkdir -p "$CWD_64"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.pending-reload-*
CWD_64_KEY=$(compute_session_key "$CWD_64")
printf '%s\n%s\n%s\n%s\n%s\n' "sess_64" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLANS_DIR/test-plan.md" > "$PLANS_DIR/.plan-state-${CWD_64_KEY}"
printf '%s\n%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_64" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_64" "plan-pending" > "$PLANS_DIR/.pending-reload-${CWD_64_KEY}"
MR_FLAG_64="$PLANS_DIR/.pending-memory-restore-20260718T000007-99999"
printf '%s\n%s\n%s\n%s\n' "sess_64" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_64" "checkpoint-64" > "$MR_FLAG_64"
OUTPUT=$(echo '{"cwd":"'"$CWD_64"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "64" "$OUTPUT" "MEMORY RESTORE" && \
   assert_contains "64" "$OUTPUT" "POST-CLEAR RESUME" && \
   assert_file_not_exists "64" "$MR_FLAG_64"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR"/.pending-reload-* "$PLANS_DIR"/.plan-state-*

# --- Test 65: memory-restore, >7-day foreign flag -> swept ---
echo "Test 65: memory-restore: 8-day-old foreign-cwd flag -> swept, and the sweep is REPORTED (no restore directive)"
CWD_65="$TEST_DIR/worktree-65"
CWD_65_OTHER="$TEST_DIR/worktree-65-other"
mkdir -p "$CWD_65" "$CWD_65_OTHER"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_65="$PLANS_DIR/.pending-memory-restore-20260710T000000-10101"
printf '%s\n%s\n%s\n%s\n' "sess_65" "2026-07-10T00:00:00+0900" "$CWD_65_OTHER" "checkpoint-65" > "$MR_FLAG_65"
touch -t "$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)" "$MR_FLAG_65"
OUTPUT=$(echo '{"cwd":"'"$CWD_65"'"}' | bash "$TEST_DIR/on-session-clear.sh")
# The sweep count is the ONLY audit trace this path leaves — the file is gone, so
# an unreported sweep is indistinguishable from a flag that never existed.
if assert_not_contains "65" "$OUTPUT" "MEMORY RESTORE" && \
   assert_contains "65" "$OUTPUT" "1 removed as older than 7 days" && \
   assert_file_not_exists "65" "$MR_FLAG_65"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 66: memory-restore, mixed fresh + stale matching flags -> single directive, both consumed ---
echo "Test 66: memory-restore: fresh + stale matching flags -> single-checkpoint directive (no collision), both consumed"
CWD_66="$TEST_DIR/worktree-66"
mkdir -p "$CWD_66"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_66A="$PLANS_DIR/.pending-memory-restore-20260716T000001-20202"
MR_FLAG_66B="$PLANS_DIR/.pending-memory-restore-20260718T000008-30303"
printf '%s\n%s\n%s\n%s\n' "sess_66a" "2026-07-16T00:00:01+0900" "$CWD_66" "checkpoint-66-stale" > "$MR_FLAG_66A"
printf '%s\n%s\n%s\n%s\n' "sess_66b" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_66" "checkpoint-66-fresh" > "$MR_FLAG_66B"
touch -t "$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M)" "$MR_FLAG_66A"
OUTPUT=$(echo '{"cwd":"'"$CWD_66"'"}' | bash "$TEST_DIR/on-session-clear.sh")
# The stale flag matched, so it was consumed and destroyed. Its label is therefore
# listed, under an explicit "consumed WITHOUT restoring" verdict: withholding it
# would leave no handle for the manual read_memory() that is the only way back to
# that checkpoint. The restore directive must still name only the fresh one.
if assert_contains "66" "$OUTPUT" "checkpoint: checkpoint-66-fresh" && \
   assert_not_contains "66" "$OUTPUT" "checkpoints for this directory" && \
   assert_contains "66" "$OUTPUT" "checkpoint-66-stale" && \
   assert_contains "66" "$OUTPUT" "consumed WITHOUT restoring" && \
   assert_file_not_exists "66" "$MR_FLAG_66A" && \
   assert_file_not_exists "66" "$MR_FLAG_66B"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 67: PLANS_DIR resolves via CLAUDE_CONFIG_DIR, falls back to $HOME/.claude when unset ---
# Every other test sources a sed-patched lib-plan.sh whose PLANS_DIR line is
# overwritten wholesale, so none of them exercise this expression itself.
# Source the REAL lib-plan.sh directly, with a throwaway HOME so a broken
# fallback can't touch anything real.
echo "Test 67: PLANS_DIR respects CLAUDE_CONFIG_DIR, falls back to \$HOME/.claude when unset or empty"
FAKE_HOME="$TEST_DIR/fake-home-67"
mkdir -p "$FAKE_HOME"
RESOLVED_UNSET=$(env -u CLAUDE_CONFIG_DIR HOME="$FAKE_HOME" bash -c 'source "'"$LIB_COMMON"'"; printf %s "$PLANS_DIR"')
RESOLVED_SET=$(env CLAUDE_CONFIG_DIR="$TEST_DIR/fake-profile-67" HOME="$FAKE_HOME" bash -c 'source "'"$LIB_COMMON"'"; printf %s "$PLANS_DIR"')
RESOLVED_EMPTY=$(env CLAUDE_CONFIG_DIR="" HOME="$FAKE_HOME" bash -c 'source "'"$LIB_COMMON"'"; printf %s "$PLANS_DIR"')
if [[ "$RESOLVED_UNSET" == "$FAKE_HOME/.claude/plans" ]] && \
   [[ "$RESOLVED_SET" == "$TEST_DIR/fake-profile-67/plans" ]] && \
   [[ "$RESOLVED_EMPTY" == "$FAKE_HOME/.claude/plans" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (unset -> '$RESOLVED_UNSET', set -> '$RESOLVED_SET', empty -> '$RESOLVED_EMPTY')"
    FAIL=$((FAIL + 1))
fi

# --- Test 68: the 3 manually-invoked scripts (list/load/plan-status) pick up
# CLAUDE_CONFIG_DIR via their new `source lib-plan.sh` -- these are never
# copied into $TEST_DIR by create_patched_scripts(), so this runs the REAL
# scripts directly against a throwaway profile directory containing one
# real plan file, and checks each picks the override up rather than the
# default $HOME/.claude/plans.
echo "Test 68: list-plans.sh/load-plan.sh/plan-status.sh resolve PLANS_DIR via CLAUDE_CONFIG_DIR"
PROFILE_68="$TEST_DIR/fake-profile-68"
mkdir -p "$PROFILE_68/plans"
FAKE_HOME_68="$TEST_DIR/fake-home-68"
mkdir -p "$FAKE_HOME_68/.claude/plans"
printf '%s\n' '# Test 68 Plan' '' '- [x] Task A' '- [ ] Task B' > "$PROFILE_68/plans/test68-plan.md"
LIST_OUT=$(HOME="$FAKE_HOME_68" CLAUDE_CONFIG_DIR="$PROFILE_68" bash "$SCRIPT_DIR/scripts/list-plans.sh" 2>&1)
LOAD_OUT=$(HOME="$FAKE_HOME_68" CLAUDE_CONFIG_DIR="$PROFILE_68" bash "$SCRIPT_DIR/scripts/load-plan.sh" test68-plan 2>&1)
STATUS_OUT=$(HOME="$FAKE_HOME_68" CLAUDE_CONFIG_DIR="$PROFILE_68" bash "$SCRIPT_DIR/scripts/plan-status.sh" test68-plan 2>&1)
if assert_contains "68" "$LIST_OUT" "test68-plan" && \
   assert_contains "68" "$LOAD_OUT" "Test 68 Plan" && \
   assert_contains "68" "$STATUS_OUT" "test68-plan.md"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 69: smith-ctx-claude/scripts/enforce-clear.sh FLAGS_DIR stays in
# sync with lib-plan.sh PLANS_DIR. That sibling hook hand-duplicates the
# directory expression (different skill directory, can't source lib-plan.sh),
# so nothing else in this suite exercises it -- compare the two expressions
# textually so an independent drift fails loudly here.
echo "Test 69: smith-ctx-claude enforce-clear.sh FLAGS_DIR expression matches lib-plan.sh PLANS_DIR"
CTX_ENFORCE="$SCRIPT_DIR/../smith-ctx-claude/scripts/enforce-clear.sh"
LIB_EXPR=$(grep -m1 '^PLANS_DIR=' "$SCRIPT_DIR/scripts/lib-plan.sh" | sed 's/^PLANS_DIR=//')
CTX_EXPR=$(grep -m1 '^FLAGS_DIR=' "$CTX_ENFORCE" | sed 's/^FLAGS_DIR=//')
if [[ -n "$LIB_EXPR" ]] && [[ "$CTX_EXPR" == "$LIB_EXPR" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (lib-plan.sh -> '$LIB_EXPR', enforce-clear.sh -> '$CTX_EXPR')"
    FAIL=$((FAIL + 1))
fi

# --- The reporting contract: a scan whose result is discarded must say what it saw.
#     Numbering is carried by each test below, not by this header — a hand-kept
#     range here rots the moment another scenario is appended. ---

# --- Test 70: zero match, but a fresh flag from another worktree of the SAME repo ---
echo "Test 70: memory-restore: same-repo flag, no exact match -> selectable candidate, NOT consumed"
REPO_70="$TEST_DIR/repo-70"
WT_70="$TEST_DIR/repo-70-worktree"
mkdir -p "$REPO_70"
git -C "$REPO_70" init -q 2>/dev/null
git -C "$REPO_70" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
git -C "$REPO_70" worktree add -q --detach "$WT_70" HEAD 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_70="$PLANS_DIR/.pending-memory-restore-20260815T000070-70070"
printf '%s\n%s\n%s\n%s\n' "sess_70" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$WT_70" "checkpoint-70" > "$MR_FLAG_70"
OUTPUT=$(echo '{"cwd":"'"$REPO_70"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ -d "$WT_70" ]] && \
   assert_contains "70" "$OUTPUT" "Checkpoint candidates seen at this /clear" && \
   assert_contains "70" "$OUTPUT" "same repository, selectable" && \
   assert_contains "70" "$OUTPUT" "checkpoint-70" && \
   assert_contains "70" "$OUTPUT" "20260815T000070-70070" && \
   assert_contains "70" "$OUTPUT" "AskUserQuestion" && \
   assert_contains "70" "$OUTPUT" "rm -f $PLANS_DIR/.pending-memory-restore-" && \
   assert_contains "70" "$OUTPUT" "Signal: resume" && \
   assert_not_contains "70" "$OUTPUT" "ACTION REQUIRED - MEMORY RESTORE" && \
   assert_file_exists "70" "$MR_FLAG_70"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 71: zero match, only a flag from an unrelated location -> shown, never offered ---
echo "Test 71: memory-restore: foreign-repo flag only -> shown only, no offer, not consumed, fresh-start"
CWD_71="$TEST_DIR/worktree-71"
CWD_71_FOREIGN="$TEST_DIR/elsewhere-71"
mkdir -p "$CWD_71" "$CWD_71_FOREIGN"
# BOTH sides must be repositories for the "different repository" verdict to be a
# checked claim. Leaving this directory outside any repository lets the test pass
# while the code says "another repository" about something that is not one: the
# fixture, not the code, would be carrying the false claim.
git -C "$CWD_71_FOREIGN" init -q 2>/dev/null
git -C "$CWD_71" init -q 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_71="$PLANS_DIR/.pending-memory-restore-20260815T000071-71071"
printf '%s\n%s\n%s\n%s\n' "sess_71" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_71_FOREIGN" "checkpoint-71" > "$MR_FLAG_71"
OUTPUT=$(echo '{"cwd":"'"$CWD_71"'"}' | bash "$TEST_DIR/on-session-clear.sh")
# Another repository's flag is COUNTED, never printed: its path and label belong to
# that project and nothing here permits acting on them.
if assert_contains "71" "$OUTPUT" "1 recorded in another repository" && \
   assert_contains "71" "$OUTPUT" "deliberately all you get" && \
   assert_not_contains "71" "$OUTPUT" "checkpoint-71" && \
   assert_not_contains "71" "$OUTPUT" "$CWD_71_FOREIGN" && \
   assert_contains "71" "$OUTPUT" "nothing to offer" && \
   assert_not_contains "71" "$OUTPUT" "AskUserQuestion" && \
   assert_not_contains "71" "$OUTPUT" "20260815T000071-71071" && \
   assert_contains "71" "$OUTPUT" "Signal: fresh-start" && \
   assert_file_exists "71" "$MR_FLAG_71"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 72: no flags at all -> the block must NOT appear (silence is correct here) ---
echo "Test 72: memory-restore: no flags at all -> no candidates block"
CWD_72="$TEST_DIR/worktree-72"
mkdir -p "$CWD_72"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
OUTPUT=$(echo '{"cwd":"'"$CWD_72"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_not_contains "72" "$OUTPUT" "Checkpoint candidates" && \
   assert_not_contains "72" "$OUTPUT" "Checkpoint flags at this /clear" && \
   assert_not_contains "72" "$OUTPUT" "MEMORY RESTORE"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 73: more fresh candidates than the row cap -> capped, remainder counted ---
echo "Test 73: memory-restore: 6 listable flags -> 5 rows listed, 1 counted as not shown"
CWD_73="$TEST_DIR/worktree-73"
mkdir -p "$CWD_73"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
# Unreachable recorded paths, not foreign ones: a flag belonging to another
# repository is now counted rather than listed, so it could not exercise the cap.
for n in 1 2 3 4 5 6; do
    printf '%s\n%s\n%s\n%s\n' "sess_73_$n" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$TEST_DIR/never-created-73-$n" "checkpoint-73-$n" \
        > "$PLANS_DIR/.pending-memory-restore-20260815T000073-7307$n"
done
OUTPUT=$(echo '{"cwd":"'"$CWD_73"'"}' | bash "$TEST_DIR/on-session-clear.sh")
# Count OCCURRENCES, not lines: the hook's output is a single JSON string whose
# row separators are the two characters \n, so every row shares one physical line.
# Count on "recorded", which only a listed row carries — the verdict wording also
# appears in the explanatory sentence below the list and would inflate the count.
T73_ROWS=$(printf '%s' "$OUTPUT" | grep -o -- '— recorded ' | wc -l | tr -d ' ')
if [[ "$T73_ROWS" == "5" ]] && \
   assert_contains "73" "$OUTPUT" "1 more not shown"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (listed rows: $T73_ROWS, expected 5)"
    FAIL=$((FAIL + 1))
fi

# --- Test 74: only stale flags -> one reporting line, never silence ---
echo "Test 74: memory-restore: only a stale foreign flag -> one-line report, flag kept"
CWD_74="$TEST_DIR/worktree-74"
CWD_74_FOREIGN="$TEST_DIR/elsewhere-74"
mkdir -p "$CWD_74" "$CWD_74_FOREIGN"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_74="$PLANS_DIR/.pending-memory-restore-20260815T000074-74074"
printf '%s\n%s\n%s\n%s\n' "sess_74" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_74_FOREIGN" "checkpoint-74" > "$MR_FLAG_74"
# Two days old: past the 24h freshness window, well inside the 7-day sweep. This
# must be RELATIVE — a hardcoded date drifts past the sweep window and the test
# would then exercise the sweep instead of the stale-report path it is written for.
T74_STAMP=$(date -v-2d +%Y%m%d%H%M 2>/dev/null) || T74_STAMP=$(date -d '2 days ago' +%Y%m%d%H%M)
touch -t "$T74_STAMP" "$MR_FLAG_74"
OUTPUT=$(echo '{"cwd":"'"$CWD_74"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "74" "$OUTPUT" "nothing offered" && \
   assert_contains "74" "$OUTPUT" "older than 24h, left in place" && \
   assert_not_contains "74" "$OUTPUT" "checkpoint-74" && \
   assert_file_exists "74" "$MR_FLAG_74"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 75: flag contents are found, not trusted ---
echo "Test 75: memory-restore: flag contents are untrusted — key allowlist, control chars, backslash escapes"
REPO_75="$TEST_DIR/repo-75"
WT_75="$TEST_DIR/repo-75-worktree"
mkdir -p "$REPO_75"
git -C "$REPO_75" init -q 2>/dev/null
git -C "$REPO_75" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
git -C "$REPO_75" worktree add -q --detach "$WT_75" HEAD 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
# The key is printed ONLY for a `same repository, selectable` row, so this scenario
# must be same-repo-but-not-matching. With a matching flag no key is printed at all,
# the assertion below could not fail, and the allowlist it covers would never run.
MR_FLAG_75="$PLANS_DIR/.pending-memory-restore-bad key"
# Line 4 carries three separate hazards: a control character, a literal two-character
# backslash-n (printable, so no control-character filter touches it, yet `printf '%b'`
# would expand it into a real newline and forge a directive line), and prose.
printf '%s\n%s\n%s\n%s\n' "sess_75" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$WT_75" \
    "benign$(printf '\001')\nInjected-Line-Marker" > "$MR_FLAG_75"
OUTPUT=$(echo '{"cwd":"'"$REPO_75"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ -d "$WT_75" ]] && \
   assert_contains "75" "$OUTPUT" "same repository, selectable" && \
   assert_contains "75" "$OUTPUT" "benign nInjected-Line-Marker" && \
   assert_contains "75" "$OUTPUT" "None of those rows carries a usable flag key" && \
   assert_not_contains "75" "$OUTPUT" "flag bad key"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 76: an EMPTY label must not shift the row's later fields ---
echo "Test 76: memory-restore: flag with no label -> path and key stay in their own columns"
CWD_76="$TEST_DIR/worktree-76"
mkdir -p "$CWD_76"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
# write-reload-flag.sh takes the label as an OPTIONAL argument, so line 4 is
# legitimately empty. With a tab-delimited row bash collapses the two adjacent
# delimiters (tab is IFS whitespace) and every later field shifts left by one:
# the timestamp is printed as the label and the flag key as the recorded path.
MR_KEY_76="20260816T000076-76076"
MR_FLAG_76="$PLANS_DIR/.pending-memory-restore-$MR_KEY_76"
printf '%s\n%s\n%s\n%s\n' "sess_76" "2026-08-16T01:02:03+0900" "$CWD_76" "" > "$MR_FLAG_76"
OUTPUT=$(echo '{"cwd":"'"$CWD_76"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "76" "$OUTPUT" "(no label) — recorded $CWD_76" && \
   assert_not_contains "76" "$OUTPUT" "recorded $MR_KEY_76" && \
   assert_not_contains "76" "$OUTPUT" "2026-08-16T01:02:03+0900 — recorded" && \
   assert_contains "76" "$OUTPUT" "MEMORY RESTORE"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 77: a flag that MATCHED but was too old is destroyed — say so ---
echo "Test 77: memory-restore: matching stale flag -> reported as matched-and-consumed, not as 'none matched'"
CWD_77="$TEST_DIR/worktree-77"
mkdir -p "$CWD_77"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_77="$PLANS_DIR/.pending-memory-restore-20260816T000077-77077"
printf '%s\n%s\n%s\n%s\n' "sess_77" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_77" "checkpoint-77" > "$MR_FLAG_77"
T77_STAMP=$(date -v-2d +%Y%m%d%H%M 2>/dev/null) || T77_STAMP=$(date -d '2 days ago' +%Y%m%d%H%M)
touch -t "$T77_STAMP" "$MR_FLAG_77"
OUTPUT=$(echo '{"cwd":"'"$CWD_77"'"}' | bash "$TEST_DIR/on-session-clear.sh")
# This flag DID match — that is why it was consumed rather than left for another
# session. Reporting it as an ordinary old flag hides the one case where the user
# irreversibly loses the pointer to a checkpoint whose memory still exists.
# The same directive must not also say nothing was consumed — one was destroyed.
if assert_not_contains "77" "$OUTPUT" "no flag was consumed" && \
   assert_contains "77" "$OUTPUT" "MATCHED but expired, consumed WITHOUT restoring" && \
   assert_contains "77" "$OUTPUT" "checkpoint-77" && \
   assert_contains "77" "$OUTPUT" "DID match this session" && \
   assert_file_not_exists "77" "$MR_FLAG_77" && \
   assert_not_contains "77" "$OUTPUT" "ACTION REQUIRED - MEMORY RESTORE"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 78: a matching flag the hook cannot claim must be REPORTED, not just logged ---
echo "Test 78: memory-restore: unclaimable matching flag -> reported in context, kept on disk"
CWD_78="$TEST_DIR/worktree-78"
mkdir -p "$CWD_78"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_78="$PLANS_DIR/.pending-memory-restore-20260816T000078-78078"
printf '%s\n%s\n%s\n%s\n' "sess_78" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_78" "checkpoint-78" > "$MR_FLAG_78"
# A read-only PLANS_DIR makes the claiming `mv` fail. stderr is NOT a channel into
# the session: additionalContext is the only one, so a warning there alone would be
# invisible exactly when a matching checkpoint failed to restore.
if [[ "$(id -u)" == "0" ]]; then
    echo "  SKIP (root ignores the missing write bit, so the claim would succeed)"
    PASS=$((PASS + 1))
else
    trap 'chmod 700 "$PLANS_DIR" 2>/dev/null; cleanup' EXIT
    chmod 500 "$PLANS_DIR"
    OUTPUT=$(echo '{"cwd":"'"$CWD_78"'"}' | bash "$TEST_DIR/on-session-clear.sh" 2>/dev/null)
    chmod 700 "$PLANS_DIR"
    trap cleanup EXIT
    if assert_contains "78" "$OUTPUT" "could NOT be claimed" && \
       assert_contains "78" "$OUTPUT" "checkpoint-78" && \
       assert_contains "78" "$OUTPUT" "filesystem error" && \
       assert_file_exists "78" "$MR_FLAG_78"; then
        echo "  PASS"
        PASS=$((PASS + 1))
    else
        echo "  FAIL"
        FAIL=$((FAIL + 1))
    fi
fi

# --- Test 79: an unreachable recorded path is "unverifiable", never "different repository" ---
echo "Test 79: memory-restore: removed-worktree path -> scope unverifiable, no false repository claim"
CWD_79="$TEST_DIR/worktree-79"
mkdir -p "$CWD_79"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_79="$PLANS_DIR/.pending-memory-restore-20260816T000079-79079"
# The directory is never created: this is a checkpoint armed inside a worktree that
# has since been removed, which is the headline scenario for this whole thread.
printf '%s\n%s\n%s\n%s\n' "sess_79" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$TEST_DIR/gone-79" "checkpoint-79" > "$MR_FLAG_79"
OUTPUT=$(echo '{"cwd":"'"$CWD_79"'"}' | bash "$TEST_DIR/on-session-clear.sh")
# The key names a flag to delete; an unverifiable row is not offerable, so
# printing its key would name something the agent must not act on.
if assert_not_contains "79" "$OUTPUT" "flag 20260816T000079-79079" && \
   assert_contains "79" "$OUTPUT" "scope unverifiable, recorded path unreachable" && \
   assert_contains "79" "$OUTPUT" "were NOT checked" && \
   assert_contains "79" "$OUTPUT" "checkpoint-79" && \
   assert_not_contains "79" "$OUTPUT" "different repository, shown only" && \
   assert_file_exists "79" "$MR_FLAG_79"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 80: the row cap must never evict the only actionable candidate ---
echo "Test 80: memory-restore: 5 newer foreign flags + 1 older same-repo flag -> the actionable row survives the cap"
REPO_80="$TEST_DIR/repo-80"
WT_80="$TEST_DIR/repo-80-worktree"
FOREIGN_80="$TEST_DIR/elsewhere-80"
mkdir -p "$REPO_80" "$FOREIGN_80"
git -C "$REPO_80" init -q 2>/dev/null
git -C "$REPO_80" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
git -C "$REPO_80" worktree add -q --detach "$WT_80" HEAD 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
# The offerable row is the OLDEST, so ordering by time alone drops it past the cap
# while the directive still tells the agent to offer "those rows only".
MR_FLAG_80="$PLANS_DIR/.pending-memory-restore-20260816T000080-80080"
printf '%s\n%s\n%s\n%s\n' "sess_80" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$WT_80" "checkpoint-80-actionable" > "$MR_FLAG_80"
touch -t "$(date -v-20H +%Y%m%d%H%M 2>/dev/null || date -d '20 hours ago' +%Y%m%d%H%M)" "$MR_FLAG_80"
# Newer, listable, and LOWER priority than the offerable row: unreachable paths.
# Flags from another repository would not do — those are counted, not listed, so
# they exert no pressure on the cap.
for n in 1 2 3 4 5; do
    printf '%s\n%s\n%s\n%s\n' "sess_80_$n" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$FOREIGN_80/never-created-$n" "checkpoint-80-other-$n" \
        > "$PLANS_DIR/.pending-memory-restore-20260816T000080-8008$n"
done
OUTPUT=$(echo '{"cwd":"'"$REPO_80"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ -d "$WT_80" ]] && \
   assert_contains "80" "$OUTPUT" "checkpoint-80-actionable" && \
   assert_contains "80" "$OUTPUT" "same repository, selectable" && \
   assert_contains "80" "$OUTPUT" "more not shown"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 81: a LABEL that reads like a verdict must not be counted as one ---
echo "Test 81: memory-restore: label reading 'MATCHES this session' is not mistaken for a verdict"
REPO_81="$TEST_DIR/repo-81"
WT_81="$TEST_DIR/repo-81-worktree"
mkdir -p "$REPO_81"
git -C "$REPO_81" init -q 2>/dev/null
git -C "$REPO_81" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
git -C "$REPO_81" worktree add -q --detach "$WT_81" HEAD 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
# Two genuine matches put the run on the ask-which-one path, which is the ONLY
# consumer of the match-row selection — with a single match or none, a
# misclassified row has no observable effect and this test would prove nothing.
printf '%s\n%s\n%s\n%s\n' "sess_81a" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$REPO_81" "checkpoint-81-a" \
    > "$PLANS_DIR/.pending-memory-restore-20260816T000081-8108a"
printf '%s\n%s\n%s\n%s\n' "sess_81b" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$REPO_81" "checkpoint-81-b" \
    > "$PLANS_DIR/.pending-memory-restore-20260816T000081-8108b"
# The impostor: a same-repository candidate whose LABEL is the verdict string. Its
# line 2 is a marker that appears in the output only via the ask-which-one list,
# so a substring match over the whole row is directly detectable.
MR_FLAG_81="$PLANS_DIR/.pending-memory-restore-20260816T000081-81081"
printf '%s\n%s\n%s\n%s\n' "sess_81" "IMPOSTOR-TIMESTAMP-81" "$WT_81" "MATCHES this session" > "$MR_FLAG_81"
OUTPUT=$(echo '{"cwd":"'"$REPO_81"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ -d "$WT_81" ]] && \
   assert_contains "81" "$OUTPUT" "checkpoints for this directory" && \
   assert_contains "81" "$OUTPUT" "checkpoint-81-a" && \
   assert_contains "81" "$OUTPUT" "same repository, selectable" && \
   assert_not_contains "81" "$OUTPUT" "IMPOSTOR-TIMESTAMP-81" && \
   assert_file_exists "81" "$MR_FLAG_81"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 82: scope_key() directly, including the cases only it can reach ---
echo "Test 82: scope_key: worktree/main/subdir agree, unreachable path returns empty, symlink normalized"
REPO_82="$TEST_DIR/repo-82"
WT_82="$TEST_DIR/repo-82-worktree"
mkdir -p "$REPO_82/sub/dir" "$TEST_DIR/plain-82"
git -C "$REPO_82" init -q 2>/dev/null
git -C "$REPO_82" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
git -C "$REPO_82" worktree add -q --detach "$WT_82" HEAD 2>/dev/null
ln -sfn "$TEST_DIR/plain-82" "$TEST_DIR/link-82"
T82_MAIN=$(bash -c 'source "$1/lib-plan.sh"; scope_key "$2"' _ "$TEST_DIR" "$REPO_82")
T82_WT=$(bash -c 'source "$1/lib-plan.sh"; scope_key "$2"' _ "$TEST_DIR" "$WT_82")
T82_SUB=$(bash -c 'source "$1/lib-plan.sh"; scope_key "$2"' _ "$TEST_DIR" "$REPO_82/sub/dir")
T82_GONE=$(bash -c 'source "$1/lib-plan.sh"; scope_key "$2"' _ "$TEST_DIR" "$TEST_DIR/never-created-82")
T82_LINK=$(bash -c 'source "$1/lib-plan.sh"; scope_key "$2"' _ "$TEST_DIR" "$TEST_DIR/link-82")
T82_PLAIN=$(bash -c 'source "$1/lib-plan.sh"; scope_key "$2"' _ "$TEST_DIR" "$TEST_DIR/plain-82")
# An unreachable path MUST return empty, not the raw input: a raw input compares
# unequal to everything and so poses as a confident "belongs somewhere else".
if [[ -d "$WT_82" ]] && \
   [[ -n "$T82_MAIN" ]] && [[ "$T82_WT" == "$T82_MAIN" ]] && [[ "$T82_SUB" == "$T82_MAIN" ]] && \
   [[ -z "$T82_GONE" ]] && \
   [[ "$T82_LINK" == "$T82_PLAIN" ]] && [[ -n "$T82_PLAIN" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (main=$T82_MAIN worktree=$T82_WT subdir=$T82_SUB gone=[$T82_GONE] link=$T82_LINK plain=$T82_PLAIN)"
    FAIL=$((FAIL + 1))
fi

# --- Test 83: a recorded path with trailing whitespace must still match ---
echo "Test 83: memory-restore: cwd with a trailing space still matches (IFS= read, not plain read)"
CWD_83="$TEST_DIR/worktree 83 "
mkdir -p "$CWD_83"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_83="$PLANS_DIR/.pending-memory-restore-20260816T000083-83083"
# A bare `read` into one variable strips leading and trailing IFS whitespace, which
# the `sed -n '3p'` it replaced did not. The flag would stop matching, and the
# trimmed path would then fail to `cd`, so the row would claim the recorded
# directory is unreachable while the hook is standing in it.
printf '%s\n%s\n%s\n%s\n' "sess_83" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_83" "checkpoint-83" > "$MR_FLAG_83"
OUTPUT=$(echo '{"cwd":"'"$CWD_83"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "83" "$OUTPUT" "MATCHES this session" && \
   assert_contains "83" "$OUTPUT" "checkpoint: checkpoint-83" && \
   assert_not_contains "83" "$OUTPUT" "scope unverifiable" && \
   assert_file_not_exists "83" "$MR_FLAG_83"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 84: a truncated flag is malformed, not a removed worktree ---
echo "Test 84: memory-restore: flag with no recorded path -> malformed, not 'path unreachable'"
CWD_84="$TEST_DIR/worktree-84"
mkdir -p "$CWD_84"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_84="$PLANS_DIR/.pending-memory-restore-20260816T000084-84084"
printf 'only-one-line\n' > "$MR_FLAG_84"
OUTPUT=$(echo '{"cwd":"'"$CWD_84"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "84" "$OUTPUT" "malformed flag, no recorded path" && \
   assert_not_contains "84" "$OUTPUT" "recorded path unreachable" && \
   assert_file_exists "84" "$MR_FLAG_84"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 85: an unclaimable flag is reported but is NOT work waiting ---
echo "Test 85: memory-restore: unclaimable matching flag -> reported, Signal stays fresh-start"
CWD_85="$TEST_DIR/worktree-85"
mkdir -p "$CWD_85"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_85="$PLANS_DIR/.pending-memory-restore-20260816T000085-85085"
printf '%s\n%s\n%s\n%s\n' "sess_85" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_85" "checkpoint-85" > "$MR_FLAG_85"
if [[ "$(id -u)" == "0" ]]; then
    echo "  SKIP (root ignores the missing write bit, so the claim would succeed)"
    PASS=$((PASS + 1))
else
  
  
    trap 'chmod 700 "$PLANS_DIR" 2>/dev/null; cleanup' EXIT
    chmod 500 "$PLANS_DIR"
    OUTPUT=$(echo '{"cwd":"'"$CWD_85"'"}' | bash "$TEST_DIR/on-session-clear.sh" 2>/dev/null)
    chmod 700 "$PLANS_DIR"
    trap cleanup EXIT
  
  
    if assert_contains "85" "$OUTPUT" "could NOT be claimed" && \
       assert_contains "85" "$OUTPUT" "Signal: fresh-start" && \
       assert_file_exists "85" "$MR_FLAG_85"; then
        echo "  PASS"
        PASS=$((PASS + 1))
    else
        echo "  FAIL"
        FAIL=$((FAIL + 1))
    fi
fi

# --- Test 86: one directory under two spellings still matches ---
echo "Test 86: memory-restore: flag recorded under a symlinked spelling still MATCHES"
CWD_86="$TEST_DIR/worktree-86"
mkdir -p "$CWD_86"
CWD_86_PHYS=$(cd "$CWD_86" && pwd -P)
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_86="$PLANS_DIR/.pending-memory-restore-20260816T000086-86086"
# The writer records its logical $PWD; the hook receives whatever spelling the
# session has. A raw string compare misses when they differ — which is the exact
# silent no-match this whole change exists to remove.
printf '%s\n%s\n%s\n%s\n' "sess_86" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_86" "checkpoint-86" > "$MR_FLAG_86"
if [[ "$CWD_86_PHYS" == "$CWD_86" ]]; then
    echo "  SKIP (sandbox path has no symlinked prefix on this machine)"
    PASS=$((PASS + 1))
else
    OUTPUT=$(echo '{"cwd":"'"$CWD_86_PHYS"'"}' | bash "$TEST_DIR/on-session-clear.sh")
    if assert_contains "86" "$OUTPUT" "MATCHES this session" && \
       assert_contains "86" "$OUTPUT" "checkpoint: checkpoint-86" && \
       assert_file_not_exists "86" "$MR_FLAG_86"; then
        echo "  PASS"
        PASS=$((PASS + 1))
    else
        echo "  FAIL"
        FAIL=$((FAIL + 1))
    fi
fi

# --- Test 87: an unreadable mtime must KEEP the flag, never age it into the sweep ---
echo "Test 87: memory-restore: stat failure treats the flag as fresh and keeps it"
CWD_87="$TEST_DIR/worktree-87"
CWD_87_OTHER="$TEST_DIR/elsewhere-87"
mkdir -p "$CWD_87" "$CWD_87_OTHER" "$TEST_DIR/shim-87"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_87="$PLANS_DIR/.pending-memory-restore-20260816T000087-87087"
printf '%s\n%s\n%s\n%s\n' "sess_87" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_87_OTHER" "checkpoint-87" > "$MR_FLAG_87"
touch -t "$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)" "$MR_FLAG_87"
# A stat that fails establishes no age at all, and a flag with no established age is
# never swept. The outcome this test pins is the same one the old substitute-now rule
# produced — the pointer survives — but the reason is now that nothing was measured,
# not that the failure was read as a fresh timestamp.
printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/shim-87/stat"
chmod +x "$TEST_DIR/shim-87/stat"
OUTPUT=$(echo '{"cwd":"'"$CWD_87"'"}' | PATH="$TEST_DIR/shim-87:$PATH" bash "$TEST_DIR/on-session-clear.sh")
if assert_file_exists "87" "$MR_FLAG_87" && \
   assert_not_contains "87" "$OUTPUT" "removed as older than 7 days"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 88: malformed flags must not evict the offerable row from the cap ---
echo "Test 88: memory-restore: 5 malformed flags + 1 same-repo flag -> the offerable row survives"
REPO_88="$TEST_DIR/repo-88"
WT_88="$TEST_DIR/repo-88-worktree"
mkdir -p "$REPO_88"
git -C "$REPO_88" init -q 2>/dev/null
git -C "$REPO_88" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
git -C "$REPO_88" worktree add -q --detach "$WT_88" HEAD 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
printf '%s\n%s\n%s\n%s\n' "sess_88" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$WT_88" "checkpoint-88-offerable" \
    > "$PLANS_DIR/.pending-memory-restore-20260816T000088-88088"
for n in 1 2 3 4 5; do
    printf 'truncated-88-%s\n' "$n" > "$PLANS_DIR/.pending-memory-restore-20260816T000088-8808$n"
done
OUTPUT=$(echo '{"cwd":"'"$REPO_88"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ -d "$WT_88" ]] && \
   assert_contains "88" "$OUTPUT" "checkpoint-88-offerable" && \
   assert_contains "88" "$OUTPUT" "same repository, selectable"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 89: a flag the hook cannot read is counted, not called malformed ---
echo "Test 89: memory-restore: unreadable flag file -> counted as unreadable, not 'malformed'"
CWD_89="$TEST_DIR/worktree-89"
mkdir -p "$CWD_89"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_89="$PLANS_DIR/.pending-memory-restore-20260816T000089-89089"
printf '%s\n%s\n%s\n%s\n' "sess_89" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_89" "checkpoint-89" > "$MR_FLAG_89"
if [[ "$(id -u)" == "0" ]]; then
    echo "  SKIP (root reads regardless of mode)"
    PASS=$((PASS + 1))
else
    chmod 000 "$MR_FLAG_89"
    OUTPUT=$(echo '{"cwd":"'"$CWD_89"'"}' | bash "$TEST_DIR/on-session-clear.sh" 2>/dev/null)
    chmod 600 "$MR_FLAG_89"
  
  
    if assert_contains "89" "$OUTPUT" "could NOT be read (permissions)" && \
       assert_not_contains "89" "$OUTPUT" "malformed flag" && \
       assert_file_exists "89" "$MR_FLAG_89"; then
        echo "  PASS"
        PASS=$((PASS + 1))
    else
        echo "  FAIL"
        FAIL=$((FAIL + 1))
    fi
fi

# --- Test 90: an irreversible row outranks recoverable ones at the cap ---
echo "Test 90: memory-restore: destroyed-pointer row survives the cap against newer selectable rows"
REPO_90="$TEST_DIR/repo-90"
WT_90="$TEST_DIR/repo-90-worktree"
mkdir -p "$REPO_90"
git -C "$REPO_90" init -q 2>/dev/null
git -C "$REPO_90" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
git -C "$REPO_90" worktree add -q --detach "$WT_90" HEAD 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
# Seven newer selectable rows would fill the five-row cap on time alone. Their
# flags SURVIVE and are offered again at the next /clear; the expired matched flag
# is deleted by this very run, so its label is the only thing left of it.
for n in 1 2 3 4 5 6 7; do
    printf '%s\n%s\n%s\n%s\n' "sess_90_$n" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$WT_90" "checkpoint-90-sel-$n" \
        > "$PLANS_DIR/.pending-memory-restore-20260816T000090-9009$n"
done
MR_FLAG_90="$PLANS_DIR/.pending-memory-restore-20260816T000090-90090"
printf '%s\n%s\n%s\n%s\n' "sess_90" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$REPO_90" "checkpoint-90-DESTROYED" > "$MR_FLAG_90"
touch -t "$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M)" "$MR_FLAG_90"
OUTPUT=$(echo '{"cwd":"'"$REPO_90"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ -d "$WT_90" ]] && \
   assert_contains "90" "$OUTPUT" "checkpoint-90-DESTROYED" && \
   assert_contains "90" "$OUTPUT" "consumed WITHOUT restoring" && \
   assert_file_not_exists "90" "$MR_FLAG_90"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 91: a readable but NON-SEARCHABLE plans directory must not read as empty ---
echo "Test 91: memory-restore: mode-600 PLANS_DIR is reported, not silently treated as having no flags"
CWD_91="$TEST_DIR/worktree-91"
mkdir -p "$CWD_91"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_91="$PLANS_DIR/.pending-memory-restore-20260816T000091-91091"
printf '%s\n%s\n%s\n%s\n' "sess_91" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_91" "checkpoint-91" > "$MR_FLAG_91"
if [[ "$(id -u)" == "0" ]]; then
    echo "  SKIP (root searches a directory regardless of the execute bit)"
    PASS=$((PASS + 1))
else
  
  
  
    trap 'chmod 700 "$PLANS_DIR" 2>/dev/null; cleanup' EXIT
    chmod 600 "$PLANS_DIR"
    OUTPUT=$(echo '{"cwd":"'"$CWD_91"'"}' | bash "$TEST_DIR/on-session-clear.sh" 2>/dev/null)
    chmod 700 "$PLANS_DIR"
    trap cleanup EXIT
    if assert_contains "91" "$OUTPUT" "could NOT be inspected" && \
       assert_not_contains "91" "$OUTPUT" "Signal: resume" && \
       assert_file_exists "91" "$MR_FLAG_91"; then
        echo "  PASS"
        PASS=$((PASS + 1))
    else
        echo "  FAIL"
        FAIL=$((FAIL + 1))
    fi
fi

# --- Test 92: when the hook's OWN cwd cannot be resolved, assert nothing ---
echo "Test 92: memory-restore: unresolvable hook cwd -> withheld, never a repository claim"
CWD_92="$TEST_DIR/worktree-92"
mkdir -p "$CWD_92"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_92="$PLANS_DIR/.pending-memory-restore-20260816T000092-92092"
printf '%s\n%s\n%s\n%s\n' "sess_92" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_92" "checkpoint-92" > "$MR_FLAG_92"
# scope_key returns empty for the hook's OWN cwd here, so no flag can be checked
# against this session at all. Calling the difference "different repository" would
# assert what was never checked; printing the row would put a path and a label into
# a session that could not establish they are its own. Both are withheld and
# counted, and the flag is left on disk for the user to read directly. Printing the
# label here instead would publish another repository's path and label whenever this
# branch is reached with a foreign flag present — see Test 94, which pins that.
OUTPUT=$(echo '{"cwd":"'"$TEST_DIR/never-created-92"'"}' | bash "$TEST_DIR/on-session-clear.sh")
# Two assertions, not one: the phrase "own directory could not be resolved" appears in
# BOTH the tail count and the legend, so either line could be deleted and the other
# would satisfy a single assertion. Each string below appears in exactly one of them.
if assert_contains "92" "$OUTPUT" "left unclassified because" && \
   assert_contains "92" "$OUTPUT" "withholding is not a claim" && \
   assert_not_contains "92" "$OUTPUT" "checkpoint-92" && \
   assert_not_contains "92" "$OUTPUT" "$CWD_92" && \
   assert_not_contains "92" "$OUTPUT" "different repository" && \
   assert_not_contains "92" "$OUTPUT" "scope unverifiable" && \
   assert_file_exists "92" "$MR_FLAG_92"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 93: a HIGHER-priority verdict must not evict the only selectable row ---
# Test 80 pins the same guarantee against LOWER-priority pressure (unreachable
# paths, priority 5), which the sort alone already handles. Priority 2
# (`MATCHED but expired`) outranks priority 3, so only higher-priority pressure
# reaches the reserved display slot.
echo "Test 93: memory-restore: 5 expired-matched rows must not evict the only selectable row"
REPO_93="$TEST_DIR/repo-93"
WT_93="$TEST_DIR/repo-93-worktree"
mkdir -p "$REPO_93"
git -C "$REPO_93" init -q 2>/dev/null
git -C "$REPO_93" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
git -C "$REPO_93" worktree add -q --detach "$WT_93" HEAD 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
OLD_93=$(date -v-30H +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || date -d '30 hours ago' +%Y-%m-%dT%H:%M:%S%z)
STAMP_93=$(date -v-30H +%Y%m%d%H%M 2>/dev/null || date -d '30 hours ago' +%Y%m%d%H%M)
for n in 1 2 3 4 5; do
    printf '%s\n%s\n%s\n%s\n' "sess_93_$n" "$OLD_93" "$REPO_93" "checkpoint-93-expired-$n" \
        > "$PLANS_DIR/.pending-memory-restore-20260816T000093-9309$n"
    touch -t "$STAMP_93" "$PLANS_DIR/.pending-memory-restore-20260816T000093-9309$n"
done
MR_FLAG_93="$PLANS_DIR/.pending-memory-restore-20260816T120093-93093"
printf '%s\n%s\n%s\n%s\n' "sess_93" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$WT_93" "checkpoint-93-selectable" > "$MR_FLAG_93"
OUTPUT=$(echo '{"cwd":"'"$REPO_93"'"}' | bash "$TEST_DIR/on-session-clear.sh")
# The notes tell the agent to offer "those rows only" and to delete the chosen
# row's flag, so BOTH the row and its key must be on screen, not merely counted.
# The reserved slot must be SPENT, not added: five rows in, five rows out. Without
# this count the cap could stay at five while the reservation also fires, printing
# six rows, and every other assertion here would still hold.
ROWS_93=$(printf '%s' "$OUTPUT" | grep -o 'n- checkpoint-93' | wc -l | tr -d ' ')
if [[ -d "$WT_93" ]] && \
   assert_contains "93" "$OUTPUT" "checkpoint-93-selectable" && \
   assert_contains "93" "$OUTPUT" "same repository, selectable" && \
   assert_contains "93" "$OUTPUT" "flag 20260816T120093-93093" && \
   assert_contains "93" "$OUTPUT" "AskUserQuestion" && \
   [[ "$ROWS_93" -eq 5 ]] && \
   assert_file_exists "93" "$MR_FLAG_93"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (rows printed: ${ROWS_93}, expected 5)"
    FAIL=$((FAIL + 1))
fi

# --- Test 94: an unresolvable hook cwd must not publish another repository's identifiers ---
# The withholding must be a property of the classification, not a side effect of this
# session's own cwd resolving. Control pair: the SAME flag, two hook cwds.
echo "Test 94: memory-restore: foreign flag stays withheld even when the hook cwd is unresolvable"
REPO_94="$TEST_DIR/repo-94"
OTHER_94="$TEST_DIR/other-client-repo-94"
mkdir -p "$REPO_94" "$OTHER_94"
git -C "$OTHER_94" init -q 2>/dev/null
git -C "$REPO_94" init -q 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
# A label is free text people fill with a ticket key or a codename, so it is treated
# as identifying material, not as a description.
MR_FLAG_94="$PLANS_DIR/.pending-memory-restore-20260816T000094-94094"
printf '%s\n%s\n%s\n%s\n' "sess_94" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$OTHER_94" "TICKET-9999-codename-94" > "$MR_FLAG_94"
# TWO flags, not one: the count is the entire deliverable of the withheld band, and
# with a single flag a hardcoded "1" would satisfy every assertion below.
OTHER2_94="$TEST_DIR/other-client-repo-94b"
mkdir -p "$OTHER2_94"
git -C "$OTHER2_94" init -q 2>/dev/null
MR_FLAG2_94="$PLANS_DIR/.pending-memory-restore-20260816T000094-94095"
printf '%s\n%s\n%s\n%s\n' "sess_94b" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$OTHER2_94" "TICKET-8888-codename-94b" > "$MR_FLAG2_94"
OUT_94_OK=$(echo '{"cwd":"'"$REPO_94"'"}' | bash "$TEST_DIR/on-session-clear.sh")
OUT_94_BAD=$(echo '{"cwd":"'"$TEST_DIR/never-created-94"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "94" "$OUT_94_OK" "2 recorded in another repository" && \
   assert_not_contains "94" "$OUT_94_OK" "TICKET-8888-codename-94b" && \
   assert_not_contains "94" "$OUT_94_OK" "TICKET-9999-codename-94" && \
   assert_not_contains "94" "$OUT_94_BAD" "TICKET-9999-codename-94" && \
   assert_not_contains "94" "$OUT_94_BAD" "$OTHER_94" && \
   assert_contains "94" "$OUT_94_BAD" "2 left unclassified because" && \
   assert_contains "94" "$OUT_94_BAD" "withholding is not a claim" && \
   assert_file_exists "94" "$MR_FLAG_94" && \
   assert_file_exists "94" "$MR_FLAG2_94"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 95: two directories inside no repository are "outside this scope", not "another repository" ---
echo "Test 95: memory-restore: non-repository directories -> outside this scope, no repository claim"
PLAIN_95_HERE="$TEST_DIR/plain-95-here"
PLAIN_95_THERE="$TEST_DIR/plain-95-there"
PLAIN_95_THERE2="$TEST_DIR/plain-95-there-b"
mkdir -p "$PLAIN_95_HERE" "$PLAIN_95_THERE" "$PLAIN_95_THERE2"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_95="$PLANS_DIR/.pending-memory-restore-20260816T000095-95095"
printf '%s\n%s\n%s\n%s\n' "sess_95" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLAIN_95_THERE" "checkpoint-95" > "$MR_FLAG_95"
# Two, so the reported number is load-bearing rather than a constant that happens to
# match: the count is all this band ever gives the reader.
MR_FLAG2_95="$PLANS_DIR/.pending-memory-restore-20260816T000095-95096"
printf '%s\n%s\n%s\n%s\n' "sess_95b" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PLAIN_95_THERE2" "checkpoint-95b" > "$MR_FLAG2_95"
# Neither directory is inside a repository, so "a different repository" names
# something neither side has. Only the difference of scope was established, and the
# withholding applies on the same rule.
OUTPUT=$(echo '{"cwd":"'"$PLAIN_95_HERE"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "95" "$OUTPUT" "2 recorded outside this scope, in a directory" && \
   assert_contains "95" "$OUTPUT" "the only established fact is that the scopes differ" && \
   assert_not_contains "95" "$OUTPUT" "recorded in another repository" && \
   assert_not_contains "95" "$OUTPUT" "checkpoint-95" && \
   assert_not_contains "95" "$OUTPUT" "$PLAIN_95_THERE" && \
   assert_file_exists "95" "$MR_FLAG_95"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 96: a git that refuses to answer must not become a repository claim ---
# `git rev-parse` exits 128 both for "not a repository" and for a refusal by a git
# that started (`safe.directory` dubious ownership, damaged repository), and its
# messages are translated, so the exit status cannot separate them. A missing `git`
# executable is a different status entirely -- command-not-found, 127 -- which is why
# the shim below exits 128 rather than simply being absent. scope_key()
# settles it with a filesystem fact: a `.git` above the path means a repository is
# there and only the resolution failed.
echo "Test 96: memory-restore: git refusing to answer -> withheld, never a repository claim"
REPO_96="$TEST_DIR/repo-96"
mkdir -p "$REPO_96/sub" "$TEST_DIR/shim-96"
git -C "$REPO_96" init -q 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_96="$PLANS_DIR/.pending-memory-restore-20260816T000096-96096"
printf '%s\n%s\n%s\n%s\n' "sess_96" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$REPO_96/sub" "checkpoint-96" > "$MR_FLAG_96"
printf '#!/bin/sh\nexit 128\n' > "$TEST_DIR/shim-96/git"
chmod +x "$TEST_DIR/shim-96/git"
OUTPUT=$(echo '{"cwd":"'"$REPO_96"'"}' | PATH="$TEST_DIR/shim-96:$PATH" bash "$TEST_DIR/on-session-clear.sh")
# The flag genuinely belongs to this repository. Reporting it as another
# repository's would withhold it under a claim that was never checked, and the
# accompanying line would tell the reader not to go looking for it.
if assert_not_contains "96" "$OUTPUT" "recorded in another repository" && \
   assert_not_contains "96" "$OUTPUT" "recorded outside this scope" && \
   assert_contains "96" "$OUTPUT" "left unclassified because" && \
   assert_contains "96" "$OUTPUT" "withholding is not a claim" && \
   assert_file_exists "96" "$MR_FLAG_96"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 97: an inaccessible directory ABOVE PLANS_DIR must not read as "no checkpoints" ---
# `-d "$PLANS_DIR"` is false both when the directory is genuinely absent and when a
# parent denies the search, and only the first justifies silence. This test uses its
# own sandbox because the parent has to be locked, and the real PLANS_DIR's parent is
# the directory holding the scripts under test.
echo "Test 97: memory-restore: unsearchable parent of PLANS_DIR is reported, not silent"
if [[ "$(id -u)" == "0" ]]; then
    echo "  SKIP (root searches a directory regardless of the execute bit)"
    PASS=$((PASS + 1))
else
    CFG_97="$TEST_DIR/cfg-97"
    PLANS_97="$CFG_97/plans"
    CWD_97="$TEST_DIR/worktree-97"
    mkdir -p "$PLANS_97" "$CWD_97" "$TEST_DIR/t97"
    sed -e 's|^PLANS_DIR=.*|PLANS_DIR="'"$PLANS_97"'"|' "$SCRIPT_DIR/scripts/lib-plan.sh" > "$TEST_DIR/t97/lib-plan.sh"
    cp "$SCRIPT_DIR/scripts/on-session-clear.sh" "$TEST_DIR/t97/on-session-clear.sh"
    printf '%s\n%s\n%s\n%s\n' "sess_97" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_97" "checkpoint-97" \
        > "$PLANS_97/.pending-memory-restore-20260816T000097-97097"
    trap 'chmod 700 "$CFG_97" 2>/dev/null; cleanup' EXIT
    chmod 600 "$CFG_97"
    OUTPUT=$(echo '{"cwd":"'"$CWD_97"'"}' | bash "$TEST_DIR/t97/on-session-clear.sh" 2>/dev/null)
    chmod 700 "$CFG_97"
    trap cleanup EXIT
  
  
  
  
    OUT_RECOVERED_97=$(echo '{"cwd":"'"$CWD_97"'"}' | bash "$TEST_DIR/t97/on-session-clear.sh" 2>/dev/null)
    rm -rf "$PLANS_97"
    OUT_GONE_97=$(echo '{"cwd":"'"$CWD_97"'"}' | bash "$TEST_DIR/t97/on-session-clear.sh" 2>/dev/null)
    if assert_contains "97" "$OUTPUT" "could NOT be inspected" && \
       assert_not_contains "97" "$OUT_GONE_97" "could NOT be inspected" && \
       assert_contains "97" "$OUT_RECOVERED_97" "checkpoint-97"; then
        echo "  PASS"
        PASS=$((PASS + 1))
    else
        echo "  FAIL"
        FAIL=$((FAIL + 1))
    fi
fi

# --- Test 98: rows are ordered by priority, and no external sort is consulted ---
# `sort` was the last fork in this path, and its result was captured unchecked: a
# failure emptied the whole row set AFTER the matched flags had been consumed, so
# the block printed a header with no rows and the labels were gone silently.
echo "Test 98: memory-restore: priority ordering holds with sort(1) broken"
REPO_98="$TEST_DIR/repo-98"
WT_98="$TEST_DIR/repo-98-worktree"
mkdir -p "$REPO_98" "$TEST_DIR/shim-98"
git -C "$REPO_98" init -q 2>/dev/null
git -C "$REPO_98" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
git -C "$REPO_98" worktree add -q --detach "$WT_98" HEAD 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
# One matching flag (priority 1) and one same-repository flag (priority 3): the
# order between them is what the replaced sort key decided.
# The glob returns these in filename order, and the SELECTABLE one is named first on
# purpose: if the fixture let scan order agree with priority order, the assertion
# below would hold even with the ordering removed entirely, and would pin nothing.
printf '%s\n%s\n%s\n%s\n' "sess_98b" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$WT_98" "checkpoint-98-selectable" \
    > "$PLANS_DIR/.pending-memory-restore-20260816T000098-98001"
printf '%s\n%s\n%s\n%s\n' "sess_98a" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$REPO_98" "checkpoint-98-match" \
    > "$PLANS_DIR/.pending-memory-restore-20260816T000098-98002"
printf '#!/bin/sh\nexit 2\n' > "$TEST_DIR/shim-98/sort"
chmod +x "$TEST_DIR/shim-98/sort"
OUTPUT=$(echo '{"cwd":"'"$REPO_98"'"}' | PATH="$TEST_DIR/shim-98:$PATH" bash "$TEST_DIR/on-session-clear.sh")
# Offset by truncation, not by line: the hook emits one JSON line, so a line-number
# comparison would call both rows equal, and a per-line column offset would only be
# comparable by accident. The prefix length before each label is exact either way.
PRE_MATCH_98="${OUTPUT%%checkpoint-98-match*}"
PRE_SEL_98="${OUTPUT%%checkpoint-98-selectable*}"
if [[ -d "$WT_98" ]] && \
   assert_contains "98" "$OUTPUT" "checkpoint-98-match" && \
   assert_contains "98" "$OUTPUT" "checkpoint-98-selectable" && \
   [[ "${#PRE_MATCH_98}" -lt "${#PRE_SEL_98}" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (match at ${#PRE_MATCH_98}, selectable at ${#PRE_SEL_98})"
    FAIL=$((FAIL + 1))
fi

# --- Tests 99-100: the per-verdict notes must reach ALL THREE outcome branches ---
# The notes are appended in all three outcome branches. Covering only the zero-match
# append leaves the other two free to lose it, and a single match would then silence
# every explanation while still printing the rows the explanations describe.
echo "Test 99: memory-restore: a single match still carries the notes block"
REPO_99="$TEST_DIR/repo-99"
mkdir -p "$REPO_99"
git -C "$REPO_99" init -q 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
printf '%s\n%s\n%s\n%s\n' "sess_99" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$REPO_99" "checkpoint-99" \
    > "$PLANS_DIR/.pending-memory-restore-20260816T000099-99099"
printf 'only-one-line\n' > "$PLANS_DIR/.pending-memory-restore-20260816T000099-99098"
OUTPUT=$(echo '{"cwd":"'"$REPO_99"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "99" "$OUTPUT" "ACTION REQUIRED - MEMORY RESTORE (checkpoint: checkpoint-99)" && \
   assert_contains "99" "$OUTPUT" "malformed flag, no recorded path" && \
   assert_contains "99" "$OUTPUT" "are corrupt or truncated flag files"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

echo "Test 100: memory-restore: several matches still carry the notes block"
REPO_100="$TEST_DIR/repo-100"
mkdir -p "$REPO_100"
git -C "$REPO_100" init -q 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
printf '%s\n%s\n%s\n%s\n' "sess_100a" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$REPO_100" "checkpoint-100-a" \
    > "$PLANS_DIR/.pending-memory-restore-20260816T000100-10001"
printf '%s\n%s\n%s\n%s\n' "sess_100b" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$REPO_100" "checkpoint-100-b" \
    > "$PLANS_DIR/.pending-memory-restore-20260816T000100-10002"
printf 'only-one-line\n' > "$PLANS_DIR/.pending-memory-restore-20260816T000100-10003"
OUTPUT=$(echo '{"cwd":"'"$REPO_100"'"}' | bash "$TEST_DIR/on-session-clear.sh")
# The header promises `(label — saved at)`. Asserting the label alone is satisfied by
# the candidates block ABOVE, which also carries it — so the collision list can have
# its fields swapped or shifted and the assertion still holds.
if assert_contains "100" "$OUTPUT" "2 checkpoints for this directory" && \
   assert_contains "100" "$OUTPUT" "n- checkpoint-100-a — 2026-" && \
   assert_contains "100" "$OUTPUT" "n- checkpoint-100-b — 2026-" && \
   assert_contains "100" "$OUTPUT" "are corrupt or truncated flag files"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 101: the unclaimable note names the directory to fix ---
# Tests 78 and 85 match text that comes from the ROW verdict, so the note itself
# — the only line that says what to DO about it — was unpinned.
echo "Test 101: memory-restore: an unclaimable match explains which directory to fix"
if [[ "$(id -u)" == "0" ]]; then
    echo "  SKIP (root writes a directory regardless of the write bit)"
    PASS=$((PASS + 1))
else
    CWD_101="$TEST_DIR/worktree-101"
    mkdir -p "$CWD_101"
    rm -f "$PLANS_DIR"/.pending-memory-restore-*
    MR_FLAG_101="$PLANS_DIR/.pending-memory-restore-20260816T000101-10101"
    printf '%s\n%s\n%s\n%s\n' "sess_101" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_101" "checkpoint-101" > "$MR_FLAG_101"
    trap 'chmod 700 "$PLANS_DIR" 2>/dev/null; cleanup' EXIT
    chmod 500 "$PLANS_DIR"
    OUTPUT=$(echo '{"cwd":"'"$CWD_101"'"}' | bash "$TEST_DIR/on-session-clear.sh" 2>/dev/null)
    chmod 700 "$PLANS_DIR"
    trap cleanup EXIT
    if assert_contains "101" "$OUTPUT" "could NOT be claimed" && \
       assert_contains "101" "$OUTPUT" "Check the permissions on" && \
       assert_file_exists "101" "$MR_FLAG_101"; then
        echo "  PASS"
        PASS=$((PASS + 1))
    else
        echo "  FAIL"
        FAIL=$((FAIL + 1))
    fi
fi

# --- Test 102: a destroyed pointer the cap could not show must be counted and said ---
echo "Test 102: memory-restore: expired-matched rows past the cap are counted as GONE labels"
CWD_102="$TEST_DIR/worktree-102"
mkdir -p "$CWD_102"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
OLD_102=$(date -v-30H +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || date -d '30 hours ago' +%Y-%m-%dT%H:%M:%S%z)
STAMP_102=$(date -v-30H +%Y%m%d%H%M 2>/dev/null || date -d '30 hours ago' +%Y%m%d%H%M)
for n in 1 2 3 4 5 6 7; do
    printf '%s\n%s\n%s\n%s\n' "sess_102_$n" "$OLD_102" "$CWD_102" "checkpoint-102-$n" \
        > "$PLANS_DIR/.pending-memory-restore-20260816T000102-1020$n"
    touch -t "$STAMP_102" "$PLANS_DIR/.pending-memory-restore-20260816T000102-1020$n"
done
OUTPUT=$(echo '{"cwd":"'"$CWD_102"'"}' | bash "$TEST_DIR/on-session-clear.sh")
# Seven expired matches, five slots: two labels are destroyed AND unprintable, and
# saying "their labels are in the list above" would then be false.
if assert_contains "102" "$OUTPUT" "2 more not shown, 2 of them destroyed pointers" && \
   assert_contains "102" "$OUTPUT" "those labels are GONE" && \
   assert_not_contains "102" "$OUTPUT" "Their labels are in the list above"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 103: a name matching the glob that cannot be opened is counted, not skipped ---
echo "Test 103: memory-restore: dangling symlink and directory sharing the flag prefix are counted"
CWD_103="$TEST_DIR/worktree-103"
mkdir -p "$CWD_103"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
ln -s "$TEST_DIR/never-created-103" "$PLANS_DIR/.pending-memory-restore-20260816T000103-10301"
mkdir -p "$PLANS_DIR/.pending-memory-restore-20260816T000103-10302"
OUTPUT=$(echo '{"cwd":"'"$CWD_103"'"}' | bash "$TEST_DIR/on-session-clear.sh")
rm -rf "$PLANS_DIR/.pending-memory-restore-20260816T000103-10302" "$PLANS_DIR/.pending-memory-restore-20260816T000103-10301"
if assert_contains "103" "$OUTPUT" "2 matched the flag name but could NOT be opened"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 104: a flag lost to a concurrent hook is NOT a filesystem error ---
# The two share a failing `mv` and are told apart by whether the file is still
# there. Confusing them would tell the user to go fix permissions that are fine,
# and would suppress the "no flag was consumed" sentence that depends on the count.
echo "Test 104: memory-restore: a lost race is reported as a race, not as a permissions fault"
CWD_104="$TEST_DIR/worktree-104"
mkdir -p "$CWD_104" "$TEST_DIR/shim-104"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
printf '%s\n%s\n%s\n%s\n' "sess_104" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_104" "checkpoint-104" \
    > "$PLANS_DIR/.pending-memory-restore-20260816T000104-10401"
# Stand in for the concurrent hook: remove the flag, then fail, so the claim finds
# the file gone rather than still present.
printf '#!/bin/sh\nrm -f "$1"\nexit 1\n' > "$TEST_DIR/shim-104/mv"
chmod +x "$TEST_DIR/shim-104/mv"
OUTPUT=$(echo '{"cwd":"'"$CWD_104"'"}' | PATH="$TEST_DIR/shim-104:$PATH" bash "$TEST_DIR/on-session-clear.sh" 2>/dev/null)
if assert_contains "104" "$OUTPUT" "claimed concurrently by another session" && \
   assert_not_contains "104" "$OUTPUT" "could NOT be claimed because of a filesystem error" && \
   assert_not_contains "104" "$OUTPUT" "no flag was consumed"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 105: a plans directory without the READ bit must be reported ---
# Test 91 covers mode 600 (readable, non-searchable). Mode 300 is the other bit and
# fails differently: the glob cannot expand at all and yields its own pattern.
echo "Test 105: memory-restore: mode-300 PLANS_DIR is reported, not treated as empty"
if [[ "$(id -u)" == "0" ]]; then
    echo "  SKIP (root reads a directory regardless of the read bit)"
    PASS=$((PASS + 1))
else
    CWD_105="$TEST_DIR/worktree-105"
    mkdir -p "$CWD_105"
    rm -f "$PLANS_DIR"/.pending-memory-restore-*
    printf '%s\n%s\n%s\n%s\n' "sess_105" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_105" "checkpoint-105" \
        > "$PLANS_DIR/.pending-memory-restore-20260816T000105-10501"
    trap 'chmod 700 "$PLANS_DIR" 2>/dev/null; cleanup' EXIT
    chmod 300 "$PLANS_DIR"
    OUTPUT=$(echo '{"cwd":"'"$CWD_105"'"}' | bash "$TEST_DIR/on-session-clear.sh" 2>/dev/null)
    chmod 700 "$PLANS_DIR"
    trap cleanup EXIT
    if assert_contains "105" "$OUTPUT" "could NOT be inspected"; then
        echo "  PASS"
        PASS=$((PASS + 1))
    else
        echo "  FAIL"
        FAIL=$((FAIL + 1))
    fi
fi

# --- Test 106: an over-long label is truncated, and says so ---
echo "Test 106: memory-restore: an over-long label is cut and marked, not printed whole"
CWD_106="$TEST_DIR/worktree-106"
mkdir -p "$CWD_106"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
LABEL_106=$(printf 'x%.0s' $(seq 1 260))
printf '%s\n%s\n%s\n%s\n' "sess_106" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_106" "$LABEL_106" \
    > "$PLANS_DIR/.pending-memory-restore-20260816T000106-10601"
OUTPUT=$(echo '{"cwd":"'"$CWD_106"'"}' | bash "$TEST_DIR/on-session-clear.sh")
# A label cut without a marker reads as a real label that simply is not the one on
# disk, which is the failure the bound exists to prevent.
if assert_not_contains "106" "$OUTPUT" "$LABEL_106" && \
   assert_contains "106" "$OUTPUT" "xxx…"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 107: the 24-hour freshness window, pinned close to 24 hours ---
# The suite's other flags sit at 20 hours and 2 days, so the window could be moved
# anywhere between them without a test noticing.
echo "Test 107: memory-restore: a 25-hour non-matching flag is stale, a 23-hour one is fresh"
REPO_107="$TEST_DIR/repo-107"
WT_107="$TEST_DIR/repo-107-worktree"
mkdir -p "$REPO_107"
git -C "$REPO_107" init -q 2>/dev/null
git -C "$REPO_107" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
git -C "$REPO_107" worktree add -q --detach "$WT_107" HEAD 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_107="$PLANS_DIR/.pending-memory-restore-20260816T000107-10701"
printf '%s\n%s\n%s\n%s\n' "sess_107" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$WT_107" "checkpoint-107" > "$MR_FLAG_107"
touch -t "$(date -v-25H +%Y%m%d%H%M 2>/dev/null || date -d '25 hours ago' +%Y%m%d%H%M)" "$MR_FLAG_107"
OUT_STALE_107=$(echo '{"cwd":"'"$REPO_107"'"}' | bash "$TEST_DIR/on-session-clear.sh")
touch -t "$(date -v-23H +%Y%m%d%H%M 2>/dev/null || date -d '23 hours ago' +%Y%m%d%H%M)" "$MR_FLAG_107"
OUT_FRESH_107=$(echo '{"cwd":"'"$REPO_107"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ -d "$WT_107" ]] && \
   assert_not_contains "107" "$OUT_STALE_107" "checkpoint-107" && \
   assert_contains "107" "$OUT_STALE_107" "older than 24h, left in place" && \
   assert_contains "107" "$OUT_FRESH_107" "checkpoint-107" && \
   assert_contains "107" "$OUT_FRESH_107" "same repository, selectable"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 108: the reported scope is the repository root, not its .git ---
# Every other assertion compares two scope_key results against each other, so the
# value itself was never pinned to a path a reader could recognize.
echo "Test 108: memory-restore: the scope shown is the repository main working tree"
REPO_108="$TEST_DIR/repo-108"
WT_108="$TEST_DIR/repo-108-worktree"
mkdir -p "$REPO_108"
git -C "$REPO_108" init -q 2>/dev/null
git -C "$REPO_108" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
git -C "$REPO_108" worktree add -q --detach "$WT_108" HEAD 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
printf 'only-one-line\n' > "$PLANS_DIR/.pending-memory-restore-20260816T000108-10801"
REPO_108_PHYS=$(cd "$REPO_108" && pwd -P)
OUTPUT=$(echo '{"cwd":"'"$WT_108"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ -d "$WT_108" ]] && \
   assert_contains "108" "$OUTPUT" "(scope: ${REPO_108_PHYS})" && \
   assert_not_contains "108" "$OUTPUT" "${REPO_108_PHYS}/.git"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 109: one message must not say a row was withheld and then print it ---
echo "Test 109: memory-restore: matched rows past the cap are not counted as withheld"
REPO_109="$TEST_DIR/repo-109"
mkdir -p "$REPO_109"
git -C "$REPO_109" init -q 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
for n in 1 2 3 4 5 6 7 8; do
    printf '%s\n%s\n%s\n%s\n' "sess_109_$n" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$REPO_109" "checkpoint-109-$n" \
        > "$PLANS_DIR/.pending-memory-restore-20260816T000109-1090$n"
done
OUTPUT=$(echo '{"cwd":"'"$REPO_109"'"}' | bash "$TEST_DIR/on-session-clear.sh")
# Eight matches, five display slots, and the ask-which-one list below prints all
# eight — so "3 more not shown" was contradicted three lines later in the same
# message. Every label must be present, and nothing may be called withheld.
LISTED_109=0
for n in 1 2 3 4 5 6 7 8; do
    printf '%s' "$OUTPUT" | grep -q "checkpoint-109-$n" && LISTED_109=$((LISTED_109 + 1))
done
if assert_contains "109" "$OUTPUT" "8 checkpoints for this directory" && \
   assert_contains "109" "$OUTPUT" "further matched flag(s) listed in full below" && \
   assert_not_contains "109" "$OUTPUT" "more not shown" && \
   [[ "$LISTED_109" -eq 8 ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (labels present: $LISTED_109/8)"
    FAIL=$((FAIL + 1))
fi

# --- Test 110: the seven-day sweep counts only what THIS hook removed ---
# `rm -f` also succeeds on a file a concurrent hook already deleted, so the sweep
# claims the flag with `mv` first. Without the claim the loser of a race reports a
# removal it did not perform, and the count is the only audit trace this path leaves.
echo "Test 110: memory-restore: a swept flag lost to a concurrent hook is not counted as removed"
CWD_110="$TEST_DIR/worktree-110"
mkdir -p "$CWD_110" "$TEST_DIR/shim-110"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_110="$PLANS_DIR/.pending-memory-restore-20260816T000110-11001"
printf '%s\n%s\n%s\n%s\n' "sess_110" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$TEST_DIR/elsewhere-110" "checkpoint-110" > "$MR_FLAG_110"
touch -t "$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)" "$MR_FLAG_110"
# Stand in for the concurrent hook: take the file, then fail, so the claim finds it gone.
printf '#!/bin/sh\nrm -f "$1"\nexit 1\n' > "$TEST_DIR/shim-110/mv"
chmod +x "$TEST_DIR/shim-110/mv"
OUTPUT=$(echo '{"cwd":"'"$CWD_110"'"}' | PATH="$TEST_DIR/shim-110:$PATH" bash "$TEST_DIR/on-session-clear.sh" 2>/dev/null)
if assert_not_contains "110" "$OUTPUT" "removed as older than 7 days"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 111: litter is reported by KIND, and an in-flight file is not litter ---
# A `.mr-claimed.*` is the ORIGINAL flag, moved rather than rewritten, so it still
# holds a label and a recorded path. A `.mr-tmp.*` may or may not: the writer fills
# the temp file before renaming it, so only an EMPTY one holds nothing. This test
# plants an empty one; tests 124-126 cover the non-empty cases. One counter for both
# said something false about the second, and sent the reader to a glob it never matches.
echo "Test 111: memory-restore: stranded claim files, interrupted writes and in-flight files are told apart"
CWD_111="$TEST_DIR/worktree-111"
mkdir -p "$CWD_111"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
OLD_111=$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)
MID_111=$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M)
GONE_111="$PLANS_DIR/.mr-claimed.99999.20260101T000000-11101"
TMPOLD_111="$PLANS_DIR/.mr-tmp.99999.old-11102"
KEPT_111="$PLANS_DIR/.mr-claimed.99999.20260810T000000-11103"
FLIGHT_111="$PLANS_DIR/.mr-claimed.99999.inflight-11104"
printf 'stranded\n' > "$GONE_111";  touch -t "$OLD_111" "$GONE_111"
printf '' > "$TMPOLD_111";          touch -t "$OLD_111" "$TMPOLD_111"
printf 'still-here\n' > "$KEPT_111"; touch -t "$MID_111" "$KEPT_111"
printf 'in-flight\n' > "$FLIGHT_111"
OUTPUT=$(echo '{"cwd":"'"$CWD_111"'"}' | bash "$TEST_DIR/on-session-clear.sh")
# The in-flight claim belongs to a concurrent hook, which has already reported it as
# a row of its own; calling it stranded reports another session's work as wreckage.
if [[ ! -e "$GONE_111" ]] && [[ ! -e "$TMPOLD_111" ]] && [[ -e "$KEPT_111" ]] && [[ -e "$FLIGHT_111" ]] && \
   assert_contains "111" "$OUTPUT" "1 stranded claim file(s) removed, whatever pointer they held is gone" && \
   assert_contains "111" "$OUTPUT" "1 stranded claim file(s)" && \
   assert_contains "111" "$OUTPUT" "still hold a checkpoint pointer no scan reads" && \
   assert_not_contains "111" "$OUTPUT" "2 stranded claim file(s)" && \
   assert_contains "111" "$OUTPUT" "1 interrupted flag write(s)" && \
   assert_contains "111" "$OUTPUT" "verified empty, so nothing was lost"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$KEPT_111" "$FLIGHT_111"

# --- Test 119: litter this hook could not remove must not vanish from the report ---
# `rm` needs write permission on the DIRECTORY. Counting only the successes let a
# stranded pointer disappear from the output entirely while staying on disk — the
# same silence this loop was rewritten to remove, reintroduced in a third outcome.
echo "Test 119: memory-restore: a stranded file that cannot be removed is reported, not passed over"
if [[ "$(id -u)" == "0" ]]; then
    echo "  SKIP (root writes a directory regardless of the write bit)"
    PASS=$((PASS + 1))
else
    CWD_119="$TEST_DIR/worktree-119"
    mkdir -p "$CWD_119"
    rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
    STUCK_119="$PLANS_DIR/.mr-claimed.99999.20260101T000000-11901"
    printf 'k\n2026-01-01T00:00:00+0900\n%s\nIMPORTANT-119\n' "$CWD_119" > "$STUCK_119"
    touch -t "$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)" "$STUCK_119"
    trap 'chmod 700 "$PLANS_DIR" 2>/dev/null; cleanup' EXIT
    chmod 0555 "$PLANS_DIR"
    OUTPUT=$(echo '{"cwd":"'"$CWD_119"'"}' | bash "$TEST_DIR/on-session-clear.sh" 2>/dev/null)
    chmod 700 "$PLANS_DIR"
    trap cleanup EXIT
    if [[ -e "$STUCK_119" ]] && \
       assert_contains "119" "$OUTPUT" "could NOT be removed" && \
       assert_not_contains "119" "$OUTPUT" "IMPORTANT-119"; then
        echo "  PASS"
        PASS=$((PASS + 1))
    else
        echo "  FAIL"
        FAIL=$((FAIL + 1))
    fi
    rm -f "$STUCK_119"
fi

# --- Test 112: the candidates block survives without sort(1) or awk(1) ---
# Ordering and row selection are builtins. Forking for them and capturing the result
# unchecked empties the row set or the matched-row list AFTER the flags have been
# consumed, taking the labels with it. This pins that the forks are gone rather than
# merely unused today.
echo "Test 112: memory-restore: the whole report is produced without sort(1) or awk(1)"
REPO_112="$TEST_DIR/repo-112"
WT_112="$TEST_DIR/repo-112-worktree"
mkdir -p "$REPO_112" "$TEST_DIR/shim-112"
git -C "$REPO_112" init -q 2>/dev/null
git -C "$REPO_112" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
git -C "$REPO_112" worktree add -q --detach "$WT_112" HEAD 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
printf '%s\n%s\n%s\n%s\n' "sess_112a" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$REPO_112" "checkpoint-112-a" \
    > "$PLANS_DIR/.pending-memory-restore-20260816T000112-11201"
printf '%s\n%s\n%s\n%s\n' "sess_112b" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$REPO_112" "checkpoint-112-b" \
    > "$PLANS_DIR/.pending-memory-restore-20260816T000112-11202"
printf '%s\n%s\n%s\n%s\n' "sess_112c" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$WT_112" "checkpoint-112-selectable" \
    > "$PLANS_DIR/.pending-memory-restore-20260816T000112-11203"
for helper in sort awk; do
    printf '#!/bin/sh\nexit 127\n' > "$TEST_DIR/shim-112/$helper"
    chmod +x "$TEST_DIR/shim-112/$helper"
done
OUTPUT=$(echo '{"cwd":"'"$REPO_112"'"}' | PATH="$TEST_DIR/shim-112:$PATH" bash "$TEST_DIR/on-session-clear.sh" 2>/dev/null)
if [[ -d "$WT_112" ]] && \
   assert_contains "112" "$OUTPUT" "2 checkpoints for this directory" && \
   assert_contains "112" "$OUTPUT" "checkpoint-112-a" && \
   assert_contains "112" "$OUTPUT" "checkpoint-112-b" && \
   assert_contains "112" "$OUTPUT" "checkpoint-112-selectable" && \
   assert_contains "112" "$OUTPUT" "same repository, selectable" && \
   assert_contains "112" "$OUTPUT" "AskUserQuestion"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 113: a separate git directory must not split one repository's identity ---
# scope_key() answers an identity, not a display path. Under
# `git init --separate-git-dir` it answers the separate git directory; what matters is
# that the working tree and its linked worktrees still agree, because a flag armed in
# one must be selectable from the other.
echo "Test 113: memory-restore: --separate-git-dir repo and its worktree share one scope"
WORK_113="$TEST_DIR/work-113"
GITDIR_113="$TEST_DIR/gitdir-113"
WT_113="$TEST_DIR/wt-113"
mkdir -p "$WORK_113"
git -C "$WORK_113" init -q --separate-git-dir="$GITDIR_113" 2>/dev/null
git -C "$WORK_113" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
git -C "$WORK_113" worktree add -q --detach "$WT_113" HEAD 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_113="$PLANS_DIR/.pending-memory-restore-20260816T000113-11301"
printf '%s\n%s\n%s\n%s\n' "sess_113" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$WT_113" "checkpoint-113" > "$MR_FLAG_113"
OUTPUT=$(echo '{"cwd":"'"$WORK_113"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ -d "$WT_113" ]] && \
   assert_contains "113" "$OUTPUT" "same repository, selectable" && \
   assert_contains "113" "$OUTPUT" "checkpoint-113" && \
   assert_not_contains "113" "$OUTPUT" "recorded outside this scope" && \
   assert_not_contains "113" "$OUTPUT" "recorded in another repository" && \
   assert_file_exists "113" "$MR_FLAG_113"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 114: a relative, missing PLANS_DIR must not hang the hook ---
# `${d%/*}` returns a slashless string UNCHANGED, so walking up by that alone never
# terminates once the last separator is gone. Reachable whenever CLAUDE_CONFIG_DIR is
# relative and its first component is missing. The hook is then killed at the
# SessionStart timeout: no checkpoint report, no plan restore, no error the session
# can see — a worse silence than the one the guard was added to remove.
echo "Test 114: memory-restore: a relative missing PLANS_DIR terminates instead of spinning"
mkdir -p "$TEST_DIR/t114" "$TEST_DIR/cwd-114"
sed -e 's|^PLANS_DIR=.*|PLANS_DIR="cfg-114-missing/plans"|' "$SCRIPT_DIR/scripts/lib-plan.sh" > "$TEST_DIR/t114/lib-plan.sh"
cp "$SCRIPT_DIR/scripts/on-session-clear.sh" "$TEST_DIR/t114/on-session-clear.sh"
OUT_114="$TEST_DIR/out-114.txt"
: > "$OUT_114"
( cd "$TEST_DIR" && echo '{"cwd":"'"$TEST_DIR/cwd-114"'"}' | bash "$TEST_DIR/t114/on-session-clear.sh" > "$OUT_114" 2>/dev/null ) &
HOOK_PID_114=$!
WAITED_114=0
while kill -0 "$HOOK_PID_114" 2>/dev/null && [[ "$WAITED_114" -lt 10 ]]; do
    sleep 1
    WAITED_114=$((WAITED_114 + 1))
done
if kill -0 "$HOOK_PID_114" 2>/dev/null; then
    kill -9 "$HOOK_PID_114" 2>/dev/null
    HUNG_114="yes"
else
    HUNG_114="no"
fi
wait "$HOOK_PID_114" 2>/dev/null || true
OUTPUT=$(cat "$OUT_114")
# The working directory IS inspectable, so the plans directory is verifiably absent
# and silence about checkpoints is the correct answer — not a report of denied access.
if [[ "$HUNG_114" == "no" ]] && \
   assert_not_contains "114" "$OUTPUT" "could NOT be inspected"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (hung: $HUNG_114 after ${WAITED_114}s)"
    FAIL=$((FAIL + 1))
fi

# --- Test 115: an undeterminable working directory must be reported, not silent ---
# The scan is skipped on an empty cwd because "" would match every truncated flag.
# Skipping is right; saying nothing about it is the pre-fix failure mode. Bash leaves
# PWD empty when it is unset in the environment AND getcwd() fails — which is what a
# REMOVED working directory does, the motivating scenario of this whole change.
echo "Test 115: memory-restore: an undeterminable cwd is reported, not passed over in silence"
CWD_115="$TEST_DIR/gone-115"
mkdir -p "$CWD_115"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
MR_FLAG_115="$PLANS_DIR/.pending-memory-restore-20260816T000115-11501"
printf '%s\n%s\n%s\n%s\n' "sess_115" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_115" "checkpoint-115" > "$MR_FLAG_115"
OUTPUT=$( cd "$CWD_115" && rmdir "$CWD_115" && echo '{}' | env -u PWD /bin/bash "$TEST_DIR/on-session-clear.sh" 2>/dev/null )
PWD_SEEN_115=$( cd / && env -u PWD /bin/bash -c 'echo "[$PWD]"' )
# Nothing may be consumed either: with no cwd, no flag can be shown to be this
# session's, so claiming one would destroy a pointer on a guess.
if assert_contains "115" "$OUTPUT" "working directory could not be determined" && \
   assert_not_contains "115" "$OUTPUT" "Checkpoint candidates seen" && \
   assert_file_exists "115" "$MR_FLAG_115"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (control: bash with a normal cwd reports PWD=$PWD_SEEN_115)"
    FAIL=$((FAIL + 1))
fi

# --- Test 116: the row ordering agrees with the sort(1) key it replaced, and is stable ---
# Checked at the function level, not through the hook: the hook cannot be made to
# produce two rows with an identical mtime AND timestamp on demand, and ties are
# exactly where a hand-written sort goes wrong.
echo "Test 116: memory-restore: _mr_sort_rows matches sort(1) and preserves input order on ties"
SORTFN_116="$TEST_DIR/sortfn-116.sh"
sed -n '/^_mr_sort_rows() {/,/^}/p' "$SCRIPT_DIR/scripts/on-session-clear.sh" > "$SORTFN_116"
SORT_OK_116=1
[[ -s "$SORTFN_116" ]] || SORT_OK_116=0
if [[ "$SORT_OK_116" -eq 1 ]]; then
    ORDER_116=$(bash -c '
        . "'"$SORTFN_116"'"
        _mr_rows=""
      
        for i in A B C D E F; do
            _mr_rows+="3"$'"'"'\037'"'"'"1700000000"$'"'"'\037'"'"'"v"$'"'"'\037'"'"'"tie-$i"$'"'"'\037'"'"'"2026-08-16T00:00:00+0900"$'"'"'\037'"'"'"/p"$'"'"'\037'"'"'"k$i"$'"'"'\n'"'"'
        done
        _mr_sort_rows
        printf "%s" "$_mr_rows" | cut -d$'"'"'\037'"'"' -f4 | tr "\n" " "
    ')
    AGREE_116=$(bash -c '
        . "'"$SORTFN_116"'"
        _mr_rows=""
      
      
        for i in 1 2 3 4 5 6; do
            p=$(( (i % 3) + 1 ))
            _mr_rows+="${p}"$'"'"'\037'"'"'"$((1700000000 + i))"$'"'"'\037'"'"'"v"$'"'"'\037'"'"'"l$i"$'"'"'\037'"'"'"2026-08-16T00:00:0${i}+0900"$'"'"'\037'"'"'"/p"$'"'"'\037'"'"'"k$i"$'"'"'\n'"'"'
        done
        expected=$(printf "%s" "$_mr_rows" | sort -t$'"'"'\037'"'"' -k1,1n -k2,2rn -k5,5r)
        _mr_sort_rows
        [[ "$(printf "%s" "$_mr_rows")" == "$expected" ]] && echo same || echo differs
    ')
  
  
  
    THIRDKEY_116=$(bash -c '
        . "'"$SORTFN_116"'"
        _mr_rows=""
        for i in 1 2 3; do
            _mr_rows+="1"$'"'"'\037'"'"'"1700000000"$'"'"'\037'"'"'"v"$'"'"'\037'"'"'"tk-$i"$'"'"'\037'"'"'"2026-08-16T00:00:0${i}+0900"$'"'"'\037'"'"'"/p"$'"'"'\037'"'"'"k$i"$'"'"'\n'"'"'
        done
        _mr_sort_rows
        printf "%s" "$_mr_rows" | cut -d$'"'"'\037'"'"' -f4 | tr "\n" " "
    ')
else
    ORDER_116="(function not extracted)"
    AGREE_116="(function not extracted)"
    THIRDKEY_116="(function not extracted)"
fi
if [[ "$ORDER_116" == "tie-A tie-B tie-C tie-D tie-E tie-F " ]] && [[ "$AGREE_116" == "same" ]] && \
   [[ "$THIRDKEY_116" == "tk-3 tk-2 tk-1 " ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (tie order: '$ORDER_116'; vs sort: $AGREE_116; third key: '$THIRDKEY_116')"
    FAIL=$((FAIL + 1))
fi

# --- Test 117: every counted match must appear in the list the agent is told to offer ---
echo "Test 117: memory-restore: a matched flag with no label and no timestamp is still offered"
CWD_117="$TEST_DIR/worktree-117"
mkdir -p "$CWD_117"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
printf '%s\n%s\n%s\n%s\n' "sess_117" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_117" "checkpoint-117-good" \
    > "$PLANS_DIR/.pending-memory-restore-20260816T000117-11701"
# Truncated flag: line 2 (timestamp) and line 4 (label) both blank. It still matched,
# so it was consumed and its pointer is gone; leaving it out of the ask list means
# the user is never offered the checkpoint this run destroyed.
printf '%s\n%s\n%s\n%s\n' "sess_117b" "" "$CWD_117" "" \
    > "$PLANS_DIR/.pending-memory-restore-20260816T000117-11702"
OUTPUT=$(echo '{"cwd":"'"$CWD_117"'"}' | bash "$TEST_DIR/on-session-clear.sh")
LIST_117="${OUTPUT#*Candidates, newest first}"
LIST_117="${LIST_117%%BEFORE doing anything else*}"
# Count OCCURRENCES, not lines: the hook emits one JSON line, so `grep -c` would
# answer 1 however many rows the list holds.
OFFERED_117=$(printf '%s' "$LIST_117" | grep -o 'n- ' | wc -l | tr -d ' ')
if assert_contains "117" "$OUTPUT" "2 checkpoints for this directory" && \
   [[ "$OFFERED_117" -eq 2 ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (header says 2, list offers $OFFERED_117)"
    FAIL=$((FAIL + 1))
fi

# --- Test 118: a failing date(1) must not drop rows the header counts ---
# `_mr_now` feeds the mtime fallback. An empty one propagates into `_mr_mtime`, which
# the display loop drops on its `-n` guard with no count, while the match count in
# the header still includes the flag. That is what this test is for, and it still is.
#
# What changed: this fixture breaks `stat` as well as `date`, so the age is not merely
# skewed, it was never established. The assertion used to be "MATCHES this session",
# which pinned the behaviour where an unmeasured age read as zero — an arbitrarily old
# checkpoint restored as this session's and then deleted. The row must still be listed
# with its label, which was always the point; it must now also survive on disk.
echo "Test 118: memory-restore: a failing date(1) still lists every counted match"
CWD_118="$TEST_DIR/worktree-118"
mkdir -p "$CWD_118" "$TEST_DIR/shim-118"
rm -f "$PLANS_DIR"/.pending-memory-restore-*
printf '%s\n%s\n%s\n%s\n' "sess_118" "2026-08-16T00:00:00+0900" "$CWD_118" "checkpoint-118" \
    > "$PLANS_DIR/.pending-memory-restore-20260816T000118-11801"
printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/shim-118/date"
chmod +x "$TEST_DIR/shim-118/date"
printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/shim-118/stat"
chmod +x "$TEST_DIR/shim-118/stat"
OUTPUT=$(echo '{"cwd":"'"$CWD_118"'"}' | PATH="$TEST_DIR/shim-118:$PATH" bash "$TEST_DIR/on-session-clear.sh" 2>/dev/null)
# Failure means keep, and keep now means keep: the flag cannot be shown to be stale,
# so it is neither swept nor consumed, and it is listed with its label so the reader
# can act on it.
if [[ -e "$PLANS_DIR/.pending-memory-restore-20260816T000118-11801" ]] && \
   assert_contains "118" "$OUTPUT" "checkpoint-118" && \
   assert_contains "118" "$OUTPUT" "age could NOT be established" && \
   assert_not_contains "118" "$OUTPUT" "MATCHES this session" && \
   assert_not_contains "118" "$OUTPUT" "removed as older than 7 days"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 120: the reserved slot is taken ONCE, by the first selectable row ---
# Test 93 pins that a selectable row survives the cap. It cannot pin "once": with a
# single selectable row, a slot taken twice looks the same as a slot taken once.
echo "Test 120: memory-restore: two selectable rows past the cap still yield one reserved slot"
REPO_120="$TEST_DIR/repo-120"
WTA_120="$TEST_DIR/repo-120-wt-a"
WTB_120="$TEST_DIR/repo-120-wt-b"
mkdir -p "$REPO_120"
git -C "$REPO_120" init -q 2>/dev/null
git -C "$REPO_120" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
git -C "$REPO_120" worktree add -q --detach "$WTA_120" HEAD 2>/dev/null
git -C "$REPO_120" worktree add -q --detach "$WTB_120" HEAD 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
OLD_120=$(date -v-30H +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || date -d '30 hours ago' +%Y-%m-%dT%H:%M:%S%z)
STAMP_120=$(date -v-30H +%Y%m%d%H%M 2>/dev/null || date -d '30 hours ago' +%Y%m%d%H%M)
for n in 1 2 3 4 5; do
    printf '%s\n%s\n%s\n%s\n' "sess_120_$n" "$OLD_120" "$REPO_120" "checkpoint-120-expired-$n" \
        > "$PLANS_DIR/.pending-memory-restore-20260816T000120-1200$n"
    touch -t "$STAMP_120" "$PLANS_DIR/.pending-memory-restore-20260816T000120-1200$n"
done
# Two selectable rows, distinguishable by mtime so "the first" is well defined: the
# newer one sorts ahead within its priority band.
SEL_A_120="$PLANS_DIR/.pending-memory-restore-20260816T120120-12011"
SEL_B_120="$PLANS_DIR/.pending-memory-restore-20260816T120120-12012"
printf '%s\n%s\n%s\n%s\n' "sess_120a" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$WTA_120" "checkpoint-120-sel-newer" > "$SEL_A_120"
printf '%s\n%s\n%s\n%s\n' "sess_120b" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$WTB_120" "checkpoint-120-sel-older" > "$SEL_B_120"
touch -t "$(date -v-3H +%Y%m%d%H%M 2>/dev/null || date -d '3 hours ago' +%Y%m%d%H%M)" "$SEL_B_120"
OUTPUT=$(echo '{"cwd":"'"$REPO_120"'"}' | bash "$TEST_DIR/on-session-clear.sh")
ROWS_120=$(printf '%s' "$OUTPUT" | grep -o 'n- checkpoint-120' | wc -l | tr -d ' ')
if [[ -d "$WTA_120" ]] && [[ -d "$WTB_120" ]] && \
   [[ "$ROWS_120" -eq 5 ]] && \
   assert_contains "120" "$OUTPUT" "checkpoint-120-sel-newer" && \
   assert_not_contains "120" "$OUTPUT" "checkpoint-120-sel-older" && \
   assert_contains "120" "$OUTPUT" "1 further selectable row(s) could NOT be shown" && \
   assert_file_exists "120" "$SEL_A_120" && \
   assert_file_exists "120" "$SEL_B_120"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL (rows printed: ${ROWS_120}, expected 5)"
    FAIL=$((FAIL + 1))
fi

# --- Test 121: the position scan must stop at the FIRST selectable row ---
# The scan decides whether a slot needs reserving. Reading the LAST selectable
# position instead of the first over-states how far down the list the actionable rows
# begin, arms the reservation when it is not needed, and costs a display slot that a
# row would otherwise have had.
echo "Test 121: memory-restore: the reservation is decided by the first selectable row, not the last"
REPO_121="$TEST_DIR/repo-121"
mkdir -p "$REPO_121"
git -C "$REPO_121" init -q 2>/dev/null
git -C "$REPO_121" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
rm -f "$PLANS_DIR"/.pending-memory-restore-*
OLD_121=$(date -v-30H +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || date -d '30 hours ago' +%Y-%m-%dT%H:%M:%S%z)
STAMP_121=$(date -v-30H +%Y%m%d%H%M 2>/dev/null || date -d '30 hours ago' +%Y%m%d%H%M)
for n in 1 2 3; do
    printf '%s\n%s\n%s\n%s\n' "sess_121_$n" "$OLD_121" "$REPO_121" "checkpoint-121-expired-$n" \
        > "$PLANS_DIR/.pending-memory-restore-20260816T000121-1210$n"
    touch -t "$STAMP_121" "$PLANS_DIR/.pending-memory-restore-20260816T000121-1210$n"
done
WT_OK_121=1
for n in 1 2 3; do
    W_121="$TEST_DIR/repo-121-wt-$n"
    git -C "$REPO_121" worktree add -q --detach "$W_121" HEAD 2>/dev/null
    [[ -d "$W_121" ]] || WT_OK_121=0
    printf '%s\n%s\n%s\n%s\n' "sess_121_s$n" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$W_121" "checkpoint-121-sel-$n" \
        > "$PLANS_DIR/.pending-memory-restore-20260816T12012$n-1211$n"
  
    touch -t "$(date -v-${n}H +%Y%m%d%H%M 2>/dev/null || date -d "$n hours ago" +%Y%m%d%H%M)" \
        "$PLANS_DIR/.pending-memory-restore-20260816T12012$n-1211$n"
done
OUTPUT=$(echo '{"cwd":"'"$REPO_121"'"}' | bash "$TEST_DIR/on-session-clear.sh")
# Three expired rows then three selectable: the first selectable sits at position 4,
# inside the cap, so NO slot needs reserving and five rows fit — three expired plus
# the two newest selectable, with exactly one selectable held back.
if [[ "$WT_OK_121" -eq 1 ]] && \
   assert_contains "121" "$OUTPUT" "checkpoint-121-sel-1" && \
   assert_contains "121" "$OUTPUT" "checkpoint-121-sel-2" && \
   assert_not_contains "121" "$OUTPUT" "checkpoint-121-sel-3" && \
   assert_contains "121" "$OUTPUT" "1 more not shown" && \
   assert_contains "121" "$OUTPUT" "1 further selectable row(s) could NOT be shown"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 122: an ancestor that is searchable but NOT readable is still "cannot tell" ---
# Test 97 locks the parent to mode 600 — readable, non-searchable — so only the `-x`
# half of the guard is exercised. Mode 300 is the other half: the directory can be
# entered but not listed, so absence cannot be established either.
echo "Test 122: memory-restore: a mode-300 ancestor of PLANS_DIR is reported, not read as absence"
if [[ "$(id -u)" == "0" ]]; then
    echo "  SKIP (root reads a directory regardless of the read bit)"
    PASS=$((PASS + 1))
else
    CFG_122="$TEST_DIR/cfg-122"
    CWD_122="$TEST_DIR/worktree-122"
    mkdir -p "$CFG_122" "$CWD_122" "$TEST_DIR/t122"
    sed -e 's|^PLANS_DIR=.*|PLANS_DIR="'"$CFG_122"'/plans"|' "$SCRIPT_DIR/scripts/lib-plan.sh" > "$TEST_DIR/t122/lib-plan.sh"
    cp "$SCRIPT_DIR/scripts/on-session-clear.sh" "$TEST_DIR/t122/on-session-clear.sh"
    trap 'chmod 700 "$CFG_122" 2>/dev/null; cleanup' EXIT
    chmod 300 "$CFG_122"
    OUTPUT=$(echo '{"cwd":"'"$CWD_122"'"}' | bash "$TEST_DIR/t122/on-session-clear.sh" 2>/dev/null)
    chmod 700 "$CFG_122"
    trap cleanup EXIT
    if assert_contains "122" "$OUTPUT" "could NOT be inspected"; then
        echo "  PASS"
        PASS=$((PASS + 1))
    else
        echo "  FAIL"
        FAIL=$((FAIL + 1))
    fi
fi

# --- Test 123: an age that could not be established is not an age of zero ---
# Both `stat` forms failing collapsed the mtime to `now`, and the 60-second in-flight
# guard then dropped the file from the report entirely. A FUTURE mtime reaches the same
# state through the positive-staleness clamp, and is the portable way to reach it here.
echo "Test 123: memory-restore: litter whose age cannot be established is reported, not skipped as in-flight"
CWD_123="$TEST_DIR/worktree-123"
mkdir -p "$CWD_123" "$TEST_DIR/fakebin-123"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
# A `stat` that always fails is the real shape of this case. An 8-day-old mtime makes
# the fixture sweepable, so the assertion that it SURVIVES also pins that nothing is
# deleted on an age nobody established.
printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/fakebin-123/stat"
chmod +x "$TEST_DIR/fakebin-123/stat"
OLD_123=$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)
UNMEASURED_123="$PLANS_DIR/.mr-tmp.99999.nostat-12301"
printf 'k\n2026-01-01T00:00:00+0900\n%s\nLABEL-123\n' "$CWD_123" > "$UNMEASURED_123"
touch -t "$OLD_123" "$UNMEASURED_123"
OUTPUT=$(echo '{"cwd":"'"$CWD_123"'"}' | PATH="$TEST_DIR/fakebin-123:$PATH" bash "$TEST_DIR/on-session-clear.sh")
if [[ -e "$UNMEASURED_123" ]] && \
   assert_contains "123" "$OUTPUT" "1 litter file(s)" && \
   assert_contains "123" "$OUTPUT" "have an age this hook could NOT establish" && \
   assert_not_contains "123" "$OUTPUT" "verified empty" && \
   assert_not_contains "123" "$OUTPUT" "are NOT empty" && \
   assert_not_contains "123" "$OUTPUT" "stranded claim file(s)" && \
   assert_not_contains "123" "$OUTPUT" "could NOT be removed" && \
   assert_not_contains "123" "$OUTPUT" "LABEL-123"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$UNMEASURED_123"
rm -rf "$TEST_DIR/fakebin-123"

# --- Test 124: a NON-EMPTY interrupted write that gets swept destroyed a pointer ---
# `write-reload-flag.sh` writes the whole body into the temp file and only then renames
# it, so a writer killed before the `mv` leaves a complete flag. Sweeping that while the
# report says it held no checkpoint deletes a pointer and denies having done so.
echo "Test 124: memory-restore: sweeping a non-empty interrupted write is reported as a destroyed pointer"
CWD_124="$TEST_DIR/worktree-124"
mkdir -p "$CWD_124"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
OLD_124=$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)
BODY_124="$PLANS_DIR/.mr-tmp.99999.body-12401"
printf 'k\n2026-01-01T00:00:00+0900\n%s\nLABEL-124\n' "$CWD_124" > "$BODY_124"
touch -t "$OLD_124" "$BODY_124"
OUTPUT=$(echo '{"cwd":"'"$CWD_124"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ ! -e "$BODY_124" ]] && \
   assert_contains "124" "$OUTPUT" "1 interrupted flag write(s)" && \
   assert_contains "124" "$OUTPUT" "were NOT empty, so whatever they held is gone" && \
   assert_not_contains "124" "$OUTPUT" "verified empty" && \
   assert_not_contains "124" "$OUTPUT" "LABEL-124"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 125: a NON-EMPTY interrupted write young enough to keep is not called empty ---
echo "Test 125: memory-restore: a surviving non-empty interrupted write is reported as still holding a body"
CWD_125="$TEST_DIR/worktree-125"
mkdir -p "$CWD_125"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
MID_125=$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M)
KEPT_125="$PLANS_DIR/.mr-tmp.99999.body-12501"
printf 'k\n2026-01-01T00:00:00+0900\n%s\nLABEL-125\n' "$CWD_125" > "$KEPT_125"
touch -t "$MID_125" "$KEPT_125"
OUTPUT=$(echo '{"cwd":"'"$CWD_125"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ -e "$KEPT_125" ]] && \
   assert_contains "125" "$OUTPUT" "1 interrupted flag write(s)" && \
   assert_contains "125" "$OUTPUT" "are NOT empty, so they may hold a checkpoint body" && \
   assert_not_contains "125" "$OUTPUT" "verified empty" && \
   assert_not_contains "125" "$OUTPUT" "LABEL-125"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$KEPT_125"

# --- Test 126: an EMPTY interrupted write must still be reported as holding nothing ---
# Guards the opposite over-correction: testing the file must not turn into claiming a
# body for every temp file, which would send the reader hunting for a checkpoint that
# genuinely is not there.
echo "Test 126: memory-restore: an empty interrupted write is still reported as holding no checkpoint"
CWD_126="$TEST_DIR/worktree-126"
mkdir -p "$CWD_126"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
MID_126=$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M)
EMPTY_126="$PLANS_DIR/.mr-tmp.99999.empty-12601"
printf '' > "$EMPTY_126"
touch -t "$MID_126" "$EMPTY_126"
OUTPUT=$(echo '{"cwd":"'"$CWD_126"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ -e "$EMPTY_126" ]] && \
   assert_contains "126" "$OUTPUT" "left in" && \
   assert_contains "126" "$OUTPUT" "verified empty, so they hold no checkpoint and can be deleted" && \
   assert_not_contains "126" "$OUTPUT" "are NOT empty" && \
   assert_not_contains "126" "$OUTPUT" "removed as older than 7 days"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$EMPTY_126"

# --- Test 127: claim-versus-temp is decided by the basename, not the whole path ---
# A whole-path test also fires on any ANCESTOR directory named `.mr-claimed.*`, filing
# every temp file below it under a glob it never matches.
echo "Test 127: memory-restore: an ancestor directory named .mr-claimed.* does not make a temp file a claim"
CFG_127="$TEST_DIR/.mr-claimed.decoy/cfg-127"
CWD_127="$TEST_DIR/worktree-127"
mkdir -p "$CFG_127/plans" "$CWD_127" "$TEST_DIR/t127"
sed -e 's|^PLANS_DIR=.*|PLANS_DIR="'"$CFG_127"'/plans"|' "$SCRIPT_DIR/scripts/lib-plan.sh" > "$TEST_DIR/t127/lib-plan.sh"
cp "$SCRIPT_DIR/scripts/on-session-clear.sh" "$TEST_DIR/t127/on-session-clear.sh"
MID_127=$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M)
TMP_127="$CFG_127/plans/.mr-tmp.99999.decoy-12701"
printf '' > "$TMP_127"
touch -t "$MID_127" "$TMP_127"
OUTPUT=$(echo '{"cwd":"'"$CWD_127"'"}' | bash "$TEST_DIR/t127/on-session-clear.sh")
if assert_contains "127" "$OUTPUT" "1 interrupted flag write(s)" && \
   assert_contains "127" "$OUTPUT" "verified empty, so they hold no checkpoint and can be deleted" && \
   assert_not_contains "127" "$OUTPUT" "stranded claim file(s)"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$TMP_127"

# --- Test 128: a FUTURE mtime is a file in flight, not a file of unknown age ---
# `_mr_now` is sampled once, before a per-flag scan that forks several times. A
# concurrent `write-reload-flag.sh` creating its temp file after that sample leaves an
# mtime AHEAD of the sample, so this is the ordinary case, not clock skew. It says the
# file is at most zero seconds old, which is exactly the in-flight case: reporting it
# as litter reports a live writer's work in progress as wreckage.
echo "Test 128: memory-restore: a future mtime takes the in-flight exit, not the unexamined one"
CWD_128="$TEST_DIR/worktree-128"
mkdir -p "$CWD_128"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
FUTURE_128=$(date -v+30S +%Y%m%d%H%M.%S 2>/dev/null || date -d '30 seconds' +%Y%m%d%H%M.%S)
LIVE_128="$PLANS_DIR/.mr-tmp.99999.live-12801"
printf 'k\n2026-01-01T00:00:00+0900\n%s\nLABEL-128\n' "$CWD_128" > "$LIVE_128"
touch -t "$FUTURE_128" "$LIVE_128"
OUTPUT=$(echo '{"cwd":"'"$CWD_128"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ -e "$LIVE_128" ]] && \
   assert_not_contains "128" "$OUTPUT" "interrupted flag write(s)" && \
   assert_not_contains "128" "$OUTPUT" "have an age this hook could NOT establish" && \
   assert_not_contains "128" "$OUTPUT" "LABEL-128"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$LIVE_128"

# --- Test 129: sweeping an EMPTY interrupted write must not be reported as still there ---
# One counter for both outcomes made the hook delete the file and then tell the reader
# it was "seen in <dir>" and "can be deleted" — two claims the code had just falsified.
echo "Test 129: memory-restore: a swept empty interrupted write is reported as removed, not as still on disk"
CWD_129="$TEST_DIR/worktree-129"
mkdir -p "$CWD_129"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
OLD_129=$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)
SWEPT_129="$PLANS_DIR/.mr-tmp.99999.empty-12901"
printf '' > "$SWEPT_129"
touch -t "$OLD_129" "$SWEPT_129"
OUTPUT=$(echo '{"cwd":"'"$CWD_129"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ ! -e "$SWEPT_129" ]] && \
   assert_contains "129" "$OUTPUT" "verified empty, so nothing was lost" && \
   assert_not_contains "129" "$OUTPUT" "can be deleted"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 130: a mtime FAR ahead of the clock is not a live writer ---
# The in-flight reading is bounded by the same 60s the guard uses, because it exists for
# one phenomenon: `_mr_now` is sampled once, so a concurrent writer lands just after it.
# A restored backup, a `cp -p` from a machine running ahead or an NFS server's clock puts
# a file years out, and reading THAT as "at most zero seconds old" hides it forever.
echo "Test 130: memory-restore: a mtime far ahead of the clock is reported, not read as in-flight"
CWD_130="$TEST_DIR/worktree-130"
mkdir -p "$CWD_130"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
FAR_130=$(date -v+2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days' +%Y%m%d%H%M)
FAR_FILE_130="$PLANS_DIR/.mr-claimed.99999.20991231T235959-13001"
printf 'k\n2026-01-01T00:00:00+0900\n%s\nLABEL-130\n' "$CWD_130" > "$FAR_FILE_130"
touch -t "$FAR_130" "$FAR_FILE_130"
OUTPUT=$(echo '{"cwd":"'"$CWD_130"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ -e "$FAR_FILE_130" ]] && \
   assert_contains "130" "$OUTPUT" "1 litter file(s)" && \
   assert_contains "130" "$OUTPUT" "have an age this hook could NOT establish" && \
   assert_not_contains "130" "$OUTPUT" "stranded claim file(s)" && \
   assert_not_contains "130" "$OUTPUT" "LABEL-130"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$FAR_FILE_130"

# --- Test 131: a failing clock must not silence the whole sweep ---
# `_mr_now` is forced to 0 when `date +%s` gives a non-number. Reading that as "every file
# is at most zero seconds old" sends EVERY litter file out the in-flight exit, so the
# report is empty and the session sees fresh-start while the files sit there untouched.
# A global clock failure is not a per-file freshness fact.
echo "Test 131: memory-restore: a failing date(1) does not silence the litter sweep"
CWD_131="$TEST_DIR/worktree-131"
mkdir -p "$CWD_131" "$TEST_DIR/fakebin-131"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
cat > "$TEST_DIR/fakebin-131/date" <<'FAKEDATE'
#!/bin/sh
for a in "$@"; do
    if [ "$a" = "+%s" ]; then echo "notanumber"; exit 0; fi
done
exec /bin/date "$@"
FAKEDATE
chmod +x "$TEST_DIR/fakebin-131/date"
OLD_131=$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)
CLAIM_131="$PLANS_DIR/.mr-claimed.99999.20260101T000000-13101"
printf 'k\n2026-01-01T00:00:00+0900\n%s\nLABEL-131\n' "$CWD_131" > "$CLAIM_131"
touch -t "$OLD_131" "$CLAIM_131"
OUTPUT=$(echo '{"cwd":"'"$CWD_131"'"}' | PATH="$TEST_DIR/fakebin-131:$PATH" bash "$TEST_DIR/on-session-clear.sh")
if [[ -e "$CLAIM_131" ]] && \
   assert_contains "131" "$OUTPUT" "have an age this hook could NOT establish" && \
   assert_not_contains "131" "$OUTPUT" "LABEL-131"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$CLAIM_131"
rm -rf "$TEST_DIR/fakebin-131"

# --- Test 132: the candidates-block tail reports litter too ---
# The tail renders only when the flag scan produced a row, so a sweep holding ONLY litter
# never reaches it. Every other litter test clears the flags first, which left all eight
# tail sentences unexecuted: a mutation blanking them kept the suite green. The two sites
# word the same counter differently, so a fallback assertion cannot cover this one.
echo "Test 132: memory-restore: litter is reported inside the candidates block, not only in the fallback"
CWD_132="$TEST_DIR/worktree-132"
mkdir -p "$CWD_132"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
MR_FLAG_132="$PLANS_DIR/.pending-memory-restore-20260718T000000-13201"
printf '%s\n%s\n%s\n%s\n' "sess_132" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_132" "checkpoint-132" > "$MR_FLAG_132"
MID_132=$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M)
BODY_132="$PLANS_DIR/.mr-tmp.99999.body-13202"
printf 'k\n2026-01-01T00:00:00+0900\n%s\nLABEL-132\n' "$CWD_132" > "$BODY_132"
touch -t "$MID_132" "$BODY_132"
OUTPUT=$(echo '{"cwd":"'"$CWD_132"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ -e "$BODY_132" ]] && \
   assert_contains "132" "$OUTPUT" "1 interrupted flag write(s) left in place are NOT empty" && \
   assert_not_contains "132" "$OUTPUT" "LABEL-132"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$BODY_132"

# --- Test 133: a swept claim file alone must reach the directive ---
# The `elif` that decides whether a directive is emitted lists every counter by name.
# With no test where a claim counter is the ONLY non-zero one, its term could be deleted
# and the suite would stay green while a scan that found something reported nothing.
echo "Test 133: memory-restore: a swept stranded claim file alone still produces a directive"
CWD_133="$TEST_DIR/worktree-133"
mkdir -p "$CWD_133"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
OLD_133=$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)
GONE_133="$PLANS_DIR/.mr-claimed.99999.20260101T000000-13301"
printf 'k\n2026-01-01T00:00:00+0900\n%s\nLABEL-133\n' "$CWD_133" > "$GONE_133"
touch -t "$OLD_133" "$GONE_133"
OUTPUT=$(echo '{"cwd":"'"$CWD_133"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ ! -e "$GONE_133" ]] && \
   assert_contains "133" "$OUTPUT" "1 stranded claim file(s) removed, whatever pointer they held is gone" && \
   assert_not_contains "133" "$OUTPUT" "LABEL-133"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# --- Test 134: a surviving claim file alone must reach the directive ---
echo "Test 134: memory-restore: a surviving stranded claim file alone still produces a directive"
CWD_134="$TEST_DIR/worktree-134"
mkdir -p "$CWD_134"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
MID_134=$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M)
KEPT_134="$PLANS_DIR/.mr-claimed.99999.20260810T000000-13401"
printf 'k\n2026-01-01T00:00:00+0900\n%s\nLABEL-134\n' "$CWD_134" > "$KEPT_134"
touch -t "$MID_134" "$KEPT_134"
OUTPUT=$(echo '{"cwd":"'"$CWD_134"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ -e "$KEPT_134" ]] && \
   assert_contains "134" "$OUTPUT" "1 stranded claim file(s)" && \
   assert_contains "134" "$OUTPUT" "should still hold a checkpoint pointer no scan reads" && \
   assert_not_contains "134" "$OUTPUT" "LABEL-134"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$KEPT_134"

# --- Test 135: one file with no establishable age must not end the sweep ---
# The unmeasured branch leaves the iteration with `continue`. A `break` there would look
# identical in every single-file fixture, and would silently abandon every later file in
# the directory while the report still read as complete.
echo "Test 135: memory-restore: an unmeasurable file does not abort the rest of the sweep"
CWD_135="$TEST_DIR/worktree-135"
mkdir -p "$CWD_135" "$TEST_DIR/fakebin-135"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
REAL_STAT_135=$(command -v stat)
cat > "$TEST_DIR/fakebin-135/stat" <<FAKESTAT
#!/bin/sh
for a in "\$@"; do
    case "\$a" in *nostat*) exit 1;; esac
done
exec $REAL_STAT_135 "\$@"
FAKESTAT
chmod +x "$TEST_DIR/fakebin-135/stat"
OLD_135=$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)
# Glob order decides which one the loop meets first; the unmeasurable one goes first, so
# a `break` would take the second file with it.
NOSTAT_135="$PLANS_DIR/.mr-tmp.99999.a-nostat-13501"
AFTER_135="$PLANS_DIR/.mr-tmp.99999.b-empty-13502"
printf 'k\n2026-01-01T00:00:00+0900\n%s\nLABEL-135\n' "$CWD_135" > "$NOSTAT_135"
printf '' > "$AFTER_135"
touch -t "$OLD_135" "$NOSTAT_135" "$AFTER_135"
OUTPUT=$(echo '{"cwd":"'"$CWD_135"'"}' | PATH="$TEST_DIR/fakebin-135:$PATH" bash "$TEST_DIR/on-session-clear.sh")
if [[ -e "$NOSTAT_135" ]] && [[ ! -e "$AFTER_135" ]] && \
   assert_contains "135" "$OUTPUT" "have an age this hook could NOT establish" && \
   assert_contains "135" "$OUTPUT" "verified empty, so nothing was lost" && \
   assert_not_contains "135" "$OUTPUT" "LABEL-135"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$NOSTAT_135"
rm -rf "$TEST_DIR/fakebin-135"

# --- Test 136: the candidates-block tail carries every litter outcome, not one ---
# The tail renders only when the flag scan produced a row, and its wording differs from
# the fallback's, so a fallback assertion transfers nothing. Deleting any one tail
# sentence used to leave the suite green.
echo "Test 136: memory-restore: every litter outcome is worded in the candidates block too"
CWD_136="$TEST_DIR/worktree-136"
mkdir -p "$CWD_136"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
MR_FLAG_136="$PLANS_DIR/.pending-memory-restore-20260718T000000-13601"
printf '%s\n%s\n%s\n%s\n' "sess_136" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_136" "checkpoint-136" > "$MR_FLAG_136"
OLD_136=$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)
MID_136=$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M)
CGONE_136="$PLANS_DIR/.mr-claimed.99999.20260101T000000-13602"
CKEPT_136="$PLANS_DIR/.mr-claimed.99999.20260810T000000-13603"
TGONE_136="$PLANS_DIR/.mr-tmp.99999.a-empty-13604"
TKEPT_136="$PLANS_DIR/.mr-tmp.99999.b-empty-13605"
TBODY_136="$PLANS_DIR/.mr-tmp.99999.c-body-13606"
# The recorded path deliberately is NOT this session's cwd. Writing $CWD_136 there would
# make an absence assertion meaningless, since the matched flag's own row prints that
# directory legitimately — the label assertions would pass while a leak of line 3 went
# unnoticed.
DECOY_136="$TEST_DIR/decoy-136-another-project"
printf 'k\n2026-01-01T00:00:00+0900\n%s\nLABEL-136A\n' "$DECOY_136" > "$CGONE_136"
printf 'k\n2026-01-01T00:00:00+0900\n%s\nLABEL-136B\n' "$DECOY_136" > "$CKEPT_136"
printf '' > "$TGONE_136"
printf '' > "$TKEPT_136"
printf 'k\n2026-01-01T00:00:00+0900\n%s\nLABEL-136C\n' "$DECOY_136" > "$TBODY_136"
touch -t "$OLD_136" "$CGONE_136" "$TGONE_136" "$TBODY_136"
touch -t "$MID_136" "$CKEPT_136" "$TKEPT_136"
OUTPUT=$(echo '{"cwd":"'"$CWD_136"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "136" "$OUTPUT" "Checkpoint candidates seen at this /clear" && \
   assert_contains "136" "$OUTPUT" "1 stranded claim file(s) removed, whatever pointer they held is gone" && \
   assert_contains "136" "$OUTPUT" "1 stranded claim file(s) should still hold a checkpoint pointer no scan reads" && \
   assert_contains "136" "$OUTPUT" "1 interrupted flag write(s) removed, verified empty, nothing lost" && \
   assert_contains "136" "$OUTPUT" "1 interrupted flag write(s) left in place, verified empty" && \
   assert_contains "136" "$OUTPUT" "1 interrupted flag write(s) removed were NOT empty" && \
   assert_not_contains "136" "$OUTPUT" "LABEL-136A" && \
   assert_not_contains "136" "$OUTPUT" "LABEL-136B" && \
   assert_not_contains "136" "$OUTPUT" "LABEL-136C" && \
   assert_not_contains "136" "$OUTPUT" "decoy-136-another-project"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$CKEPT_136" "$TKEPT_136"

# --- Test 137: the candidates block reports litter it could not remove ---
# Test 136 cannot reach this sentence: making `rm` fail needs a non-writable plans
# directory, which also stops the flag being claimed. That is fine — an unclaimable flag
# still produces a row, so the tail still renders, and the two outcomes coexist.
echo "Test 137: memory-restore: unremovable litter is reported inside the candidates block"
if [[ "$(id -u)" == "0" ]]; then
    echo "  SKIP (root writes a directory regardless of the write bit)"
    PASS=$((PASS + 1))
else
    CWD_137="$TEST_DIR/worktree-137"
    mkdir -p "$CWD_137"
    rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
    MR_FLAG_137="$PLANS_DIR/.pending-memory-restore-20260718T000000-13701"
    printf '%s\n%s\n%s\n%s\n' "sess_137" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_137" "checkpoint-137" > "$MR_FLAG_137"
    STUCK_137="$PLANS_DIR/.mr-claimed.99999.20260101T000000-13702"
    printf 'k\n2026-01-01T00:00:00+0900\n%s\nLABEL-137\n' "$TEST_DIR/decoy-137-another-project" > "$STUCK_137"
    touch -t "$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)" "$STUCK_137"
    trap 'chmod 700 "$PLANS_DIR" 2>/dev/null; cleanup' EXIT
    chmod 0555 "$PLANS_DIR"
    OUTPUT=$(echo '{"cwd":"'"$CWD_137"'"}' | bash "$TEST_DIR/on-session-clear.sh" 2>/dev/null)
    chmod 700 "$PLANS_DIR"
    trap cleanup EXIT
    if assert_contains "137" "$OUTPUT" "Checkpoint candidates seen at this /clear" && \
       assert_contains "137" "$OUTPUT" "1 litter file(s) could NOT be removed" && \
       assert_not_contains "137" "$OUTPUT" "LABEL-137" && \
       assert_not_contains "137" "$OUTPUT" "decoy-137-another-project"; then
        echo "  PASS"
        PASS=$((PASS + 1))
    else
        echo "  FAIL"
        FAIL=$((FAIL + 1))
    fi
    rm -f "$STUCK_137" "$MR_FLAG_137"
fi

# --- Test 138: the candidates block reports litter whose age it could not establish ---
# The `stat` shim has to fail for the LITTER file only. A blanket failure takes the flag's
# own row out, and without a row the tail never renders, which is how this sentence stayed
# untested: every fixture that produced it landed in the fallback instead.
echo "Test 138: memory-restore: litter with no establishable age is reported inside the candidates block"
CWD_138="$TEST_DIR/worktree-138"
mkdir -p "$CWD_138" "$TEST_DIR/fakebin-138"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
REAL_STAT_138=$(command -v stat)
cat > "$TEST_DIR/fakebin-138/stat" <<FAKESTAT
#!/bin/sh
for a in "\$@"; do
    case "\$a" in *nostat138*) exit 1;; esac
done
exec $REAL_STAT_138 "\$@"
FAKESTAT
chmod +x "$TEST_DIR/fakebin-138/stat"
MR_FLAG_138="$PLANS_DIR/.pending-memory-restore-20260718T000000-13801"
printf '%s\n%s\n%s\n%s\n' "sess_138" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_138" "checkpoint-138" > "$MR_FLAG_138"
NOSTAT_138="$PLANS_DIR/.mr-tmp.99999.nostat138-13802"
printf 'k\n2026-01-01T00:00:00+0900\n%s\nLABEL-138\n' "$TEST_DIR/decoy-138-another-project" > "$NOSTAT_138"
touch -t "$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)" "$NOSTAT_138"
OUTPUT=$(echo '{"cwd":"'"$CWD_138"'"}' | PATH="$TEST_DIR/fakebin-138:$PATH" bash "$TEST_DIR/on-session-clear.sh")
if [[ -e "$NOSTAT_138" ]] && \
   assert_contains "138" "$OUTPUT" "Checkpoint candidates seen at this /clear" && \
   assert_contains "138" "$OUTPUT" "1 litter file(s) whose age could NOT be established" && \
   assert_not_contains "138" "$OUTPUT" "LABEL-138" && \
   assert_not_contains "138" "$OUTPUT" "decoy-138-another-project"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$NOSTAT_138"
rm -rf "$TEST_DIR/fakebin-138"

# --- Test 139: scope_key() must not answer from an inherited GIT_DIR ---
# `rev-parse` reads the environment before it looks at `-C`, so an exported GIT_DIR makes
# every directory report that repository — including one inside no repository at all.
# on-session-clear.sh uses this answer to decide whether another session's recorded path
# and label may be printed, so collapsing every scope to one identity does not merely lose
# precision: every foreign flag compares as "same repository, selectable" and is disclosed.
# `git rebase --exec` and git hooks both export it, so a session launched from either
# inherits it.
echo "Test 139: scope_key: an inherited GIT_DIR does not make a non-repository report a repository"
REPO_139="$TEST_DIR/repo-139"
PLAIN_139="$TEST_DIR/plain-139"
mkdir -p "$REPO_139" "$PLAIN_139"
git -C "$REPO_139" init -q . 2>/dev/null
# The control comes first: if the sandbox itself sat inside a repository, or scope_key were
# broken outright, the plain directory would not answer `dir:` even without GIT_DIR, and the
# main assertion below would prove nothing.
CONTROL_139=$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR bash -c 'source "'"$LIB_COMMON"'"; scope_key "'"$PLAIN_139"'"')
# Only GIT_DIR is meant to be inherited here; leaving the other two to whatever the
# ambient environment holds would make the result depend on how the suite was launched.
INHERITED_139=$(env -u GIT_WORK_TREE -u GIT_COMMON_DIR GIT_DIR="$REPO_139/.git" bash -c 'source "'"$LIB_COMMON"'"; scope_key "'"$PLAIN_139"'"')
REALREPO_139=$(env -u GIT_WORK_TREE -u GIT_COMMON_DIR GIT_DIR="$REPO_139/.git" bash -c 'source "'"$LIB_COMMON"'"; scope_key "'"$REPO_139"'"')
if [[ "$CONTROL_139" == dir:* ]] && \
   [[ "$INHERITED_139" == "$CONTROL_139" ]] && \
   [[ "$REALREPO_139" == repo:* ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    echo "    control (no GIT_DIR):   $CONTROL_139"
    echo "    with GIT_DIR inherited: $INHERITED_139"
    echo "    the repository itself:  $REALREPO_139"
    FAIL=$((FAIL + 1))
fi

# --- Test 140: an ancient matching flag is not restored on an age nobody measured ---
# Substituting `now` for a failed `stat` made the age zero, which reads as fresh: a
# checkpoint from years ago was announced as this session's, a full restore directive was
# emitted for it, and then the flag was deleted — the one path that destroys the pointer,
# taken on a number the hook never established. Unlike test 118 the clock works here, so
# the only thing missing is the file's own mtime.
echo "Test 140: memory-restore: a matching flag with no establishable age is reported, not restored or consumed"
CWD_140="$TEST_DIR/worktree-140"
mkdir -p "$CWD_140" "$TEST_DIR/fakebin-140"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/fakebin-140/stat"
chmod +x "$TEST_DIR/fakebin-140/stat"
FLAG_140="$PLANS_DIR/.pending-memory-restore-20230101T000000-14001"
printf '%s\n%s\n%s\n%s\n' "sess_140" "2023-01-01T00:00:00+0900" "$CWD_140" "ancient-checkpoint-140" > "$FLAG_140"
touch -t 202301010000 "$FLAG_140"
OUTPUT=$(echo '{"cwd":"'"$CWD_140"'"}' | PATH="$TEST_DIR/fakebin-140:$PATH" bash "$TEST_DIR/on-session-clear.sh")
if [[ -e "$FLAG_140" ]] && \
   assert_contains "140" "$OUTPUT" "ancient-checkpoint-140" && \
   assert_contains "140" "$OUTPUT" "age unknown" && \
   assert_contains "140" "$OUTPUT" "age could NOT be established" && \
   assert_not_contains "140" "$OUTPUT" "MATCHES this session" && \
   assert_not_contains "140" "$OUTPUT" "0m ago" && \
   assert_not_contains "140" "$OUTPUT" "MEMORY RESTORE"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$FLAG_140"
rm -rf "$TEST_DIR/fakebin-140"

# --- Test 141: entries that are not plain regular files are reported, never swept ---
# `-f` and `-s` follow a symlink while `stat` does not, so a link to a live file read as
# old and non-empty, was deleted — taking only the LINK — and was then reported as a
# destroyed body while the target sat untouched. A dangling link, a directory or a socket
# left through the old `-f` guard counted by nothing at all. Nothing this hook writes is
# anything but a regular file, so all of these arrived from outside and none of them can
# be measured on its own terms.
echo "Test 141: memory-restore: symlinks and non-regular entries are reported, not swept or misreported"
CWD_141="$TEST_DIR/worktree-141"
mkdir -p "$CWD_141"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
rm -rf "$PLANS_DIR"/.mr-tmp.99999.adir-14103
OLD_141=$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)
TARGET_141="$TEST_DIR/live-target-141"
printf 'k\n2026-01-01T00:00:00+0900\n%s\nLABEL-141\n' "$CWD_141" > "$TARGET_141"
LINK_141="$PLANS_DIR/.mr-tmp.99999.link-14101"
DANGLE_141="$PLANS_DIR/.mr-tmp.99999.dangle-14102"
ADIR_141="$PLANS_DIR/.mr-tmp.99999.adir-14103"
ln -s "$TARGET_141" "$LINK_141"
ln -s "$TEST_DIR/no-such-file-141" "$DANGLE_141"
mkdir -p "$ADIR_141"
touch -h -t "$OLD_141" "$LINK_141" "$DANGLE_141" 2>/dev/null || true
OUTPUT=$(echo '{"cwd":"'"$CWD_141"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ -L "$LINK_141" ]] && [[ -L "$DANGLE_141" ]] && [[ -d "$ADIR_141" ]] && [[ -s "$TARGET_141" ]] && \
   assert_contains "141" "$OUTPUT" "3 litter file(s)" && \
   assert_contains "141" "$OUTPUT" "have an age this hook could NOT establish" && \
   assert_not_contains "141" "$OUTPUT" "were NOT empty" && \
   assert_not_contains "141" "$OUTPUT" "verified empty" && \
   assert_not_contains "141" "$OUTPUT" "LABEL-141"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$LINK_141" "$DANGLE_141" "$TARGET_141"
rm -rf "$ADIR_141"

# --- Test 142: a legend must not describe a row the cap kept off screen ---
# The two hidden-row counters exist so a legend never talks about a row nobody can see.
# These two legends fired on the total count instead, so five expired rows could push the
# only unverifiable row past the cap while the notes still said "Rows marked ... Show the
# recorded path", with no such row printed and no count of what was withheld.
echo "Test 142: memory-restore: the scope-unverifiable legend fires only when such a row is on screen"
CWD_142="$TEST_DIR/worktree-142"
mkdir -p "$CWD_142"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
OLD_142=$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M)
for n in 1 2 3 4 5; do
    F="$PLANS_DIR/.pending-memory-restore-2026081600014${n}-1420${n}"
    printf '%s\n%s\n%s\n%s\n' "sess_142_${n}" "2026-08-16T00:00:00+0900" "$CWD_142" "expired-142-${n}" > "$F"
    touch -t "$OLD_142" "$F"
done
UNVER_142="$PLANS_DIR/.pending-memory-restore-20260816000146-14206"
printf '%s\n%s\n%s\n%s\n' "sess_142_u" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$TEST_DIR/removed-worktree-142" "unver-142" > "$UNVER_142"
OUTPUT=$(echo '{"cwd":"'"$CWD_142"'"}' | bash "$TEST_DIR/on-session-clear.sh")
# Every assertion here is a negative, so an empty report would satisfy all of them. The
# two positives are what make the negatives mean something: the block was produced and it
# does carry rows, and the row that is missing is missing because the cap withheld it.
if assert_contains "142" "$OUTPUT" "Checkpoint candidates seen at this /clear" && \
   assert_contains "142" "$OUTPUT" "expired-142-1" && \
   assert_not_contains "142" "$OUTPUT" "unver-142" && \
   assert_not_contains "142" "$OUTPUT" "Show the recorded path and let the user decide"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.*

# --- Test 143: a claim this hook could not delete is reported, not asserted away ---
# `mv` then `rm` is the one-shot contract. The `rm` was unchecked, so a failure left the
# file alive as `.mr-claimed.*` — outside the scan glob — while the report said the flag
# had been consumed or swept.
echo "Test 143: memory-restore: a flag claimed but not deleted is reported as surviving"
CWD_143="$TEST_DIR/worktree-143"
mkdir -p "$CWD_143" "$TEST_DIR/fakebin-143"
rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
REAL_RM_143=$(command -v rm)
cat > "$TEST_DIR/fakebin-143/rm" <<FAKERM
#!/bin/sh
for a in "\$@"; do
    case "\$a" in *.mr-claimed.*) exit 1;; esac
done
exec $REAL_RM_143 "\$@"
FAKERM
chmod +x "$TEST_DIR/fakebin-143/rm"
FLAG_143="$PLANS_DIR/.pending-memory-restore-20260816000143-14301"
printf '%s\n%s\n%s\n%s\n' "sess_143" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_143" "checkpoint-143" > "$FLAG_143"
OUTPUT=$(echo '{"cwd":"'"$CWD_143"'"}' | PATH="$TEST_DIR/fakebin-143:$PATH" bash "$TEST_DIR/on-session-clear.sh")
CLAIMED_143=$(find "$PLANS_DIR" -name '.mr-claimed.*' | wc -l | tr -d ' ')
if [[ "$CLAIMED_143" == "1" ]] && \
   assert_contains "143" "$OUTPUT" "could NOT delete"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -rf "$TEST_DIR/fakebin-143"
/bin/rm -f "$PLANS_DIR"/.mr-claimed.* "$FLAG_143"

# --- Test 144: the seven-day sweep must not count a removal that failed ---
# Sibling of 143 on the other `rm`. A non-matching flag past seven days is claimed and
# deleted; counting the sweep without checking the delete asserted a removal that may not
# have happened. This one produces no row, so it also pins the assembled fallback
# sentence, which is the only place that reports it here.
echo "Test 144: memory-restore: a sweep whose delete failed is not counted as removed"
CWD_144="$TEST_DIR/worktree-144"
mkdir -p "$CWD_144" "$TEST_DIR/fakebin-144"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
REAL_RM_144=$(command -v rm)
cat > "$TEST_DIR/fakebin-144/rm" <<FAKERM
#!/bin/sh
for a in "\$@"; do
    case "\$a" in *.mr-claimed.*) exit 1;; esac
done
exec $REAL_RM_144 "\$@"
FAKERM
chmod +x "$TEST_DIR/fakebin-144/rm"
OLD_144=$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)
FLAG_144="$PLANS_DIR/.pending-memory-restore-20260101000144-14401"
printf '%s\n%s\n%s\n%s\n' "sess_144" "2026-01-01T00:00:00+0900" "$TEST_DIR/elsewhere-144" "checkpoint-144" > "$FLAG_144"
touch -t "$OLD_144" "$FLAG_144"
OUTPUT=$(echo '{"cwd":"'"$CWD_144"'"}' | PATH="$TEST_DIR/fakebin-144:$PATH" bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "144" "$OUTPUT" "could NOT delete" && \
   assert_not_contains "144" "$OUTPUT" "removed as older than 7 days" && \
   assert_not_contains "144" "$OUTPUT" "checkpoint-144"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
/bin/rm -rf "$TEST_DIR/fakebin-144"
/bin/rm -f "$PLANS_DIR"/.mr-claimed.* "$FLAG_144"

# --- Test 145: a broken clock is as disqualifying as a broken stat ---
# It takes both to have an age. `date` failing sets the sampled clock to 0, so every real
# mtime is in the future and the negative difference was clamped to zero — "fresh" in
# every comparison below it. Test 140 breaks `stat`; here `stat` works and only the clock
# is gone, which is the half that was still live.
echo "Test 145: memory-restore: a matching flag is not restored when only the clock is broken"
CWD_145="$TEST_DIR/worktree-145"
mkdir -p "$CWD_145" "$TEST_DIR/fakebin-145"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/fakebin-145/date"
chmod +x "$TEST_DIR/fakebin-145/date"
FLAG_145="$PLANS_DIR/.pending-memory-restore-20230101000145-14501"
printf '%s\n%s\n%s\n%s\n' "sess_145" "2023-01-01T00:00:00+0900" "$CWD_145" "ancient-checkpoint-145" > "$FLAG_145"
touch -t 202301010000 "$FLAG_145"
OUTPUT=$(echo '{"cwd":"'"$CWD_145"'"}' | PATH="$TEST_DIR/fakebin-145:$PATH" bash "$TEST_DIR/on-session-clear.sh")
if [[ -e "$FLAG_145" ]] && \
   assert_contains "145" "$OUTPUT" "ancient-checkpoint-145" && \
   assert_contains "145" "$OUTPUT" "age could NOT be established" && \
   assert_not_contains "145" "$OUTPUT" "MATCHES this session" && \
   assert_not_contains "145" "$OUTPUT" "MEMORY RESTORE"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_145"
/bin/rm -rf "$TEST_DIR/fakebin-145"

# --- Test 146: an unverifiable flag forbids the "none recorded this scope" claim ---
# The sentence asserts that every flag was compared and none matched. A flag whose
# recorded path could not be resolved was never compared at all, so the claim states
# as fact the one thing this scan failed to establish.
echo "Test 146: memory-restore: an unverifiable flag suppresses the none-matched claim"
CWD_146="$TEST_DIR/worktree-146"
mkdir -p "$CWD_146"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
FLAG_146="$PLANS_DIR/.pending-memory-restore-20260818T000146-14601"
printf '%s\n%s\n%s\n%s\n' "sess_146" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$TEST_DIR/gone-146" "checkpoint-146" > "$FLAG_146"
OUTPUT=$(echo '{"cwd":"'"$CWD_146"'"}' | bash "$TEST_DIR/on-session-clear.sh")
# The positive assertion is load-bearing: without it an empty report would satisfy
# the absence check, which is how a negative-only test guards nothing.
if assert_contains "146" "$OUTPUT" "scope unverifiable, recorded path unreachable" && \
   assert_not_contains "146" "$OUTPUT" "No checkpoint flag recorded this session's working directory" && \
   assert_file_exists "146" "$FLAG_146"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_146"

# --- Test 147: the same claim is unfounded when NOTHING could be compared ---
# The hook's own directory does not resolve, so no flag was checked against this
# session at all — a stronger version of Test 146's objection.
echo "Test 147: memory-restore: an unresolvable own scope suppresses the none-matched claim"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
FLAG_147="$PLANS_DIR/.pending-memory-restore-20260818T000147-14701"
printf '%s\n%s\n%s\n%s\n' "sess_147" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$TEST_DIR/worktree-147" "checkpoint-147" > "$FLAG_147"
OUTPUT=$(echo '{"cwd":"'"$TEST_DIR/never-created-147"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "147" "$OUTPUT" "left unclassified because" && \
   assert_not_contains "147" "$OUTPUT" "No checkpoint flag recorded this session's working directory" && \
   assert_file_exists "147" "$FLAG_147"; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_147"

# --- Tests 148-151: every state that bears on the none-matched sentence ---
# The sentence claims BOTH that no flag recorded this session's working directory and that
# nothing was consumed. Each fixture below adds one flag that contradicts it
# alongside a row-producing flag, because the whole block is gated on at least
# one displayed row existing — in isolation these states take the fallback path
# and the sentence never appears, which is why they went unnoticed.
# Each test asserts the row IS present as well, so an empty report cannot pass.
mr_bearing_repo() {
    MR_R="$TEST_DIR/repo-$1"; MR_W="$TEST_DIR/wt-$1"
    mkdir -p "$MR_R"
    git -C "$MR_R" init -q 2>/dev/null
    git -C "$MR_R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
    git -C "$MR_R" worktree add -q --detach "$MR_W" HEAD 2>/dev/null
    /bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
    /bin/rm -rf "$PLANS_DIR"/.pending-memory-restore-dir
    printf '%s\n%s\n%s\n%s\n' "sess_$1" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$MR_W" "row-maker-$1" \
        > "$PLANS_DIR/.pending-memory-restore-2026081800$1-$1"
}
mr_bearing_check() {
    if assert_contains "$1" "$OUTPUT" "same repository, selectable" && \
       assert_not_contains "$1" "$OUTPUT" "No checkpoint flag recorded this session's working directory"; then
        echo "  PASS"; PASS=$((PASS + 1))
    else
        echo "  FAIL"; FAIL=$((FAIL + 1))
    fi
}

echo "Test 148: memory-restore: an unreadable flag suppresses the none-matched claim"
mr_bearing_repo 148
if [[ "$(id -u)" == "0" ]]; then
    echo "  SKIP (root reads a mode-000 file, so the flag would not be unreadable)"
    PASS=$((PASS + 1))
else
    printf '%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$MR_R" "unreadable-148" > "$PLANS_DIR/.pending-memory-restore-x148"
    chmod 000 "$PLANS_DIR/.pending-memory-restore-x148"
    OUTPUT=$(echo '{"cwd":"'"$MR_R"'"}' | bash "$TEST_DIR/on-session-clear.sh")
    mr_bearing_check 148
    chmod 644 "$PLANS_DIR/.pending-memory-restore-x148"; /bin/rm -f "$PLANS_DIR/.pending-memory-restore-x148"
fi

echo "Test 149: memory-restore: an unopenable flag name suppresses the none-matched claim"
mr_bearing_repo 149
mkdir -p "$PLANS_DIR/.pending-memory-restore-dir"
OUTPUT=$(echo '{"cwd":"'"$MR_R"'"}' | bash "$TEST_DIR/on-session-clear.sh")
mr_bearing_check 149
/bin/rm -rf "$PLANS_DIR/.pending-memory-restore-dir"

# The sweep DELETES this flag, so the sentence's second half — "no flag was
# consumed" — is false in the same message that reports the removal.
echo "Test 150: memory-restore: a swept flag falsifies the no-flag-consumed half"
mr_bearing_repo 150
printf '%s\n%s\n%s\n%s\n' "s" "2018-01-01T00:00:00+0900" "$TEST_DIR/other-150" "old-150" > "$PLANS_DIR/.pending-memory-restore-x150"
mkdir -p "$TEST_DIR/other-150"
touch -t 201801010000 "$PLANS_DIR/.pending-memory-restore-x150"
OUTPUT=$(echo '{"cwd":"'"$MR_R"'"}' | bash "$TEST_DIR/on-session-clear.sh")
mr_bearing_check 150
/bin/rm -f "$PLANS_DIR/.pending-memory-restore-x150"

echo "Test 151: memory-restore: a malformed flag suppresses the none-matched claim"
mr_bearing_repo 151
printf '%s\n%s\n\n\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" > "$PLANS_DIR/.pending-memory-restore-x151"
OUTPUT=$(echo '{"cwd":"'"$MR_R"'"}' | bash "$TEST_DIR/on-session-clear.sh")
mr_bearing_check 151
/bin/rm -f "$PLANS_DIR/.pending-memory-restore-x151"

# --- Test 152: the sentence must still be PRINTED when nothing bears against it ---
# Tests 146-151 all assert its ABSENCE. Absence-only coverage cannot tell a correct
# suppression from a permanent one: deleting any subtracted term from the bearing
# sum would silence the sentence forever and every one of those tests would still
# pass. This is the positive direction, and it is what makes those subtractions
# load-bearing.
echo "Test 152: memory-restore: the none-matched sentence is printed when nothing bears"
mr_bearing_repo 152
OUTPUT=$(echo '{"cwd":"'"$MR_R"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "152" "$OUTPUT" "same repository, selectable" && \
   assert_contains "152" "$OUTPUT" "No checkpoint flag recorded this session's working directory"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi

# --- Tests 153-154: a flag name that is a link is never read ---
# `-f` follows a symlink, so before this guard the loop read lines 2-4 of whatever
# the link pointed at and PRINTED lines 3 and 4 in the row — an arbitrary file the
# user can read, injected into this session's context and re-read at every /clear,
# since a non-matching flag is never consumed. A hard link reaches the same
# disclosure while being neither -L nor irregular, so the link count closes it.
# Both fixtures put a marker in the target that must never appear in the output.
mr_link_target() {
    MR_T="$TEST_DIR/link-target-$1"
    printf '%s\n%s\n%s\n%s\n' "x" "2026-08-18T00:00:00+0900" "LEAKPATH-$1" "LEAKLABEL-$1" > "$MR_T"
    /bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-claimed.* "$PLANS_DIR"/.mr-tmp.*
}
mr_link_check() {
    if assert_not_contains "$1" "$OUTPUT" "LEAKLABEL-$1" && \
       assert_not_contains "$1" "$OUTPUT" "LEAKPATH-$1" && \
       assert_contains "$1" "$OUTPUT" "are a link or share an inode and were NOT read"; then
        echo "  PASS"; PASS=$((PASS + 1))
    else
        echo "  FAIL"; FAIL=$((FAIL + 1))
    fi
}

echo "Test 153: memory-restore: a symlinked flag name is never read or printed"
CWD_153="$TEST_DIR/wd-153"; mkdir -p "$CWD_153"
mr_link_target 153
ln -s "$MR_T" "$PLANS_DIR/.pending-memory-restore-20260818T000153-153"
OUTPUT=$(echo '{"cwd":"'"$CWD_153"'"}' | bash "$TEST_DIR/on-session-clear.sh")
mr_link_check 153
/bin/rm -f "$PLANS_DIR/.pending-memory-restore-20260818T000153-153"

echo "Test 154: memory-restore: a hard-linked flag name is never read or printed"
CWD_154="$TEST_DIR/wd-154"; mkdir -p "$CWD_154"
mr_link_target 154
ln "$MR_T" "$PLANS_DIR/.pending-memory-restore-20260818T000154-154"
OUTPUT=$(echo '{"cwd":"'"$CWD_154"'"}' | bash "$TEST_DIR/on-session-clear.sh")
mr_link_check 154
/bin/rm -f "$PLANS_DIR/.pending-memory-restore-20260818T000154-154"

# --- Test 155: the three states declared NOT to bear must not suppress the sentence ---
# The bearing sum subtracts stale-kept, foreign and outside because each was compared
# and established to be somewhere this session can name. Only the `same` subtraction
# was covered before: deleting any of the other three silently withheld a true
# sentence and every test still passed. One fixture carries all three at once.
echo "Test 155: memory-restore: compared-and-elsewhere flags do not suppress the sentence"
mr_bearing_repo 155
OTHER_155="$TEST_DIR/otherrepo-155"; mkdir -p "$OTHER_155" "$TEST_DIR/plain-155"
git -C "$OTHER_155" init -q 2>/dev/null
git -C "$OTHER_155" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
# foreign: both sides resolve to a repository, and they differ
printf '%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$OTHER_155" "foreign-155" > "$PLANS_DIR/.pending-memory-restore-f155"
# outside: resolves, but is a directory inside no repository
printf '%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$TEST_DIR/plain-155" "outside-155" > "$PLANS_DIR/.pending-memory-restore-o155"
# stale-kept: non-matching and past the 24-hour window, left where it is
# Three days back: past the 24-hour window, well short of the seven-day sweep.
# A fixed date drifts into the sweep as the calendar moves, which is what a literal
# 2026-08-01 did here — it was removed as older than 7 days, not kept.
STALE_155=$(date -v-3d +%Y%m%d%H%M 2>/dev/null || date -d '3 days ago' +%Y%m%d%H%M)
printf '%s\n%s\n%s\n%s\n' "s" "$(date -v-3d +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || date -d '3 days ago' +%Y-%m-%dT%H:%M:%S%z)" "$OTHER_155" "stale-155" > "$PLANS_DIR/.pending-memory-restore-s155"
touch -t "$STALE_155" "$PLANS_DIR/.pending-memory-restore-s155"
OUTPUT=$(echo '{"cwd":"'"$MR_R"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "155" "$OUTPUT" "same repository, selectable" && \
   assert_contains "155" "$OUTPUT" "No checkpoint flag recorded this session's working directory"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi

# --- Test 156: scope_compare's class/priority table, and the caller's coverage ---
# The function decides which flags are printed and which are withheld, and it had no
# direct test: only end-to-end fixtures reached it, so the SET of classes it can emit
# was never pinned. Test 82 sets the precedent for calling a lib-common function
# directly. The second half asserts the caller handles every class the function can
# emit by name, so adding a class for the plan-file subsystem cannot silently land on
# a verdict written for a different one.
echo "Test 156: scope_compare: class and priority for every documented input"
# Chained with && so a failed source or a missing function yields no output at all
# rather than a partial one. Measured, not assumed: with scope_compare renamed away,
# the unchained form prints "/" and this form prints "", and BOTH fail the comparison
# below — each bash -c is a fresh shell, so there is no stale value to publish. The
# chain states the invariant; it does not close a hole.
sc() { bash -c 'source "$1" && scope_compare "$2" "$3" && printf "%s/%s" "$SCOPE_CLASS" "$SCOPE_PRIO"' _ "$LIB_COMMON" "$1" "$2"; }
SC_OK=1
check_sc() {
    local got; got=$(sc "$1" "$2")
    if [[ "$got" != "$3" ]]; then
        echo "  scope_compare('$1','$2') = $got, expected $3"; SC_OK=0
    fi
}
check_sc ""            "repo:/a"     "selfunver/6"
check_sc "repo:/a"     ""            "unver/5"
check_sc "repo:/a"     "repo:/a"     "same/3"
check_sc "repo:/a"     "repo:/b"     "foreign/6"
check_sc "dir:/a"      "dir:/b"      "outside/6"
check_sc "repo:/a"     "dir:/b"      "outside/6"
check_sc ""            ""            "selfunver/6"
# Every class the function can emit must be named by an arm in the caller.
SC_CLASSES=$(grep -o 'SCOPE_CLASS="[a-z]*"' "$LIB_COMMON" | sed 's/.*="//;s/"//' | sort -u)
for c in $SC_CLASSES; do
    grep -q "^ *${c})" "$TEST_DIR/on-session-clear.sh" || { echo "  class '$c' has no arm in the caller"; SC_OK=0; }
done
[[ -n "$SC_CLASSES" ]] || { echo "  no classes found - the grep is broken, not the code"; SC_OK=0; }
if [[ "$SC_OK" -eq 1 ]]; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-[fos]155

# --- Tests 156-157: the `stat` probes must select the form, not trust a number ---
# The probes here pick their fallback on the OUTPUT rather than the exit status,
# because GNU `-f` means --file-system and SUCCEEDS on a regular file. For `%m`
# that is sufficient: GNU prints a mount point, which is not numeric. For `%l` it
# is NOT — GNU's `-f %l` is "maximum length of filenames", typically 255, and a
# number satisfies the same guard the real link count does. The probe order is
# therefore load-bearing: the GNU form has to be asked first, and the BSD form
# kept as its fallback. See https://man7.org/linux/man-pages/man1/stat.1.html
mr_gnu_stat() {
    MR_SHIM="$TEST_DIR/gnustat-$1"; mkdir -p "$MR_SHIM"
    cat > "$MR_SHIM/stat" <<'GNUSTAT'
#!/bin/sh
# GNU coreutils stat(1), emulated for the forms this hook uses. Under `-c` the
# default sequences apply (%h number of hard links, %Y seconds since Epoch, %y a
# human-readable time); under `-f` the FILE SYSTEM is reported, where %l is the
# maximum length of filenames and %m the mount point. Unknown directives print
# `?`. Terse mode (-t) is not emulated.
# https://man7.org/linux/man-pages/man1/stat.1.html
#
# The `-c` answers are DETERMINISTIC STAND-INS, not readings of the file, and
# deliberately so: delegating to the host's own stat would make this shim mean
# different things on a BSD host and a GNU host -- on GNU, `stat -f %l` is the
# 255 this shim exists to simulate, so the fixture would contradict itself on
# the very platform the behaviour is about. A link count of 1 stands for the
# plain file every fixture here plants; no fixture combines this shim with a
# link, which is what tests 153 and 154 cover against the real stat.
case "$1" in
  -c) case "$2" in
        %h) echo 1; exit 0 ;;
        %Y) date +%s; exit 0 ;;
        %y) date '+%Y-%m-%d %H:%M:%S.000000000 +0000'; exit 0 ;;
      esac
      echo '?'; exit 0 ;;
  -f) case "$2" in
        %l) echo 255; exit 0 ;;
        %m) echo /; exit 0 ;;
      esac
      echo '?'; exit 0 ;;
esac
exit 1
GNUSTAT
    chmod +x "$MR_SHIM/stat"
}
echo "Test 156: memory-restore: a plain flag survives the link probe under GNU stat"
mr_bearing_repo 156
mr_gnu_stat 156
OUTPUT=$(echo '{"cwd":"'"$MR_R"'"}' | PATH="$MR_SHIM:$PATH" bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "156" "$OUTPUT" "same repository, selectable" && \
   assert_not_contains "156" "$OUTPUT" "share an inode and were NOT read"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi

echo "Test 157: state file age is established under GNU stat, not left unknown"
CWD_157="$TEST_DIR/wd-157"; mkdir -p "$CWD_157"
KEY_157=$(compute_session_key "$CWD_157")
mr_gnu_stat 157
printf '%s\n%s\n%s\n%s\n%s\n' "sess_157" "$TEST_DIR/transcript-157" "51200" \
    "$(date +%Y-%m-%dT%H:%M:%S%z)" "" > "$PLANS_DIR/.plan-state-${KEY_157}"
OUTPUT=$(echo '{"cwd":"'"$CWD_157"'"}' | PATH="$MR_SHIM:$PATH" bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "157" "$OUTPUT" "State file: found (no plan recorded, age: [0-9]"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$PLANS_DIR/.plan-state-${KEY_157}"

# --- Test 158: the human-readable mtime probe must also ask GNU first ---
# Six call sites carried their own copy of this two-form probe and four asked BSD
# first, chained on the exit status -- which on GNU never reaches the fallback,
# because `-f` means --file-system and succeeds on a regular file. All six now go
# through mtime_human(). The GNU shim answers `-c %y` and gives `-f` the `?` that
# GNU prints for a directive it does not recognise, so a BSD-first probe surfaces
# `?` where the timestamp belongs.
echo "Test 158: plan load reports a real modification time under GNU stat"
create_test_plan
mr_gnu_stat 158
OUTPUT=$(echo '{"prompt":"load the plan","session_id":"sess_158","cwd":"'"$PWD"'"}' \
    | PATH="$MR_SHIM:$PATH" bash "$TEST_DIR/inject-plan.sh")
if assert_contains "158" "$OUTPUT" '\*\*Modified:\*\* 20[0-9][0-9]-'; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi

# --- Test 159: an unverifiable scope must not be blamed on a missing directory ---
# The legend used to assert the recorded directory no longer exists. A directory
# that still exists and merely cannot be entered reaches the same row, and so does a
# repository git declines to resolve, so the hook was stating a cause it never
# established -- the failure this whole change exists to remove. The row is correct;
# only the explanation was invented. Asserting the corrected sentence rather than the
# absence of the old one, so this test can fail when it stops being true.
echo "Test 159: memory-restore: an unenterable but EXISTING path is not called missing"
CWD_159="$TEST_DIR/wd-159"; SEALED_159="$TEST_DIR/sealed-159"
mkdir -p "$CWD_159" "$SEALED_159"
if [[ "$(id -u)" == "0" ]]; then
    echo "  SKIP (root enters a mode-000 directory, so the path would be reachable)"
    PASS=$((PASS + 1))
else
    /bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*
    printf '%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$SEALED_159" "sealed-159" \
        > "$PLANS_DIR/.pending-memory-restore-x159"
    chmod 000 "$SEALED_159"
    OUTPUT=$(echo '{"cwd":"'"$CWD_159"'"}' | bash "$TEST_DIR/on-session-clear.sh")
    chmod 755 "$SEALED_159"
    if [[ -d "$SEALED_159" ]] && \
       assert_contains "159" "$OUTPUT" "scope unverifiable, recorded path unreachable" && \
       assert_contains "159" "$OUTPUT" "the recorded path could not be resolved" && \
       assert_not_contains "159" "$OUTPUT" "the recorded directory no longer exists"; then
        echo "  PASS"; PASS=$((PASS + 1))
    else
        echo "  FAIL"; FAIL=$((FAIL + 1))
    fi
    /bin/rm -f "$PLANS_DIR/.pending-memory-restore-x159"
fi

# --- Test 160: a malformed row must name the file the note tells the user to delete ---
# The note fires on malformed rows and asks the user to delete them, but a malformed
# flag has no label and no recorded path, so the row identified nothing and the
# instruction could not be carried out. The key names a file this hook did NOT
# consume and that belongs to no repository -- neither of the two cases the key was
# withheld for (a matched flag is already gone; a foreign one must not be acted on).
echo "Test 160: memory-restore: a malformed row names its flag so the note is actionable"
CWD_160="$TEST_DIR/wd-160"; mkdir -p "$CWD_160"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*
printf 'sess\n2026-08-19T00:00:00+0900\n' > "$PLANS_DIR/.pending-memory-restore-20260819T000160-160"
OUTPUT=$(echo '{"cwd":"'"$CWD_160"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "160" "$OUTPUT" "malformed flag, no recorded path" && \
   assert_contains "160" "$OUTPUT" "flag 20260819T000160-160"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$PLANS_DIR/.pending-memory-restore-20260819T000160-160"

# --- Test 161: a flag a parallel /clear consumed is a race, not an unopenable name ---
# The glob expands to a list of names; a concurrent session's /clear may legitimately
# consume one before this loop reaches it. The `-f` branch counted that under
# "matched the flag name but could NOT be opened", which reads as a broken permission
# or a corrupt entry when nothing was wrong -- and its own comment listed three causes
# without this one. The shim deletes the SECOND flag while the FIRST is being probed,
# which is exactly where the race falls, and is deterministic.
echo "Test 161: memory-restore: a concurrently consumed flag is reported as a race"
CWD_161="$TEST_DIR/wd-161"; mkdir -p "$CWD_161" "$TEST_DIR/race-161"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*
printf '%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$TEST_DIR/elsewhere-161" "first-161" \
    > "$PLANS_DIR/.pending-memory-restore-a161"
printf '%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$TEST_DIR/elsewhere-161" "second-161" \
    > "$PLANS_DIR/.pending-memory-restore-b161"
REAL_STAT_161=$(command -v stat)
printf '#!/bin/sh\nrm -f "%s"\nexec %s "$@"\n' "$PLANS_DIR/.pending-memory-restore-b161" "$REAL_STAT_161" \
    > "$TEST_DIR/race-161/stat"
chmod +x "$TEST_DIR/race-161/stat"
OUTPUT=$(echo '{"cwd":"'"$CWD_161"'"}' | PATH="$TEST_DIR/race-161:$PATH" bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "161" "$OUTPUT" "claimed concurrently by another session" && \
   assert_not_contains "161" "$OUTPUT" "matched the flag name but could NOT be opened"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-[ab]161

# --- Test 162: a backslash in a displayed path must not truncate the directive ---
# The assembled directive is emitted with `printf '%b'`, which is why labels, paths
# and timestamps go through _mr_clean. The scope line and PLANS_DIR did not, and both
# come from the environment: a directory named with a `\c` sequence ended printf
# output there, silently dropping the candidate rows, the restore directive, the
# state block and -- on the plan path -- the whole plan injection. A `\n` forges
# structure instead of truncating. The control is the same fixture under a plain
# directory name.
echo "Test 162: memory-restore: a backslash in the session path does not truncate output"
CWD_162_PLAIN="$TEST_DIR/wd-162-plain"
CWD_162_BS="$TEST_DIR/wd-162-a\\cb"
mkdir -p "$CWD_162_PLAIN" "$CWD_162_BS"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*
mk_162() {
    printf '%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$TEST_DIR/elsewhere-162" "lbl-162" \
        > "$PLANS_DIR/.pending-memory-restore-x162"
}
mk_162
OUT_PLAIN=$(printf '{"cwd":"%s"}' "$CWD_162_PLAIN" | bash "$TEST_DIR/on-session-clear.sh")
mk_162
# The only JSON-hostile character in this path is the backslash, so doubling it is
# the whole of the escaping needed -- no interpreter required.
CWD_162_BS_JSON=${CWD_162_BS//\\/\\\\}
OUT_BS=$(printf '{"cwd":"%s"}' "$CWD_162_BS_JSON" | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "162" "$OUT_PLAIN" "State check" && \
   assert_contains "162" "$OUT_BS" "State check"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$PLANS_DIR/.pending-memory-restore-x162"

# --- Test 163: a failed clock must leave the state age unknown, not enormous ---
# This was the one unguarded `date` fork left in the file. An empty capture makes
# bash evaluate `(( ( - <mtime>) / 60 ))`, so the state line reported an age of
# roughly minus twenty-nine million minutes -- a number, and therefore not obviously
# a failure to whoever reads it. `?` is already the initialised value; the sibling
# capture for the flag scan validates the same reading for the same reason.
echo "Test 163: state age is left unknown when the clock cannot be read"
CWD_163="$TEST_DIR/wd-163"; mkdir -p "$CWD_163" "$TEST_DIR/nodate-163"
KEY_163=$(compute_session_key "$CWD_163")
printf '%s\n%s\n%s\n%s\n%s\n' "sess_163" "$TEST_DIR/transcript-163" "51200" \
    "$(date +%Y-%m-%dT%H:%M:%S%z)" "" > "$PLANS_DIR/.plan-state-${KEY_163}"
printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/nodate-163/date"
chmod +x "$TEST_DIR/nodate-163/date"
OUTPUT=$(echo '{"cwd":"'"$CWD_163"'"}' | PATH="$TEST_DIR/nodate-163:$PATH" bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "163" "$OUTPUT" "age: ?m" && \
   assert_not_contains "163" "$OUTPUT" "age: -"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$PLANS_DIR/.plan-state-${KEY_163}"

# --- Tests 164-165: the two skipped-scan directives must NAME the directory ---
# Both exist to tell the reader which path to look at, and both ran with an empty one.
# The sanitised display copy of PLANS_DIR was assigned inside the scan block, and
# these two branches are the `elif`s of the very `if` that opens it -- they run
# exactly when that assignment did not. Nothing covered either branch's path text.
echo "Test 164: an uninspectable plans directory is named in the directive"
CWD_164="$TEST_DIR/wd-164"; mkdir -p "$CWD_164"
if [[ "$(id -u)" == "0" ]]; then
    echo "  SKIP (root inspects a mode-000 directory, so the branch is unreachable)"
    PASS=$((PASS + 1))
else
    trap 'chmod 700 "$PLANS_DIR" 2>/dev/null; cleanup' EXIT
    chmod 000 "$PLANS_DIR"
    OUTPUT=$(echo '{"cwd":"'"$CWD_164"'"}' | bash "$TEST_DIR/on-session-clear.sh" 2>/dev/null)
    chmod 700 "$PLANS_DIR"
    trap cleanup EXIT
    if assert_contains "164" "$OUTPUT" "\`$PLANS_DIR\` could NOT be inspected"; then
        echo "  PASS"; PASS=$((PASS + 1))
    else
        echo "  FAIL"; FAIL=$((FAIL + 1))
    fi
fi

# A working directory that no longer exists is what the branch documents as its
# reachable case, and it is exactly the removed worktree this change is about.
echo "Test 165: a session whose directory is gone is told where its pointers are"
DOOMED_165="$TEST_DIR/doomed-165"; mkdir -p "$DOOMED_165"
OUTPUT=$( cd "$DOOMED_165" && rmdir "$DOOMED_165" && echo '{}' | env -u PWD bash "$TEST_DIR/on-session-clear.sh" 2>/dev/null )
if assert_contains "165" "$OUTPUT" "working directory could not be determined" && \
   assert_contains "165" "$OUTPUT" "still in \`$PLANS_DIR\`"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi

# --- Test 166: a flag the scan called fresh must not be displayed as ageless ---
# `_mr_now` is read once, before a forking per-flag loop, so a flag written during
# that loop lands slightly AHEAD of the sample. The scan treats that as the ordinary
# race, gives it an age of zero, and restores and consumes it -- but the display
# required now >= mtime, so the row read "age unknown" beside "MATCHES this session":
# the same report saying the age was established and that it was not.
echo "Test 166: a flag written during the scan is displayed with an age, not as unknown"
CWD_166="$TEST_DIR/wd-166"; mkdir -p "$CWD_166"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*
printf '%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_166" "ahead-166" \
    > "$PLANS_DIR/.pending-memory-restore-ahead166"
# `touch -t` only reaches minute granularity, so a 30-second offset rounds away and
# the fixture stops being ahead at all -- the mutation pass caught exactly that.
# Selecting on the exit status is safe here, unlike the `stat -f` case: `-A` is not a
# GNU option at all, so it fails there rather than succeeding with another meaning.
touch -A 000030 "$PLANS_DIR/.pending-memory-restore-ahead166" 2>/dev/null || \
    touch -d '+30 seconds' "$PLANS_DIR/.pending-memory-restore-ahead166"
OUTPUT=$(echo '{"cwd":"'"$CWD_166"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "166" "$OUTPUT" "MATCHES this session" && \
   assert_contains "166" "$OUTPUT" "0m ago" && \
   assert_not_contains "166" "$OUTPUT" "age unknown"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-ahead166

# --- Test 167: "nothing belongs to this repository" must not follow a matched row ---
# The sentence was gated on the priority-3 counter alone, so it fired beside rows at
# priority 2 and 4 -- flags that matched this session's exact directory. The row then
# said MATCHED while the next line said nothing was verified as belonging here, and
# the directive told the agent to say so and move on. The second fixture is the
# control: with only a foreign flag the sentence is TRUE and must still be printed,
# so this test fails if the gate is simply deleted.
echo "Test 167: a matched-but-expired row suppresses the nothing-belongs-here sentence"
CWD_167="$TEST_DIR/wd-167"; mkdir -p "$CWD_167"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*
OLD_167=$(date -v-2d +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || date -d '2 days ago' +%Y-%m-%dT%H:%M:%S%z)
printf '%s\n%s\n%s\n%s\n' "s" "$OLD_167" "$CWD_167" "expired-167" \
    > "$PLANS_DIR/.pending-memory-restore-x167"
touch -t "$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M)" \
    "$PLANS_DIR/.pending-memory-restore-x167"
OUT_MINE=$(echo '{"cwd":"'"$CWD_167"'"}' | bash "$TEST_DIR/on-session-clear.sh")
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*
# Control: a flag recorded in a directory inside no repository, nothing of ours.
mkdir -p "$TEST_DIR/foreign-167"
printf '%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$TEST_DIR/foreign-167" "other-167" \
    > "$PLANS_DIR/.pending-memory-restore-f167"
OUT_OTHER=$(echo '{"cwd":"'"$CWD_167"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "167" "$OUT_MINE" "MATCHED but expired" && \
   assert_not_contains "167" "$OUT_MINE" "No row was verified as belonging to this repository" && \
   assert_contains "167" "$OUT_OTHER" "No row was verified as belonging to this repository"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-f167

# --- Test 168: hidden-row counts are subsets of the cap overflow, and say so ---
# `_mr_over`, `_mr_gone_hidden_n` and `_mr_same_hidden_n` are all incremented in the
# same `continue` branch, so the second two are subsets of the first. Printed as
# separate clauses they invited the reader to add them: six expired flags, five
# displayed, one hidden, and the tail said "1 more not shown; 1 destroyed pointers
# NOT shown above" -- two counts of one row. The point of a count is that it can be
# totalled.
echo "Test 168: hidden-row counts are reported as a subset, not as a second population"
CWD_168="$TEST_DIR/wd-168"; mkdir -p "$CWD_168"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*
OLD_168=$(date -v-2d +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || date -d '2 days ago' +%Y-%m-%dT%H:%M:%S%z)
OLDST_168=$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M)
for i in 1 2 3 4 5 6; do
    printf '%s\n%s\n%s\n%s\n' "s" "$OLD_168" "$CWD_168" "exp-168-$i" \
        > "$PLANS_DIR/.pending-memory-restore-e168$i"
    touch -t "$OLDST_168" "$PLANS_DIR/.pending-memory-restore-e168$i"
done
OUTPUT=$(echo '{"cwd":"'"$CWD_168"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "168" "$OUTPUT" "1 more not shown, 1 of them destroyed pointers" && \
   assert_not_contains "168" "$OUTPUT" "destroyed pointers NOT shown above"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-e168*

# --- Test 169: one message must not issue two AskUserQuestion orders ---
# With two or more matched flags the directive enumerates them and says "BEFORE
# doing anything else, use AskUserQuestion to ask which checkpoint to restore". The
# selectable note then said "use AskUserQuestion to ask whether to restore one of
# them (offer those rows only)" over a DISJOINT set -- rows the first list excludes.
# Only one question can be asked, and "those rows only" pointed at the wrong ones.
# The control is the same note when no such question is being issued: there it is
# the only instruction and must keep asking on its own.
echo "Test 169: selectable rows join the existing question instead of starting a second"
REPO_169="$TEST_DIR/repo-169"; WT_169="$TEST_DIR/wt-169"
mkdir -p "$REPO_169"
git -C "$REPO_169" init -q 2>/dev/null
git -C "$REPO_169" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
git -C "$REPO_169" worktree add -q --detach "$WT_169" HEAD 2>/dev/null
NOW_169=$(date +%Y-%m-%dT%H:%M:%S%z)
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*
printf '%s\n%s\n%s\n%s\n' "s" "$NOW_169" "$REPO_169" "m1-169" > "$PLANS_DIR/.pending-memory-restore-m1_169"
printf '%s\n%s\n%s\n%s\n' "s" "$NOW_169" "$REPO_169" "m2-169" > "$PLANS_DIR/.pending-memory-restore-m2_169"
printf '%s\n%s\n%s\n%s\n' "s" "$NOW_169" "$WT_169" "sel-169" > "$PLANS_DIR/.pending-memory-restore-s1_169"
OUT_TWO=$(echo '{"cwd":"'"$REPO_169"'"}' | bash "$TEST_DIR/on-session-clear.sh")
# Control: only a selectable row, no matched ones -> the note must still ask.
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*
printf '%s\n%s\n%s\n%s\n' "s" "$NOW_169" "$WT_169" "sel-only-169" > "$PLANS_DIR/.pending-memory-restore-s2_169"
OUT_SEL=$(echo '{"cwd":"'"$REPO_169"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "169" "$OUT_TWO" "ask which checkpoint to restore" && \
   assert_contains "169" "$OUT_TWO" "add them to the SAME AskUserQuestion" && \
   assert_not_contains "169" "$OUT_TWO" "ask whether to restore one of them" && \
   assert_contains "169" "$OUT_SEL" "ask whether to restore one of them"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*169

# --- Test 170: a recorded path that looks like an option must not become $HOME ---
# `cd "$dir"` takes the flag's own line 3 as its FIRST WORD, so `-P`, `-L` and `-e`
# are consumed as options and `cd` then chdirs to $HOME with no operand left. A
# planted flag recording `-P`, scanned by a hook standing in $HOME, was resolved to
# $HOME, reported as MATCHES this session, given the full restore directive with the
# planted label, and CONSUMED -- destroying a pointer and injecting chosen text. Same
# threat model as the planted symlink and hard link this scan already refuses; only
# write-reload-flag.sh's own output is trustworthy content.
echo "Test 170: a recorded path beginning with a dash is not resolved to \$HOME"
HOME_170="$TEST_DIR/fakehome-170"; mkdir -p "$HOME_170"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*
FLAG_170="$PLANS_DIR/.pending-memory-restore-planted170"
printf '%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "-P" "PLANTED-170" > "$FLAG_170"
OUTPUT=$(echo '{"cwd":"'"$HOME_170"'"}' | HOME="$HOME_170" bash "$TEST_DIR/on-session-clear.sh")
if assert_not_contains "170" "$OUTPUT" "MATCHES this session" && \
   assert_not_contains "170" "$OUTPUT" "ACTION REQUIRED - MEMORY RESTORE" && \
   assert_file_exists "170" "$FLAG_170"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_170"

# --- Test 171: scope_key must not resolve an option-shaped path to $HOME ---
# The match site is covered by test 170; this pins the other half. Without `--`,
# scope_key "-P" answers `dir:$HOME` -- a real scope for a path that does not exist,
# which a flag recording `-P` could then be compared against as though it belonged
# somewhere. The honest answer is the empty string: nothing was resolved.
echo "Test 171: scope_key answers nothing for an option-shaped path"
OUT_171=$(HOME="$TEST_DIR" bash -c 'source "'"$LIB_COMMON"'"; scope_key "-P"')
if [[ -z "$OUT_171" ]]; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  ASSERT FAILED: scope_key \"-P\" returned '$OUT_171', expected nothing"
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi

# --- Test 172: a flag whose session key matches is this session's own ---
echo "Test 172: memory-restore: a flag whose session key matches is restored and consumed"
CWD_172="$TEST_DIR/worktree-172"; mkdir -p "$CWD_172"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*
FLAG_172="$PLANS_DIR/.pending-memory-restore-keyed172"
printf '%s\n%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_172" "checkpoint-172" \
    "$(compute_session_key "$(cd "$CWD_172" && pwd -P)")" > "$FLAG_172"
OUTPUT=$(echo '{"cwd":"'"$CWD_172"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "172" "$OUTPUT" "MATCHES this session" && \
   assert_contains "172" "$OUTPUT" "ACTION REQUIRED - MEMORY RESTORE" && \
   assert_contains "172" "$OUTPUT" "checkpoint-172" && \
   [[ ! -e "$FLAG_172" ]]; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    [[ -e "$FLAG_172" ]] && echo "  ASSERT FAILED: matched flag was not consumed"
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_172"

# --- Test 173: same directory, different session -> offered, never consumed ---
echo "Test 173: memory-restore: a flag from a DIFFERENT session in this directory is offered, not consumed"
CWD_173="$TEST_DIR/worktree-173"; mkdir -p "$CWD_173"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*
FLAG_173="$PLANS_DIR/.pending-memory-restore-foreign173"
printf '%s\n%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_173" "checkpoint-173" \
    "ffffffffffffffff" > "$FLAG_173"
OUTPUT=$(echo '{"cwd":"'"$CWD_173"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_not_contains "173" "$OUTPUT" "MATCHES this session" && \
   assert_not_contains "173" "$OUTPUT" "ACTION REQUIRED - MEMORY RESTORE" && \
   assert_contains "173" "$OUTPUT" "recorded in THIS directory by a DIFFERENT session" && \
   assert_contains "173" "$OUTPUT" "checkpoint-173" && \
   assert_contains "173" "$OUTPUT" "ask whether to restore one of them" && \
   assert_file_exists "173" "$FLAG_173"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_173"

# --- Test 174: a keyless flag keeps the cwd-only rule it was written under ---
echo "Test 174: memory-restore: a keyless (4-line) flag is still restored on a cwd match"
CWD_174="$TEST_DIR/worktree-174"; mkdir -p "$CWD_174"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*
FLAG_174="$PLANS_DIR/.pending-memory-restore-legacy174"
printf '%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$CWD_174" "checkpoint-174" > "$FLAG_174"
OUTPUT=$(echo '{"cwd":"'"$CWD_174"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "174" "$OUTPUT" "MATCHES this session" && \
   assert_contains "174" "$OUTPUT" "checkpoint-174" && \
   [[ ! -e "$FLAG_174" ]]; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    [[ -e "$FLAG_174" ]] && echo "  ASSERT FAILED: keyless flag was not consumed"
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_174"

# --- Test 175: no PPID source -> line 5 written EMPTY, not guessed ---
echo "Test 175: write-reload-flag: no PPID source leaves the session key empty"
CWD_175="$TEST_DIR/worktree-175"; mkdir -p "$CWD_175"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*
T175_OK=false
if patch_lib_common; then
    cp "$SCRIPT_DIR/scripts/write-reload-flag.sh" "$TEST_DIR/write-reload-flag.sh"
    OUT_175=$(cd "$CWD_175" && env -u _SMITH_PPID -u CLAUDE_PID bash "$TEST_DIR/write-reload-flag.sh" "checkpoint-175")
    F175=$(find "$PLANS_DIR" -name '.pending-memory-restore-*' | head -1)
    [[ -n "$F175" ]] && [[ "$(wc -l < "$F175" | tr -d ' ')" == "5" ]] \
        && [[ -z "$(sed -n '5p' "$F175")" ]] && T175_OK=true
fi
if [[ "$T175_OK" == "true" ]] && assert_contains "175" "$OUT_175" "no session key"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  ASSERT FAILED: expected an empty line 5 and a 'no session key' notice"
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*

# --- Test 176: a non-numeric PPID is not a PPID ---
echo "Test 176: write-reload-flag: a non-numeric CLAUDE_PID leaves the session key empty"
CWD_176="$TEST_DIR/worktree-176"; mkdir -p "$CWD_176"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*
T176_OK=false
if patch_lib_common; then
    cp "$SCRIPT_DIR/scripts/write-reload-flag.sh" "$TEST_DIR/write-reload-flag.sh"
    OUT_176=$(cd "$CWD_176" && env -u _SMITH_PPID CLAUDE_PID="not-a-pid" bash "$TEST_DIR/write-reload-flag.sh" "checkpoint-176")
    F176=$(find "$PLANS_DIR" -name '.pending-memory-restore-*' | head -1)
    [[ -n "$F176" ]] && [[ "$(wc -l < "$F176" | tr -d ' ')" == "5" ]] \
        && [[ -z "$(sed -n '5p' "$F176")" ]] && T176_OK=true
fi
if [[ "$T176_OK" == "true" ]] && assert_contains "176" "$OUT_176" "no session key"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  ASSERT FAILED: expected an empty line 5 and a 'no session key' notice"
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-*

# --- Test 177: mark-session-restart records the route, and only the two that discard ---
echo "Test 177: mark-session-restart marks clear and compact, ignores startup, arms the gate only on clear"
/bin/rm -f "$PLANS_DIR"/.session-restart-* "$PLANS_DIR/.sr-hook-installed"
MARKER_177="$PLANS_DIR/.session-restart-${CWD_DEFAULT_KEY}"
echo '{"source":"compact","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/mark-session-restart.sh"
T177_COMPACT=$([[ -f "$MARKER_177" ]] && sed -n '1p' "$MARKER_177" || echo "MISSING")
T177_SENTINEL_AFTER_COMPACT=$([[ -f "$PLANS_DIR/.sr-hook-installed" ]] && echo "yes" || echo "no")
/bin/rm -f "$MARKER_177"
echo '{"source":"startup","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/mark-session-restart.sh"
T177_STARTUP=$([[ -f "$MARKER_177" ]] && echo "wrote" || echo "silent")
echo '{"source":"clear","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/mark-session-restart.sh"
T177_CLEAR=$([[ -f "$MARKER_177" ]] && sed -n '1p' "$MARKER_177" || echo "MISSING")
T177_SENTINEL_AFTER_CLEAR=$([[ -f "$PLANS_DIR/.sr-hook-installed" ]] && echo "yes" || echo "no")
if [[ "$T177_COMPACT" == "compact" ]] && [[ "$T177_SENTINEL_AFTER_COMPACT" == "no" ]] && \
   [[ "$T177_STARTUP" == "silent" ]] && \
   [[ "$T177_CLEAR" == "clear" ]] && [[ "$T177_SENTINEL_AFTER_CLEAR" == "yes" ]]; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  ASSERT FAILED: compact='$T177_COMPACT' sentinel_after_compact='$T177_SENTINEL_AFTER_COMPACT' startup='$T177_STARTUP' clear='$T177_CLEAR' sentinel_after_clear='$T177_SENTINEL_AFTER_CLEAR'"
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$PLANS_DIR"/.session-restart-* "$PLANS_DIR/.sr-hook-installed"

# --- Test 178: gated, nothing restarted -> no announcement, flag KEPT ---
echo "Test 178: gated + no restart marker -> no POST-CLEAR directive and the flag survives"
create_test_plan
/bin/rm -f "$PLANS_DIR"/.session-restart-*
touch "$PLANS_DIR/.sr-hook-installed"
FLAG_178="$PLANS_DIR/.pending-reload-${CWD_DEFAULT_KEY}"
printf '%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_test" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" > "$FLAG_178"
TRANSCRIPT=$(create_transcript_pct 5)
OUTPUT=$(echo '{"prompt":"hi","session_id":"sess_new","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_not_contains "178" "$OUTPUT" "RESUME:" && \
   assert_file_exists "178" "$FLAG_178"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_178" "$PLANS_DIR/.sr-hook-installed"

# --- Test 179: gated + a real /clear -> the announcement fires, both files consumed ---
echo "Test 179: gated + clear marker -> POST-CLEAR RESUME, flag and marker both consumed"
create_test_plan
touch "$PLANS_DIR/.sr-hook-installed"
FLAG_179="$PLANS_DIR/.pending-reload-${CWD_DEFAULT_KEY}"
MARKER_179="$PLANS_DIR/.session-restart-${CWD_DEFAULT_KEY}"
printf '%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_test" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" > "$FLAG_179"
printf '%s\n%s\n%s\n' "clear" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" > "$MARKER_179"
TRANSCRIPT=$(create_transcript_pct 5)
OUTPUT=$(echo '{"prompt":"hi","session_id":"sess_new","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_contains "179" "$OUTPUT" "POST-CLEAR RESUME" && \
   [[ ! -e "$FLAG_179" ]] && [[ ! -e "$MARKER_179" ]]; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    [[ -e "$FLAG_179" ]] && echo "  ASSERT FAILED: pending-reload flag was not consumed"
    [[ -e "$MARKER_179" ]] && echo "  ASSERT FAILED: restart marker was not consumed"
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_179" "$MARKER_179" "$PLANS_DIR/.sr-hook-installed"

# --- Test 180: a compact is named a compact ---
echo "Test 180: gated + compact marker -> POST-COMPACT RESUME, never POST-CLEAR"
create_test_plan
touch "$PLANS_DIR/.sr-hook-installed"
FLAG_180="$PLANS_DIR/.pending-reload-${CWD_DEFAULT_KEY}"
MARKER_180="$PLANS_DIR/.session-restart-${CWD_DEFAULT_KEY}"
printf '%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_test" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" > "$FLAG_180"
printf '%s\n%s\n%s\n' "compact" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" > "$MARKER_180"
TRANSCRIPT=$(create_transcript_pct 5)
OUTPUT=$(echo '{"prompt":"hi","session_id":"sess_new","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_contains "180" "$OUTPUT" "POST-COMPACT RESUME" && \
   assert_not_contains "180" "$OUTPUT" "POST-CLEAR RESUME"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_180" "$MARKER_180" "$PLANS_DIR/.sr-hook-installed"

# --- Test 181: an unregistered installation keeps working ---
echo "Test 181: no sentinel -> ungated legacy behaviour is preserved"
create_test_plan
/bin/rm -f "$PLANS_DIR"/.session-restart-* "$PLANS_DIR/.sr-hook-installed"
FLAG_181="$PLANS_DIR/.pending-reload-${CWD_DEFAULT_KEY}"
printf '%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_test" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" > "$FLAG_181"
TRANSCRIPT=$(create_transcript_pct 5)
OUTPUT=$(echo '{"prompt":"hi","session_id":"sess_new","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_contains "181" "$OUTPUT" "POST-CLEAR RESUME" && \
   [[ ! -e "$FLAG_181" ]]; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    [[ -e "$FLAG_181" ]] && echo "  ASSERT FAILED: ungated path did not consume the flag"
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_181"

# --- Test 182: a route nobody recorded is not a route ---
echo "Test 182: gated + marker with an unknown source -> treated as no restart"
create_test_plan
touch "$PLANS_DIR/.sr-hook-installed"
FLAG_182="$PLANS_DIR/.pending-reload-${CWD_DEFAULT_KEY}"
MARKER_182="$PLANS_DIR/.session-restart-${CWD_DEFAULT_KEY}"
printf '%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_test" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" > "$FLAG_182"
printf '%s\n%s\n%s\n' "teleport" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" > "$MARKER_182"
TRANSCRIPT=$(create_transcript_pct 5)
OUTPUT=$(echo '{"prompt":"hi","session_id":"sess_new","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_not_contains "182" "$OUTPUT" "RESUME:" && \
   assert_file_exists "182" "$FLAG_182"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_182" "$MARKER_182" "$PLANS_DIR/.sr-hook-installed"

# --- Test 183: a selectable flag is offered once per session, not once per /clear ---
echo "Test 183: a selectable flag is offered once, then suppressed on the next /clear"
REPO_183="$TEST_DIR/repo-183"; WT_183="$TEST_DIR/wt-183"
mkdir -p "$REPO_183"
git -C "$REPO_183" init -q 2>/dev/null
git -C "$REPO_183" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
git -C "$REPO_183" worktree add -q --detach "$WT_183" HEAD 2>/dev/null
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-offered-*
FLAG_183="$PLANS_DIR/.pending-memory-restore-sel183"
printf '%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$WT_183" "checkpoint-183" > "$FLAG_183"
OUT_183A=$(echo '{"cwd":"'"$REPO_183"'"}' | bash "$TEST_DIR/on-session-clear.sh")
OUT_183B=$(echo '{"cwd":"'"$REPO_183"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ -d "$WT_183" ]] && \
   assert_contains "183" "$OUT_183A" "same repository, selectable" && \
   assert_not_contains "183" "$OUT_183A" "by a DIFFERENT session" && \
   assert_contains "183" "$OUT_183A" "checkpoint-183" && \
   assert_not_contains "183" "$OUT_183B" "checkpoint-183" && \
   assert_contains "183" "$OUT_183B" "already offered to this session" && \
   assert_file_exists "183" "$FLAG_183"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_183" "$PLANS_DIR"/.mr-offered-*

# --- Test 184: an unrecordable key is repeated, never silently withheld ---
echo "Test 184: a flag whose key fails the allowlist keeps being offered"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-offered-*
FLAG_184="$PLANS_DIR/.pending-memory-restore-bad key 184"
printf '%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$WT_183" "checkpoint-184" > "$FLAG_184"
OUT_184A=$(echo '{"cwd":"'"$REPO_183"'"}' | bash "$TEST_DIR/on-session-clear.sh")
OUT_184B=$(echo '{"cwd":"'"$REPO_183"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if [[ -d "$WT_183" ]] && \
   assert_contains "184" "$OUT_184A" "same repository, selectable" && \
   assert_not_contains "184" "$OUT_184A" "by a DIFFERENT session" && \
   assert_contains "184" "$OUT_184A" "checkpoint-184" && \
   assert_contains "184" "$OUT_184B" "checkpoint-184"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_184" "$PLANS_DIR"/.mr-offered-*

# --- Test 185: a plan-mode prompt must not swallow the restart ---
echo "Test 185: gated + plan-mode prompt -> marker survives for the next non-plan prompt"
create_test_plan
touch "$PLANS_DIR/.sr-hook-installed"
FLAG_185="$PLANS_DIR/.pending-reload-${CWD_DEFAULT_KEY}"
MARKER_185="$PLANS_DIR/.session-restart-${CWD_DEFAULT_KEY}"
printf '%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_test" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" > "$FLAG_185"
printf '%s\n%s\n%s\n' "clear" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" > "$MARKER_185"
TRANSCRIPT=$(create_transcript_pct 5)
OUT_185A=$(echo '{"prompt":"hi","session_id":"s","permission_mode":"plan","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
T185_MARKER_KEPT=$([[ -f "$MARKER_185" ]] && echo "yes" || echo "no")
printf '%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_test" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" > "$FLAG_185"
OUT_185B=$(echo '{"prompt":"hi","session_id":"s","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if [[ "$T185_MARKER_KEPT" == "yes" ]] && assert_not_contains "185" "$OUT_185A" "RESUME:" \
   && assert_contains "185" "$OUT_185B" "POST-CLEAR RESUME"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    [[ "$T185_MARKER_KEPT" != "yes" ]] && echo "  ASSERT FAILED: plan-mode prompt consumed the restart marker"
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_185" "$MARKER_185" "$PLANS_DIR/.sr-hook-installed"

# --- Test 186: .mr-offered-* must not be written through a symlink ---
echo "Test 186: a symlinked .mr-offered-* is refused, not appended through"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-offered-*
VICTIM_186="$TEST_DIR/victim-186.txt"
printf 'original\n' > "$VICTIM_186"
OFFERED_186="$PLANS_DIR/.mr-offered-$(compute_session_key "$REPO_183")"
ln -s "$VICTIM_186" "$OFFERED_186"
FLAG_186="$PLANS_DIR/.pending-memory-restore-sel186"
printf '%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$WT_183" "checkpoint-186" > "$FLAG_186"
OUT_186=$(echo '{"cwd":"'"$REPO_183"'"}' | bash "$TEST_DIR/on-session-clear.sh")
T186_VICTIM=$(cat "$VICTIM_186")
T186_LINK=$([[ -L "$OFFERED_186" ]] && echo "link" || echo "gone")
if [[ -d "$WT_183" ]] && \
   [[ "$T186_VICTIM" == "original" ]] && [[ "$T186_LINK" == "link" ]] && \
   assert_contains "186" "$OUT_186" "same repository, selectable" && \
   assert_not_contains "186" "$OUT_186" "by a DIFFERENT session" && \
   assert_contains "186" "$OUT_186" "checkpoint-186" && \
   assert_contains "186" "$OUT_186" "is a link or shares an inode"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    [[ "$T186_VICTIM" != "original" ]] && echo "  ASSERT FAILED: wrote through the symlink; victim now: $T186_VICTIM"
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_186" "$OFFERED_186" "$VICTIM_186"

# --- Test 187: the sentinel must not be created through a symlink ---
echo "Test 187: a symlinked .sr-hook-installed is replaced, not followed"
/bin/rm -f "$PLANS_DIR/.sr-hook-installed"
VICTIM_187="$TEST_DIR/victim-187-branch-guard.disabled"
/bin/rm -f "$VICTIM_187"
ln -s "$VICTIM_187" "$PLANS_DIR/.sr-hook-installed"
echo '{"source":"clear","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/mark-session-restart.sh"
T187_VICTIM=$([[ -e "$VICTIM_187" ]] && echo "created" || echo "absent")
T187_SENTINEL=$([[ -f "$PLANS_DIR/.sr-hook-installed" && ! -L "$PLANS_DIR/.sr-hook-installed" ]] && echo "plain" || echo "not-plain")
if [[ "$T187_VICTIM" == "absent" ]] && [[ "$T187_SENTINEL" == "plain" ]]; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    [[ "$T187_VICTIM" != "absent" ]] && echo "  ASSERT FAILED: touch/create followed the symlink and created $VICTIM_187"
    [[ "$T187_SENTINEL" != "plain" ]] && echo "  ASSERT FAILED: sentinel is still not a plain file"
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$PLANS_DIR/.sr-hook-installed" "$VICTIM_187" "$PLANS_DIR"/.session-restart-*

# --- Test 188: a cap-hidden selectable row is NOT recorded as offered ---
echo "Test 188: a selectable row hidden by the display cap is still offered at the next /clear"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-offered-*
NOW_188=$(date +%Y-%m-%dT%H:%M:%S%z)
for i in 1 2 3 4 5 6 7 8; do
    printf '%s\n%s\n%s\n%s\n' "s" "$NOW_188" "$WT_183" "checkpoint-188-$i" \
        > "$PLANS_DIR/.pending-memory-restore-cap188_$i"
done
OUT_188A=$(echo '{"cwd":"'"$REPO_183"'"}' | bash "$TEST_DIR/on-session-clear.sh")
OUT_188B=$(echo '{"cwd":"'"$REPO_183"'"}' | bash "$TEST_DIR/on-session-clear.sh")
T188_SHOWN_A=0
T188_SHOWN_B=0
for i in 1 2 3 4 5 6 7 8; do
    case "$OUT_188A" in *"checkpoint-188-$i"*) T188_SHOWN_A=$((T188_SHOWN_A + 1)) ;; esac
    case "$OUT_188B" in *"checkpoint-188-$i"*) T188_SHOWN_B=$((T188_SHOWN_B + 1)) ;; esac
done
T188_OVERLAP=0
for i in 1 2 3 4 5 6 7 8; do
    case "$OUT_188A" in *"checkpoint-188-$i"*)
        case "$OUT_188B" in *"checkpoint-188-$i"*) T188_OVERLAP=$((T188_OVERLAP + 1)) ;; esac
    ;; esac
done
if [[ -d "$WT_183" ]] && \
   [[ "$T188_SHOWN_A" -lt 8 ]] && [[ "$T188_SHOWN_B" -gt 0 ]] && [[ "$T188_OVERLAP" -eq 0 ]]; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  ASSERT FAILED: shown_first=$T188_SHOWN_A shown_second=$T188_SHOWN_B repeated=$T188_OVERLAP (want first<8, second>0, repeated=0)"
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-cap188_* "$PLANS_DIR"/.mr-offered-*

# --- Test 189: the reserved slot recognises the foreign-session verdict ---
echo "Test 189: a foreign-session selectable row still gets the reserved slot"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-offered-*
OLD_189=$(date -v-3d +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || date -d '3 days ago' +%Y-%m-%dT%H:%M:%S%z)
for i in 1 2 3 4 5 6; do
    printf '%s\n%s\n%s\n%s\n' "s" "$OLD_189" "$REPO_183" "filler-189-$i" \
        > "$PLANS_DIR/.pending-memory-restore-fill189_$i"
done
printf '%s\n%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$REPO_183" "checkpoint-189" "ffffffffffffffff" \
    > "$PLANS_DIR/.pending-memory-restore-fs189"
OUT_189=$(echo '{"cwd":"'"$REPO_183"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "189" "$OUT_189" "checkpoint-189" && \
   assert_contains "189" "$OUT_189" "recorded in THIS directory by a DIFFERENT session"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-offered-*

# --- Test 190: a symlink-spelled cwd must not make our own flag look foreign ---
echo "Test 190: a physical-path cwd match is not reclassified as another session"
REALDIR_190="$TEST_DIR/real-190"; mkdir -p "$REALDIR_190"
ln -s "$REALDIR_190" "$TEST_DIR/link-190"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-offered-*
FLAG_190="$PLANS_DIR/.pending-memory-restore-phys190"
PHYS_190=$(cd -- "$TEST_DIR/link-190" && pwd -P)
printf '%s\n%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$TEST_DIR/link-190" "checkpoint-190" \
    "$(compute_session_key "$PHYS_190")" > "$FLAG_190"
OUT_190=$(echo '{"cwd":"'"$REALDIR_190"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "190" "$OUT_190" "MATCHES this session" && \
   assert_not_contains "190" "$OUT_190" "by a DIFFERENT session"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_190" "$PLANS_DIR"/.mr-offered-*

# --- Test 191: destroying another session's flag names its label ---
echo "Test 191: a foreign-session flag swept at 7 days is announced with its label"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-offered-*
FLAG_191="$PLANS_DIR/.pending-memory-restore-old191"
printf '%s\n%s\n%s\n%s\n%s\n' "s" "old" "$PWD" "checkpoint-191" "ffffffffffffffff" > "$FLAG_191"
touch -t 202501010000 "$FLAG_191"
OUT_191=$(echo '{"cwd":"'"$PWD"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "191" "$OUT_191" "checkpoint-191" && \
   assert_contains "191" "$OUT_191" "REMOVED as older than 7 days" && \
   [[ ! -e "$FLAG_191" ]]; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    [[ -e "$FLAG_191" ]] && echo "  ASSERT FAILED: expired foreign-session flag was not swept"
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_191" "$PLANS_DIR"/.mr-offered-*

# --- Test 192: a stale sentinel un-arms the gate instead of latching forever ---
echo "Test 192: a sentinel older than 14 days falls back to ungated behaviour"
create_test_plan
/bin/rm -f "$PLANS_DIR"/.session-restart-*
touch -t 202501010000 "$PLANS_DIR/.sr-hook-installed"
FLAG_192="$PLANS_DIR/.pending-reload-${CWD_DEFAULT_KEY}"
printf '%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_test" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" > "$FLAG_192"
TRANSCRIPT=$(create_transcript_pct 5)
OUT_192=$(echo '{"prompt":"hi","session_id":"s","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_contains "192" "$OUT_192" "POST-CLEAR RESUME"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_192" "$PLANS_DIR/.sr-hook-installed"

# --- Test 193: a symlinked spelling must not let another session's flag be consumed ---
echo "Test 193: a foreign key still refuses when the cwd matched only after resolution"
REALDIR_193="$TEST_DIR/real-193"; mkdir -p "$REALDIR_193"
ln -s "$REALDIR_193" "$TEST_DIR/link-193"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-offered-*
FLAG_193="$PLANS_DIR/.pending-memory-restore-fsphys193"
printf '%s\n%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$TEST_DIR/link-193" "checkpoint-193" \
    "ffffffffffffffff" > "$FLAG_193"
OUT_193=$(echo '{"cwd":"'"$REALDIR_193"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_not_contains "193" "$OUT_193" "MATCHES this session" && \
   assert_not_contains "193" "$OUT_193" "ACTION REQUIRED - MEMORY RESTORE" && \
   assert_file_exists "193" "$FLAG_193"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    [[ ! -e "$FLAG_193" ]] && echo "  ASSERT FAILED: another session's checkpoint pointer was CONSUMED"
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_193" "$PLANS_DIR"/.mr-offered-*

# --- Test 194: a flag recorded in THIS directory contradicts the nothing-here sentence ---
echo "Test 194: a foreign-session row suppresses the no-flag-recorded-this-directory claim"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-offered-*
FLAG_194="$PLANS_DIR/.pending-memory-restore-bear194"
printf '%s\n%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" "checkpoint-194" \
    "ffffffffffffffff" > "$FLAG_194"
OUT_194=$(echo '{"cwd":"'"$PWD"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "194" "$OUT_194" "checkpoint-194" && \
   assert_not_contains "194" "$OUT_194" "No checkpoint flag recorded this session's working directory"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_194" "$PLANS_DIR"/.mr-offered-*

# --- Test 195: once-per-session suppression on the foreign-session arm ---
echo "Test 195: a foreign-session candidate is offered once, then suppressed"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-offered-*
FLAG_195="$PLANS_DIR/.pending-memory-restore-fs195"
printf '%s\n%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" "checkpoint-195" \
    "ffffffffffffffff" > "$FLAG_195"
OUT_195A=$(echo '{"cwd":"'"$PWD"'"}' | bash "$TEST_DIR/on-session-clear.sh")
OUT_195B=$(echo '{"cwd":"'"$PWD"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "195" "$OUT_195A" "checkpoint-195" && \
   assert_not_contains "195" "$OUT_195B" "checkpoint-195" && \
   assert_contains "195" "$OUT_195B" "already offered to this session" && \
   assert_file_exists "195" "$FLAG_195"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_195" "$PLANS_DIR"/.mr-offered-*

# --- Test 196: a live installation keeps its sentinel fresh ---
echo "Test 196: every clear re-arms the sentinel, so a live install never ages out"
/bin/rm -f "$PLANS_DIR"/.session-restart-*
touch -t 202501010000 "$PLANS_DIR/.sr-hook-installed"
echo '{"source":"clear","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/mark-session-restart.sh"
T196_FRESH=$(find "$PLANS_DIR" -name '.sr-hook-installed' -mtime -1 2>/dev/null)
create_test_plan
/bin/rm -f "$PLANS_DIR"/.session-restart-*
FLAG_196="$PLANS_DIR/.pending-reload-${CWD_DEFAULT_KEY}"
printf '%s\n%s\n%s\n%s\n' "$PLANS_DIR/test-plan.md" "sess_test" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" > "$FLAG_196"
TRANSCRIPT=$(create_transcript_pct 5)
OUT_196=$(echo '{"prompt":"hi","session_id":"s","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/inject-plan.sh")
if [[ -n "$T196_FRESH" ]] && assert_not_contains "196" "$OUT_196" "RESUME:" && \
   assert_file_exists "196" "$FLAG_196"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    [[ -z "$T196_FRESH" ]] && echo "  ASSERT FAILED: clear did not refresh the sentinel mtime"
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_196" "$PLANS_DIR/.sr-hook-installed"

# --- Test 197: the mixed state every install enters on the day this ships ---
echo "Test 197: a legacy keyless flag and a foreign-keyed flag in one directory"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-offered-*
LEGACY_197="$PLANS_DIR/.pending-memory-restore-legacy197"
KEYED_197="$PLANS_DIR/.pending-memory-restore-keyed197"
printf '%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" "checkpoint-197-legacy" > "$LEGACY_197"
printf '%s\n%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" "checkpoint-197-keyed" \
    "ffffffffffffffff" > "$KEYED_197"
OUT_197=$(echo '{"cwd":"'"$PWD"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "197" "$OUT_197" "checkpoint-197-legacy" && \
   assert_contains "197" "$OUT_197" "checkpoint-197-keyed" && \
   assert_contains "197" "$OUT_197" "MATCHES this session" && \
   assert_contains "197" "$OUT_197" "by a DIFFERENT session" && \
   [[ ! -e "$LEGACY_197" ]] && assert_file_exists "197" "$KEYED_197"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    [[ -e "$LEGACY_197" ]] && echo "  ASSERT FAILED: the legacy flag was not restored and consumed"
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$LEGACY_197" "$KEYED_197" "$PLANS_DIR"/.mr-offered-*

# --- Test 198: a suppressed candidate must not be reported as nothing to offer ---
echo "Test 198: an already-offered candidate still counts as something to offer"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-offered-*
FLAG_198="$PLANS_DIR/.pending-memory-restore-sup198"
printf '%s\n%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$PWD" "checkpoint-198" \
    "ffffffffffffffff" > "$FLAG_198"
echo '{"cwd":"'"$PWD"'"}' | bash "$TEST_DIR/on-session-clear.sh" > /dev/null
MALFORMED_198="$PLANS_DIR/.pending-memory-restore-mal198"
printf '%s\n%s\n\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "checkpoint-198-malformed" > "$MALFORMED_198"
OUT_198=$(echo '{"cwd":"'"$PWD"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "198" "$OUT_198" "already offered to this session" && \
   assert_not_contains "198" "$OUT_198" "there is nothing to offer automatically" && \
   assert_not_contains "198" "$OUT_198" "Signal: fresh-start"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_198" "$MALFORMED_198" "$PLANS_DIR"/.mr-offered-*

# --- Test 199: a compact keeps an existing sentinel alive ---
echo "Test 199: a compact refreshes an existing sentinel but never creates one"
/bin/rm -f "$PLANS_DIR"/.session-restart-* "$PLANS_DIR/.sr-hook-installed"
echo '{"source":"compact","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/mark-session-restart.sh"
T199_CREATED=$([[ -e "$PLANS_DIR/.sr-hook-installed" ]] && echo "created" || echo "absent")
touch -t 202501010000 "$PLANS_DIR/.sr-hook-installed"
echo '{"source":"compact","cwd":"'"$PWD"'"}' | bash "$TEST_DIR/mark-session-restart.sh"
T199_FRESH=$(find "$PLANS_DIR" -name '.sr-hook-installed' -mtime -1 2>/dev/null)
if [[ "$T199_CREATED" == "absent" ]] && [[ -n "$T199_FRESH" ]]; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    [[ "$T199_CREATED" != "absent" ]] && echo "  ASSERT FAILED: a compact created the sentinel"
    [[ -z "$T199_FRESH" ]] && echo "  ASSERT FAILED: a compact did not refresh an existing sentinel"
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$PLANS_DIR"/.session-restart-* "$PLANS_DIR/.sr-hook-installed"

# --- Test 200: an unresolvable cwd must not be reported as a different session ---
echo "Test 200: ownership that could not be checked says so, instead of naming another session"
REAL_200="$TEST_DIR/real-200"; mkdir -p "$REAL_200"
ln -s "$REAL_200" "$TEST_DIR/link-200"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-offered-*
FLAG_200="$PLANS_DIR/.pending-memory-restore-unchk200"
printf '%s\n%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$TEST_DIR/link-200" "checkpoint-200" \
    "$(compute_session_key "$(cd -- "$TEST_DIR/link-200" && pwd -P)")" > "$FLAG_200"
rmdir "$REAL_200"
OUT_200=$(echo '{"cwd":"'"$TEST_DIR/link-200"'"}' | bash "$TEST_DIR/on-session-clear.sh")
mkdir -p "$REAL_200"
if assert_contains "200" "$OUT_200" "checkpoint-200" && \
   assert_not_contains "200" "$OUT_200" "by a DIFFERENT session" && \
   assert_file_exists "200" "$FLAG_200"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_200" "$PLANS_DIR"/.mr-offered-*

# --- Test 201: a flag from the previous writer, which hashed the raw path ---
echo "Test 201: a raw-path key from the previous writer still matches"
REAL_201="$TEST_DIR/real-201"; mkdir -p "$REAL_201"
ln -s "$REAL_201" "$TEST_DIR/link-201"
/bin/rm -f "$PLANS_DIR"/.pending-memory-restore-* "$PLANS_DIR"/.mr-offered-*
FLAG_201="$PLANS_DIR/.pending-memory-restore-raw201"
printf '%s\n%s\n%s\n%s\n%s\n' "s" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$TEST_DIR/link-201" "checkpoint-201" \
    "$(compute_session_key "$TEST_DIR/link-201")" > "$FLAG_201"
OUT_201=$(echo '{"cwd":"'"$TEST_DIR/link-201"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "201" "$OUT_201" "MATCHES this session" && \
   assert_contains "201" "$OUT_201" "checkpoint-201" && \
   [[ ! -e "$FLAG_201" ]]; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    [[ -e "$FLAG_201" ]] && echo "  ASSERT FAILED: a previous-writer flag was not restored"
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
/bin/rm -f "$FLAG_201" "$PLANS_DIR"/.mr-offered-*

# --- Test 202: plan-mode first entry -> foreign-claimed newest is refused, not adopted ---
echo "Test 202: plan-mode first entry -> newest plan claimed by another scope is refused"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*
CWD_202="$TEST_DIR/worktree-202"; mkdir -p "$CWD_202"
CWD_202_KEY=$(compute_session_key "$CWD_202")
printf '%s\n' '# Foreign Plan 202' '' '- [ ] client task' > "$PLANS_DIR/foreign-plan-202.md"
printf '%s\n%s\n%s\n%s\n%s\n%s\n' "sess_f202" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" \
    "$PLANS_DIR/foreign-plan-202.md" "repo:/some/client/repo" > "$PLANS_DIR/.plan-state-deadbeefdeadbeef"
TRANSCRIPT_202=$(create_transcript_pct 10 "t202")
OUT_202=$(echo '{"prompt":"do something","session_id":"sess_202","transcript_path":"'"$TRANSCRIPT_202"'","cwd":"'"$CWD_202"'","permission_mode":"plan"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_contains "202" "$OUT_202" "PLAN ADOPTION REFUSED" && \
   assert_file_not_exists "202" "$PLANS_DIR/.plan-state-${CWD_202_KEY}" && \
   assert_file_not_exists "202" "$PLANS_DIR/.pending-reload-${CWD_202_KEY}"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*

# --- Test 203: plan-mode first entry -> unclaimed newest adopted, scope recorded on line 6 ---
echo "Test 203: plan-mode first entry -> unclaimed newest is adopted and records its scope"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*
CWD_203="$TEST_DIR/worktree-203"; mkdir -p "$CWD_203"
CWD_203_KEY=$(compute_session_key "$CWD_203")
printf '%s\n' '# Own Plan 203' '' '- [ ] my task' > "$PLANS_DIR/own-plan-203.md"
EXP_SCOPE_203=$(bash -c 'source "$1/lib-plan.sh"; scope_key "$2"' _ "$TEST_DIR" "$CWD_203")
TRANSCRIPT_203=$(create_transcript_pct 10 "t203")
echo '{"prompt":"do something","session_id":"sess_203","transcript_path":"'"$TRANSCRIPT_203"'","cwd":"'"$CWD_203"'","permission_mode":"plan"}' | bash "$TEST_DIR/inject-plan.sh" > /dev/null
STATE_203="$PLANS_DIR/.plan-state-${CWD_203_KEY}"
T203_PLAN=$(sed -n '5p' "$STATE_203" 2>/dev/null || true)
T203_SCOPE=$(sed -n '6p' "$STATE_203" 2>/dev/null || true)
if assert_file_exists "203" "$STATE_203" && \
   [[ "$T203_PLAN" == *"own-plan-203.md" ]] && \
   [[ -n "$EXP_SCOPE_203" ]] && [[ "$T203_SCOPE" == "$EXP_SCOPE_203" ]]; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL (plan=$T203_PLAN scope=$T203_SCOPE expected=$EXP_SCOPE_203)"; FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*

# --- Test 204: a guessed first-entry adoption must NOT arm the auto-resume flag ---
echo "Test 204: a guessed first-entry adoption does not create a pending-reload flag"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*
CWD_204="$TEST_DIR/worktree-204"; mkdir -p "$CWD_204"
CWD_204_KEY=$(compute_session_key "$CWD_204")
printf '%s\n' '# Own Plan 204' '' '- [ ] my task' > "$PLANS_DIR/own-plan-204.md"
TRANSCRIPT_204=$(create_transcript_pct 10 "t204")
echo '{"prompt":"do something","session_id":"sess_204","transcript_path":"'"$TRANSCRIPT_204"'","cwd":"'"$CWD_204"'","permission_mode":"plan"}' | bash "$TEST_DIR/inject-plan.sh" > /dev/null
T204_PLAN=$(sed -n '5p' "$PLANS_DIR/.plan-state-${CWD_204_KEY}" 2>/dev/null || true)
if assert_file_exists "204" "$PLANS_DIR/.plan-state-${CWD_204_KEY}" && \
   [[ "$T204_PLAN" == *"own-plan-204.md" ]] && \
   assert_file_not_exists "204" "$PLANS_DIR/.pending-reload-${CWD_204_KEY}"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*

# --- Test 205: newest claimed only by a same-scope sibling is adopted, not refused ---
echo "Test 205: plan-mode first entry -> a same-scope sibling's plan is adopted"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*
CWD_205="$TEST_DIR/worktree-205"; mkdir -p "$CWD_205"
CWD_205_KEY=$(compute_session_key "$CWD_205")
printf '%s\n' '# Shared Plan 205' '' '- [ ] shared task' > "$PLANS_DIR/shared-plan-205.md"
OWN_SCOPE_205=$(bash -c 'source "$1/lib-plan.sh"; scope_key "$2"' _ "$TEST_DIR" "$CWD_205")
printf '%s\n%s\n%s\n%s\n%s\n%s\n' "sess_sib205" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" \
    "$PLANS_DIR/shared-plan-205.md" "$OWN_SCOPE_205" > "$PLANS_DIR/.plan-state-cafecafecafecafe"
TRANSCRIPT_205=$(create_transcript_pct 10 "t205")
OUT_205=$(echo '{"prompt":"do something","session_id":"sess_205","transcript_path":"'"$TRANSCRIPT_205"'","cwd":"'"$CWD_205"'","permission_mode":"plan"}' | bash "$TEST_DIR/inject-plan.sh")
STATE_205="$PLANS_DIR/.plan-state-${CWD_205_KEY}"
T205_PLAN=$(sed -n '5p' "$STATE_205" 2>/dev/null || true)
if assert_file_exists "205" "$STATE_205" && \
   [[ "$T205_PLAN" == *"shared-plan-205.md" ]] && \
   assert_not_contains "205" "$OUT_205" "PLAN ADOPTION REFUSED"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL (plan=$T205_PLAN)"; FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*

# --- Test 206: foreign newest is skipped and an adoptable older plan is taken (no refusal) ---
echo "Test 206: plan-mode first entry -> foreign newest skipped, older unclaimed plan adopted"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*
CWD_206="$TEST_DIR/worktree-206"; mkdir -p "$CWD_206"
CWD_206_KEY=$(compute_session_key "$CWD_206")
printf '%s\n' '# Older Own 206' '' '- [ ] mine' > "$PLANS_DIR/older-206.md"
touch -t "$(date -v-2H +%Y%m%d%H%M 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M)" "$PLANS_DIR/older-206.md"
printf '%s\n' '# Newer Foreign 206' '' '- [ ] theirs' > "$PLANS_DIR/newer-foreign-206.md"
touch -t "$(date -v-1H +%Y%m%d%H%M 2>/dev/null || date -d '1 hour ago' +%Y%m%d%H%M)" "$PLANS_DIR/newer-foreign-206.md"
printf '%s\n%s\n%s\n%s\n%s\n%s\n' "sess_f206" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" \
    "$PLANS_DIR/newer-foreign-206.md" "repo:/some/client/repo" > "$PLANS_DIR/.plan-state-beefbeefbeefbeef"
TRANSCRIPT_206=$(create_transcript_pct 10 "t206")
OUT_206=$(echo '{"prompt":"do something","session_id":"sess_206","transcript_path":"'"$TRANSCRIPT_206"'","cwd":"'"$CWD_206"'","permission_mode":"plan"}' | bash "$TEST_DIR/inject-plan.sh")
STATE_206="$PLANS_DIR/.plan-state-${CWD_206_KEY}"
T206_PLAN=$(sed -n '5p' "$STATE_206" 2>/dev/null || true)
T206_NEWEST=$(ls -t "$PLANS_DIR"/*.md 2>/dev/null | head -1)
if assert_file_exists "206" "$STATE_206" && \
   [[ "$T206_NEWEST" == *"newer-foreign-206.md" ]] && \
   [[ "$T206_PLAN" == *"older-206.md" ]] && \
   assert_not_contains "206" "$OUT_206" "PLAN ADOPTION REFUSED"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL (newest=$T206_NEWEST plan=$T206_PLAN)"; FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*

# --- Test 207: a legacy 5-line claimant (no recorded scope) blocks adoption ---
echo "Test 207: plan-mode first entry -> plan claimed by a legacy scope-less state file is refused"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*
CWD_207="$TEST_DIR/worktree-207"; mkdir -p "$CWD_207"
CWD_207_KEY=$(compute_session_key "$CWD_207")
printf '%s\n' '# Legacy-claimed 207' '' '- [ ] task' > "$PLANS_DIR/legacy-207.md"
printf '%s\n%s\n%s\n%s\n%s\n' "sess_l207" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" \
    "$PLANS_DIR/legacy-207.md" > "$PLANS_DIR/.plan-state-1207120712071207"
TRANSCRIPT_207=$(create_transcript_pct 10 "t207")
OUT_207=$(echo '{"prompt":"do something","session_id":"sess_207","transcript_path":"'"$TRANSCRIPT_207"'","cwd":"'"$CWD_207"'","permission_mode":"plan"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_contains "207" "$OUT_207" "PLAN ADOPTION REFUSED" && \
   assert_file_not_exists "207" "$PLANS_DIR/.plan-state-${CWD_207_KEY}"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*

# --- Test 208: emitter listing withholds a foreign-claimed plan, keeps an in-scope one ---
echo "Test 208: on-session-clear recent-plans listing omits a foreign-claimed plan"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*
CWD_208="$TEST_DIR/worktree-208"; mkdir -p "$CWD_208"
printf '%s\n' '# Visible 208' '' '- [ ] task' > "$PLANS_DIR/visible-emit-208.md"
printf '%s\n' '# Foreign 208' '' '- [ ] task' > "$PLANS_DIR/foreign-emit-208.md"
printf '%s\n%s\n%s\n%s\n%s\n%s\n' "sess_f208" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" \
    "$PLANS_DIR/foreign-emit-208.md" "repo:/some/client/repo" > "$PLANS_DIR/.plan-state-2082082082082082"
OUT_208=$(echo '{"cwd":"'"$CWD_208"'"}' | bash "$TEST_DIR/on-session-clear.sh")
if assert_contains "208" "$OUT_208" "visible-emit-208" && \
   assert_not_contains "208" "$OUT_208" "foreign-emit-208"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*

# --- Test 210: explicit !load-plan in plan mode overrides the scope refusal ---
echo "Test 210: plan-mode + explicit !load-plan of a foreign-claimed plan loads it, no refusal"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*
CWD_210="$TEST_DIR/worktree-210"; mkdir -p "$CWD_210"
printf '%s\n' '# Foreign 210' '' '- [ ] task' > "$PLANS_DIR/foreign-210.md"
printf '%s\n%s\n%s\n%s\n%s\n%s\n' "sess_f210" "unknown" "0" "$(date +%Y-%m-%dT%H:%M:%S%z)" \
    "$PLANS_DIR/foreign-210.md" "repo:/some/client/repo" > "$PLANS_DIR/.plan-state-2102102102102102"
TRANSCRIPT_210=$(create_transcript_pct 10 "t210")
OUT_210=$(echo '{"prompt":"!load-plan foreign-210","session_id":"sess_210","transcript_path":"'"$TRANSCRIPT_210"'","cwd":"'"$CWD_210"'","permission_mode":"plan"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_contains "210" "$OUT_210" "Foreign 210" && \
   assert_not_contains "210" "$OUT_210" "PLAN ADOPTION REFUSED"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*

# --- Test 211: a stale unclaimed plan (orphan window) is not guess-adopted ---
echo "Test 211: plan-mode first entry -> a stale unclaimed plan is refused, not adopted"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*
CWD_211="$TEST_DIR/worktree-211"; mkdir -p "$CWD_211"
CWD_211_KEY=$(compute_session_key "$CWD_211")
printf '%s\n' '# Stale Orphan 211' '' '- [ ] task' > "$PLANS_DIR/stale-211.md"
touch -t 202501010000 "$PLANS_DIR/stale-211.md"
TRANSCRIPT_211=$(create_transcript_pct 10 "t211")
OUT_211=$(echo '{"prompt":"do something","session_id":"sess_211","transcript_path":"'"$TRANSCRIPT_211"'","cwd":"'"$CWD_211"'","permission_mode":"plan"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_contains "211" "$OUT_211" "PLAN ADOPTION REFUSED" && \
   assert_file_not_exists "211" "$PLANS_DIR/.plan-state-${CWD_211_KEY}"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*

# --- Test 212: a just-fresh (23h) unclaimed plan is still guess-adopted ---
echo "Test 212: plan-mode first entry -> a 23h-old unclaimed plan is adopted (inside the 24h window)"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*
CWD_212="$TEST_DIR/worktree-212"; mkdir -p "$CWD_212"
CWD_212_KEY=$(compute_session_key "$CWD_212")
printf '%s\n' '# Fresh Edge 212' '' '- [ ] task' > "$PLANS_DIR/fresh-212.md"
touch -t "$(date -v-23H +%Y%m%d%H%M 2>/dev/null || date -d '23 hours ago' +%Y%m%d%H%M)" "$PLANS_DIR/fresh-212.md"
TRANSCRIPT_212=$(create_transcript_pct 10 "t212")
echo '{"prompt":"do something","session_id":"sess_212","transcript_path":"'"$TRANSCRIPT_212"'","cwd":"'"$CWD_212"'","permission_mode":"plan"}' | bash "$TEST_DIR/inject-plan.sh" > /dev/null
T212_PLAN=$(sed -n '5p' "$PLANS_DIR/.plan-state-${CWD_212_KEY}" 2>/dev/null || true)
if assert_file_exists "212" "$PLANS_DIR/.plan-state-${CWD_212_KEY}" && \
   [[ "$T212_PLAN" == *"fresh-212.md" ]]; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL (plan=$T212_PLAN)"; FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*

# --- Test 213: a just-stale (25h) unclaimed plan is not guess-adopted ---
echo "Test 213: plan-mode first entry -> a 25h-old unclaimed plan is refused (past the 24h window)"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*
CWD_213="$TEST_DIR/worktree-213"; mkdir -p "$CWD_213"
CWD_213_KEY=$(compute_session_key "$CWD_213")
printf '%s\n' '# Stale Edge 213' '' '- [ ] task' > "$PLANS_DIR/stale-213.md"
touch -t "$(date -v-25H +%Y%m%d%H%M 2>/dev/null || date -d '25 hours ago' +%Y%m%d%H%M)" "$PLANS_DIR/stale-213.md"
TRANSCRIPT_213=$(create_transcript_pct 10 "t213")
OUT_213=$(echo '{"prompt":"do something","session_id":"sess_213","transcript_path":"'"$TRANSCRIPT_213"'","cwd":"'"$CWD_213"'","permission_mode":"plan"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_contains "213" "$OUT_213" "PLAN ADOPTION REFUSED" && \
   assert_file_not_exists "213" "$PLANS_DIR/.plan-state-${CWD_213_KEY}"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*

# --- Test 214: an explicit trigger-word load is NOT age-gated ---
echo "Test 214: non-plan 'execute plan' loads a stale unclaimed plan (explicit intent, no freshness gate)"
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*
CWD_214="$TEST_DIR/worktree-214"; mkdir -p "$CWD_214"
printf '%s\n' '# Old Own 214' '' '- [ ] task' > "$PLANS_DIR/old-own-214.md"
touch -t 202501010000 "$PLANS_DIR/old-own-214.md"
TRANSCRIPT_214=$(create_transcript_pct 10 "t214")
OUT_214=$(echo '{"prompt":"execute the plan","session_id":"sess_214","transcript_path":"'"$TRANSCRIPT_214"'","cwd":"'"$CWD_214"'"}' | bash "$TEST_DIR/inject-plan.sh")
if assert_contains "214" "$OUT_214" "Old Own 214" && \
   assert_not_contains "214" "$OUT_214" "Plan Not Found"; then
    echo "  PASS"; PASS=$((PASS + 1))
else
    echo "  FAIL"; FAIL=$((FAIL + 1))
fi
rm -f "$PLANS_DIR"/*.md "$PLANS_DIR"/.plan-state-* "$PLANS_DIR"/.pending-reload-*

# --- Summary ---
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
if [[ $((PASS + FAIL)) -ne $TOTAL ]]; then
    echo "COUNT MISMATCH: ran $((PASS + FAIL)) test(s) but TOTAL=$TOTAL (a test increment was lost or TOTAL is stale)"
    exit 1
fi
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
