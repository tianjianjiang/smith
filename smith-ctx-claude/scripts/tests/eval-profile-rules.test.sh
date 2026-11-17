#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib/eval-profile-rules.mjs"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: eval-profile-rules - $1"; }

rewritten() {
  node --input-type=module -e 'const { evalPermissionRule } = await import(process.argv[1]); console.log(evalPermissionRule(process.argv[2], { home: process.argv[3], evalConfigFolder: process.argv[4] }));' "$LIB" "$1" "$2" "$3"
}

deny_rules() {
  node --input-type=module -e 'const { evalDenyRules } = await import(process.argv[1]); console.log(JSON.stringify(evalDenyRules([process.argv[2]], { home: process.argv[3], evalConfigFolder: process.argv[4] })));' "$LIB" "$1" "$2" "$3"
}

eval_folder_is_usable() {
  node --input-type=module -e 'const { evalConfigFolderIsUsable } = await import(process.argv[1]); console.log(evalConfigFolderIsUsable({ home: process.argv[2], evalConfigFolder: process.argv[3] }));' "$LIB" "$1" "$2"
}

names_an_installed_copy() {
  node --input-type=module -e 'const { namesAnInstalledCopy } = await import(process.argv[1]); console.log(namesAnInstalledCopy(process.argv[2], process.argv[3]));' "$LIB" "$1" "$2"
}

HOME_FOLDER=/Users/fixture
EVAL_FOLDER=/Users/fixture/.claude-smith-eval
OUTSIDE_EVAL_FOLDER='/tmp/eval$&profile'

expect_rule() {
  local description=$1 rule=$2 eval_folder=$3 expected=$4 got
  got=$(rewritten "$rule" "$HOME_FOLDER" "$eval_folder") || fail "$description: the rewrite did not run"
  [ "$got" = "$expected" ] || fail "$description: '$rule' became '$got', expected '$expected'"
  pass "$description"
}

expect_rule "an absolute path rule moves to the eval folder" "Read(//Users/fixture/.claude/**)" "$EVAL_FOLDER" "Read(//Users/fixture/.claude-smith-eval/**)"
expect_rule "a home path rule keeps the home form" "Read(~/.claude/**)" "$EVAL_FOLDER" "Read(~/.claude-smith-eval/**)"
expect_rule "a rule naming the folder itself moves" "Edit(~/.claude)" "$EVAL_FOLDER" "Edit(~/.claude-smith-eval)"
expect_rule "a Bash rule keeps a path a command can type" "Bash(cat ~/.claude/x:*)" "$EVAL_FOLDER" "Bash(cat ~/.claude-smith-eval/x:*)"
expect_rule "a Bash rule with the folder before a space moves" "Bash(ls ~/.claude *)" "$EVAL_FOLDER" "Bash(ls ~/.claude-smith-eval *)"
expect_rule "another profile's folder stays" "Read(~/.claude-elu/**)" "$EVAL_FOLDER" "Read(~/.claude-elu/**)"
expect_rule "a longer folder name stays" "Read(//Users/fixture/.claudex/**)" "$EVAL_FOLDER" "Read(//Users/fixture/.claudex/**)"
expect_rule "a rule without the folder stays" "Bash(ls:*)" "$EVAL_FOLDER" "Bash(ls:*)"
expect_rule "a single-slash absolute Bash rule keeps its form" "Bash(rm /Users/fixture/.claude/settings.json)" "$EVAL_FOLDER" "Bash(rm /Users/fixture/.claude-smith-eval/settings.json)"
expect_rule "a \$HOME rule keeps its form" "Edit(\$HOME/.claude/settings.json)" "$EVAL_FOLDER" "Edit(\$HOME/.claude-smith-eval/settings.json)"
expect_rule "a \${HOME} Bash rule keeps its form" "Bash(cat \${HOME}/.claude/x)" "$EVAL_FOLDER" "Bash(cat \${HOME}/.claude-smith-eval/x)"
expect_rule "a Bash rule for an eval folder outside the home folder names the folder as a command types it" "Bash(cat ~/.claude/x:*)" "$OUTSIDE_EVAL_FOLDER" "Bash(cat /tmp/eval\$&profile/x:*)"
expect_rule "an eval folder outside the home folder is written as an absolute path, dollar signs kept" "Read(~/.claude/**)" "$OUTSIDE_EVAL_FOLDER" "Read(//tmp/eval\$&profile/**)"
expect_rule "a quoted \$HOME path outside the home folder keeps its quotes" "Bash(cat \"\$HOME/.claude/x\":*)" /tmp/eval-profile "Bash(cat \"/tmp/eval-profile/x\":*)"
expect_rule "a quoted \$HOME path inside the home folder keeps its quotes" "Bash(cat \"\$HOME/.claude/x\":*)" "$EVAL_FOLDER" "Bash(cat \"\$HOME/.claude-smith-eval/x\":*)"
expect_rule "a separately quoted \$HOME keeps its quotes inside the home folder" "Bash(cat \"\$HOME\"/.claude/x)" "$EVAL_FOLDER" "Bash(cat \"\$HOME\"/.claude-smith-eval/x)"
expect_rule "a separately quoted \$HOME keeps its quotes outside the home folder" "Bash(cat \"\$HOME\"/.claude/x)" /tmp/eval-profile "Bash(cat \"/tmp/eval-profile\"/x)"
expect_rule "a \${HOME:-…} rule keeps its form" "Bash(cat \${HOME:-x}/.claude/x)" "$EVAL_FOLDER" "Bash(cat \${HOME:-x}/.claude-smith-eval/x)"
expect_rule "a path that only ends in the home path stays" "Read(/data/Users/fixture/.claude/**)" "$EVAL_FOLDER" "Read(/data/Users/fixture/.claude/**)"
expect_rule "an absolute rule keeps dollar signs of the eval folder" "Read(//Users/fixture/.claude/**)" "$OUTSIDE_EVAL_FOLDER" "Read(//tmp/eval\$&profile/**)"

