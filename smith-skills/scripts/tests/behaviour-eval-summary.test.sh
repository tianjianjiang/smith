#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
SUMMARY="$HERE/../behaviour-eval-summary.mjs"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

[ -f "$SUMMARY" ] || fail "the script under test does not exist: $SUMMARY"

random_word() { head -c 30 /dev/urandom | base64 | tr -d '=+/\n' | cut -c1-16; }
random_commit() { od -An -tx1 -N20 /dev/urandom | tr -d ' \n'; }

PLANT_EXPLANATION="planted-explanation-$(random_word)"
PLANT_PATH="/planted/path/$(random_word)/artifact"
PLANT_IDENTIFIER="planted-id-$(random_word)"
PLANT_TITLE="planted-title-$(random_word)"
PLANT_PROMPT="planted-prompt-$(random_word)"
PLANT_RESPONSE="planted-response-$(random_word)"
PLANT_MODEL_NAME="planted-model-name-$(random_word)"
export PLANT_EXPLANATION PLANT_PATH PLANT_IDENTIFIER PLANT_TITLE PLANT_PROMPT PLANT_RESPONSE PLANT_MODEL_NAME

cat > "$TMPD/make-result.mjs" <<'EOF'
import fs from 'node:fs';

const [file, skill, observedModel, ...specs] = process.argv.slice(2);

function caseStatus(verdicts) {
  if (verdicts.some((verdict) => verdict !== 'PASS' && verdict !== 'FAIL')) return 'ERROR';
  return verdicts.includes('FAIL') ? 'FAIL' : 'PASS';
}

function caseResult(spec) {
  const [caseId, verdictList] = spec.split('=');
  const verdicts = verdictList.split(',');
  const status = caseStatus(verdicts);
  return {
    case_id: caseId,
    title: process.env.PLANT_TITLE,
    status,
    duration_ms: 1,
    turns: 1,
    grading: {
      status,
      assertion_results: verdicts.map((verdict) => ({
        text: process.env.PLANT_EXPLANATION,
        passed: verdict === 'PASS',
        evidence: process.env.PLANT_EXPLANATION,
      })),
    },
    judge_results: verdicts.map((verdict, index) => ({
      id: `${process.env.PLANT_IDENTIFIER}-${index}`,
      type: 'script',
      status: verdict,
      artifacts_dir: process.env.PLANT_PATH,
      result: { status: verdict },
    })),
    prompt: process.env.PLANT_PROMPT,
    response: process.env.PLANT_RESPONSE,
  };
}

fs.writeFileSync(file, JSON.stringify({
  skill_name: skill,
  schema_version: 'synthetic',
  model_name: process.env.PLANT_MODEL_NAME,
  request_id: process.env.PLANT_IDENTIFIER,
  case_results: specs.map(caseResult),
  requested_configuration: { model: 'model-requested-synthetic' },
  applied_configuration: { model: 'model-requested-synthetic' },
  observed_configuration: { model: observedModel },
}));
EOF

cat > "$TMPD/check-output.mjs" <<'EOF'
import fs from 'node:fs';

const [mode, outputFile, tableFile] = process.argv.slice(2);
const lines = fs.readFileSync(outputFile, 'utf8').split('\n').filter((line) => line.length > 0);
const recordLines = lines.filter((line) => line.startsWith('{'));
const otherLines = lines.filter((line) => !line.startsWith('{'));
const records = recordLines.map((line) => JSON.parse(line));
const table = fs.readFileSync(tableFile, 'utf8').split('\n').filter((line) => line.length > 0).map((line) => line.split('|'));
const ALLOWED_KEYS = ['skill', 'case', 'arm', 'iteration', 'model', 'skill_commit', 'eval_commit', 'verdicts'];

function recordKey(record) {
  return [record.skill, record.case, record.arm, record.iteration].join('|');
}

function differences(expected, actual) {
  const missing = expected.filter((item) => !actual.includes(item));
  const unexpected = actual.filter((item) => !expected.includes(item));
  const repeated = actual.filter((item, index) => actual.indexOf(item) !== index);
  return [
    ...missing.map((item) => `missing ${item}`),
    ...unexpected.map((item) => `unexpected ${item}`),
    ...repeated.map((item) => `repeated ${item}`),
  ];
}

