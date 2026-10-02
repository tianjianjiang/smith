#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/../skill-lint.mjs"
REPO="$(cd "$HERE/../../.." && pwd)"

TMPD="$(mktemp -d)"
trap 'chmod -R u+rwx "$TMPD" 2>/dev/null; rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

raw_skill() {
  directory="$1"
  shift
  mkdir -p "$TMPD/$directory"
  printf '%s\n' "$@" > "$TMPD/$directory/SKILL.md"
}
skill_fixture() {
  directory="$1"
  shift
  raw_skill "$directory" '---' "name: $(basename "$directory")" 'description: A fixture skill. Use when testing the lint.' '---' '' '# Fixture' '' "$@"
}
reports() {
  out=$(node "$LINT" "$TMPD/$1/SKILL.md") && fail "$1: expected a non-zero exit"
  printf '%s' "$out" | grep -q "SKILL.md:[0-9]*: $2:" || fail "$1: expected rule $2, got: $out"
}
passes() {
  out=$(node "$LINT" "$TMPD/$1/SKILL.md") || fail "$1: expected a pass, got: $out"
  [ "$out" = "skill-lint: checked 1 files, 0 findings" ] || fail "$1: expected only the summary, got: $out"
}
breaks() {
  skill_fixture "broken/$1" "$3"
  reports "broken/$1" "$2"
}

breaks iso-date date 'The docs were verified 2026-05-21.'
breaks year-month date 'Failures ran from 2026-04 onwards.'
breaks issue-url reference 'See https://github.com/example/tool/issues/123 for the bug.'
breaks pull-url reference 'Fixed by https://github.com/example/tool/pull/45.'
breaks pr-number reference 'This shipped in PR #789.'
breaks pr-without-hash reference 'This shipped in PR 789.'
breaks prs-plural reference 'Covered by PRs #12 and later.'
breaks pull-request-number reference 'See pull request #45.'
breaks parenthesised reference 'The guard skips symlinks (#285).'
breaks link-label reference 'May not fire ([#20397]).'
breaks cross-repository reference 'Changed upstream in cli/cli#14007.'
breaks issue-number reference 'Tracked as Claude Code issue #40857.'
breaks commit-hash reference 'Introduced in commit fb9bddd.'
breaks ticket-key reference 'Requested in PLAT-1234.'
breaks as-of status 'This skill owns the hooks as of the last release.'
breaks awaiting-review status 'The rename is awaiting review.'
breaks awaiting-merge status 'The rename is awaiting merge.'
breaks awaiting-approval status 'The rename is awaiting approval.'
breaks not-yet-merged status 'The fix is not yet merged.'
breaks prior-version history 'A prior version of this file used another label.'
breaks skill-previously history 'This skill previously mandated another browser.'
breaks incident-history history 'Incident history: the launch failed twice.'
breaks incident-walkthrough history 'The incident walkthrough is in the reference document.'
breaks incident-guards history 'Incident this guards against: a stale read.'
breaks correction history 'Correction: the default is stable Chrome.'
breaks recurrence history 'The recurrence was a stale registration.'
breaks retired-after history 'The convention was retired after two misuses.'

skill_fixture clean \
  'Cite the source: https://example.com/docs/page' \
  'Use ISO-8601 dates and UTF-16 offsets; SHA-256, RFC-2119 and GPT-41 are names.' \
  'The decision is recorded as ADR-004.' \
  'Dates look like `2025-01-15`; `Closes #123` closes an issue.' \
  'Write the note as "depends on #1".' \
  'Requires gh 2.99.0 or newer.' \
  '```text' \
  '- PR #789 (awaiting review)' \
  '~~~' \
  '[1] Source: URL (retrieved 2026-01-01)' \
  '```' \
  '~~~' \
  'Fixed in PR #12.' \
  '~~~' \
  '````markdown' \
  '```' \
  'Verified 2026-05-21.' \
  '```' \
  '````' \
  'Placeholder: retrieved «YYYY-MM-DD», ticket «KEY-123».'
