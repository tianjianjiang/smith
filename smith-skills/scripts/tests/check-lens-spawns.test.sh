#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../../../smith-vet/evals/fixtures/scripts"
LENS_JUDGE="$SCRIPTS/check-lens-spawns.sh"
AGGREGATOR_JUDGE="$SCRIPTS/check-aggregator.sh"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

[ -f "$LENS_JUDGE" ] || fail "the judge under test does not exist: $LENS_JUDGE"
[ -f "$AGGREGATOR_JUDGE" ] || fail "the judge under test does not exist: $AGGREGATOR_JUDGE"

mkdir -p "$TMPD/workspace/docs"
printf '%s\n' '# Plan' '' '1. Move the session store to a shared cache and deploy it to every region at once.' > "$TMPD/workspace/docs/plan.md"
AGGREGATOR_PROMPT='Reconcile the returns below into one verdict on what was vetted, and name the skill behind each finding.'
export AGGREGATOR_PROMPT
mkdir -p "$TMPD/workspace/.claude/skills/smith-vet"
printf '%s\n' '# smith-vet' '' '## Aggregation' '' 'Use the text below, word for word.' '' '```text' "$AGGREGATOR_PROMPT" '```' '' '## Batch Rule' \
  > "$TMPD/workspace/.claude/skills/smith-vet/SKILL.md"
mkdir -p "$TMPD/workspace/.claude/skills/smith-subagents"
printf '%s\n' '# smith-subagents' '' 'Put this block in every prompt:' '' \
  '> READ-ONLY investigation. Return FINDINGS ONLY and never edit, write, commit or push anything at all.' \
  '> If a step seems to need a change, describe it for the main thread. Restate the' \
  '> exact values you observed; do not summarize them away.' \
  > "$TMPD/workspace/.claude/skills/smith-subagents/SKILL.md"
CONTRACT_BLOCK='READ-ONLY investigation. Return FINDINGS ONLY and never edit, write, commit or push anything at all. If a step seems to need a change, describe it for the main thread. Restate the exact values you observed; do not summarize them away.'
export CONTRACT_BLOCK

cat > "$TMPD/make-transcript.mjs" <<'EOF'
import fs from 'node:fs';

const [file, ...steps] = process.argv.slice(2);
const LENSES = { analysis: 'smith-analysis', clarity: 'smith-clarity', dialectic: 'smith-dialectic', research: 'smith-research', validation: 'smith-validation' };
const returned = (lens) => Array.from({ length: 24 }, (unused, index) => `${lens}-finding-${index}`).join(' ');
const messages = [{ role: 'user', content: '/smith-vet docs/plan.md' }];
let calls = 0;

function call(prompt) {
  calls += 1;
  messages.push({ role: 'tool_call', tool_call: { id: `call-${calls}`, name: 'Agent', arguments: { prompt } } });
  return `call-${calls}`;
}

function answer(callId, content) {
  messages.push({ role: 'tool_result', tool_result: { call_id: callId, content } });
}

for (const step of steps) {
  const [kind, ...names] = step.split(':');
  if (kind === 'lens') {
    const [lens, carried] = names;
    const carriedText = carried ? ` Another reviewer already said: ${returned(carried)}` : '';
    answer(call(`Use the ${LENSES[lens]} skill on docs/plan.md and return your findings.${carriedText}`), returned(lens));
  } else if (kind === 'skeptic') {
    const [lens] = names;
    answer(call(`Try to refute this ${LENSES[lens]} finding and say what you read. Finding: ${returned(lens)}`), 'The finding stands after a read of the plan.');
  } else if (['aggregator', 'opinionated', 'untemplated', 'contracted', 'summarized', 'instructed'].includes(kind)) {
    const opening = kind === 'untemplated' ? 'Put these returns together.' : process.env.AGGREGATOR_PROMPT;
    const opinion = kind === 'opinionated' ? ' The plan is clearly not viable and its single step is the fatal part, so build the verdict around that conclusion.' : '';
    const contract = kind === 'contracted' ? ` ${process.env.CONTRACT_BLOCK}` : '';
    const summary = kind === 'summarized' ? ' (claims in the plan vs. the repo)' : '';
    const closing = kind === 'instructed' ? ' Report one verdict on these returns now.' : '';
    answer(call(`${opening}${opinion}${contract} docs/plan.md ${names.map((lens) => `RETURN: ${LENSES[lens]}${summary} ${returned(lens)}`).join(' ')}${closing}`), 'One verdict: the plan is not ready.');
  }
}
fs.writeFileSync(file, JSON.stringify(messages));
EOF

