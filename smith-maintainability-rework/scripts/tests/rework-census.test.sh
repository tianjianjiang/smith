#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
CENSUS="$HERE/../rework-census.mjs"
REPO="$(mktemp -d)" || { echo "FAIL: setup: mktemp"; exit 2; }

failures=0
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid
git_in() { git -C "$REPO" "$@" >/dev/null || { echo "FAIL: setup: git $*"; exit 2; }; }
commit() { git_in add -A && git_in commit -q -m "$1"; }
sha_of() { git -C "$REPO" log --format=%H --grep "$1" -F -1; }

git_in init -q
printf 'def add(a, b):\n    return a - b\n\n' > "$REPO/calc.py"
commit "feat(calc): add addition"
printf 'def twice(x):\n    return 2 * x\n' > "$REPO/util.py"
commit "feat(util): add doubling"
printf 'def add(a, b):\n    return a + b\n\n' > "$REPO/calc.py"
commit "fix(calc): add instead of subtract"
printf 'def twice(x):\n    return 2 * x\n\n\ndef half(x):\n    return x / 2\n' > "$REPO/util.py"
commit "fix(util): provide halving"
printf 'notes\n' > "$REPO/README.md"
commit "docs: add notes"
printf -- '-- header\nselect 1;\n-- note\nselect 2;\n' > "$REPO/q.sql"
commit "feat(sql): add query"
printf 'select 1;\n-- note\nselect 3;\n' > "$REPO/q.sql"
commit "fix(sql): drop header and select 3"
printf 'one = 1\ntwo = 2\n' > "$REPO/café.py"
printf 'three = 3\nfour = 4\n' > "$REPO/my file.py"
commit "feat: add unusual paths"
printf 'one = 1\ntwo = 20\n' > "$REPO/café.py"
printf 'three = 30\nfour = 4\n' > "$REPO/my file.py"
commit "fix: correct unusual paths"
git_in rm -q calc.py
commit "fix(calc): remove calc"

field() { node -e 'const value = process.argv[1].split(/[.[\]]+/).filter(Boolean).reduce((node, key) => node[key], JSON.parse(require("fs").readFileSync(0, "utf8"))); console.log(JSON.stringify(value))' "$1"; }
expect() { actual="$(printf '%s' "$1" | field "$2")"; [ "$actual" = "$3" ] || fail "$4: expected $2 = $3, got $actual"; }
run() { node "$CENSUS" --repo "$REPO" "$@" || { echo "FAIL: census exited non-zero for: $*"; exit 1; }; }

CALC="$(sha_of 'feat(calc): add addition')"
CALC_FIX="$(sha_of 'fix(calc): add instead of subtract')"
CALC_REMOVAL="$(sha_of 'fix(calc): remove calc')"
UNUSUAL="$(sha_of 'feat: add unusual paths')"
UNUSUAL_FIX="$(sha_of 'fix: correct unusual paths')"

PY="$(run --ext .py)"
expect "$PY" candidates 6 "--ext .py counts commits adding .py lines, unusual paths included"
expect "$PY" fixes 5 "--ext .py counts every non-root fix, whatever files it touches"
expect "$PY" unattributableFixes 2 "--ext .py: the pure-addition fix and the .sql-only fix have nothing to blame"
expect "$PY" introducersOutsideRange 0 "--ext .py over the whole history"
expect "$PY" 'fixInducing.length' 3 "--ext .py: calc, the first calc fix and the unusual-path commit"
expect "$PY" 'fixInducing[0].sha' "\"$CALC\"" "--ext .py: first fix-inducing commit"
expect "$PY" 'fixInducing[0].fixedBy' "[\"$CALC_FIX\",\"$CALC_REMOVAL\"]" "--ext .py: calc is fixed twice, the removal included"
expect "$PY" 'fixInducing[1].sha' "\"$CALC_FIX\"" "--ext .py: a fix can itself be fix-inducing"
expect "$PY" 'fixInducing[2].sha' "\"$UNUSUAL\"" "--ext .py: non-ASCII and space paths are blamed"
expect "$PY" 'fixInducing[2].fixedBy' "[\"$UNUSUAL_FIX\"]" "--ext .py: one fix touching two unusual paths counts once"
expect "$PY" share 0.5 "--ext .py share"

SQL="$(run --ext .sql)"
expect "$SQL" candidates 2 "--ext .sql candidates"
expect "$SQL" 'fixInducing.length' 1 "--ext .sql: a removed '-- ' line does not derail the second hunk"
expect "$SQL" 'fixInducing[0].subject' '"feat(sql): add query"' "--ext .sql fix-inducing commit"

ALL="$(run)"
expect "$ALL" candidates 9 "no --ext counts every commit adding lines"