expect_deny_rules() {
  local description=$1 rule=$2 expected=$3 got
  got=$(deny_rules "$rule" "$HOME_FOLDER" "$EVAL_FOLDER") || fail "$description: the deny rules were not built"
  [ "$got" = "$expected" ] || fail "$description: '$rule' gave $got, expected $expected"
  pass "$description"
}

expect_deny_rules "a deny rule on the default profile also denies the eval folder" "Edit(~/.claude/settings.json)" '["Edit(~/.claude/settings.json)","Edit(~/.claude-smith-eval/settings.json)"]'
expect_deny_rules "a deny rule elsewhere is copied once" "Bash(rm -rf:*)" '["Bash(rm -rf:*)"]'

expect_installed_copy() {
  local description=$1 text=$2 expected=$3 got
  got=$(names_an_installed_copy "$text" "$HOME_FOLDER") || fail "$description: the check did not run"
  [ "$got" = "$expected" ] || fail "$description: '$text' gave $got, expected $expected"
  pass "$description"
}

expect_installed_copy "a command on \$HOME/.claude names the installed copy" 'bash $HOME/.claude/skills/a.sh' true
expect_installed_copy "a command on \${HOME}/.claude names the installed copy" 'bash ${HOME}/.claude/skills/a.sh' true
expect_installed_copy "a command on ~/.smith names the installed copy" 'cat ~/.smith/x' true
expect_installed_copy "a command on the home path names the installed copy" 'cat /Users/fixture/.claude/settings.json' true
expect_installed_copy "the unused default of CLAUDE_CONFIG_DIR is not read" 'bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude/skills}/a.sh"' false
expect_installed_copy "the unused default without a colon is not read" 'D=${CLAUDE_CONFIG_DIR-~/.claude/}' false
expect_installed_copy "an installed copy after the default is still found" 'ls ${CLAUDE_CONFIG_DIR:-x}; cat $HOME/.claude/y' true
expect_installed_copy "the installed folder itself without a slash names the installed copy" 'cat ~/.claude' true
expect_installed_copy "a change into ~/.smith names the installed copy" 'cd ~/.smith && ls' true
expect_installed_copy "a quoted \$HOME names the installed copy" 'cat "$HOME"/.claude/settings.json' true
expect_installed_copy "a nested unused default is not read" 'cat ${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/x' false
expect_installed_copy "an installed copy after a nested default is still found" 'cat ${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/x; cat ~/.claude/y' true
expect_installed_copy "a path that only ends in the home path is not the installed copy" 'cat /data/Users/fixture/.claude/x' false
expect_installed_copy "the default is read once the command unsets CLAUDE_CONFIG_DIR" 'unset CLAUDE_CONFIG_DIR; cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"' true
expect_installed_copy "the default is read once env drops CLAUDE_CONFIG_DIR" 'env -u CLAUDE_CONFIG_DIR sh -c "cat ${CLAUDE_CONFIG_DIR:-~/.claude}/x"' true
expect_installed_copy "the default is read once the command sets CLAUDE_CONFIG_DIR" 'CLAUDE_CONFIG_DIR= cat ${CLAUDE_CONFIG_DIR:-~/.claude}/x' true
expect_installed_copy "the default is read once env unsets CLAUDE_CONFIG_DIR with a long option" 'env --unset=CLAUDE_CONFIG_DIR sh -c '\''cat ${CLAUDE_CONFIG_DIR:-~/.claude}/x'\''' true
expect_installed_copy "the default is read once env clears the environment" 'env -i sh -c '\''cat ${CLAUDE_CONFIG_DIR:-~/.claude}/x'\''' true
expect_installed_copy "the default is read once unset names CLAUDE_CONFIG_DIR after another variable" 'unset UNUSED CLAUDE_CONFIG_DIR; cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"' true
expect_installed_copy "a \${HOME:-…} default names the installed copy" 'cat ${HOME:-x}/.claude/x' true
expect_installed_copy "a .env file does not count as running env" 'cat .env; cat ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/x' false
expect_installed_copy "an --env-file option does not count as running env" 'uv run --env-file a bash ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/x' false
expect_installed_copy "the default is read once the command stops exporting CLAUDE_CONFIG_DIR" 'export -n CLAUDE_CONFIG_DIR; bash -c '\''cat ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/x'\''' true
expect_installed_copy "a script named env.sh does not count as running env" 'bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/env.sh"' false
expect_installed_copy "the default is read once env runs from an absolute path" '/usr/bin/env -i /bin/sh -c '\''cat "${CLAUDE_CONFIG_DIR:-/Users/fixture/.claude}/settings.json"'\''' true
expect_installed_copy "a folder named env does not count as running env" 'cat ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/env/x' false
expect_installed_copy "the eval folder is not the installed copy" 'cat ~/.claude-smith-eval/skills/x' false