function checkKeys() {
  const expected = table.map((row) => row.slice(0, 4).join('|'));
  const wrongType = records.filter((record) => typeof record.iteration !== 'number').map(recordKey);
  return [...differences(expected, records.map(recordKey)), ...wrongType.map((key) => `iteration is not a number: ${key}`)];
}

function checkVerdicts() {
  const expected = new Map(table.map((row) => [row.slice(0, 4).join('|'), row[4]]));
  return records
    .filter((record) => expected.has(recordKey(record)))
    .filter((record) => !Array.isArray(record.verdicts) || record.verdicts.join(',') !== expected.get(recordKey(record)))
    .map((record) => `verdicts differ: ${recordKey(record)}`);
}

function checkAllowlist() {
  return records
    .filter((record) => Object.keys(record).some((key) => !ALLOWED_KEYS.includes(key)))
    .map((record) => `a field outside the allowlist: ${recordKey(record)}`);
}

function checkModels() {
  const expected = new Map(table.map((row) => [row[0], row[1]]));
  return records.filter((record) => record.model !== expected.get(record.skill)).map((record) => `model differs: ${recordKey(record)}`);
}

function checkCommits() {
  const expected = new Map(table.map((row) => [`${row[0]}|${row[1]}`, row]));
  return records.flatMap((record) => {
    const [, , skillCommit, evalCommit] = expected.get(`${record.skill}|${record.arm}`) ?? [];
    const problems = [];
    if (record.skill_commit !== skillCommit) problems.push(`skill commit differs: ${recordKey(record)}`);
    const evalCommitAbsent = record.eval_commit === undefined || record.eval_commit === null || record.eval_commit === '';
    if (evalCommit === '' && !evalCommitAbsent) problems.push(`eval commit present without a source: ${recordKey(record)}`);
    if (evalCommit !== '' && record.eval_commit !== evalCommit) problems.push(`eval commit differs: ${recordKey(record)}`);
    return problems;
  });
}

function tokensOf(line) {
  return line.split(/[\s/:,=]+/);
}

function ruleValue(line, rule) {
  if (new RegExp(`${rule}-rule: met(\\s|$)`).test(line)) return 'met';
  if (new RegExp(`${rule}-rule: not met(\\s|$)`).test(line)) return 'not-met';
  return 'missing';
}

function checkRules() {
  return table.flatMap(([skill, caseId, goal, regression, incomplete]) => {
    const matching = otherLines.filter((line) => tokensOf(line).includes(skill) && tokensOf(line).includes(caseId));
    if (matching.length !== 1) return [`no single rule line for ${skill} ${caseId}`];
    const line = matching[0];
    const problems = [];
    if (ruleValue(line, 'goal') !== goal) problems.push(`goal-rule differs: ${skill} ${caseId}`);
    if (ruleValue(line, 'regression') !== regression) problems.push(`regression-rule differs: ${skill} ${caseId}`);
    if (/\bincomplete\b/.test(line) !== (incomplete === 'yes')) problems.push(`incomplete flag differs: ${skill} ${caseId}`);
    return problems;
  });
}

function checkOrder() {
  const lastRecord = lines.map((line, index) => (line.startsWith('{') ? index : -1)).reduce((a, b) => Math.max(a, b), -1);
  const firstOther = lines.findIndex((line) => !line.startsWith('{'));
  return firstOther !== -1 && firstOther < lastRecord ? ['a rule line comes before a record'] : [];
}

const checks = { keys: checkKeys, verdicts: checkVerdicts, allowlist: checkAllowlist, models: checkModels, commits: checkCommits, rules: checkRules, order: checkOrder };
const problems = checks[mode]();
if (problems.length > 0) {
  console.log(problems.slice(0, 4).join('; '));
  process.exit(1);
}
EOF

GOOD="$TMPD/good"
mkdir -p "$GOOD"
: > "$TMPD/expected-records.txt"