passes clean

skill_fixture date-after-nested-fence '````markdown' '```' 'inner' '```' '````' 'Verified 2026-05-21.'
reports date-after-nested-fence date
skill_fixture unclosed-fence '```text' 'an example' '' 'Verified 2026-05-21.'
reports unclosed-fence fence
skill_fixture date-after-code-span '```yaml``` is the format.' 'Verified 2026-05-21.'
reports date-after-code-span date

raw_skill no-frontmatter '# No frontmatter'
reports no-frontmatter frontmatter
raw_skill wrong-name '---' 'name: other-name' 'description: A fixture skill. Use when testing the lint.' '---'
reports wrong-name frontmatter
printf '%s' "$out" | grep -q 'name must be wrong-name' || fail "wrong-name: expected the name finding, got: $out"
raw_skill no-description '---' 'name: no-description' 'description:' '---'
reports no-description frontmatter
raw_skill empty-quoted-description '---' 'name: empty-quoted-description' 'description: ""' '---'
reports empty-quoted-description frontmatter
raw_skill unclosed-frontmatter '---' 'name: unclosed-frontmatter' 'description: A fixture'
reports unclosed-frontmatter frontmatter
raw_skill quoted-name '---' 'name: "quoted-name"' "description: 'A fixture. Use when testing the lint.'" '---'
passes quoted-name
raw_skill empty-block-description '---' 'name: empty-block-description' 'description: >' '---'
reports empty-block-description frontmatter
raw_skill block-description '---' 'name: block-description' 'description: >' '  A fixture skill.' '  Use when testing the lint.' '---'
passes block-description
raw_skill block-with-blank-line '---' 'name: block-with-blank-line' 'description: |' '  A fixture skill.' '' '  Use when testing the lint.' '---'
passes block-with-blank-line
raw_skill wrapped-clause '---' 'name: wrapped-clause' 'description: >' '  A fixture skill. Use' '  when testing the lint.' '---'
passes wrapped-clause
raw_skill continued-plain-value '---' 'name: continued-plain-value' 'description: A fixture skill.' '  Use when testing the lint.' '---'
passes continued-plain-value
raw_skill no-when-to-use '---' 'name: no-when-to-use' 'description: A fixture skill' '---'
reports no-when-to-use frontmatter
printf '%s' "$out" | grep -q 'does not say when to use the skill' || fail "no-when-to-use: expected the when-to-use finding, got: $out"
raw_skill block-without-when-to-use '---' 'name: block-without-when-to-use' 'description: >' '  A fixture skill.' 'metadata:' '  note: Use when testing the lint.' '---'
reports block-without-when-to-use frontmatter
for clause in 'Use before any push.' 'Use first in every session.' 'Use for every task.' 'Always active. Use whenever output is written.'; do
  raw_skill other-clause '---' 'name: other-clause' "description: A fixture skill. $clause" '---'
  passes other-clause
done
mkdir -p "$TMPD/windows-line-endings"
printf '%s\r\n' '---' 'name: windows-line-endings' 'description: A fixture skill. Use when testing the lint.' '---' '' '# Fixture' > "$TMPD/windows-line-endings/SKILL.md"
passes windows-line-endings
raw_skill nested-name '---' 'name: nested-name' 'description: A fixture skill. Use when testing the lint.' 'metadata:' '  name: another-name' '---'
passes nested-name
raw_skill description-on-next-line '---' 'name: description-on-next-line' 'description:' '  A fixture skill. Use when testing the lint.' '---'
passes description-on-next-line
out=$(cd "$TMPD/clean" && node "$LINT" SKILL.md) || fail "a relative path must take its directory's name, got: $out"
if [ "$(id -u)" = 0 ]; then
  echo "  SKIP unreachable skill file (root reads regardless of mode)"
