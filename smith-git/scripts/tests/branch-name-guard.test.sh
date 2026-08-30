#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/branch-name-guard.mjs"

fail() { echo "FAIL: $1"; exit 1; }

assert_exit() {
  printf '%s' "$2" | node "$HOOK" >/dev/null 2>&1
  got=$?
  [ "$got" = "$3" ] || fail "$1 (expected exit $3, got $got)"
}

assert_exit "checkout -b valid kebab name allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feat/user-authentication"}}' 0
assert_exit "switch -c valid name allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git switch -c fix/plan-claude-model-detection"}}' 0
assert_exit "plain git branch create valid name allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch docs/gh-pr-attribution-wording"}}' 0
assert_exit "dotted segment allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b chore/deps-node18.20-bump"}}' 0
assert_exit "single-word description allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b chore/cleanup"}}' 0

assert_exit "underscore in description blocked" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feat/user_authentication"}}' 2

assert_exit "uppercase blocked" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b Feat/AddLogin"}}' 2

assert_exit "unknown type blocked" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b wip/exploring-thing"}}' 2

assert_exit "missing type prefix blocked" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b just-a-slug"}}' 2

assert_exit "consecutive hyphens blocked" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feat/double--hyphen"}}' 2
assert_exit "leading hyphen blocked" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feat/-leading"}}' 2

assert_exit "post-review substring blocked" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b fix/auth-post-review"}}' 2
assert_exit "after-review substring blocked" \
  '{"tool_name":"Bash","tool_input":{"command":"git switch -c fix/token-after-review"}}' 2

assert_exit "dollar-variable name is not validated literally" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b $NAME"}}' 0
assert_exit "braced-variable name is not validated literally" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b ${NAME}"}}' 0
assert_exit "command-substitution name is not validated literally" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b $(echo feat/x)"}}' 0
assert_exit "backtick command-substitution name is not validated literally" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b `echo feat/x`"}}' 0
assert_exit "a forbidden substring smuggled next to an empty-resolving substitution is still blocked" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feat/post-review$(true)"}}' 2
assert_exit "a forbidden substring smuggled next to an empty-resolving backtick is still blocked" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feat/post-review`true`"}}' 2
assert_exit "a benign name next to a command substitution is still allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feat/x$(true)"}}' 0

assert_exit "rename to valid name allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -m feat/new-name"}}' 0
assert_exit "rename to invalid name blocked" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -m feat/new_name"}}' 2
assert_exit "old-to-new rename validates the new name" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -m old-name feat/new-name"}}' 0
assert_exit "force rename -M validates" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -M feat/bad_name"}}' 2
assert_exit "copy -c validates the new name, not the source" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -c feat/valid-source feat/Invalid_Name"}}' 2
assert_exit "copy --copy validates the new name" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch --copy feat/valid-source feat/Invalid_Name"}}' 2
assert_exit "copy -c with a valid new name allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -c feat/valid-source feat/valid-target"}}' 0
assert_exit "--track creates a new branch and is validated" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch --track feat/tracked_bad master"}}' 2
assert_exit "--track with a valid new name allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch --track feat/tracked-ok master"}}' 0
assert_exit "--unset-upstream is not mistaken for a create" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch --unset-upstream feature-x"}}' 0
assert_exit "bundled -fc (force + copy) validates the new name" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -fc master post-review"}}' 2
assert_exit "bundled -fm (force + move) validates the new name" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -fm master feat/bad_name"}}' 2
assert_exit "-u with an attached value containing 'm' is not misread as rename" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -umain feature-x"}}' 0
assert_exit "-u with an attached value containing 'c' is not misread as copy" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -uconfig feature-x"}}' 0

assert_exit "checking out an existing branch (no create flag) is not validated" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout main"}}' 0
assert_exit "switching to an existing branch (no create flag) is not validated" \
  '{"tool_name":"Bash","tool_input":{"command":"git switch develop"}}' 0
assert_exit "checkout with an unrelated short flag and no create flag is not validated" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -f main"}}' 0
assert_exit "git status allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git status"}}' 0
assert_exit "-v is a cosmetic modifier, not a listing skip - still validates" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -v feat/user_bad"}}' 2
assert_exit "--verbose is a cosmetic modifier, not a listing skip - still validates" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch --verbose feat/user_bad"}}' 2
assert_exit "bundled -vf (verbose + force) still validates" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -vf feat/user_bad"}}' 2
assert_exit "git branch listing (-a) allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -a"}}' 0
assert_exit "git branch -d delete allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -d old-branch"}}' 0
assert_exit "git -C before branch still checked" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C /repo checkout -b feat/user_bad"}}' 2
assert_exit "quoted -C value containing a space does not shift the subcommand" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C \"/repo with spaces\" checkout -b feat/user_bad"}}' 2
assert_exit "backslash-escaped spaces in a -C value do not shift the subcommand" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C /repo\\ with\\ spaces checkout -b feat/user_bad"}}' 2
assert_exit "space-separated --config-env value does not shift the subcommand" \
  '{"tool_name":"Bash","tool_input":{"command":"git --config-env core.pager=X checkout -b feat/user_bad"}}' 2
