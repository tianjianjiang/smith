#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
LINE_BREAK='
'
refuse_line_break() {
  case "$1" in
    *"$LINE_BREAK"*)
      echo "list-folders: the path of a tests folder holds a line break, so it cannot be listed: $1" >&2
      exit 1
      ;;
  esac
}
below_a_git_folder() {
  folder="$HERE"
  while :; do
    if [ -e "$folder/.git" ]; then
      return 0
    fi
    if [ "$folder" = / ]; then
      return 1
    fi
    folder="$(dirname "$folder")"
  done
}
ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" || {
  refusal="$(LC_ALL=C git -C "$HERE" rev-parse --show-toplevel 2>&1)"
  case "$refusal" in
    *'not a git repository'*)
      if ! below_a_git_folder; then
        refuse_line_break "$HERE"
        printf '%s\n' "$HERE"
        exit 0
      fi
      ;;
  esac
  echo "list-folders: git could not name the checkout that holds $HERE: $refusal" >&2
  exit 1
}
for skill in "$ROOT"/*/; do
  for folder in "${skill%/}" "${skill}scripts" "${skill}scripts/tests"; do
    if [ -d "$folder" ] && { [ ! -r "$folder" ] || [ ! -x "$folder" ]; }; then
      echo "list-folders: the folder $folder cannot be read, so the tests under it cannot be listed" >&2
      exit 1
    fi
  done
done
for folder in "$ROOT"/*/scripts/tests; do
  for test_file in "$folder"/*.test.sh; do
    if [ -e "$test_file" ] || [ -L "$test_file" ]; then
      refuse_line_break "$folder"
      printf '%s\n' "$folder"
      break
    fi
  done
done
