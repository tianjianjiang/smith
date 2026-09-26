#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../link-worktree-memories.sh"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: link-worktree-memories - $1"; }

TMP=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$TMP"' EXIT

new_repo() {
    local repo="$TMP/$1"
    git init -q "$repo"
    git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    printf '.serena\n' > "$repo/.git/info/exclude"
    mkdir -p "$repo/.serena/memories"
    echo "primary" > "$repo/.serena/memories/shared_note.md"
    echo "$repo"
}

new_worktree() {
    git -C "$1" worktree add -q "$1/.claude/worktrees/$2" -b "wt-$2" 2>/dev/null
    echo "$1/.claude/worktrees/$2"
}

run_in() { printf '{"cwd":"%s"}' "$1" | bash "$HOOK"; }

repo=$(new_repo repo-a)

wt=$(new_worktree "$repo" missing)
out=$(run_in "$wt")
[[ -L "$wt/.serena/memories" ]] || fail "missing folder was not linked"
[[ "$(readlink "$wt/.serena/memories")" == "$repo/.serena/memories" ]] || fail "missing folder linked to wrong target"
[[ -f "$wt/.serena/memories/shared_note.md" ]] || fail "primary memory not visible through link"
echo "$out" | grep -q '"additionalContext"' || fail "no additionalContext when linking"
pass "missing worktree folder is linked to the primary"

wt=$(new_worktree "$repo" empty)
mkdir -p "$wt/.serena/memories"
run_in "$wt" >/dev/null
[[ -L "$wt/.serena/memories" ]] || fail "empty folder was not linked"
pass "empty worktree folder is replaced by a link"

wt=$(new_worktree "$repo" nonempty)
mkdir -p "$wt/.serena/memories"
echo "local" > "$wt/.serena/memories/local_note.md"
out=$(run_in "$wt")
[[ ! -L "$wt/.serena/memories" && -f "$wt/.serena/memories/local_note.md" ]] || fail "non-empty folder was modified"
echo "$out" | grep -q "NOT linked" || fail "no warning for non-empty folder"
pass "non-empty worktree folder is left alone with a warning"

wt="$repo/.claude/worktrees/missing"
out=$(run_in "$wt")
[[ -z "$out" ]] || fail "already-linked worktree was not silent: $out"
pass "already-linked worktree is a silent no-op"

out=$(run_in "$repo")
[[ -z "$out" && ! -L "$repo/.serena/memories" ]] || fail "primary checkout was touched"
mkdir -p "$TMP/not-git"
out=$(run_in "$TMP/not-git")
[[ -z "$out" ]] || fail "non-git dir was not silent"
pass "primary checkout and non-git dir are no-ops"

repo_b=$(new_repo repo-b)
rm -rf "$repo_b/.serena"
wt=$(new_worktree "$repo_b" noserena)
out=$(run_in "$wt")
[[ -z "$out" && ! -e "$wt/.serena/memories" ]] || fail "primary without Serena memories was not a no-op"
pass "primary without Serena memories is a no-op"

repo_c=$(new_repo repo-c)
mkdir -p "$TMP/external-bucket"
echo "external" > "$TMP/external-bucket/bucket_note.md"
rm -rf "$repo_c/.serena/memories"
ln -s "$TMP/external-bucket" "$repo_c/.serena/memories"
wt=$(new_worktree "$repo_c" chained)
run_in "$wt" >/dev/null
[[ "$(readlink "$wt/.serena/memories")" == "$repo_c/.serena/memories" ]] || fail "chain not kept"
[[ -f "$wt/.serena/memories/bucket_note.md" ]] || fail "external bucket not visible through chain"
pass "symlinked primary memories are reached through the kept chain"

git -C "$repo" worktree add -q "$TMP/outside-tree" -b wt-outside 2>/dev/null
run_in "$TMP/outside-tree" >/dev/null
[[ "$(readlink "$TMP/outside-tree/.serena/memories")" == "$repo/.serena/memories" ]] || fail "worktree outside the repo tree not linked"
pass "worktree outside the repo tree is linked to the primary checkout"

wt=$(new_worktree "$repo" regularfile)
mkdir -p "$wt/.serena"
echo "x" > "$wt/.serena/memories"
out=$(run_in "$wt")
[[ -f "$wt/.serena/memories" && ! -L "$wt/.serena/memories" ]] || fail "regular file was modified"
echo "$out" | grep -q "is a file" || fail "no warning for regular file"
pass "regular file at the memories path is left alone with a warning"

wt=$(new_worktree "$repo" otherlink)
mkdir -p "$wt/.serena" "$TMP/elsewhere"
ln -s "$TMP/elsewhere" "$wt/.serena/memories"
out=$(run_in "$wt")
[[ "$(readlink "$wt/.serena/memories")" == "$TMP/elsewhere" ]] || fail "foreign symlink was changed"
echo "$out" | grep -q "left unchanged" || fail "no warning for foreign symlink"
pass "symlink to another place is left alone with a warning"

wt="$repo/.claude/worktrees/with space"
git -C "$repo" worktree add -q "$wt" -b wt-spaced 2>/dev/null
(cd "$wt" && echo "not json" | bash "$HOOK") >/dev/null
[[ "$(readlink "$wt/.serena/memories")" == "$repo/.serena/memories" ]] || fail "non-JSON stdin or spaced path not linked via PWD"
pass "non-JSON stdin falls back to PWD, and paths with spaces work"

wt=$(new_worktree "$repo" lnfails)
mkdir -p "$TMP/failing-bin"
printf '#!/bin/sh\nexit 1\n' > "$TMP/failing-bin/ln"
chmod +x "$TMP/failing-bin/ln"
out=$(printf '{"cwd":"%s"}' "$wt" | PATH="$TMP/failing-bin:$PATH" bash "$HOOK")
echo "$out" | grep -q "FAILED" || fail "no warning when the link cannot be created"
pass "a link that cannot be created is reported, never silent"

repo_d=$(new_repo repo-d)
rm -f "$repo_d/.serena/memories/shared_note.md"
wt=$(new_worktree "$repo_d" sharedserena)
ln -s "$repo_d/.serena" "$wt/.serena"
out=$(run_in "$wt")
[[ -z "$out" && -d "$repo_d/.serena/memories" && ! -L "$repo_d/.serena/memories" ]] || fail "primary memories touched through a shared .serena"
pass "a worktree whose .serena already resolves to the primary's is a no-op"

git -C "$repo" worktree remove --force "$repo/.claude/worktrees/missing"
[[ -f "$repo/.serena/memories/shared_note.md" ]] || fail "worktree removal deleted the primary's memories"
pass "git worktree remove keeps the primary's memories"

echo "ALL PASS: link-worktree-memories"
