#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../personal-data-guard.mjs"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $1"; exit 1; }

node "$HERE/protected-text.test.mjs" || fail "protected-text unit tests"

FIXTURE_EMAIL="someone@example.invalid"
FIXTURE_PHONE="+81-90-0000-0000"
printf '[user]\n\temail = %s\n\tname = Fixture Person Name\n' "$FIXTURE_EMAIL" \
  > "$WORK/gitconfig"
: > "$WORK/gitconfig-empty"
printf '{"protectedIdentifiers":["%s"]}\n' "$FIXTURE_PHONE" > "$WORK/config.json"
printf 'not json' > "$WORK/config-malformed.json"
printf '{"protectedIdentifiers":["%s",819000000000]}\n' "$FIXTURE_PHONE" \
  > "$WORK/config-with-a-number.json"

GUARD_GITCONFIG="$WORK/gitconfig"
GUARD_CONFIG="$WORK/config.json"
run() {
  (
    cd "$WORK" || exit 99
    printf '%s' "$1" | HOME="/Users/fixture.person" \
      GIT_CONFIG_GLOBAL="$GUARD_GITCONFIG" GIT_CONFIG_NOSYSTEM=1 \
      SMITH_PERSONAL_DATA_GUARD_CONFIG="$GUARD_CONFIG" \
      node "$HOOK" 2>"$WORK/stderr" >"$WORK/stdout"
  )
}
blocks() {
  run "$2"
  code=$?
  [ "$code" = 2 ] || fail "$1: expected exit 2, got $code"
  grep -qF "Blocked:" "$WORK/stderr" || fail "$1: expected a refusal on stderr"
  grep -qiF -e "$FIXTURE_EMAIL" -e "$FIXTURE_PHONE" "$WORK/stderr" \
    && fail "$1: the refusal printed a protected string"
  return 0
}
passes() {
  run "$2"
  code=$?
  [ "$code" = 0 ] || fail "$1: expected exit 0, got $code: $(cat "$WORK/stderr")"
  [ -s "$WORK/stdout" ] && fail "$1: expected silent, got: $(cat "$WORK/stdout")"
  return 0
}
advises() {
  run "$2"
  code=$?
  [ "$code" = 0 ] || fail "$1: expected exit 0, got $code: $(cat "$WORK/stderr")"
  grep -qF "$3" "$WORK/stdout" \
    || fail "$1: expected the advisory to say '$3', got: $(cat "$WORK/stdout")"
}

LS='{"tool_name":"Bash","tool_input":{"command":"ls"}}'

blocks "address from git in a request" \
  '{"tool_name":"Bash","tool_input":{"command":"curl https://example.invalid/?email=someone%40example.invalid"}}'
blocks "string from the config file" \
  '{"tool_name":"Write","tool_input":{"content":"call +81-90-0000-0000"}}'
blocks "name from git, spaces and all" \
  '{"tool_name":"Edit","tool_input":{"new_string":"author = Fixture Person Name"}}'
passes "call without personal data" "$LS"
passes "stdin that does not parse" 'not json at all'
passes "payload without a tool_input" '{"tool_name":"Bash"}'

GUARD_CONFIG="$WORK/config-malformed.json"
advises "config file that cannot be used" "$LS" "protectedIdentifiers"
blocks "git's strings still block beside an unusable config file" \
  '{"tool_name":"WebSearch","tool_input":{"query":"someone@example.invalid"}}'

GUARD_CONFIG="$WORK/config-with-a-number.json"
advises "config entry that is not a string" "$LS" "protectedIdentifiers"
blocks "the config file's strings still block beside one that is not" \
  '{"tool_name":"Write","tool_input":{"content":"call +81-90-0000-0000"}}'

GUARD_CONFIG="$WORK/missing.json"
passes "a missing config file is the ordinary case" "$LS"
GUARD_GITCONFIG="$WORK/gitconfig-empty"
advises "no protected string from either source" "$LS" "nothing is protected"

echo "PASS: personal-data-guard"
