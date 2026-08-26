#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../rtk-find-symlink-guard.mjs"

SHIM="$(mktemp -d)"
NO_RTK="$(mktemp -d)"
trap 'rm -rf "$SHIM" "$NO_RTK"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

cat > "$SHIM/rtk" <<'EOF'
#!/bin/sh
case "$*" in
  *"--help"*)
    if [ "${RTK_IS_REAL_RTK:-1}" = "1" ]; then
      printf 'Usage: rtk [OPTIONS] <COMMAND>\n\nCommands:\n  gain  Show token savings summary\n'
    else
      printf 'Usage: rtk [OPTIONS] <COMMAND>\n\nCommands:\n  init  Initialize a project\n'
    fi
    ;;
  *) : ;;
esac
EOF
chmod +x "$SHIM/rtk"
export PATH="$SHIM:$PATH"

NODE="$(command -v node)"

run() { printf '%s' "$2" | node "$HOOK"; }
advises() {
  out=$(run "$1" "$2") || fail "$1: hook crashed"
  echo "$out" | grep -q 'rtk-find-symlink-guard' || fail "$1: expected advisory, got: $out"
}
silent() {
  out=$(run "$1" "$2") || fail "$1: hook crashed"
  [ -z "$out" ] || fail "$1: expected silent, got: $out"
}
advisesText() {
  out=$(run "$1" "$2") || fail "$1: hook crashed"
  echo "$out" | grep -qF "$3" || fail "$1: expected '$3' in output, got: $out"
}

advises "bare find -L advises" \
  '{"tool_name":"Bash","tool_input":{"command":"find -L . -name \"*.ts\""}}'
advises "rtk find -L advises" \
  '{"tool_name":"Bash","tool_input":{"command":"rtk find -L . -name \"*.ts\""}}'
advises "chained command with bare find -L advises" \
  '{"tool_name":"Bash","tool_input":{"command":"cd /repo && find -L . -type f"}}'
advises "sudo-wrapped find -L advises" \
  '{"tool_name":"Bash","tool_input":{"command":"sudo find -L . -type f"}}'
advises "env-prefixed rtk find -L advises" \
  '{"tool_name":"Bash","tool_input":{"command":"FOO=bar rtk find -L . -name \"*.ts\""}}'

advisesText "bare find -L message names find" \
  '{"tool_name":"Bash","tool_input":{"command":"find -L . -name \"*.ts\""}}' \
  "'find ... -L'"
advisesText "rtk find -L message names rtk find" \
  '{"tool_name":"Bash","tool_input":{"command":"rtk find -L . -name \"*.ts\""}}' \
  "'rtk find ... -L'"
advisesText "mixed find and rtk find in one command prefers find's label" \
  '{"tool_name":"Bash","tool_input":{"command":"rtk find -L . && find -L . -type f"}}' \
  "'find ... -L'"
advises "trailing -L after other flags advises" \
  '{"tool_name":"Bash","tool_input":{"command":"find . -name \"*.ts\" -L"}}'
silent "-L belonging to an -exec sub-command on rtk find is silent" \
  '{"tool_name":"Bash","tool_input":{"command":"rtk find . -exec someprog -L {} +"}}'
advises "a nested rtk find -L inside -exec still advises" \
  '{"tool_name":"Bash","tool_input":{"command":"find . -exec rtk find -L {} +"}}'
advisesText "an outer bare find with a nested risky rtk find blames the nested one" \
  '{"tool_name":"Bash","tool_input":{"command":"find . -exec rtk find -L {} +"}}' \
  "'rtk find ... -L'"
advisesText "an outer rtk find with a nested risky bare find blames the nested one" \
  '{"tool_name":"Bash","tool_input":{"command":"rtk find . -exec find -L {} +"}}' \
  "'find ... -L'"
advises "a sudo-wrapped nested rtk find -L inside -exec still advises" \
  '{"tool_name":"Bash","tool_input":{"command":"find . -exec sudo rtk find -L {} +"}}'
