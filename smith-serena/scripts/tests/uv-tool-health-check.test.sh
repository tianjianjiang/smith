#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../uv-tool-health-check.sh"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: uv-tool-health-check - $1"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

fake_uv() {
    cat > "$TMP/bin/uv" <<EOF
#!/bin/bash
$1
EOF
    chmod +x "$TMP/bin/uv"
}

run() { PATH="$TMP/bin:$PATH" bash "$HOOK"; }

fake_uv '
if [ "$1 $2" = "tool list" ]; then
  echo "serena-agent v1.7.0"
  exit 0
fi
echo "unexpected uv args: $*" >&2
exit 1
'
out=$(run) || fail "hook crashed on healthy venv"
[ -z "$out" ] || fail "expected silent on healthy venv, got: $out"
pass "silent when serena-agent is healthy"

fake_uv '
if [ "$1 $2" = "tool list" ]; then
  echo "Broken symlink at \`/home/x/.local/share/uv/tools/serena-agent/bin/python3\`, was the underlying Python interpreter removed?" >&2
  exit 0
fi
if [ "$1 $2 $3" = "tool install serena-agent" ] && [ "$4" = "--reinstall" ]; then
  exit 0
fi
echo "unexpected uv args: $*" >&2
exit 1
'
out=$(run) || fail "hook crashed on broken venv (reinstall succeeds)"
echo "$out" | grep -q "reinstalled broken tool venv" || fail "expected heal message, got: $out"
echo "$out" | grep -q "serena-agent" || fail "expected serena-agent named, got: $out"
echo "$out" | grep -q '"hookEventName": "SessionStart"' || fail "expected SessionStart output, got: $out"
pass "self-heals and reports when serena-agent is broken"

fake_uv '
if [ "$1 $2" = "tool list" ]; then
  echo "Broken symlink at \`/home/x/.local/share/uv/tools/serena-agent/bin/python3\`, was the underlying Python interpreter removed?" >&2
  exit 0
fi
if [ "$1 $2 $3" = "tool install serena-agent" ] && [ "$4" = "--reinstall" ]; then
  exit 1
fi
echo "unexpected uv args: $*" >&2
exit 1
'
out=$(run) || fail "hook crashed on broken venv (reinstall fails)"
echo "$out" | grep -q "FAILED to reinstall" || fail "expected failure message, got: $out"
echo "$out" | grep -q "serena-agent" || fail "expected serena-agent named, got: $out"
pass "reports when reinstall itself fails, never silent"

fake_uv '
if [ "$1 $2" = "tool list" ]; then
  echo "Broken symlink at \`/home/x/.local/share/uv/tools/ruff/bin/python3\`, was the underlying Python interpreter removed?" >&2
  exit 0
fi
echo "unexpected uv args: $*" >&2
exit 1
'
out=$(run) || fail "hook crashed on unmonitored tool broken"
[ -z "$out" ] || fail "expected silent when only an unmonitored tool is broken, got: $out"
pass "silent when a non-monitored tool (ruff) is broken"

out=$(PATH="/usr/bin:/bin" bash "$HOOK" 2>/dev/null) || fail "hook crashed with no uv on PATH"
[ -z "$out" ] || fail "expected silent with no uv installed, got: $out"
pass "silent when uv is not installed"

echo "PASS: uv-tool-health-check"
