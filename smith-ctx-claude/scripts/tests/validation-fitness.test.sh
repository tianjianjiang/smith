#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
VERIFICATION=smith-verification
VALIDATION=smith-validation
ANALYSIS=smith-analysis
LOCK_TOOL="$REPO/smith-ctx-claude/scripts/anchors-lock.sh"
EVALS="$REPO/smith-ctx-claude/evals/skill-trigger"
TAB="$(printf '\t')"
SCHEMA_PROMPT='Validate that config/pipelines.yaml matches the JSON schema in schemas/pipeline.json and list every violation.'
export SCHEMA_PROMPT
status=0

fail() { echo "FAIL: validation-fitness: $1"; status=1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

eval_overlap() {
  node -e '
    const fs = require("fs");
    const path = require("path");
    const sets = process.argv.slice(1).map((file) => ({
      name: path.basename(file),
      data: JSON.parse(fs.readFileSync(file, "utf8")),
    }));
    const list = (set, key) => (Array.isArray(set.data[key]) ? set.data[key] : []);
    const schema = process.env.SCHEMA_PROMPT;
    for (const set of sets) {
      for (const key of ["should_trigger", "should_not_trigger"]) {
        if (list(set, key).length === 0) console.log(`${set.name} has no ${key} prompts`);
      }
      const triggers = new Set(list(set, "should_trigger"));
      for (const prompt of list(set, "should_not_trigger")) {
        if (triggers.has(prompt)) console.log(`prompt in both should_trigger and should_not_trigger of ${set.name}: ${prompt}`);
      }
      if (!list(set, "should_not_trigger").includes(schema)) console.log(`schema prompt missing from ${set.name} should_not_trigger`);
      if (triggers.has(schema)) console.log(`schema prompt in ${set.name} should_trigger`);
    }
    for (const own of sets) {
      for (const other of sets) {
        if (own === other) continue;
        const triggers = new Set(list(other, "should_trigger"));
        if (own.name < other.name) {
          for (const prompt of list(own, "should_trigger")) {
            if (triggers.has(prompt)) console.log(`should_trigger prompt in both ${own.name} and ${other.name}: ${prompt}`);
          }
        }
        if (!list(own, "should_not_trigger").some((prompt) => triggers.has(prompt))) {
          console.log(`${own.name} should_not_trigger holds no should_trigger prompt of ${other.name}`);
        }
      }
    }
  ' "$@"
}

plant_eval() {
  node -e '
    const fs = require("fs");
    const [mode, file] = process.argv.slice(1);
    const data = JSON.parse(fs.readFileSync(file, "utf8"));
    const schema = process.env.SCHEMA_PROMPT;
    if (mode === "self") data.should_not_trigger = [...(data.should_not_trigger || []), ...(data.should_trigger || []).slice(0, 1)];
    if (mode === "drop-schema") data.should_not_trigger = (data.should_not_trigger || []).filter((prompt) => prompt !== schema);
    if (mode === "trigger-schema") data.should_trigger = [...(data.should_trigger || []), schema];
    fs.writeFileSync(file, JSON.stringify(data));
  ' "$1" "$2"
}

reset_plant() {
  for skill in $VERIFICATION $VALIDATION $ANALYSIS; do
    cp "$EVALS/$skill.json" "$WORK/plant/$skill.json" 2> /dev/null
  done
}

expect_plant() {
  reset_plant
  if plant_eval "$1" "$WORK/plant/$2.json" 2> /dev/null; then
    three_evals "$WORK/plant" 2> /dev/null | grep -qF "$3" ||
      fail "control: $4 was not reported"
  else
    fail "control: the planted eval for $4 could not be written"
  fi
}

three_evals() {
  eval_overlap "$1/$VERIFICATION.json" "$1/$VALIDATION.json" "$1/$ANALYSIS.json"
}

RELATED_ANCHOR='<a name="related-v1"></a>'
related_pointer() {
  awk -v want="- \`@$VALIDATION/SKILL.md\`" -v anchor="$RELATED_ANCHOR" '
    /^## / { inside = held; held = 0; next }
    { held = ($0 == anchor) }
    inside && index($0, want) == 1 { found = 1 }
    END { exit found ? 0 : 1 }' "$1"
}

rows=$(sh "$LOCK_TOOL" --print "$REPO" 2> "$WORK/lock.err") ||
  fail "control: anchors-lock.sh --print failed: $(cat "$WORK/lock.err")"
got=$(printf '%s\n' "$rows" | awk -F "$TAB" -v file="$VALIDATION/SKILL.md" '$2 == file { print $3 }' | sort -u | tr '\n' ' ')
[ "$got" = "validation " ] ||
  fail "$VALIDATION/SKILL.md sections are not anchored under the question validation (lock rows give: ${got:-none})"

for skill in $VERIFICATION $VALIDATION $ANALYSIS; do
  [ -f "$EVALS/$skill.json" ] || fail "trigger eval missing: $skill.json"
done
overlap=$(three_evals "$EVALS" 2> "$WORK/node.err") ||
  fail "control: the trigger eval check did not run (node exited non-zero): $(grep -m 1 "Error" "$WORK/node.err")"
[ -z "$overlap" ] || fail "the trigger evals do not separate the three questions:
$overlap"

(PATH=/nonexistent; three_evals "$EVALS") > /dev/null 2>&1 &&
  fail "control: the trigger eval check passed without node"

mkdir -p "$WORK/plant"
for skill in $VERIFICATION $VALIDATION $ANALYSIS; do
  cp "$EVALS/$skill.json" "$WORK/plant/$skill.json" 2> /dev/null
done
if node -e '
  const fs = require("fs");
  const [from, to] = process.argv.slice(1);
  const source = JSON.parse(fs.readFileSync(from, "utf8"));
  const target = JSON.parse(fs.readFileSync(to, "utf8"));
  target.should_trigger = [...(target.should_trigger || []), ...(source.should_trigger || []).slice(0, 1)];
  fs.writeFileSync(to, JSON.stringify(target));
' "$EVALS/$VERIFICATION.json" "$WORK/plant/$VALIDATION.json" 2> /dev/null; then
  three_evals "$WORK/plant" 2> /dev/null |
    grep -q 'should_trigger prompt in both' ||
    fail "control: a should_trigger prompt planted in two trigger evals was not reported"
else
  fail "control: the planted shared prompt could not be written"
fi

for skill in $VERIFICATION $VALIDATION $ANALYSIS; do
  cp "$EVALS/$skill.json" "$WORK/plant/$skill.json" 2> /dev/null
done
if node -e '
  const fs = require("fs");
  const [from, to] = process.argv.slice(1);
  const source = new Set(JSON.parse(fs.readFileSync(from, "utf8")).should_trigger || []);
  const target = JSON.parse(fs.readFileSync(to, "utf8"));
  target.should_not_trigger = (target.should_not_trigger || []).filter((prompt) => !source.has(prompt));
  fs.writeFileSync(to, JSON.stringify(target));
' "$EVALS/$VALIDATION.json" "$WORK/plant/$ANALYSIS.json" 2> /dev/null; then
  three_evals "$WORK/plant" 2> /dev/null |
    grep -q "$ANALYSIS.json should_not_trigger holds no should_trigger prompt of $VALIDATION.json" ||
    fail "control: an eval whose near-misses from another question were removed was not reported"
else
  fail "control: the planted eval without near-misses could not be written"
fi

expect_plant self "$VALIDATION" "prompt in both should_trigger and should_not_trigger of $VALIDATION.json" \
  "a should_trigger prompt planted into the same eval's should_not_trigger"
expect_plant drop-schema "$ANALYSIS" "schema prompt missing from $ANALYSIS.json should_not_trigger" \
  "the schema prompt removed from a should_not_trigger"
expect_plant trigger-schema "$VERIFICATION" "schema prompt in $VERIFICATION.json should_trigger" \
  "the schema prompt planted into a should_trigger"

related_pointer "$REPO/$VERIFICATION/SKILL.md" ||
  fail "the Related section of $VERIFICATION/SKILL.md lacks a bullet opening with the $VALIDATION pointer"
printf '%s\n' "$RELATED_ANCHOR" '## Related' '' '- `@smith-guidance/SKILL.md` - steering' '' '## Before You Finish' \
  "- \`@$VALIDATION/SKILL.md\` - outside Related" > "$WORK/related.md"
! related_pointer "$WORK/related.md" ||
  fail "control: a $VALIDATION pointer outside the Related section was accepted"
printf '%s\n' "$RELATED_ANCHOR" '## Renamed Related' '' "- \`@$VALIDATION/SKILL.md\` - fitness" > "$WORK/related.md"
related_pointer "$WORK/related.md" ||
  fail "control: a bullet opening with the $VALIDATION pointer under the related-v1 anchor was rejected"
printf '%s\n' '## Related' '' "- \`@$VALIDATION/SKILL.md\` - fitness" > "$WORK/related.md"
! related_pointer "$WORK/related.md" ||
  fail "control: a Related heading without the related-v1 anchor was accepted, so the section is still found by its heading text"

if [ -z "${VALIDATION_FITNESS_NO_NODE_RUN:-}" ]; then
  if (PATH=/usr/bin:/bin; command -v node) > /dev/null 2>&1; then
    fail "control: node is on /usr/bin:/bin, so the whole test cannot be run without node"
  else
    no_node=$(VALIDATION_FITNESS_NO_NODE_RUN=1 PATH=/usr/bin:/bin sh "$0" 2>&1)
    no_node_status=$?
    [ "$no_node_status" != 0 ] &&
      printf '%s\n' "$no_node" | grep -q '^FAIL: validation-fitness: control: the trigger eval check did not run' ||
      fail "control: the whole test run without node on PATH did not exit non-zero with a FAIL line for the eval check"
  fi
fi

[ "$status" = 0 ] && echo "PASS: validation-fitness"
exit "$status"