expect_usable_folder() {
  local description=$1 eval_folder=$2 expected=$3 got
  got=$(eval_folder_is_usable "$HOME_FOLDER" "$eval_folder") || fail "$description: the check did not run"
  [ "$got" = "$expected" ] || fail "$description: '$eval_folder' gave $got, expected $expected"
  pass "$description"
}

expect_usable_folder "a folder inside the home folder can be the eval profile" "$EVAL_FOLDER" true
expect_usable_folder "a folder outside the home folder can be the eval profile" /tmp/eval-profile true
expect_usable_folder "the home folder cannot be the eval profile" "$HOME_FOLDER" false
expect_usable_folder "a folder above the home folder cannot be the eval profile" /Users false
expect_usable_folder "the default profile cannot be the eval profile" /Users/fixture/.claude false
expect_usable_folder "a folder inside the default profile cannot be the eval profile" /Users/fixture/.claude/eval false
expect_usable_folder "a folder whose name starts with two dots is not above the home folder" /Users/fixture/..eval true

REAL_HOME=$(mktemp -d)
trap 'rm -rf "$REAL_HOME"' EXIT
mkdir "$REAL_HOME/.claude"
ln -s "$REAL_HOME/.claude" "$REAL_HOME/.claude-smith-eval"
got=$(eval_folder_is_usable "$REAL_HOME" "$REAL_HOME/.claude-smith-eval") || fail "a link to the default profile: the check did not run"
[ "$got" = false ] || fail "a link to the default profile was accepted as the eval profile"
pass "a link to the default profile cannot be the eval profile"
ln -s "$REAL_HOME/.claude" "$REAL_HOME/profile-link"
got=$(eval_folder_is_usable "$REAL_HOME" "$REAL_HOME/profile-link/new-eval") || fail "a missing folder under a link to the default profile: the check did not run"
[ "$got" = false ] || fail "a missing folder under a link to the default profile was accepted as the eval profile"
pass "a missing folder under a link to the default profile cannot be the eval profile"
if [ -d "$REAL_HOME/.CLAUDE" ]; then
  got=$(eval_folder_is_usable "$REAL_HOME" "$REAL_HOME/.CLAUDE") || fail "a case variant of the default profile: the check did not run"
  [ "$got" = false ] || fail "a case variant of the default profile was accepted as the eval profile"
  pass "a case variant of the default profile cannot be the eval profile"
fi