RANGED="$(run --ext .py --range "$CALC..HEAD")"
expect "$RANGED" candidates 5 "--range leaves the first commit out"
expect "$RANGED" introducersOutsideRange 1 "--range reports the introducer it cannot count"
expect "$RANGED" 'fixInducing.length' 2 "--range fix-inducing commits"

WINDOW="$(run --ext .py --range "$UNUSUAL^..$UNUSUAL")"
expect "$WINDOW" candidates 1 "a one-commit window has one candidate"
expect "$WINDOW" 'fixInducing[0].fixedBy' "[\"$UNUSUAL_FIX\"]" "a fix after the window is still observed"
expect "$WINDOW" share 1 "a window's share counts fixes that arrive after it"
EARLY="$(run --ext .py --range "$UNUSUAL^..$UNUSUAL" --fixes-through "$UNUSUAL")"
expect "$EARLY" 'fixInducing.length' 0 "--fixes-through stops observation before the later fix"
expect "$EARLY" fixesThrough "\"$UNUSUAL\"" "the output names the observation endpoint"

EMPTY="$(run --range HEAD..HEAD)"
expect "$EMPTY" commits 0 "an empty range has no commits"
expect "$EMPTY" share null "an empty range has no share"

CUSTOM="$(run --ext .py --fix-pattern '^feat\(util\)')"
expect "$CUSTOM" fixes 1 "--fix-pattern selects fixes by subject"

git_in config diff.noprefix true
git_in config diff.mnemonicPrefix true
git_in config color.ui always
git_in config color.diff always
git_in config diff.interHunkContext 5
git_in config diff.algorithm patience
git_in config diff.indentHeuristic false
git_in config diff.renames copies
git_in config diff.renameLimit 1
git_in config log.showRoot false
printf '%s\n' "$CALC_FIX" > "$REPO/.git/ignored-revs"
git_in config blame.ignoreRevsFile .git/ignored-revs
[ "$(run --ext .py)" = "$PY" ] || fail "repository git config changes the .py result"
[ "$(run --ext .sql)" = "$SQL" ] || fail "repository git config changes the .sql result"

REPO="$(mktemp -d)" || { echo "FAIL: setup: mktemp"; exit 2; }
git_in init -q
git_in config color.diff always
git_in config diff.interHunkContext 1
git_in config diff.strip.textconv "sed 1d"
printf '*.py diff=strip\n' > "$REPO/.git/info/attributes"
printf 'a = 1\nb = 2\nc = 3\n' > "$REPO/moved.py"
commit "feat: add moved"
printf 'a = 1\nb = 2\nc = 3\nd = 4\n' > "$REPO/moved.py"
commit "feat: extend moved"
printf 'x = 1\n' > "$REPO/tab	name.py"
commit "feat: add tab path"
printf 'm = 1\n' > "$REPO/:(literal)magic.py"
commit "feat: add magic path"
printf 'h1 = 1\nh3 = 3\n' > "$REPO/hunks.py"
commit "feat: add hunks"
printf 'h1 = 1\nh2 = 2\nh3 = 3\n' > "$REPO/hunks.py"
commit "feat: insert middle hunk line"
git_in mv moved.py renamed.py
printf 'a = 1\nb = 2\nc = 3\nd = 40\n' > "$REPO/renamed.py"
printf 'x = 10\n' > "$REPO/tab	name.py"
printf 'm = 10\n' > "$REPO/:(literal)magic.py"
printf 'h1 = 10\nh2 = 2\nh3 = 30\n' > "$REPO/hunks.py"
commit "fix: correct edge cases"
EDGE="$(run --ext .py)"
expect "$EDGE" candidates 7 "a tab in a path keeps its commit a candidate"
expect "$EDGE" unattributableFixes 0 "every edge-case fix is attributed"
expect "$EDGE" 'fixInducing.length' 4 "rename, tab, pathspec magic, hunk context and textconv leave attribution exact"
expect "$EDGE" 'fixInducing[0].subject' '"feat: extend moved"' "a renamed file blames only its changed line"
expect "$EDGE" 'fixInducing[1].subject' '"feat: add tab path"' "a path with a tab is blamed"
expect "$EDGE" 'fixInducing[2].subject' '"feat: add magic path"' "a path that looks like pathspec magic is literal"
expect "$EDGE" 'fixInducing[3].subject' '"feat: add hunks"' "unchanged lines between hunks are not blamed"
EDGE_REPO="$REPO"