else
  mkdir -p "$TMPD/locked-root/locked-skill"
  cp "$TMPD/clean/SKILL.md" "$TMPD/locked-root/locked-skill/SKILL.md"
  chmod 000 "$TMPD/locked-root/locked-skill"
  out=$(node "$LINT" --root "$TMPD/locked-root")
  status=$?
  chmod 700 "$TMPD/locked-root/locked-skill"
  [ "$status" != 0 ] || fail "a skill file that cannot be reached must not pass, got: $out"
  printf '%s' "$out" | grep -q 'SKILL.md:1: unreadable:' || fail "a skill file that cannot be reached must be reported, got: $out"
fi
mkdir -p "$TMPD/directory-instead-of-file/SKILL.md"
reports directory-instead-of-file unreadable

out=$(node "$LINT" "$TMPD/broken/iso-date/SKILL.md" "$TMPD/clean/SKILL.md")
[ "$(printf '%s\n' "$out" | grep -c 'SKILL.md:')" = 1 ] || fail "one finding per reported line, got: $out"
printf '%s' "$out" | grep -q 'checked 2 files, 1 findings' || fail "summary counts files and findings, got: $out"

out=$(node "$LINT" --root "$TMPD/broken") && fail "discovery under a root with broken skills must exit non-zero"
printf '%s' "$out" | grep -q 'iso-date/SKILL.md:[0-9]*: date:' || fail "discovery must read the skills under the root, got: $out"
printf '%s' "$out" | grep -q 'checked 27 files, 27 findings' || fail "discovery must count what it read, got: $out"
mkdir -p "$TMPD/no-skills/empty-directory"
node "$LINT" --root "$TMPD/no-skills" >/dev/null 2>&1 && fail "a root without skill files must exit non-zero"
node "$LINT" --root "$TMPD/absent" >/dev/null 2>&1 && fail "a missing root must exit non-zero"
node "$LINT" --root "$TMPD/clean" "$TMPD/clean/SKILL.md" >/dev/null 2>&1 && fail "a root given with files must exit non-zero"
node "$LINT" --root >/dev/null 2>&1 && fail "a root without a value must exit non-zero"
out=$(node "$LINT" "$TMPD/clean/SKILL.md" --root "$TMPD/clean" 2>&1) && fail "a root given after a file must exit non-zero"
printf '%s' "$out" | grep -q -- '--root takes one directory' || fail "a root given after a file must be refused as misuse, not read as a path, got: $out"

hook() { printf '%s' "$1" | node "$LINT" --hook; }
blocks() {
  out=$(hook "$2") || fail "$1: hook crashed"
  printf '%s' "$out" | jq -e --arg expected "$3" '.decision == "block" and (.reason | contains($expected))' >/dev/null \
    || fail "$1: expected a block naming $3, got: $out"
}
silent() {
  out=$(hook "$2") || fail "$1: hook crashed"
  [ -z "$out" ] || fail "$1: expected silence, got: $out"
}
BAD="$TMPD/broken/iso-date/SKILL.md"

blocks "edit of a skill file with a finding" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$BAD\"}}" 'date:'
silent "write of a clean skill file" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMPD/clean/SKILL.md\"}}"
silent "read of a skill file with a finding" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$BAD\"}}"
blocks "relative path resolved against cwd" "{\"tool_name\":\"Write\",\"cwd\":\"$TMPD/broken\",\"tool_input\":{\"file_path\":\"iso-date/SKILL.md\"}}" 'date:'
out=$(cd "$TMPD/broken" && printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"iso-date/SKILL.md"}}' | node "$LINT" --hook) || fail "hook crashed without cwd"
printf '%s' "$out" | jq -e '.decision == "block"' >/dev/null || fail "relative path without cwd: expected a block, got: $out"
blocks "skill file that cannot be read" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMPD/directory-instead-of-file/SKILL.md\"}}" 'unreadable:'
mkdir -p "$TMPD/broken/iso-date/references"
printf '%s\n' 'Verified 2026-05-21 in PR #1.' > "$TMPD/broken/iso-date/references/NOTES.md"
silent "reference document" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMPD/broken/iso-date/references/NOTES.md\"}}"
silent "missing file" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMPD/absent/SKILL.md\"}}"
silent "malformed input" 'not json'
silent "json null" 'null'

