#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/branch-guard.mjs"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: branch-guard - $1"; }

command -v node >/dev/null 2>&1 || { echo "SKIP: branch-guard - node not installed"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: branch-guard - jq not installed"; exit 0; }

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CEILING_DIRECTORIES

TMP=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$TMP"' EXIT

repo="$TMP/repo"
git init -q -b main "$repo"
mkdir -p "$repo/src"
echo "alpha" > "$repo/src/alpha.txt"
git -C "$repo" add src
git -C "$repo" -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c core.excludesFile=/dev/null \
    commit -q -m init || fail "fixture commit"
printf '.claude/\n' >> "$repo/.git/info/exclude"
feature="$repo/.claude/worktrees/feature"
protected="$repo/.claude/worktrees/protected"
git -C "$repo" worktree add -q "$feature" -b fix/one || fail "fixture worktree feature"
git -C "$repo" worktree add -q "$protected" -b develop || fail "fixture worktree protected"
git -C "$repo" config core.excludesFile /dev/null
feature_prefix=".claude/worktrees/feature"
protected_prefix=".claude/worktrees/protected"

ERR=""
STATUS=0
run_hook() {
    local launch="$1" cwd="$2" tool="$3" tool_input="$4"
    local payload
    payload=$(jq -cn --arg cwd "$cwd" --arg tool "$tool" --argjson ti "$tool_input" \
        '{cwd: $cwd, tool_name: $tool, tool_input: $ti}')
    if [[ "$launch" == "UNSET" ]]; then
        printf '%s' "$payload" | env -u CLAUDE_PROJECT_DIR node "$HOOK" >/dev/null 2>"$TMP/stderr"
    else
        printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$launch" node "$HOOK" >/dev/null 2>"$TMP/stderr"
    fi
    STATUS=$?
    ERR=$(cat "$TMP/stderr")
}

expect_allow() { [[ "$STATUS" == 0 && -z "$ERR" ]] || fail "$1: expected a silent exit 0, got $STATUS ($ERR)"; }
expect_block_on() {
    [[ "$STATUS" == 2 ]] || fail "$1: expected exit 2, got $STATUS ($ERR)"
    [[ "$ERR" == *"protected branch '$2' of $3."* ]] || fail "$1: expected a block on '$2' of $3, got: $ERR"
}

SERENA=mcp__serena__replace_content

run_hook "$repo" "$feature" "$SERENA" '{"relative_path":"src/alpha.txt"}'
expect_block_on "unprefixed Serena path after EnterWorktree" main "$repo"
pass "an unprefixed Serena path resolves to the primary checkout"

run_hook "$repo" "$feature" "$SERENA" "{\"relative_path\":\"$feature_prefix/src/alpha.txt\"}"
expect_allow "Serena path prefixed into a feature worktree"
run_hook "$repo" "$feature" "$SERENA" "{\"relative_path\":\"$protected_prefix/src/alpha.txt\"}"
expect_block_on "Serena path prefixed into a protected worktree" develop "$protected"
pass "a prefixed Serena path resolves to the branch of the worktree it names"

run_hook "$repo/src" "$feature" mcp__plugin_serena_serena__replace_content '{"relative_path":"src/alpha.txt"}'
expect_block_on "launch directory below the primary, plugin tool name" main "$repo"
pass "the root walks up from the launch directory for both tool name prefixes"

run_hook "$repo" "$feature" "$SERENA" "{\"relative_path\":\"$protected/src/alpha.txt\"}"
expect_block_on "absolute Serena path" develop "$protected"
pass "an absolute Serena path is used as given"

run_hook UNSET "$protected" "$SERENA" '{"relative_path":"src/alpha.txt"}'
expect_block_on "no launch directory" develop "$protected"
run_hook "$TMP/does-not-exist" "$protected" "$SERENA" '{"relative_path":"src/alpha.txt"}'
expect_block_on "launch directory does not exist" develop "$protected"
pass "without a usable launch directory a Serena path falls back to the session cwd"

run_hook "$protected" "$protected" "$SERENA" '{"relative_path":"src/alpha.txt"}'
expect_block_on "session started in a protected worktree" develop "$protected"
run_hook "$feature" "$feature" "$SERENA" '{"relative_path":"src/alpha.txt"}'
expect_allow "session started in a feature worktree"
pass "a session that started inside a worktree resolves against that worktree"

run_hook "$repo" "$protected" Edit '{"file_path":"src/alpha.txt"}'
expect_block_on "built-in Edit relative path" develop "$protected"
run_hook "$repo" "$feature" Edit "{\"file_path\":\"$repo/src/alpha.txt\"}"
expect_block_on "built-in Edit on the primary" main "$repo"
pass "a built-in tool resolves a relative path against the session cwd"

run_hook "$repo" "$repo" mcp__serena__replace_in_files '{"needle":"a","repl":"b"}'
expect_block_on "Serena call without a path, cwd on main" main "$repo"
run_hook "$repo" "$feature" mcp__serena__replace_in_files '{"needle":"a","repl":"b"}'
expect_block_on "Serena call without a path after EnterWorktree" main "$repo"
run_hook "$feature" "$feature" mcp__serena__replace_in_files '{"needle":"a","repl":"b"}'
expect_allow "Serena call without a path, Serena rooted on a feature branch"
run_hook UNSET "$protected" mcp__serena__replace_in_files '{"needle":"a","repl":"b"}'
expect_block_on "Serena call without a path, no launch directory" develop "$protected"
run_hook "$repo" "$repo" Edit '{}'
expect_allow "built-in call without a path"
pass "a Serena call without a path is checked where Serena is rooted"

run_hook "$repo" "$repo" "$SERENA" "{\"relative_path\":\".claude/notes.txt\"}"
expect_allow "gitignored target"
pass "a gitignored target is allowed"

touch "$repo/.claude/branch-guard.disabled"
run_hook "$repo" "$repo" "$SERENA" '{"relative_path":"src/alpha.txt"}'
expect_allow "opt-out marker"
pass "the per-repo opt-out marker is honoured"