advises "a risky second -exec block after a benign first one still advises" \
  '{"tool_name":"Bash","tool_input":{"command":"find . -type f -exec true {} + -exec rtk find {} -L +"}}'
advises "a nested bare find -L inside -exec still advises" \
  '{"tool_name":"Bash","tool_input":{"command":"find . -exec find -L {} +"}}'
silent "-L as the value of -name is silent" \
  '{"tool_name":"Bash","tool_input":{"command":"find . -name \"-L\""}}'
silent "-L as the value of -newer is silent" \
  '{"tool_name":"Bash","tool_input":{"command":"find . -newer -L"}}'
silent "-L as the value of -neweraB is silent" \
  '{"tool_name":"Bash","tool_input":{"command":"find . -neweraB -L"}}'
silent "-L as -fprintf's second (format) argument is silent" \
  '{"tool_name":"Bash","tool_input":{"command":"find . -fprintf out.log -L"}}'
silent "-L as the value of -fls is silent" \
  '{"tool_name":"Bash","tool_input":{"command":"find . -fls -L"}}'
silent "-L as the value of -newerBa is silent" \
  '{"tool_name":"Bash","tool_input":{"command":"find . -newerBa -L"}}'
silent "-L as the value of -wholename is silent" \
  '{"tool_name":"Bash","tool_input":{"command":"find . -wholename -L"}}'
advises "a plain outer -L after a benign -exec block still advises" \
  '{"tool_name":"Bash","tool_input":{"command":"find . -exec someprog {} + -L"}}'

silent "rtk proxy find -L is the documented workaround" \
  '{"tool_name":"Bash","tool_input":{"command":"rtk proxy find -L . -name \"*.ts\""}}'
silent "find without -L is silent" \
  '{"tool_name":"Bash","tool_input":{"command":"find . -name \"*.ts\""}}'
silent "rtk find without -L is silent" \
  '{"tool_name":"Bash","tool_input":{"command":"rtk find . -name \"*.ts\""}}'
silent "-L belonging to an -exec sub-command is silent" \
  '{"tool_name":"Bash","tool_input":{"command":"find . -exec someprog -L {} +"}}'
silent "echoed find -L is not an invocation" \
  '{"tool_name":"Bash","tool_input":{"command":"echo find -L . -name \"*.ts\""}}'
silent "unrelated command is silent" \
  '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
silent "non-Bash tool is silent" \
  '{"tool_name":"Read","tool_input":{"file_path":"/x"}}'
silent "malformed stdin is silent" 'not json'
silent "json null is silent" 'null'

(
  RTK_IS_REAL_RTK=0
  export RTK_IS_REAL_RTK
  silent "a name-collision rtk (no gain subcommand) stays silent" \
    '{"tool_name":"Bash","tool_input":{"command":"find -L . -type f"}}'
)

out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"find -L . -type f"}}' \
  | PATH="$NO_RTK" "$NODE" "$HOOK") || fail "rtk missing: hook crashed"
[ -z "$out" ] || fail "rtk missing (ENOENT) should stay silent, got: $out"

deep_wrap_payload=$("$NODE" -e "
  let cmd = 'find -L . -type f';
  for (let i = 0; i < 9; i++) cmd = 'eval ' + JSON.stringify(cmd);
  process.stdout.write(JSON.stringify({tool_name: 'Bash', tool_input: {command: cmd}}));
")
silent "a find -L nested past the tokenizer's unwrap depth limit stays silent" "$deep_wrap_payload"

sibling_depth_payload=$("$NODE" -e "
  let deep = 'true';
  for (let i = 0; i < 9; i++) deep = 'eval ' + JSON.stringify(deep);
  const cmd = 'find -L . -type f; ' + deep;
  process.stdout.write(JSON.stringify({tool_name: 'Bash', tool_input: {command: cmd}}));
")
advises "an over-nested sibling segment does not blind detection of a plain find -L elsewhere in the same command" "$sibling_depth_payload"

echo "PASS: rtk-find-symlink-guard"
