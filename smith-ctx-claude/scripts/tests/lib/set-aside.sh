set_aside() (
  status=0
  report() {
    printf 'set_aside: could not move %s into a fresh mktemp -d folder: %s\n' "$given" "$1" >&2
    status=1
  }
  for given in "$@"; do
    path=$given
    named_as_folder=false
    while [ "$path" != "${path%/}" ] && [ -n "${path%/}" ]; do
      path=${path%/}
      named_as_folder=true
    done
    if [ ! -e "$path" ] && { [ "$named_as_folder" = true ] || [ ! -L "$path" ]; }; then
      ancestor=$(dirname -- "$path")
      while [ ! -e "$ancestor" ] && [ "$ancestor" != "$(dirname -- "$ancestor")" ]; do
        ancestor=$(dirname -- "$ancestor")
      done
      if [ ! -d "$ancestor" ]; then
        report "$ancestor is not a folder"
      elif [ ! -x "$ancestor" ]; then
        report "$ancestor cannot be searched, so whether it exists is unknown"
      fi
      continue
    fi
    if [ "$named_as_folder" = true ] && [ ! -d "$path" ]; then
      report "it was named with a trailing slash but is not a folder"
      continue
    fi
    if ! folder=$(mktemp -d); then
      report "mktemp -d failed"
    elif [ ! -d "$folder" ]; then
      report "mktemp -d named no folder: $folder"
    elif ! mv -- "$path" "$folder"; then
      report "the move failed"
    fi
  done
  return "$status"
)