add_iteration() {
  skill="$1"
  arm="$2"
  iteration="$3"
  relative_dir="$4"
  model="$5"
  shift 5
  mkdir -p "$GOOD/$skill/$arm/$relative_dir"
  node "$TMPD/make-result.mjs" "$GOOD/$skill/$arm/$relative_dir/result.json" "$skill" "$model" "$@"
  for spec in "$@"; do
    verdicts="$(printf '%s' "${spec#*=}" | sed 's/TIMEOUT/ERROR/g')"
    printf '%s|%s|%s|%s|%s\n' "$skill" "${spec%%=*}" "$arm" "$iteration" "$verdicts" >> "$TMPD/expected-records.txt"
  done
}

ALPHA_MODEL="model-observed-alpha"
BETA_MODEL="model-observed-beta"
PASS_PASS="PASS,PASS"
OWN_BASELINE_CASES_PASSING="case-own-baseline.engine=$PASS_PASS case-own-baseline-error.engine=$PASS_PASS case-named-baseline.baseline.engine=$PASS_PASS"

add_iteration skill-alpha with-change 1 iteration-1 "$ALPHA_MODEL" \
  "case-goal=$PASS_PASS" "case-both-pass=$PASS_PASS" "case-change-fails=$PASS_PASS" \
  "case-error=PASS,ERROR" "case-baseline-error=$PASS_PASS" "case-no-baseline=$PASS_PASS" \
  $OWN_BASELINE_CASES_PASSING
add_iteration skill-alpha with-change 2 iteration-2 "$ALPHA_MODEL" \
  "case-goal=$PASS_PASS" "case-both-pass=$PASS_PASS" "case-change-fails=PASS,FAIL" \
  "case-error=$PASS_PASS" "case-baseline-error=$PASS_PASS" "case-no-baseline=$PASS_PASS" \
  $OWN_BASELINE_CASES_PASSING
add_iteration skill-alpha with-change 3 iteration-3/nested/deeper "$ALPHA_MODEL" \
  "case-goal=$PASS_PASS" "case-both-pass=$PASS_PASS" "case-change-fails=$PASS_PASS" \
  "case-error=$PASS_PASS" "case-baseline-error=$PASS_PASS" "case-no-baseline=$PASS_PASS" \
  $OWN_BASELINE_CASES_PASSING
add_iteration skill-alpha baseline 1 iteration-1 "$ALPHA_MODEL" \
  "case-goal=$PASS_PASS" "case-both-pass=$PASS_PASS" "case-change-fails=FAIL,FAIL" \
  "case-error=FAIL,FAIL" "case-baseline-error=FAIL,TIMEOUT" \
  "case-own-baseline.baseline.engine=FAIL,PASS" "case-own-baseline-error.baseline.engine=FAIL,TIMEOUT" \
  "case-named-baseline.baseline.engine=$PASS_PASS"
add_iteration skill-alpha baseline 2 iteration-2 "$ALPHA_MODEL" \
  "case-goal=FAIL,PASS" "case-both-pass=$PASS_PASS" "case-change-fails=FAIL,FAIL" \
  "case-error=FAIL,FAIL" "case-baseline-error=FAIL,FAIL" \
  "case-own-baseline.baseline.engine=$PASS_PASS" "case-own-baseline-error.baseline.engine=$PASS_PASS" \
  "case-named-baseline.baseline.engine=$PASS_PASS"
add_iteration skill-beta with-change 1 iteration-1 "$BETA_MODEL" "case-beta=$PASS_PASS"
mkdir -p "$GOOD/skill-beta/baseline"

ALPHA_CHANGE_COMMIT="$(random_commit)"
ALPHA_BASELINE_COMMIT="$(random_commit)"
ALPHA_EVAL_COMMIT="$(random_commit)"
BETA_CHANGE_COMMIT="$(random_commit)"
BETA_BASELINE_COMMIT="$(random_commit)"
cat > "$GOOD/arms.txt" <<EOF
skill=skill-alpha arm=with-change ref=feature-branch commit=$ALPHA_CHANGE_COMMIT eval-file=alpha.eval.json eval-commit=$ALPHA_EVAL_COMMIT
skill=skill-alpha arm=baseline ref=main commit=$ALPHA_BASELINE_COMMIT eval-file=alpha.eval.json eval-commit=$ALPHA_EVAL_COMMIT
skill=skill-beta arm=with-change ref=feature-branch commit=$BETA_CHANGE_COMMIT eval-file=beta.eval.json
skill=skill-beta arm=baseline ref=main commit=$BETA_BASELINE_COMMIT eval-file=beta.eval.json
EOF
printf 'root: synthetic\nfiles-read: yes\n' > "$GOOD/leak-scan.txt"

cat > "$TMPD/expected-models.txt" <<EOF
skill-alpha|$ALPHA_MODEL
skill-beta|$BETA_MODEL
EOF
cat > "$TMPD/expected-commits.txt" <<EOF
skill-alpha|with-change|$ALPHA_CHANGE_COMMIT|$ALPHA_EVAL_COMMIT
skill-alpha|baseline|$ALPHA_BASELINE_COMMIT|$ALPHA_EVAL_COMMIT
skill-beta|with-change|$BETA_CHANGE_COMMIT|
skill-beta|baseline|$BETA_BASELINE_COMMIT|
EOF
cat > "$TMPD/expected-rules.txt" <<'EOF'
skill-alpha|case-goal|met|not-met|no
skill-alpha|case-both-pass|not-met|met|no
skill-alpha|case-change-fails|not-met|not-met|no
skill-alpha|case-error|not-met|not-met|yes
skill-alpha|case-baseline-error|not-met|not-met|yes
skill-alpha|case-no-baseline|not-met|not-met|yes
skill-alpha|case-own-baseline.engine|met|not-met|no
skill-alpha|case-own-baseline-error.engine|not-met|not-met|yes
skill-alpha|case-named-baseline.baseline.engine|not-met|met|no
skill-beta|case-beta|not-met|not-met|yes
EOF

run_summary() {
  NAME="$1"
  shift
  node "$SUMMARY" "$@" >"$TMPD/$NAME.out" 2>"$TMPD/$NAME.err"
  STATUS=$?
  OUT="$TMPD/$NAME.out"
  ERR="$TMPD/$NAME.err"
}
expect_status() { [ "$STATUS" = "$1" ] || fail "$2, got status $STATUS"; }
check() {
  problems="$(node "$TMPD/check-output.mjs" "$1" "$OUT" "$2" 2>&1)" || fail "$3: $problems"
}
expect_refusal() {
  expect_status 3 "$1: the run must be refused with status 3"
  grep -q '^{' "$OUT" && fail "$1: a refused run must print no record"
  grep -q 'goal-rule' "$OUT" && fail "$1: a refused run must print no rule line"
  [ -s "$OUT" ] || [ -s "$ERR" ] || fail "$1: a refused run must say why"
  return 0
}
variant_of_good() {
  VARIANT="$TMPD/variant-$1"
  cp -R "$GOOD" "$VARIANT"
}

run_summary good "$GOOD"
expect_status 0 "a complete run folder must exit 0"
check keys "$TMPD/expected-records.txt" "records: one per skill, case, arm and iteration, with the iteration as a number"
check verdicts "$TMPD/expected-records.txt" "verdicts: PASS, FAIL or ERROR per judge in order, any other status as ERROR"
check allowlist "$TMPD/expected-records.txt" "allowlist: a record may hold only the allowlisted fields"
check models "$TMPD/expected-models.txt" "model: the model that answered, from the result file"
check commits "$TMPD/expected-commits.txt" "commits: each arm's own commit from arms.txt, the eval commit only when arms.txt has it"
check rules "$TMPD/expected-rules.txt" "rules: one line per skill and case with both rules and the incomplete flag"
check order "$TMPD/expected-rules.txt" "order: the rule lines come after the records"
grep -v '^{' "$OUT" | grep -F -q -e 'case-own-baseline.baseline.engine' -e 'case-own-baseline-error.baseline.engine' \
  && fail "pairing: a baseline case with its own case id shares the rule line of the with-change case it pairs with"

run_summary no-argument
expect_status 2 "no argument: the run must exit 2"
grep -q '^{' "$OUT" && fail "no argument: no record may be printed"
cat "$OUT" "$ERR" | grep -qi 'usage' || fail "no argument: a usage line must be printed"

run_summary missing-folder "$TMPD/no-such-folder"
expect_refusal "a run folder that does not exist"

variant_of_good leak-found
: > "$VARIANT/LEAK-FOUND"
run_summary leak-found "$VARIANT"
expect_refusal "a folder with the LEAK-FOUND marker"

variant_of_good scan-missing
rm "$VARIANT/leak-scan.txt"
run_summary scan-missing "$VARIANT"
expect_refusal "a folder without leak-scan.txt"

variant_of_good scan-read-nothing
printf 'root: synthetic\nfiles-read: no\n' > "$VARIANT/leak-scan.txt"
run_summary scan-read-nothing "$VARIANT"
expect_refusal "a leak scan that says files-read: no"

variant_of_good scan-without-signal
printf 'root: synthetic\n' > "$VARIANT/leak-scan.txt"
run_summary scan-without-signal "$VARIANT"
expect_refusal "a leak scan with no files-read line"

variant_of_good arms-missing
rm "$VARIANT/arms.txt"
run_summary arms-missing "$VARIANT"
expect_refusal "a folder without arms.txt"

variant_of_good arm-not-in-arms
mkdir -p "$VARIANT/skill-gamma/with-change/iteration-1"
node "$TMPD/make-result.mjs" "$VARIANT/skill-gamma/with-change/iteration-1/result.json" skill-gamma "$ALPHA_MODEL" "case-gamma=$PASS_PASS"
run_summary arm-not-in-arms "$VARIANT"
expect_refusal "a skill and arm with results but no line in arms.txt"

variant_of_good unparsable-result
printf '{"case_results": [' > "$VARIANT/skill-alpha/baseline/iteration-1/result.json"
run_summary unparsable-result "$VARIANT"
expect_refusal "a result.json that is not valid JSON"

variant_of_good no-results
rm -rf "$VARIANT/skill-alpha" "$VARIANT/skill-beta"
mkdir -p "$VARIANT/skill-alpha/with-change" "$VARIANT/skill-alpha/baseline"
run_summary no-results "$VARIANT"
expect_refusal "a clean folder holding no result.json"

variant_of_good two-baseline-cases-for-one
mkdir -p "$VARIANT/skill-alpha/baseline/iteration-3"
node "$TMPD/make-result.mjs" "$VARIANT/skill-alpha/baseline/iteration-3/result.json" skill-alpha "$ALPHA_MODEL" "case-own-baseline.engine=$PASS_PASS"
run_summary two-baseline-cases-for-one "$VARIANT"
expect_refusal "two baseline cases that pair with one with-change case"

cat > "$TMPD/single-judge.mjs" <<'EOF'
import fs from 'node:fs';

const [file, caseId, shape] = process.argv.slice(2);
const data = JSON.parse(fs.readFileSync(file, 'utf8'));
const target = data.case_results.find((caseResult) => caseResult.case_id === caseId);
const passedByShape = { fails: false, passes: true, 'not-boolean': 'unknown' };
delete target.judge_results;
if (shape === 'no-grading') {
  target.grading = null;
} else {
  target.status = shape === 'passes' ? 'PASS' : 'FAIL';
  target.grading = {
    status: target.status,
    assertion_results: [{ text: process.env.PLANT_PATH, passed: passedByShape[shape], evidence: process.env.PLANT_EXPLANATION }],
  };
}
fs.writeFileSync(file, JSON.stringify(data));
EOF

single_judge_variant() {
  variant_of_good "single-judge-$1"
  node "$TMPD/single-judge.mjs" "$VARIANT/skill-beta/with-change/iteration-1/result.json" case-beta "$1"
  sed "s/^skill-beta|case-beta|with-change|1|.*/skill-beta|case-beta|with-change|1|$2/" "$TMPD/expected-records.txt" > "$TMPD/expected-records-single-judge-$1.txt"
  run_summary "single-judge-$1" "$VARIANT"
  expect_status 0 "a case with one judge recorded only under grading ($1) must exit 0"
  check keys "$TMPD/expected-records-single-judge-$1.txt" "single judge ($1): every record is still printed"
  check verdicts "$TMPD/expected-records-single-judge-$1.txt" "single judge ($1): the verdict comes from the grading assertion"
  check rules "$TMPD/expected-rules.txt" "single judge ($1): the rule lines are still printed"
}
single_judge_variant fails FAIL
single_judge_variant passes PASS
single_judge_variant not-boolean ERROR

variant_of_good single-judge-no-grading
node "$TMPD/single-judge.mjs" "$VARIANT/skill-beta/with-change/iteration-1/result.json" case-beta no-grading
run_summary single-judge-no-grading "$VARIANT"
expect_refusal "a case with neither judge_results nor grading assertions"

assert_absent() {
  for artifact in "$TMPD"/*.out "$TMPD"/*.err; do
    grep -F -q -e "$2" "$artifact" && fail "no result.json free text in output: the $1 is in $(basename "$artifact")"
  done
  return 0
}
assert_absent "judge explanation" "$PLANT_EXPLANATION"
assert_absent "file path" "$PLANT_PATH"
assert_absent "id-like string" "$PLANT_IDENTIFIER"
assert_absent "case title" "$PLANT_TITLE"
assert_absent "prompt" "$PLANT_PROMPT"
assert_absent "response" "$PLANT_RESPONSE"
assert_absent "combined model name" "$PLANT_MODEL_NAME"

echo "PASS: behaviour-eval-summary"
