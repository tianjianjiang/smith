#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
JOBS="${RUN_ALL_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "check-test-deps: $HERE is not inside a git checkout"
  exit 1
}
RELATIVE_REAL_PATH='const { realpathSync } = require("fs"); const { basename, dirname, join, relative } = require("path"); const { argv } = process; console.log(relative(realpathSync(argv[1]), join(realpathSync(dirname(argv[2])), basename(argv[2]))));'
export RELATIVE_REAL_PATH
WORK="$(mktemp -d)"
trap 'chmod -R u+rwx "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
for test_file in "$@"; do
  shift
  set -- "$@" "$(cd "$(dirname "$test_file")" && pwd)/$(basename "$test_file")"
done
if [ "$#" = 0 ]; then
  for test_file in "$HERE"/*.test.sh; do
    [ -f "$test_file" ] && set -- "$@" "$test_file"
  done
fi
if [ "$#" = 0 ]; then
  echo "check-test-deps: NO TESTS FOUND in $HERE"
  exit 1
fi
index=0
for test_file in "$@"; do
  index=$((index + 1))
  printf '%s\0%s\0' "$index" "$test_file"
done | xargs -0 -n 2 -P "$JOBS" sh -c '
  here="$1" root="$2" work="$3" index="$4" test_file="$5"
  prefix="$work/$index"
  tree="$prefix.tree"
  result="$prefix.result"
  if ! node "$here/test-deps.mjs" files "$root" "$here" "$test_file" > "$prefix.files" 2> "$prefix.files.err"; then
    echo "NO DEPENDENCY LIST" > "$result"
    exit 0
  fi
  while IFS= read -r file; do
    mkdir -p "$tree/$(dirname "$file")" && cp -Pp "$root/$file" "$tree/$file" || {
      echo "could not copy $file" >> "$prefix.files.err"
      echo "TREE NOT BUILT" > "$result"
      exit 0
    }
  done < "$prefix.files"
  if ! { git -C "$tree" init -q && git -C "$tree" add -A &&
    git -C "$tree" -c user.name=check -c user.email=check@example.invalid \
      -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm tree; } >> "$prefix.files.err" 2>&1; then
    echo "TREE NOT BUILT" > "$result"
    exit 0
  fi
  test_in_tree="$tree/$(node -e "$RELATIVE_REAL_PATH" "$root" "$test_file")"
  (cd "$tree" && bash "$test_in_tree" < /dev/null > "$prefix.tree.log" 2>&1)
  tree_status=$?
  (cd "$root" && bash "$test_file" < /dev/null > "$prefix.repo.log" 2>&1)
  repo_status=$?
  if [ "$repo_status" != 0 ]; then
    echo "FAILS IN REPO" > "$result"
  elif [ "$tree_status" != 0 ]; then
    echo "MISSING DEPENDENCY" > "$result"
  elif grep "SKIP" "$prefix.tree.log" | grep -vxF -f "$prefix.repo.log" > "$prefix.skips"; then
    echo "SKIPS IN TREE" > "$result"
  elif grep -q "SKIP" "$prefix.repo.log"; then
    echo "SKIPPED" > "$result"
  else
    echo PASS > "$result"
  fi
' check-one "$HERE" "$ROOT" "$WORK"
status=0
skipped=
index=0
for test_file in "$@"; do
  index=$((index + 1))
  shown="$(node -e "$RELATIVE_REAL_PATH" "$ROOT" "$test_file" 2>/dev/null || echo "$test_file")"
  result="$(cat "$WORK/$index.result" 2>/dev/null || echo "NOT RUN")"
  case "$result" in PASS | SKIPPED) ;; *) status=1 ;; esac
  case "$result" in
    PASS) echo "PASS: $shown" ;;
    SKIPPED)
      skipped=1
      echo "SKIPPED: $shown skips in the repo too, so its dependencies were not checked:"
      grep "SKIP" "$WORK/$index.repo.log" | sed 's/^/    /'
      ;;
    "MISSING DEPENDENCY")
      echo "MISSING DEPENDENCY: $shown passes in the repo but fails in a tree of its dependencies:"
      tail -n 20 "$WORK/$index.tree.log" | sed 's/^/    /'
      ;;
    "SKIPS IN TREE")
      echo "MISSING DEPENDENCY: $shown skips in a tree of its dependencies but not in the repo:"
      sed 's/^/    /' "$WORK/$index.skips"
      ;;
    "FAILS IN REPO")
      echo "FAILS IN REPO: $shown fails in the repo too, so its dependencies cannot be judged:"
      tail -n 20 "$WORK/$index.repo.log" | sed 's/^/    /'
      ;;
    *)
      echo "$result: $shown"
      cat "$WORK/$index.files" "$WORK/$index.files.err" 2>/dev/null | sed 's/^/    /'
      ;;
  esac
done
if [ "$status" = 0 ] && [ -n "$skipped" ]; then
  echo "EVERY TEST THAT RAN PASSES WITH ITS DEPENDENCIES ALONE; SKIPPED TESTS WERE NOT CHECKED"
elif [ "$status" = 0 ]; then
  echo "EVERY TEST PASSES WITH ITS DEPENDENCIES ALONE"
else
  echo "SOME TESTS NEED UNDECLARED DEPENDENCIES OR FAIL"
fi
exit "$status"