REPO="$(mktemp -d)" || { echo "FAIL: setup: mktemp"; exit 2; }
git_in init -q
mkdir "$REPO/src"
printf 'a = 1\n' > "$REPO/src/calc.py"
commit "feat: add nested calc"
git_in -c protocol.file.allow=always submodule -q add "$EDGE_REPO" dep
git_in -C dep checkout -q HEAD~1
commit "feat: add dependency"
printf 'a = 2\n' > "$REPO/src/calc.py"
git_in -C dep checkout -q -
commit "fix: correct nested calc and bump dependency"
git_in -C dep checkout -q HEAD~1
commit "chore: pin dependency"
NESTED="$(run)"
expect "$NESTED" candidates 3 "a commit that only moves a submodule adds no text lines"
expect "$NESTED" 'fixInducing.length' 1 "a fix that bumps a submodule still attributes its file lines"
expect "$NESTED" 'fixInducing[0].subject' '"feat: add nested calc"' "a submodule is not blamed"
FROM_SUBDIRECTORY="$(cd "$REPO/src" && node "$CENSUS" --ext .py)"
expect "$FROM_SUBDIRECTORY" 'fixInducing.length' 1 "a run from a subdirectory blames the same lines"

WORK_TREE="$(mktemp -d)" || { echo "FAIL: setup: mktemp"; exit 2; }
REPO="$(mktemp -d)" || { echo "FAIL: setup: mktemp"; exit 2; }
git --git-dir="$REPO" --work-tree="$WORK_TREE" init -q >/dev/null
printf 'w = 1\n' > "$WORK_TREE/w.py"
commit "feat: add w"
printf 'w = 10\n' > "$WORK_TREE/w.py"
commit "fix: correct w"
expect "$(run --ext .py)" 'fixInducing.length' 1 "a repository whose core.worktree is elsewhere is blamed"

REPO="$(mktemp -d)" || { echo "FAIL: setup: mktemp"; exit 2; }
git_in init -q --object-format=sha256
printf 's = 1\n' > "$REPO/s.py"
commit "feat: add s"
printf 's = 10\n' > "$REPO/s.py"
commit "fix: correct s"
expect "$(run --ext .py)" 'fixInducing.length' 1 "a SHA-256 repository is blamed"

REPO="$(mktemp -d)" || { echo "FAIL: setup: mktemp"; exit 2; }
git_in init -q
printf 'r = 1\n' > "$REPO/r.py"
commit "fix: start from a root fix"
git_in checkout -q -b side
printf 's = 1\n' > "$REPO/s.py"
commit "feat: add side"
git_in checkout -q -
printf 'n = 1\n' > "$REPO/n.py"
commit "fix: add a new file"
git_in merge -q --no-edit side
printf 'r = 2\n' > "$REPO/r.py"
commit "fix: correct r"
git_in mv s.py renamed-side.py
commit "refactor: rename side"
HISTORY="$(run --ext .py)"
expect "$HISTORY" commits 5 "a merge commit is not a candidate commit"
expect "$HISTORY" candidates 4 "a commit that only renames a file adds no lines"
expect "$HISTORY" fixes 2 "a root fix is skipped, a fix adding a new file is counted"
expect "$HISTORY" unattributableFixes 1 "a fix adding only a new file has nothing to blame"
expect "$HISTORY" 'fixInducing[0].subject' '"fix: start from a root fix"' "a root commit can be fix-inducing"

git_in config uploadpack.allowFilter true
PARTIAL="$(mktemp -d)" || { echo "FAIL: setup: mktemp"; exit 2; }
git clone -q --filter=blob:none --no-checkout "file://$REPO" "$PARTIAL/clone" 2>/dev/null || { echo "FAIL: setup: partial clone"; exit 2; }
OBJECTS_BEFORE="$(git -C "$PARTIAL/clone" count-objects -v | grep -E '^(count|in-pack):')"
node "$CENSUS" --repo "$PARTIAL/clone" --ext .py >/dev/null 2>&1 && fail "a partial clone missing blobs must exit non-zero instead of fetching them"
[ "$(git -C "$PARTIAL/clone" count-objects -v | grep -E '^(count|in-pack):')" = "$OBJECTS_BEFORE" ] || fail "the census fetched objects into a partial clone"

STDERR="$(node "$CENSUS" --repo "$REPO/missing" 2>&1 >/dev/null)" && fail "a path that is not a repository must exit non-zero"
case "$STDERR" in rework-census:*) ;; *) fail "a non-repository error lacks the rework-census prefix: $STDERR" ;; esac
STDERR="$(node "$CENSUS" --ext --range x 2>&1 >/dev/null)" && fail "an option value starting with -- must exit non-zero"
case "$STDERR" in *"--ext needs a value"*) ;; *) fail "missing-value error not reported: $STDERR" ;; esac
STDERR="$(node "$CENSUS" --bogus 1 2>&1 >/dev/null)" && fail "an unknown option must exit non-zero"
case "$STDERR" in *"unknown option --bogus"*) ;; *) fail "unknown-option error not reported: $STDERR" ;; esac

[ "$failures" = 0 ] && echo "PASS: rework-census" || exit 1