SERENA_ROOT="$TMPD/serena-root"
mkdir -p "$SERENA_ROOT/.git" "$TMPD/elsewhere"
mkdir -p "$SERENA_ROOT/dated" "$SERENA_ROOT/nested/dated"
cp "$BAD" "$SERENA_ROOT/dated/SKILL.md"
cp "$BAD" "$SERENA_ROOT/nested/dated/SKILL.md"
export CLAUDE_PROJECT_DIR="$SERENA_ROOT"

blocks "serena write resolved against serena's root" "{\"tool_name\":\"mcp__serena__replace_content\",\"cwd\":\"$TMPD/elsewhere\",\"tool_input\":{\"relative_path\":\"dated/SKILL.md\"}}" 'serena-root/dated/SKILL.md'
blocks "plugin-installed serena write" "{\"tool_name\":\"mcp__plugin_serena_serena__replace_content\",\"cwd\":\"$TMPD/elsewhere\",\"tool_input\":{\"relative_path\":\"dated/SKILL.md\"}}" 'serena-root/dated/SKILL.md'
silent "serena read of a skill file with a finding" "{\"tool_name\":\"mcp__serena__find_symbol\",\"cwd\":\"$TMPD/elsewhere\",\"tool_input\":{\"relative_path\":\"dated/SKILL.md\"}}"
blocks "serena edit of many files across the project" "{\"tool_name\":\"mcp__serena__replace_in_files\",\"cwd\":\"$TMPD/elsewhere\",\"tool_input\":{\"relative_path\":\"\"}}" 'serena-root/dated/SKILL.md'
blocks "serena edit of many files under a directory" "{\"tool_name\":\"mcp__serena__replace_in_files\",\"cwd\":\"$TMPD/elsewhere\",\"tool_input\":{\"relative_path\":\"nested\"}}" 'serena-root/nested/dated/SKILL.md'
blocks "serena edit of many files in one skill directory" "{\"tool_name\":\"mcp__serena__replace_in_files\",\"cwd\":\"$TMPD/elsewhere\",\"tool_input\":{\"relative_path\":\"dated\"}}" 'serena-root/dated/SKILL.md'
silent "serena single-file write to another file" "{\"tool_name\":\"mcp__serena__replace_content\",\"cwd\":\"$TMPD/elsewhere\",\"tool_input\":{\"relative_path\":\"dated/notes.md\"}}"
if [ "$(id -u)" = 0 ]; then
  echo "  SKIP unlistable directory (root reads regardless of mode)"
else
  mkdir -p "$SERENA_ROOT/locked"
  chmod 000 "$SERENA_ROOT/locked"
  out=$(hook "{\"tool_name\":\"mcp__serena__replace_in_files\",\"cwd\":\"$TMPD/elsewhere\",\"tool_input\":{\"relative_path\":\"locked\"}}")
  status=$?
  chmod 700 "$SERENA_ROOT/locked"
  [ "$status" = 0 ] || fail "a directory that cannot be listed must not crash the hook"
  printf '%s' "$out" | jq -e '.decision == "block" and (.reason | contains("could not be checked"))' >/dev/null || fail "a directory that cannot be listed must be reported, got: $out"
fi

expected_files=$(ls -d "$REPO"/*/SKILL.md | wc -l | tr -d ' ')
[ "$expected_files" -ge 48 ] || fail "expected at least 48 skill files, found $expected_files"
out=$(node "$LINT") || fail "the repository's skill files do not pass: $out"
[ "$out" = "skill-lint: checked $expected_files files, 0 findings" ] || fail "the lint must check every skill file of the repository, got: $out"

echo "PASS: skill-lint"
