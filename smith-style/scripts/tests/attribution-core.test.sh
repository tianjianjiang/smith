#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/.."

fail() { echo "FAIL: $1"; exit 1; }

TMP=$(mktemp -d) || fail "mktemp"
trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/smith"
mkdir -p "$ROOT/smith-style/scripts/lib" "$ROOT/agents"
cp "$SCRIPTS/attribution.sh" "$ROOT/smith-style/scripts/attribution.sh"
cp "$SCRIPTS/lib/attribution.mjs" "$ROOT/smith-style/scripts/lib/attribution.mjs"
SOURCES="$ROOT/smith-style/scripts/attribution-model-sources.txt"
CMD="$ROOT/smith-style/scripts/attribution.sh"

printf '#!/bin/sh\nexit 1\n' > "$ROOT/agents/silent.sh"
printf '#!/bin/sh\necho "Other:model-$1"\n' > "$ROOT/agents/other.sh"
printf '#!/bin/sh\necho "not a value"\n' > "$ROOT/agents/broken.sh"
chmod +x "$ROOT/agents/"*.sh

printf 'agents/silent.sh\n' > "$SOURCES"
out=$("$CMD" 2>/dev/null); rc=$?
[ "$rc" = 1 ] || fail "no source knows the model: expected exit 1, got $rc"
[ -z "$out" ] || fail "no source knows the model: expected no output, got: $out"

printf 'agents/silent.sh\nagents/broken.sh\n\nagents/other.sh' > "$SOURCES"
out=$("$CMD" s7)
[ "$out" = "Assisted-by: Other:model-s7" ] || fail "first source with a well-formed value wins, arguments pass through: got: $out"
out=$("$CMD" value s7)
[ "$out" = "Other:model-s7" ] || fail "value mode: got: $out"
out=$("$CMD" line s7)
[ "$out" = "Assisted-by: Other:model-s7" ] || fail "line mode: got: $out"

command -v node >/dev/null 2>&1 || { echo "SKIP: attribution core check (node not installed)"; exit 0; }

check() {
  node --input-type=module -e '
    const { expectedAttribution, attributionProblems } = await import(process.argv[1]);
    const attribution = expectedAttribution(...process.argv[3].split(" ").filter(Boolean));
    console.log(JSON.stringify(attributionProblems(process.argv[2], attribution)));
  ' "$ROOT/smith-style/scripts/lib/attribution.mjs" "$1" "${2:-s7}"
}

nl='
'
out=$(check "Body${nl}${nl}Assisted-by: Other:model-s7")
[ "$out" = "[]" ] || fail "the script's line passes: got: $out"
out=$(check "Body${nl}${nl}Assisted-by: Other:model-s7 [semgrep]")
[ "$out" = "[]" ] || fail "a tool suffix passes: got: $out"
out=$(check "Body only")
[ "$out" = '["no Assisted-by line"]' ] || fail "a missing line is not used: got: $out"
out=$(check "Body${nl}${nl}Assisted-by: Other:model-s8")
case "$out" in *"invalid line 'Assisted-by: Other:model-s8'"*) ;; *) fail "a different line is not used: got: $out" ;; esac
out=$(check "Body${nl}${nl}Assisted-by: Other:model-s7${nl}Assisted-by: Other:model-s9")
case "$out" in *"invalid line 'Assisted-by: Other:model-s9'"*) ;; *) fail "an extra line is not used: got: $out" ;; esac
out=$(check "Body${nl}${nl}Assisted-by: Other:model-s7${nl}assisted‐by: Other:x")
case "$out" in *"invalid line"*) ;; *) fail "a look-alike line is not used: got: $out" ;; esac
out=$(check "Body${nl}\`\`\`${nl}Assisted-by: Other:quoted${nl}\`\`\`${nl}Assisted-by: Other:model-s7")
[ "$out" = "[]" ] || fail "a line inside a closed fence is quoted text: got: $out"
out=$(check "Body${nl}\`\`\`${nl}Assisted-by: Other:wrong${nl}Assisted-by: Other:model-s7")
case "$out" in *"invalid line 'Assisted-by: Other:wrong'"*) ;; *) fail "an unclosed fence hides nothing: got: $out" ;; esac
out=$(check "Body${nl}Assisted​-by: Other:wrong${nl}Assisted-by: Other:model-s7")
case "$out" in *"invalid line"*) ;; *) fail "a zero-width character does not hide a line: got: $out" ;; esac
out=$(check "Body on behalf of someone${nl}${nl}Assisted-by: Other:model-s7")
[ "$out" = "[\"the forbidden phrase 'on behalf of'\"]" ] || fail "on behalf of is forbidden: got: $out"
printf 'agents/silent.sh\n' > "$SOURCES"
out=$(check "Body${nl}${nl}Assisted-by: Other:model-s7")
[ "$out" = '["the session model is unknown"]' ] || fail "an unknown model blocks: got: $out"

echo "PASS: attribution-core"