assert_exit "quoted branch name strips quotes" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b \"feat/user_bad\""}}' 2
assert_exit "echoed git command is not a real invocation" \
  '{"tool_name":"Bash","tool_input":{"command":"echo git checkout -b feat/user_bad"}}' 0
assert_exit "non-Bash tool allowed" \
  '{"tool_name":"Read","tool_input":{"file_path":"/x"}}' 0
assert_exit "malformed stdin allowed" 'not json' 0
assert_exit "null stdin allowed" 'null' 0

assert_exit "-umain upstream flag is not mistaken for a rename" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -umain feature-x"}}' 0
assert_exit "--set-upstream-to is not mistaken for a create" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch --set-upstream-to=origin/main feature-x"}}' 0
assert_exit "long-option create with = value is validated" \
  '{"tool_name":"Bash","tool_input":{"command":"git switch --create=feat/bad_name"}}' 2
assert_exit "attached short flag -bNAME is validated" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -bfeat/user_bad"}}' 2
assert_exit "attached short flag -bNAME allows valid names" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -bfeat/attached-ok"}}' 0
assert_exit "bundled -qb (quiet + create) is validated" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -qb feat/user_bad"}}' 2
assert_exit "bundled -qb with a valid name allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -qb feat/valid-name"}}' 0
assert_exit "bundled -fb (force + create) is validated" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -fb feat/user_bad"}}' 2
assert_exit "bundled -qc (quiet + create) on switch is validated" \
  '{"tool_name":"Bash","tool_input":{"command":"git switch -qc feat/user_bad"}}' 2
assert_exit "checkout -B force-create is validated" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -B feat/user_bad"}}' 2
assert_exit "switch -C force-create is validated" \
  '{"tool_name":"Bash","tool_input":{"command":"git switch -C feat/user_bad"}}' 2
assert_exit "checkout --orphan is validated" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout --orphan feat/user_bad"}}' 2
assert_exit "switch --orphan is validated" \
  '{"tool_name":"Bash","tool_input":{"command":"git switch --orphan feat/user_bad"}}' 2
assert_exit "git stash branch is validated" \
  '{"tool_name":"Bash","tool_input":{"command":"git stash branch feat/user_bad"}}' 2
assert_exit "git worktree add -b is validated" \
  '{"tool_name":"Bash","tool_input":{"command":"git worktree add ../wt -b feat/user_bad"}}' 2
assert_exit "git worktree add without -b is not a create" \
  '{"tool_name":"Bash","tool_input":{"command":"git worktree add ../wt existing-branch"}}' 0
assert_exit "env-prefixed checkout -b is validated" \
  '{"tool_name":"Bash","tool_input":{"command":"GIT_EDITOR=true git checkout -b feat/user_bad"}}' 2
assert_exit "plain git branch invalid name blocked" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch feat/user_bad"}}' 2
assert_exit "detached HEAD checkout target is skipped" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b HEAD"}}' 0
assert_exit "bad name after an unrelated chained command still blocks" \
  '{"tool_name":"Bash","tool_input":{"command":"git status && git checkout -b feat/user_bad"}}' 2
assert_exit "bad name in a semicolon-chained command still blocks" \
  '{"tool_name":"Bash","tool_input":{"command":"echo start; git checkout -b feat/user_bad"}}' 2

message_contains() {
  out=$(printf '%s' "$2" | node "$HOOK" 2>&1 >/dev/null)
  case "$out" in
    *"$3"*) ;;
    *) fail "$1: expected stderr to contain '$3', got: $out" ;;
  esac
}

message_contains "fixable underscore name offers a suggestion" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feat/bad_name"}}' \
  "Did you mean 'feat/bad-name'?"
message_contains "leading-hyphen name whose stripped form is still invalid falls back to the generic message" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feat/-leading"}}' \
  "Choose a name matching the pattern."
message_contains "a suggestion that would itself contain a forbidden substring falls back to the generic message" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b fix/auth_post_review"}}' \
  "Choose a name matching the pattern."

echo "PASS: branch-name-guard"
