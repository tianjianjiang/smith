#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
VERIFICATION=smith-verification
ANALYSIS=smith-analysis
VALIDATION=smith-validation
LOCK_TOOL="$REPO/smith-ctx-claude/scripts/anchors-lock.sh"
EVALS="$REPO/smith-ctx-claude/evals/skill-trigger"
TAB="$(printf '\t')"
METHODS_LABEL=methods-v1
HANDBOOK_URL=https://www.nasa.gov/reference/systems-engineering-handbook/
status=0

fail() { echo "FAIL: verification-move: $1"; status=1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

copy_tracked() {
  mkdir -p "$1"
  (cd "$REPO" && git ls-files -z | tar --null -T - -cf -) | tar -xf - -C "$1"
}

headings() { grep '^## ' "$1" | sed 's/[[:space:]]*$//' | sort -u; }

left_in_validation() {
  headings "$1/$VERIFICATION/SKILL.md" > "$WORK/headings.verification"
  headings "$1/$ANALYSIS/SKILL.md" > "$WORK/headings.analysis"
  comm -3 "$WORK/headings.verification" "$WORK/headings.analysis" | tr -d "$TAB" > "$WORK/headings.single"
  [ -s "$WORK/headings.single" ] || return 0
  grep -x -F -f "$WORK/headings.single" "$1/$VALIDATION/SKILL.md"
}

eval_overlap() {
  node -e '
    const fs = require("fs");
    const path = require("path");
    const [first, second] = process.argv.slice(1).map((file) => ({
      name: path.basename(file),
      data: JSON.parse(fs.readFileSync(file, "utf8")),
    }));
    const list = (set, key) => (Array.isArray(set.data[key]) ? set.data[key] : []);
    for (const set of [first, second]) {
      if (list(set, "should_trigger").length === 0) console.log(`${set.name} has no should_trigger prompts`);
    }
    const firstTriggers = new Set(list(first, "should_trigger"));
    for (const prompt of list(second, "should_trigger")) {
      if (firstTriggers.has(prompt)) console.log(`should_trigger prompt in both: ${prompt}`);
    }
    for (const [own, other] of [[first, second], [second, first]]) {
      const triggers = new Set(list(other, "should_trigger"));
      if (!list(own, "should_not_trigger").some((prompt) => triggers.has(prompt))) {
        console.log(`${own.name} should_not_trigger holds no should_trigger prompt of ${other.name}`);
      }
    }
  ' "$1" "$2"
}

question_problems() {
  rows=$(sh "$LOCK_TOOL" --print "$1" 2> "$WORK/lock.err") ||
    echo "control: anchors-lock.sh --print failed: $(cat "$WORK/lock.err")"
  for pair in "$VERIFICATION verification" "$ANALYSIS analysis"; do
    set -- $pair
    got=$(printf '%s\n' "$rows" | awk -F "$TAB" -v file="$1/SKILL.md" '$2 == file && $1 != "frontmatter:description" { print $3 }' | sort -u | tr '\n' ' ')
    [ "$got" = "$2 " ] || echo "$1/SKILL.md sections are not anchored under the question $2 (lock rows give: ${got:-none})"
  done
}

techniques_problems() {
  [ -s "$1/$ANALYSIS/references/TECHNIQUES.md" ] ||
    echo "references/TECHNIQUES.md not in $ANALYSIS/"
  for skill in $VALIDATION $VERIFICATION; do
    [ ! -e "$1/$skill/references/TECHNIQUES.md" ] ||
      echo "references/TECHNIQUES.md still in $skill/"
  done
}

ROUTER_FILE=smith-ctx-claude/skill-triggers.json
REFERENCE_FILE=smith-ctx-claude/REFERENCE.md

router_problems() {
  node -e '
    const fs = require("fs");
    const [file, label, analysis, verification] = process.argv.slice(1);
    const matchers = [
      ["MCP setup", (why) => why === "MCP setup"],
      ["dialectic / stress-test", (why) => why.startsWith("dialectic / stress-test")],
      ["research before recommending", (why) => why === "research before recommending"],
    ];
    let rules;
    try {
      rules = JSON.parse(fs.readFileSync(file, "utf8")).rules;
    } catch (error) {
      console.log(label + " cannot be parsed: " + error.message);
      process.exit(0);
    }
    for (const [name, matches] of matchers) {
      const row = rules.find((rule) => matches(String(rule.why)));
      if (!row) {
        console.log(label + " has no row whose why is \"" + name + "\"");
        continue;
      }
      if (!row.skills.includes(analysis)) console.log(label + " row \"" + name + "\" does not list " + analysis);
      if (row.skills.includes(verification)) console.log(label + " row \"" + name + "\" still lists " + verification);
    }
  ' "$1/$ROUTER_FILE" "$ROUTER_FILE" "$ANALYSIS" "$VERIFICATION"
}

reference_problems() {
  for marker in "MCP setup/lifecycle →" "Dialectic/grill/stress-test plan →"; do
    line=$(grep -F -- "$marker" "$1/$REFERENCE_FILE")
    if [ -z "$line" ]; then
      echo "$REFERENCE_FILE has no line containing \"$marker\""
      continue
    fi
    printf '%s\n' "$line" | grep -qF "@$ANALYSIS/SKILL.md" ||
      echo "$REFERENCE_FILE line containing \"$marker\" does not name @$ANALYSIS/SKILL.md"
    ! printf '%s\n' "$line" | grep -qF "@$VERIFICATION/SKILL.md" ||
      echo "$REFERENCE_FILE line containing \"$marker\" still names @$VERIFICATION/SKILL.md"
  done
}

methods_section() {
  awk -v anchor="<a name=\"$METHODS_LABEL\"></a>" '
    $0 == anchor { inside = 1; next }
    inside && /^<a name="/ { exit }
    inside { print }' "$1/$VERIFICATION/SKILL.md"
}

methods_source_problems() {
  section=$(methods_section "$1")
  if [ -z "$section" ]; then
    echo "$VERIFICATION/SKILL.md has no section anchored as $METHODS_LABEL"
    return
  fi
  printf '%s\n' "$section" | grep -qF -- "$HANDBOOK_URL" ||
    echo "$VERIFICATION/SKILL.md section $METHODS_LABEL does not cite $HANDBOOK_URL"
}

rewrite_router_rows() {
  node -e '
    const fs = require("fs");
    const [file, prefix, mode, analysis, verification] = process.argv.slice(1);
    const document = JSON.parse(fs.readFileSync(file, "utf8"));
    if (mode === "remove") {
      document.rules = document.rules.filter((rule) => !String(rule.why).startsWith(prefix));
    } else {
      document.rules
        .filter((rule) => String(rule.why).startsWith(prefix))
        .forEach((rule) => { rule.skills = [analysis, verification]; });
    }
    fs.writeFileSync(file, JSON.stringify(document, null, 2) + "\n");
  ' "$1/$ROUTER_FILE" "$2" "$3" "$ANALYSIS" "$VERIFICATION"
}

report() {
  printf '%s\n' "$1" | while IFS= read -r line; do
    [ -n "$line" ] && echo "FAIL: verification-move: $line"
  done
}

copy_tracked "$WORK/real"

problems=$(question_problems "$REPO")
[ -z "$problems" ] || { report "$problems"; status=1; }
C="$WORK/control-question"
cp -R "$WORK/real" "$C"
grep -v '^<a name="' "$C/$VERIFICATION/SKILL.md" > "$C/x" && mv "$C/x" "$C/$VERIFICATION/SKILL.md"
question_problems "$C" | grep -qF "$VERIFICATION/SKILL.md sections are not anchored under the question verification" ||
  fail "control: $VERIFICATION/SKILL.md with its anchors removed was not reported"
rm -rf "$C"

left=$(left_in_validation "$WORK/real")
[ -z "$left" ] || fail "sections that belong to one question are still in $VALIDATION/SKILL.md: $left"
planted=$(head -n 1 "$WORK/headings.single")
if [ -z "$planted" ]; then
  fail "control: $VERIFICATION and $ANALYSIS share every heading, so no planted section can be checked"
else
  C="$WORK/control-heading"
  cp -R "$WORK/real" "$C"
  printf '\n%s\n' "$planted" >> "$C/$VALIDATION/SKILL.md"
  [ -n "$(left_in_validation "$C")" ] || fail "control: a planted section in $VALIDATION/SKILL.md was not reported"
  rm -rf "$C"
fi

problems=$(techniques_problems "$REPO")
[ -z "$problems" ] || { report "$problems"; status=1; }
C="$WORK/control-techniques"
cp -R "$WORK/real" "$C"
rm -f "$C/$ANALYSIS/references/TECHNIQUES.md"
for skill in $VALIDATION $VERIFICATION; do
  mkdir -p "$C/$skill/references"
  printf 'planted\n' > "$C/$skill/references/TECHNIQUES.md"
done
planted=$(techniques_problems "$C")
for want in "not in $ANALYSIS/" "still in $VALIDATION/" "still in $VERIFICATION/"; do
  printf '%s\n' "$planted" | grep -qF "references/TECHNIQUES.md $want" ||
    fail "control: TECHNIQUES.md $want was not reported"
done
rm -rf "$C"

overlap=$(eval_overlap "$EVALS/$VERIFICATION.json" "$EVALS/$ANALYSIS.json") ||
  fail "control: the trigger eval check did not run (node exited non-zero)"
[ -z "$overlap" ] || fail "the trigger evals do not separate the questions:
$overlap"
(PATH=/nonexistent; eval_overlap "$EVALS/$VERIFICATION.json" "$EVALS/$ANALYSIS.json") > /dev/null 2>&1 &&
  fail "control: the trigger eval check passed without node"
mkdir -p "$WORK/plant"
node -e '
  const fs = require("fs");
  const [from, to, out] = process.argv.slice(1);
  const source = JSON.parse(fs.readFileSync(from, "utf8"));
  const target = JSON.parse(fs.readFileSync(to, "utf8"));
  target.should_trigger = [...(target.should_trigger || []), ...(source.should_trigger || []).slice(0, 1)];
  fs.writeFileSync(out, JSON.stringify(target));
' "$EVALS/$VERIFICATION.json" "$EVALS/$ANALYSIS.json" "$WORK/plant/$ANALYSIS.json" ||
  fail "control: the planted trigger eval could not be written"
eval_overlap "$EVALS/$VERIFICATION.json" "$WORK/plant/$ANALYSIS.json" 2> /dev/null | grep -q 'in both' ||
  fail "control: a should_trigger prompt planted in both trigger evals was not reported"

problems=$(router_problems "$REPO")
[ -z "$problems" ] || { report "$problems"; status=1; }
problems=$(reference_problems "$REPO")
[ -z "$problems" ] || { report "$problems"; status=1; }
C="$WORK/control-router-restored"
cp -R "$WORK/real" "$C"
rewrite_router_rows "$C" "MCP setup" restore
router_problems "$C" | grep -qF "$ROUTER_FILE row \"MCP setup\" still lists $VERIFICATION" ||
  fail "control: a router row with $VERIFICATION put back was not reported"
rm -rf "$C"
C="$WORK/control-router-removed"
cp -R "$WORK/real" "$C"
rewrite_router_rows "$C" "research before recommending" remove
router_problems "$C" | grep -qF "$ROUTER_FILE has no row whose why is \"research before recommending\"" ||
  fail "control: a removed router row was not reported"
rm -rf "$C"
C="$WORK/control-reference-restored"
cp -R "$WORK/real" "$C"
sed "/MCP setup\/lifecycle →/ s|\$| @$VERIFICATION/SKILL.md|" "$C/$REFERENCE_FILE" > "$C/x" && mv "$C/x" "$C/$REFERENCE_FILE"
reference_problems "$C" | grep -qF "$REFERENCE_FILE line containing \"MCP setup/lifecycle →\" still names @$VERIFICATION/SKILL.md" ||
  fail "control: a reference line with $VERIFICATION put back was not reported"
rm -rf "$C"

problems=$(methods_source_problems "$REPO")
[ -z "$problems" ] || { report "$problems"; status=1; }
C="$WORK/control-methods-source"
cp -R "$WORK/real" "$C"
grep -vF -- "$HANDBOOK_URL" "$C/$VERIFICATION/SKILL.md" > "$C/x" && mv "$C/x" "$C/$VERIFICATION/SKILL.md"
methods_source_problems "$C" | grep -qF "section $METHODS_LABEL does not cite $HANDBOOK_URL" ||
  fail "control: a Methods section without the handbook link was not reported"
grep -vF -- "<a name=\"$METHODS_LABEL\"></a>" "$C/$VERIFICATION/SKILL.md" > "$C/x" && mv "$C/x" "$C/$VERIFICATION/SKILL.md"
methods_source_problems "$C" | grep -qF "has no section anchored as $METHODS_LABEL" ||
  fail "control: a missing Methods anchor was not reported"
rm -rf "$C"

[ "$status" = 0 ] && echo "PASS: verification-move"
exit "$status"