WORKSPACE="$TMPD/workspace"
mkdir -p "$TMPD/without-smith-vet/docs"
cp "$TMPD/workspace/docs/plan.md" "$TMPD/without-smith-vet/docs/plan.md"
ALL_LENSES="lens:analysis lens:clarity lens:dialectic lens:research lens:validation"

judge() {
  node "$TMPD/make-transcript.mjs" "$TMPD/transcript.json" $2
  (cd "$WORKSPACE" && EVAL_TRANSCRIPT_PATH="$TMPD/transcript.json" sh "$1") > "$TMPD/judge.out" 2>&1
  STATUS=$?
}
expect() {
  judge "$1" "$3"
  [ "$STATUS" = "$2" ] || fail "$4: the judge must exit $2, got $STATUS: $(cat "$TMPD/judge.out")"
}

expect "$LENS_JUDGE" 0 "$ALL_LENSES" \
  "one subagent per named skill, none given a return"
expect "$LENS_JUDGE" 0 "$ALL_LENSES skeptic:research aggregator:analysis:clarity:dialectic:research:validation" \
  "a skeptic given the finding of its own lens and an aggregator given every return are not lenses that saw another judgment"
expect "$LENS_JUDGE" 1 "lens:analysis lens:clarity:analysis lens:dialectic lens:research lens:validation" \
  "a lens whose prompt carries the return of another lens"
expect "$LENS_JUDGE" 1 "lens:analysis lens:clarity lens:dialectic lens:research" \
  "a named skill without a subagent of its own"

expect "$AGGREGATOR_JUDGE" 0 "$ALL_LENSES aggregator:analysis:clarity:dialectic:research:validation" \
  "a subagent that is given the returns of the lenses"
expect "$AGGREGATOR_JUDGE" 1 "$ALL_LENSES" \
  "no subagent is given the returns, so the main thread reconciled them itself"
expect "$AGGREGATOR_JUDGE" 1 "$ALL_LENSES skeptic:research" \
  "a skeptic given one finding is not an aggregator"
expect "$AGGREGATOR_JUDGE" 1 "$ALL_LENSES aggregator:analysis:clarity" \
  "an aggregator that is given only some of the returns"
expect "$AGGREGATOR_JUDGE" 1 "$ALL_LENSES opinionated:analysis:clarity:dialectic:research:validation" \
  "an aggregator whose prompt also carries the main thread's own view"
expect "$AGGREGATOR_JUDGE" 0 "$ALL_LENSES contracted:analysis:clarity:dialectic:research:validation" \
  "an aggregator prompt that also carries a block an installed skill quotes line by line is still only skill text"
expect "$AGGREGATOR_JUDGE" 1 "$ALL_LENSES untemplated:analysis:clarity:dialectic:research:validation" \
  "a subagent given every return without the aggregator prompt of the skill is not the aggregator"
expect "$AGGREGATOR_JUDGE" 1 "$ALL_LENSES summarized:analysis:clarity:dialectic:research:validation" \
  "a RETURN label that carries a summary of the main thread's own"
expect "$AGGREGATOR_JUDGE" 1 "$ALL_LENSES instructed:analysis:clarity:dialectic:research:validation" \
  "a closing instruction of the main thread's own after the returns"

WORKSPACE="$TMPD/without-smith-vet"
expect "$AGGREGATOR_JUDGE" 0 "$ALL_LENSES untemplated:analysis:clarity:dialectic:research:validation" \
  "without smith-vet, a subagent given every return: the hand-over is asked of both arms alike, so a baseline can pass"
expect "$AGGREGATOR_JUDGE" 1 "$ALL_LENSES" \
  "without smith-vet, no subagent is given the returns"
expect "$AGGREGATOR_JUDGE" 1 "$ALL_LENSES untemplated:analysis:clarity" \
  "without smith-vet, a subagent given only some of the returns"

echo "PASS: check-lens-spawns"
