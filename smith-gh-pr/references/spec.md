# Spec: Fix PR review comment assisted-by attribution format
Status: draft. Based on: `smith-gh-pr/references/intent.md`

## Requirements

### Functional Requirements

**FR1**: PreToolUse hook for `gh pr comment` and `gh pr review` MUST validate attribution format
- Hook location: `smith-gh-pr/scripts/enforce-attribution.sh`
- Validates: presence of `Assisted-by: Claude:claude-[model]` pattern
- Blocks: "on behalf of" pattern, missing `:model-id`, hand-typed attribution
- On failure: shows error with correct format from `attribution.sh`

**FR2**: PreToolUse hook for external writes MUST enforce skill loading
- Hook location: `smith-ctx-claude/scripts/enforce-required-skills.sh`
- Triggers: when pattern matches PR/Slack/Jira AND tool is external write
- Validates: required skills were invoked this turn (smith-gh-pr + smith-style for gh commands)
- On failure: shows "Load required skills first: /smith-gh-pr /smith-style"

**FR3**: Basic-Memory notes MUST use correct attribution format
- Search for: "on behalf of" pattern, incomplete `Assisted-by: Claude`
- Update to: require `attribution.sh`, show correct format example
- Document corrections in changelog

**FR4**: smith-gh-pr skill MUST include pre-draft verification checkpoint
- Location: new "Pre-Draft Verification" section
- Steps: run attribution.sh, validate format, append to comment
- Format validation rules documented

### Non-Functional Requirements

**NFR1**: Hooks add minimal latency (<50ms per invocation)

