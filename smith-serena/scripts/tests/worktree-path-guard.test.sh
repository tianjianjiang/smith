#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../worktree-path-guard.mjs"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: worktree-path-guard - $1"; }

command -v node >/dev/null 2>&1 || { echo "SKIP: worktree-path-guard - node not installed"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: worktree-path-guard - jq not installed"; exit 0; }

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CEILING_DIRECTORIES

TMP=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$TMP"' EXIT

commit_all() {
    git -C "$1" add -A
    git -C "$1" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m "$2" \
        || { echo "FAIL: fixture commit in $1" >&2; return 1; }
}

new_repo() {
    local repo="$TMP/$1"
    git init -q "$repo"
    mkdir -p "$repo/src/nested"
    echo "alpha" > "$repo/src/alpha.md"
    echo "beta" > "$repo/src/nested/beta.md"
    commit_all "$repo" init || return 1
    printf '.claude/\n' >> "$repo/.git/info/exclude"
    echo "$repo"
}

new_worktree() {
    git -C "$1" worktree add -q "$1/.claude/worktrees/$2" -b "wt-$2" \
        || { echo "FAIL: fixture worktree $2 in $1" >&2; return 1; }
    echo "$1/.claude/worktrees/$2"
}

OUT=""
ERR=""
STATUS=0
run_hook() {
    local launch="$1" cwd="$2" tool="$3" tool_input="$4"
    local payload
    payload=$(jq -cn --arg cwd "$cwd" --arg tool "$tool" --argjson ti "$tool_input" \
        '{cwd: $cwd, tool_name: $tool, tool_input: $ti}')
    if [[ "$launch" == "UNSET" ]]; then
        OUT=$(printf '%s' "$payload" | env -u CLAUDE_PROJECT_DIR node "$HOOK" 2>"$TMP/stderr")
    else
        OUT=$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$launch" node "$HOOK" 2>"$TMP/stderr")
    fi
    STATUS=$?
    ERR=$(cat "$TMP/stderr")
}

expect_block() { [[ "$STATUS" == 2 ]] || fail "$1: expected exit 2, got $STATUS ($ERR)"; }
expect_allow() { [[ "$STATUS" == 0 ]] || fail "$1: expected exit 0, got $STATUS ($ERR)"; }
expect_silent() { expect_allow "$1"; [[ -z "$OUT" && -z "$ERR" ]] || fail "$1: expected silence, got out=[$OUT] err=[$ERR]"; }
expect_stderr() { [[ "$ERR" == *"$2"* ]] || fail "$1: stderr lacks [$2]: $ERR"; }
expect_context() {
    echo "$OUT" | jq -e --arg text "$2" '.hookSpecificOutput.hookEventName == "PreToolUse"
        and (.hookSpecificOutput.additionalContext | contains($text))' >/dev/null \
        || fail "$1: additionalContext lacks [$2]: $OUT"
}
expect_built_in_only() {
    expect_block "$1"
    expect_stderr "$1" "built-in Edit/Write with absolute paths"
    [[ "$ERR" != *'relative_path="'* ]] || fail "$1: a prefixed path was suggested: $ERR"
}

REPLACE=mcp__serena__replace_content
OVERVIEW=mcp__serena__get_symbols_overview
repo=$(new_repo repo-a) || fail "fixture repo-a"
wt=$(new_worktree "$repo" one) || fail "fixture worktree one"
other=$(new_worktree "$repo" two) || fail "fixture worktree two"
prefix=".claude/worktrees/one"

run_hook "$repo" "$wt" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_block "unprefixed write"
expect_stderr "unprefixed write" "relative_path=\"$prefix/src/alpha.md\""
expect_stderr "unprefixed write" "built-in Edit/Write"
pass "unprefixed write is blocked with the prefixed path"

run_hook "$repo" "$wt" "$REPLACE" "{\"relative_path\":\"$prefix/src/alpha.md\"}"
expect_silent "prefixed write"
pass "prefixed write passes silently"

run_hook "$repo" "$wt" "$REPLACE" "{\"relative_path\":\"$wt/src/alpha.md\"}"
expect_silent "absolute path inside the worktree"
pass "absolute path inside the worktree passes"

run_hook "$repo" "$wt" "$REPLACE" "{\"relative_path\":\"$repo/src/alpha.md\"}"
expect_block "absolute path in the primary"
expect_stderr "absolute path in the primary" "relative_path=\"$prefix/src/alpha.md\""
pass "absolute path in the primary is blocked with the prefixed path"

run_hook "$repo" "$wt" mcp__serena__find_symbol '{"name_path_pattern":"main"}'
expect_block "find_symbol without a path"
expect_stderr "find_symbol without a path" "relative_path=\"$prefix\""
run_hook "$repo" "$wt" mcp__serena__find_symbol '{"name_path_pattern":"main","relative_path":"  "}'
expect_block "find_symbol with a blank path"
expect_stderr "find_symbol with a blank path" "relative_path=\"$prefix\""
run_hook "$repo" "$wt" mcp__serena__replace_in_files '{"needle":"a","repl":"b"}'
expect_block "replace_in_files without a path"
run_hook "$repo" "$wt" mcp__serena__replace_in_files '{"needle":"a","repl":"b","relative_path":null}'
expect_block "replace_in_files with a null path"
run_hook "$repo" "$wt" mcp__serena__search_for_pattern '{"substring_pattern":"a"}'
expect_block "search_for_pattern without a path"
expect_stderr "search_for_pattern without a path" "relative_path=\"$prefix\""
pass "a call over the whole project is blocked"

run_hook "$repo" "$wt" mcp__serena__replace_in_files \
    "{\"relative_path\":\"$prefix\",\"paths_include_glob\":\"src/**/*.md\"}"
expect_block "unprefixed include glob"
expect_stderr "unprefixed include glob" "paths_include_glob=\"$prefix/src/**/*.md\""
run_hook "$repo" "$wt" mcp__serena__replace_in_files \
    "{\"relative_path\":\"$prefix\",\"paths_include_glob\":\"src/*.md\",\"paths_exclude_glob\":\"src/nested/*\"}"
expect_block "both globs unprefixed"
expect_stderr "both globs unprefixed" \
    "paths_include_glob=\"$prefix/src/*.md\" and paths_exclude_glob=\"$prefix/src/nested/*\""
pass "unprefixed globs are blocked with the prefixed glob"

run_hook "$repo" "$wt" mcp__serena__replace_in_files \
    "{\"relative_path\":\"$prefix\",\"paths_include_glob\":\"**/*.md\",\"paths_exclude_glob\":\"$prefix/src/nested/*\"}"
expect_silent "anchored globs"
run_hook "$repo" "$wt" mcp__serena__replace_in_files \
    "{\"relative_path\":\"$prefix\",\"paths_include_glob\":\"\",\"paths_exclude_glob\":\"  \"}"
expect_silent "blank globs"
pass "globs that are prefixed, start with **/, or are blank pass"

run_hook "$repo" "$wt" mcp__serena__replace_in_files \
    "{\"relative_path\":\"$prefix\",\"paths_exclude_glob\":\"*.md\"}"
expect_block "glob without a directory part"
expect_stderr "glob without a directory part" "paths_exclude_glob=\"$prefix/*.md\""
pass "a glob without a directory part is blocked, because Serena anchors it at its root"

run_hook "$repo" "$wt" mcp__serena__replace_in_files \
    '{"relative_path":".claude/worktrees/two/src","paths_include_glob":"src/*.md"}'
expect_block "unprefixed glob with a path into another worktree"
expect_stderr "unprefixed glob with a path into another worktree" \
    'paths_include_glob=".claude/worktrees/two/src/*.md"'
run_hook "$repo" "$wt" mcp__serena__replace_in_files \
    '{"relative_path":".claude/worktrees/two/src","paths_include_glob":".claude/worktrees/two/src/*.md"}'
expect_silent "prefixed glob with a path into another worktree"
pass "globs follow the worktree that the path names"

run_hook "$repo" "$wt" "$OVERVIEW" '{"relative_path":"src/alpha.md"}'
expect_block "unprefixed read"
expect_stderr "unprefixed read" "relative_path=\"$prefix/src/alpha.md\""
pass "unprefixed read is blocked with the prefixed path"

for tool in write_memory read_memory list_memories delete_memory rename_memory edit_memory \
    initial_instructions onboarding; do
    run_hook "$repo" "$wt" "mcp__serena__$tool" '{"memory_name":"note","topic":""}'
    expect_silent "$tool"
done
pass "memory tools and tools without a path pass silently"

run_hook "$repo" "$repo" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_silent "cwd is the primary"
pass "a session working in the primary checkout is left alone"

run_hook "$wt" "$wt" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_silent "session started in the worktree"
run_hook "$wt" "$wt/src/nested" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_silent "session started in the worktree, cwd in a subdirectory"
pass "a session that started inside the worktree is left alone"

run_hook "$wt" "$repo" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_built_in_only "session returned to the primary, write"
expect_stderr "session returned to the primary, write" "works in checkout $repo, but Serena is rooted at $wt "
expect_stderr "session returned to the primary, write" "absolute paths inside $repo."
run_hook "$wt" "$repo" "$OVERVIEW" '{"relative_path":"src/alpha.md"}'
expect_allow "session returned to the primary, read"
expect_context "session returned to the primary, read" "describes $wt, not $repo"
pass "a session that returned to the primary while Serena is rooted in a worktree is covered"

deep=$(new_worktree "$wt" deep) || fail "fixture worktree nested in a worktree"
run_hook "$wt" "$deep" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_block "worktree nested in the worktree Serena is rooted in"
expect_stderr "worktree nested in the worktree Serena is rooted in" \
    'relative_path=".claude/worktrees/deep/src/alpha.md"'
run_hook "$wt" "$deep" "$REPLACE" '{"relative_path":".claude/worktrees/deep/src/alpha.md"}'
expect_silent "prefixed path into the nested worktree"
pass "Serena's own root does not count as another worktree"

run_hook "$repo" "$wt" "$REPLACE" "{\"relative_path\":\" $prefix/src/alpha.md\"}"
expect_block "path with a leading space"
run_hook "$repo" "$wt" "$REPLACE" "{\"relative_path\":\" /../src/alpha.md\"}"
expect_block "path that turns absolute only after trimming"
expect_stderr "path that turns absolute only after trimming" "relative_path=\"$prefix/src/alpha.md\""
pass "a path is judged as given, not trimmed"

run_hook UNSET "$wt" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_silent "CLAUDE_PROJECT_DIR unset"
mkdir -p "$TMP/not-git"
run_hook "$TMP/not-git" "$wt" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_silent "launch directory is not a repository"
run_hook "$TMP/does-not-exist" "$wt" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_silent "launch directory does not exist"
run_hook "$repo" "$TMP/not-git" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_silent "cwd is not a repository"
foreign=$(new_repo repo-foreign) || fail "fixture repo-foreign"
run_hook "$foreign" "$wt" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_silent "launch directory in an unrelated repository"
pass "a launch directory or cwd that cannot be related fails open"

OUT=$(printf 'not json' | CLAUDE_PROJECT_DIR="$repo" node "$HOOK" 2>"$TMP/stderr"); STATUS=$?
ERR=$(cat "$TMP/stderr")
expect_silent "malformed stdin"
run_hook "$repo" "$wt" "$REPLACE" '{"relative_path":42}'
expect_silent "numeric relative_path"
run_hook "$repo" "$wt" "$REPLACE" '{"relative_path":null}'
expect_silent "null relative_path"
run_hook "$repo" "$wt" Edit '{"file_path":"src/alpha.md","relative_path":"src/alpha.md"}'
expect_silent "non-Serena tool"
pass "malformed input, non-string path and non-Serena tools fail open"

run_hook "$repo" "$wt" mcp__plugin_serena_serena__replace_content '{"relative_path":"src/alpha.md"}'
expect_block "plugin tool name"
expect_stderr "plugin tool name" "relative_path=\"$prefix/src/alpha.md\""
pass "the plugin tool name prefix is covered"

run_hook "$repo" "$wt" "$REPLACE" "{\"relative_path\":\"src/../$prefix/src/alpha.md\"}"
expect_silent "path that normalizes into the worktree"
run_hook "$repo" "$wt" "$REPLACE" "{\"relative_path\":\"$prefix/../../../src/alpha.md\"}"
expect_block "path that normalizes out of the worktree"
expect_stderr "path that normalizes out of the worktree" "relative_path=\"$prefix/src/alpha.md\""
pass "paths are normalized before the check"

run_hook "$repo" "$wt" "$REPLACE" '{"relative_path":"../outside.md"}'
expect_silent "relative path outside the root"
run_hook "$repo" "$wt" "$REPLACE" "{\"relative_path\":\"$TMP/not-git/outside.md\"}"
expect_silent "absolute path outside the root"
mkdir -p "$TMP/repo-a2"
run_hook "$repo" "$wt" "$REPLACE" "{\"relative_path\":\"$TMP/repo-a2/outside.md\"}"
expect_silent "sibling directory sharing the root's name prefix"
pass "a path outside Serena's root is left to Serena"

ln -s "$repo" "$TMP/link"
run_hook "$TMP/link" "$TMP/link/$prefix" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_block "symlinked launch directory and cwd"
expect_stderr "symlinked launch directory and cwd" "relative_path=\"$prefix/src/alpha.md\""
expect_stderr "symlinked launch directory and cwd" "rooted at $repo."
run_hook "$TMP/link" "$wt" "$REPLACE" "{\"relative_path\":\"$TMP/link/$prefix/src/new-file.md\"}"
expect_silent "symlinked absolute path to a new file in the worktree"
run_hook "$TMP/link" "$wt" "$REPLACE" "{\"relative_path\":\"$TMP/link/src/new-file.md\"}"
expect_block "symlinked absolute path to a new file in the primary"
expect_stderr "symlinked absolute path to a new file in the primary" "relative_path=\"$prefix/src/new-file.md\""
pass "symlinked paths are resolved before comparison"

upper="$TMP/REPO-A"
if [[ -d "$upper" ]]; then
    run_hook "$upper" "$wt" "$REPLACE" '{"relative_path":"src/alpha.md"}'
    expect_block "launch directory typed in another case"
    expect_stderr "launch directory typed in another case" "rooted at $repo."
    pass "a launch directory typed in another case resolves to its real case"
else
    echo "SKIP: worktree-path-guard - case-sensitive file system"
fi

run_hook "$repo" "$wt" "$REPLACE" '{"relative_path":".claude/worktrees/two/src/alpha.md"}'
expect_silent "path into another worktree"
pass "an explicit path into another worktree passes"

run_hook "$other" "$wt" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_built_in_only "Serena rooted at another worktree"
pass "a session launched in another worktree cannot reach this one"

run_hook "$repo" "$wt/src/nested" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_block "cwd is a subdirectory of the worktree"
expect_stderr "cwd is a subdirectory of the worktree" "relative_path=\"$prefix/src/alpha.md\""
pass "the prefix is computed from the worktree top"

run_hook "$repo/src/nested" "$wt" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_block "launch directory is a subdirectory of the primary"
expect_stderr "launch directory is a subdirectory of the primary" "rooted at $repo."
pass "the root walks up from the launch directory"

spaced=$(new_repo "repo with space") || fail "fixture repo with space"
spaced_wt=$(new_worktree "$spaced" "one") || fail "fixture worktree in repo with space"
run_hook "$spaced" "$spaced_wt" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_block "path with a space"
expect_stderr "path with a space" "works in checkout $spaced_wt,"
pass "a path with a space is reported intact"

mkdir -p "$TMP/umbrella/.serena"
echo "project_name: umbrella" > "$TMP/umbrella/.serena/project.yml"
inner=$(new_repo umbrella/inner) || fail "fixture umbrella/inner"
inner_wt=$(new_worktree "$inner" one) || fail "fixture worktree in umbrella/inner"
run_hook "$inner" "$inner_wt" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_block "Serena project above the git root"
expect_stderr "Serena project above the git root" "rooted at $inner."
pass "the nearest boundary wins over an ancestor project.yml"

mkdir -p "$inner/src/nested/.serena"
echo "project_name: nested" > "$inner/src/nested/.serena/project.yml"
run_hook "$inner/src/nested" "$inner_wt" "$REPLACE" '{"relative_path":"alpha.md"}'
expect_built_in_only "Serena rooted below the primary"
expect_stderr "Serena rooted below the primary" "rooted at $inner/src/nested "
run_hook "$inner/src/nested" "$inner/src/nested" "$REPLACE" '{"relative_path":"alpha.md"}'
expect_silent "Serena rooted below the primary, session in the primary"
pass "a Serena root below the primary checkout cannot reach the worktree"

outside=$(new_repo repo-outside) || fail "fixture repo-outside"
git -C "$outside" worktree add -q "$TMP/elsewhere" -b wt-elsewhere || fail "fixture worktree elsewhere"
run_hook "$outside" "$TMP/elsewhere" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_built_in_only "worktree outside the root, write"
run_hook "$outside" "$TMP/elsewhere" "$OVERVIEW" '{"relative_path":"src/alpha.md"}'
expect_allow "worktree outside the root, read"
expect_context "worktree outside the root, read" "describes $outside, not $TMP/elsewhere"
pass "a worktree outside the root blocks writes and annotates reads"

ignored=$(new_repo repo-ignored) || fail "fixture repo-ignored"
printf '.claude/worktrees/\n' > "$ignored/.gitignore"
commit_all "$ignored" ignore || fail "fixture commit in repo-ignored"
ignored_wt=$(new_worktree "$ignored" one) || fail "fixture worktree in repo-ignored"
run_hook "$ignored" "$ignored_wt" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_built_in_only "worktree ignored through .gitignore, write"
run_hook "$ignored" "$ignored_wt" "$OVERVIEW" '{"relative_path":"src/alpha.md"}'
expect_allow "worktree ignored through .gitignore, read"
expect_context "worktree ignored through .gitignore, read" "describes $ignored, not $ignored_wt"
pass "a worktree ignored through a .gitignore file is unreachable"

partial=$(new_repo repo-partial) || fail "fixture repo-partial"
printf '*.log\nnode_modules/\n' > "$partial/.gitignore"
commit_all "$partial" ignore || fail "fixture commit in repo-partial"
partial_wt=$(new_worktree "$partial" one) || fail "fixture worktree in repo-partial"
echo "x" > "$partial_wt/debug.log"
mkdir -p "$partial_wt/node_modules/p"
echo "x" > "$partial_wt/node_modules/p/index.js"
run_hook "$partial" "$partial_wt" "$REPLACE" '{"relative_path":"src/alpha.md"}'
expect_block "ignored files inside the worktree"
expect_stderr "ignored files inside the worktree" "relative_path=\"$prefix/src/alpha.md\""
pass "ignored files inside a worktree do not make it unreachable"

below=$(new_repo repo-below) || fail "fixture repo-below"
mkdir -p "$below/src/.serena"
echo "project_name: below" > "$below/src/.serena/project.yml"
git -C "$below" worktree add -q "$below/src/wt" -b wt-below || fail "fixture worktree below Serena's root"
run_hook "$below/src" "$below/src/wt" "$REPLACE" '{"relative_path":"alpha.md"}'
expect_block "Serena rooted in a subdirectory, path inside the root"
expect_stderr "Serena rooted in a subdirectory, path inside the root" "rooted at $below/src."
expect_stderr "Serena rooted in a subdirectory, path inside the root" 'relative_path="wt/src/alpha.md"'
run_hook "$below/src" "$below/src/wt" "$REPLACE" '{"relative_path":"../top.md"}'
expect_block "Serena rooted in a subdirectory, path above the root"
expect_stderr "Serena rooted in a subdirectory, path above the root" 'relative_path="wt/top.md"'
run_hook "$below/src" "$below/src/wt" mcp__serena__find_symbol '{"name_path_pattern":"main"}'
expect_block "Serena rooted in a subdirectory, whole project"
expect_stderr "Serena rooted in a subdirectory, whole project" 'relative_path="wt/src"'
run_hook "$below/src" "$below/src/wt" "$REPLACE" '{"relative_path":"wt/src/alpha.md"}'
expect_silent "Serena rooted in a subdirectory, prefixed path"
run_hook "$below/src" "$below/src/wt" "$REPLACE" '{"relative_path":"../../outside.md"}'
expect_silent "Serena rooted in a subdirectory, path outside the checkout"
below_other=$(new_worktree "$below" other) || fail "fixture worktree outside Serena's root"
run_hook "$below/src" "$below/src/wt" mcp__serena__replace_in_files \
    "{\"relative_path\":\"$below_other/src\",\"paths_include_glob\":\"**/*.md\"}"
expect_block "path into a worktree outside Serena's root"
[[ "$ERR" != *'glob="..'* ]] || fail "a glob prefix that leaves Serena's root was suggested: $ERR"
pass "the corrected path is relative to the top of Serena's checkout"

gone=$(new_worktree "$repo" gone) || fail "fixture worktree gone"
rm -rf "$gone"
run_hook "$repo" "$wt" "$REPLACE" '{"relative_path":".claude/worktrees/gone/src/alpha.md"}'
expect_block "path into a worktree whose directory is gone"
pass "a registered worktree whose directory is gone does not count"

run_hook "$repo" "$wt" mcp__serena__rename_symbol \
    "{\"relative_path\":\"$prefix/src/alpha.md\",\"name_path\":\"a\",\"new_name\":\"b\"}"
expect_allow "prefixed rename_symbol"
expect_context "prefixed rename_symbol" "git status"
run_hook "$repo" "$wt" mcp__serena__safe_delete_symbol \
    "{\"relative_path\":\"$prefix/src/alpha.md\",\"name_path_pattern\":\"a\"}"
expect_silent "prefixed safe_delete_symbol"
pass "rename_symbol passes with a cross-tree warning, safe_delete_symbol silently"

[[ -z "$(git -C "$repo" status --porcelain)" ]] || fail "the hook modified the primary checkout"
[[ -z "$(git -C "$wt" status --porcelain)" ]] || fail "the hook modified the worktree"
for created in "$wt/src/new-file.md" "$repo/src/new-file.md" "$TMP/outside.md" \
    "$TMP/not-git/outside.md" "$TMP/repo-a2/outside.md" "$below/top.md"; do
    [[ ! -e "$created" ]] || fail "the hook created $created"
done
pass "the hook changes no files"
