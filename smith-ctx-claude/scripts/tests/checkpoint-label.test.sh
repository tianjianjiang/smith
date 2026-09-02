#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../lib-context.sh"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: checkpoint-label - $1"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

printf '# Fix smith-checkpoint Basic-Memory NOTE_ALREADY_EXISTS — Plan\n\nbody\n' > "$TMP/groovy-greeting-pearl.md"
got=$(checkpoint_label_from_plan "$TMP/groovy-greeting-pearl.md")
[ "$got" = "fix_smith_checkpoint_basic_memory_note_already_exists" ] || fail "H1 title should drive the label, got: $got"
pass "label from H1 title"

printf 'no heading here\n- [ ] todo\n' > "$TMP/quiet-river-stone.md"
got=$(checkpoint_label_from_plan "$TMP/quiet-river-stone.md")
[ "$got" = "quiet_river_stone" ] || fail "missing H1 should fall back to filename, got: $got"
pass "fallback to filename"

printf '# Smith Skills Consolidated Plan\n' > "$TMP/smith-consolidated-plan.md"
got=$(checkpoint_label_from_plan "$TMP/smith-consolidated-plan.md")
[ "$got" = "smith_skills_consolidated_plan" ] || fail "trailing word Plan without dash must stay, got: $got"
pass "plain title kept"

printf '# %s\n' "$(printf 'word %.0s' $(seq 1 30))" > "$TMP/long.md"
got=$(checkpoint_label_from_plan "$TMP/long.md")
[ "${#got}" -le 60 ] || fail "label longer than 60 chars: $got"
case "$got" in *_) fail "label must not end with underscore: $got" ;; esac
pass "capped at 60 chars"

printf '# 修正檢查點標題 — Plan\n' > "$TMP/mandarin-title-plan.md"
got=$(checkpoint_label_from_plan "$TMP/mandarin-title-plan.md")
[ "$got" = "mandarin_title_plan" ] || fail "non-ASCII-only H1 must fall back to the filename, got: '$got'"
pass "non-ASCII title falls back to filename"

printf '# Fix labels - Plan\n' > "$TMP/ascii-dash.md"
got=$(checkpoint_label_from_plan "$TMP/ascii-dash.md")
[ "$got" = "fix_labels" ] || fail "ASCII dash Plan suffix must be stripped, got: $got"
pass "ascii dash suffix stripped"

printf '# 修正檢查點標題\n' > "$TMP/計畫.md"
got=$(checkpoint_label_from_plan "$TMP/計畫.md")
[ "$got" = "plan_checkpoint" ] || fail "non-ASCII H1 and filename must yield the literal fallback, got: '$got'"
pass "non-ASCII title and filename fall back to plan_checkpoint"

printf '# Fix labels – Plan\n' > "$TMP/en-dash.md"
got=$(checkpoint_label_from_plan "$TMP/en-dash.md")
[ "$got" = "fix_labels" ] || fail "en dash Plan suffix must be stripped, got: $got"
pass "en dash suffix stripped"

got=$(checkpoint_label_from_cwd "/Users/x/Projects/My Repo")
[ "$got" = "my_repo_checkpoint" ] || fail "cwd label regressed, got: $got"
pass "cwd label unchanged"

got=$(checkpoint_label_from_cwd "/Users/x/專案")
[ "$got" = "session_checkpoint" ] || fail "non-ASCII cwd must not yield a bare _checkpoint, got: '$got'"
pass "non-ASCII cwd falls back to session_checkpoint"

echo "PASS: checkpoint-label"