**NFR2**: Error messages are actionable (show what's wrong + how to fix)

**NFR3**: Both enforcement layers are complementary (not redundant)
- FR1 catches format errors at execution
- FR2 prevents errors at composition by ensuring rules loaded

## Design

### FR1 Implementation: PreToolUse Hook for Attribution Validation

**File**: `smith-gh-pr/scripts/enforce-attribution.sh`

```bash
#!/usr/bin/env bash
# PreToolUse hook: validate gh pr comment/review attribution format

set -euo pipefail

# Extract tool name and arguments
TOOL_NAME="$1"
shift
TOOL_ARGS="$*"

# Only intercept gh pr commands
[[ "$TOOL_NAME" != "gh" ]] && exit 0
[[ "$TOOL_ARGS" != *"pr comment"* ]] && [[ "$TOOL_ARGS" != *"pr review"* ]] && exit 0

# Extract comment body (handles -b, -F, heredoc)
BODY=""
if [[ "$TOOL_ARGS" =~ -b[[:space:]]+"([^"]*)" ]] || [[ "$TOOL_ARGS" =~ -b[[:space:]]+'([^']*)' ]]; then
    BODY="${BASH_REMATCH[1]}"
elif [[ "$TOOL_ARGS" =~ -F[[:space:]]+([^[:space:]]+) ]]; then
    FILE="${BASH_REMATCH[1]}"
    [[ -f "$FILE" ]] && BODY=$(cat "$FILE")
fi

# No body provided (user will edit in editor) - allow
[[ -z "$BODY" ]] && exit 0

# Validate attribution format
if ! grep -qE 'Assisted-by: Claude:claude-(sonnet|opus|haiku|fable)-[0-9]+-[0-9]+' <<< "$BODY"; then
    echo "Error: Missing or invalid assisted-by attribution" >&2
    echo "" >&2
    echo "Required format:" >&2
    ~/.smith/smith-ctx-claude/scripts/attribution.sh >&2
    echo "" >&2
    echo "NEVER hand-type the attribution - always run the script above" >&2
    exit 1
fi

# Block "on behalf of" pattern
if grep -qi "on behalf of" <<< "$BODY"; then
    echo "Error: Found forbidden 'on behalf of' pattern" >&2
    echo "Use assisted-by attribution only (run attribution.sh)" >&2
    exit 1
fi

exit 0
```

### FR2 Implementation: Skill Enforcement Hook

**File**: `smith-ctx-claude/scripts/enforce-required-skills.sh`

```bash
#!/usr/bin/env bash
# PreToolUse hook: enforce required skills loaded for external writes

set -euo pipefail

TOOL_NAME="$1"

# Protected tool → required skills mapping
# Format: "tool_pattern:skill1,skill2"
PROTECTED_TOOLS=(
    "gh:smith-gh-pr,smith-style"
    "slack_send_message_draft:smith-slack"
    "mcp__plugin_atlassian.*addOrEditJiraIssueComment:smith-tickets"
)

# Check if tool needs protection
REQUIRED_SKILLS=""
for ENTRY in "${PROTECTED_TOOLS[@]}"; do
    PATTERN="${ENTRY%%:*}"
    SKILLS="${ENTRY##*:}"
    if [[ "$TOOL_NAME" =~ ^$PATTERN$ ]]; then
        REQUIRED_SKILLS="$SKILLS"
        break
    fi
done

# No protection needed
[[ -z "$REQUIRED_SKILLS" ]] && exit 0

# Check which skills were invoked this turn
# Read from turn metadata file (written by Skill tool wrapper)
TURN_STATE="${CLAUDE_SESSION_DIR:-$HOME/.claude/sessions/current}/turn-state.json"
[[ ! -f "$TURN_STATE" ]] && {
    echo "Error: Cannot verify skill loading (turn state unavailable)" >&2
    echo "Required skills: $REQUIRED_SKILLS" >&2
    exit 1
}

# Verify all required skills were invoked
IFS=',' read -ra SKILLS <<< "$REQUIRED_SKILLS"
for SKILL in "${SKILLS[@]}"; do
    if ! jq -e ".invoked_skills | contains([\"$SKILL\"])" "$TURN_STATE" > /dev/null 2>&1; then
        echo "Error: Required skill '$SKILL' not loaded" >&2
        echo "Load required skills first:" >&2
        for S in "${SKILLS[@]}"; do
            echo "  /smith-$S" >&2
        done
        exit 1
    fi
done

exit 0
```

**Note**: Turn state tracking requires Skill tool wrapper enhancement (separate implementation)

### FR3 Implementation: Basic-Memory Corrections

**Search queries**:
1. Full-text search: `"on behalf of"` in PR review context
2. Full-text search: `Assisted-by: Claude` (without colon after)

**Update template**:
```markdown
## Correct Attribution Format

ALWAYS use the script - NEVER hand-type:
```bash
~/.smith/smith-ctx-claude/scripts/attribution.sh
```

Format: `Assisted-by: Claude:claude-sonnet-4-5` (or actual session model)

❌ WRONG: "Posted by Claude Code on behalf of @username"
❌ WRONG: `Assisted-by: Claude` (missing :model-id)
✅ CORRECT: Output from attribution.sh script
```

### FR4 Implementation: Verification Checkpoint in smith-gh-pr

**Location**: `smith-gh-pr/SKILL.md`, new section after "PR Review Comments"

```markdown
## Pre-Draft Verification

Before drafting any PR review comment:

1. **Get attribution from script**:
   ```bash
   ~/.smith/smith-ctx-claude/scripts/attribution.sh
   ```

2. **Validate format**:
   - ✅ Matches: `Assisted-by: Claude:claude-[a-z]+-[0-9]+-.*`
   - ✅ Model ID is valid session model (sonnet|opus|haiku|fable)
   - ❌ NO "on behalf of" anywhere in comment
   - ❌ NO hand-typed model IDs

3. **Append to comment body**:
   - Blank line before attribution
   - Attribution as last line of comment body
```

## Design Decisions

**D1**: Both FR1 (hook) and FR2 (skill enforcement) are needed - defense in depth
- FR1: tactical (catches at execution point)
- FR2: strategic (ensures rules loaded during composition)
- Neither is redundant - they protect different failure modes

**D2**: FR2 uses PreToolUse validation instead of skill-router blocking
- Preserves skill-router as advisory mechanism
- Fits existing hook architecture
- User-space implementation (no harness changes)

**D3**: Turn state tracking via JSON file written by Skill tool wrapper
- Alternative A: Parse conversation log (fragile, expensive)
- Alternative B: Check loaded file list (unreliable markers)
- Alternative C: JSON state file (chosen - clean, fast, reliable)

**D4**: Start with narrow scope (PR/Slack/Jira), expand based on evidence
- These three have documented failures (intent.md)
- Other tools (git push, etc.) have different protection needs
- Easy to extend protected tools list after validating mechanism

**D5**: Hook errors show both problem and solution
- Error message states what's wrong
- Shows correct format OR points to script
- User can fix and retry immediately

## Implementation Plan

### Phase 1: FR1 - Attribution Validation Hook
1. Create `smith-gh-pr/scripts/enforce-attribution.sh`
2. Test against sample `gh pr comment` commands
3. Document hook registration in smith-gh-pr README

### Phase 2: FR2 - Skill Enforcement Hook
1. Create `smith-ctx-claude/scripts/enforce-required-skills.sh`
2. Create protected tools mapping (JSON config or inline array)
3. Implement Skill tool wrapper to write turn state
4. Test with PR review workflow
5. Document hook registration in smith-ctx-claude README

### Phase 3: FR3 - Basic-Memory Corrections
1. Search basic-memory for affected notes
2. Update each with correct format template
3. Verify no "on behalf of" remains
4. Document changes in this spec's changelog

### Phase 4: FR4 - Verification Checkpoint
1. Add "Pre-Draft Verification" section to smith-gh-pr SKILL.md
2. Test skill loading in PR review scenarios

### Phase 5: Integration
1. Register both hooks in `~/.claude/settings.json`
2. Determine hook execution order (enforce-required-skills before enforce-attribution)
3. Full workflow test: PR review from planning to posting
4. Monitor first 10 sessions for false positives

## Success Criteria

1. ✅ FR1 hook blocks `gh pr` commands with wrong attribution
2. ✅ FR2 hook blocks external writes when required skills not loaded
3. ✅ All basic-memory notes use correct attribution format
4. ✅ smith-gh-pr skill contains verification checkpoint
5. ✅ No "on behalf of" in any new PR comments
6. ✅ All attributions pulled from script, none hand-typed
7. ✅ Both hooks registered with clear installation instructions

## Open Questions

**Q1**: Turn state tracking - which mechanism?
- Proposed: JSON file written by Skill tool wrapper
- Needs: wrapper enhancement to track invoked skills
- Alternative: conversation log parsing (fallback if wrapper unavailable)

**Q2**: Hook execution order matters?
- Proposed: enforce-required-skills runs before enforce-attribution
- Rationale: If skills not loaded, no point checking format
- Implementation: registration order in settings.json

**Q3**: Error message verbosity?
- Proposed: Show example + require script call
- Ensures agent calls script (gets fresh model ID)
- User gets fast feedback from example

## Non-Goals

- Fixing attribution in already-posted comments (historical)
- Enforcing attribution in git commit messages (different format)
- Validating attribution in artifacts/documents (not applicable)

## Rollout Plan

1. Implement in `~/.smith` directory
2. Test in isolated worktree
3. Commit and PR to tianjianjiang/smith
4. After merge, symlinks propagate to `~/.claude/skills/smith-*`
5. Monitor first 10 PR review sessions

## Changelog

- 2026-09-08: Initial spec draft based on intent.md
