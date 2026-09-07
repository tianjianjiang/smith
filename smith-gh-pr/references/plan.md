# Plan: Fix PR review comment assisted-by attribution format (from intent.md 2026-09-08)

## Files that change

**New files**:
1. `smith-gh-pr/scripts/enforce-attribution.sh` - PreToolUse hook for gh pr comment/review validation

**Modified files**:
1. `smith-gh-pr/SKILL.md` - Add "Pre-Draft Verification" section
2. `smith-gh-pr/README.md` - Document hook registration
3. `~/.claude/settings.json` - Register PreToolUse hook

## Order of work

### Phase 1: Attribution Validation Hook (FR1)
1. Create `smith-gh-pr/scripts/enforce-attribution.sh`
   - Validate `Assisted-by: Claude:claude-[model]` pattern
   - Block "on behalf of" pattern
   - Show error with attribution.sh script path
2. Make executable: `chmod +x smith-gh-pr/scripts/enforce-attribution.sh`
3. Test with sample commands:
   - Valid: `gh pr comment --body "...\n\nAssisted-by: Claude:claude-sonnet-4-5"`
   - Invalid: `gh pr comment --body "...on behalf of..."`
   - Invalid: `gh pr comment --body "...\n\nAssisted-by: Claude"`
4. Document hook registration in `smith-gh-pr/README.md`

### Phase 2: Verification Checkpoint (FR4)
1. Add "Pre-Draft Verification" section to `smith-gh-pr/SKILL.md`
   - Run attribution.sh script
   - Format validation rules
   - Append to comment body
2. Test skill loading in PR review scenario

### Phase 3: Integration & Registration
1. Register hook in `~/.claude/settings.json`:
   ```json
   "hooks": {
     "PreToolUse": [
       "~/.smith/smith-gh-pr/scripts/enforce-attribution.sh"
     ]
   }
   ```
2. Full workflow test: PR review from planning to posting
3. Monitor first 10 sessions for false positives

### Phase 4: Commit & PR
1. Commit all changes in worktree
2. Push to remote
3. Create PR to tianjianjiang/smith
4. After merge, symlinks propagate to `~/.claude/skills/smith-*`

## Risks

**R1**: False positives block legitimate commands
- **Mitigation**: Monitor first 10 sessions, adjust regex if needed
- **Impact**: Medium (user friction)

**R2**: attribution.sh might not exist on fresh clone
- **Mitigation**: Hook should gracefully handle missing script
- **Impact**: Low (user gets clear error)

**R3**: Hook adds latency to every gh command
- **Mitigation**: Early exit for non-PR commands, target <50ms
- **Impact**: Low (NFR1)

## Proof

**Test cases**:

1. **FR1 validation**:
   - ✅ `gh pr comment 123 -b "Fix\n\nAssisted-by: Claude:claude-sonnet-4-5"` → allowed
   - ❌ `gh pr comment 123 -b "Fix\n\nAssisted-by: Claude"` → blocked
   - ❌ `gh pr comment 123 -b "Posted on behalf of @user"` → blocked
   - ✅ `gh pr comment 123` (no -b, opens editor) → allowed

2. **FR4 checkpoint**:
   - ✅ smith-gh-pr/SKILL.md contains "Pre-Draft Verification" section
   - ✅ Section shows attribution.sh usage
   - ✅ Format validation rules documented

3. **Integration**:
   - ✅ Hook registered in ~/.claude/settings.json
   - ✅ Full PR review workflow completes without false positives
   - ✅ Attribution format correct in test comment draft

**Verification method**: Run test suite in isolated worktree, then monitor 10 real PR review sessions after deployment.

## Future Work

**FR2: Skill Enforcement Hook** (deferred)
- **Goal**: PreToolUse hook to enforce required skills are loaded before external writes
- **Complexity**: Requires turn state tracking mechanism (Skill tool wrapper or conversation log parsing)
- **ROI uncertain**: FR1 already blocks wrong format at execution time
- **Decision**: Evaluate need after FR1 deployment and monitoring
