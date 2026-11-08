#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
PLAN_LABEL="$HERE/../plan-label.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: plan-label - $1"; }

run_label() {
    got=$(bash "$PLAN_LABEL" "$@" 2>"$WORK/stderr")
    status=$?
}

expect() {
    case_name="$1" expected_status="$2" expected_out="$3"
    [ "$status" = "$expected_status" ] || fail "$case_name: expected exit $expected_status, got $status: $(cat "$WORK/stderr")"
    [ "$got" = "$expected_out" ] || fail "$case_name: expected stdout '$expected_out', got '$got'"
    pass "$case_name"
}

expect_stderr() {
    grep -qF -- "$2" "$WORK/stderr" || fail "$1: stderr must contain '$2': $(cat "$WORK/stderr")"
}

printf '# smith-checkpoint follow-up PRs\n\n<!-- checkpoint-label-v1: double_blind_subagent_audit_in_smith_checkpoint -->\n\nbody\n' > "$WORK/resume-cached-glacier.md"
run_label "$WORK/resume-cached-glacier.md"
expect "marker names the checkpoint" 0 double_blind_subagent_audit_in_smith_checkpoint

printf '# Compression follow-up\n\n<!-- checkpoint-label-v1: checkpoint-compression -->\n' > "$WORK/compression.md"
run_label "$WORK/compression.md"
expect "marker value kept verbatim" 0 checkpoint-compression

printf '# Anywhere\n\nbody\n\n## Notes\n\n<!-- checkpoint-label-v1: anywhere_label -->\n' > "$WORK/anywhere.md"
run_label "$WORK/anywhere.md"
expect "marker counts wherever it sits" 0 anywhere_label

printf '# Fix labels – Plan\n\nbody\n' > "$WORK/en-dash.md"
run_label "$WORK/en-dash.md"
expect "no marker suggests the heading slug" 3 fix_labels

printf 'no heading here\n' > "$WORK/quiet-river-stone.md"
run_label "$WORK/quiet-river-stone.md"
expect "no heading or marker suggests the filename slug" 3 quiet_river_stone

for unsafe in ../x a/b -x .x 'a b' ''; do
    printf '# Unsafe\n\n<!-- checkpoint-label-v1: %s -->\n' "$unsafe" > "$WORK/unsafe.md"
    run_label "$WORK/unsafe.md"
    expect "unsafe marker value '$unsafe' is no marker" 3 unsafe
done

for safe in _a 1a a.b; do
    printf '# Safe\n\n<!-- checkpoint-label-v1: %s -->\n' "$safe" > "$WORK/safe.md"
    run_label "$WORK/safe.md"
    expect "safe marker value '$safe' kept verbatim" 0 "$safe"
done

printf '# Prose only\n\nWe add `checkpoint-label-v1` support.\n' > "$WORK/prose.md"
run_label "$WORK/prose.md"
expect "a prose mention is no marker" 3 prose_only

printf '# Prose and marker\n\n<!-- checkpoint-label-v1: real_label -->\n\nThe `checkpoint-label-v1` marker is described here.\n' > "$WORK/prose-and-marker.md"
run_label "$WORK/prose-and-marker.md"
expect "a prose mention beside a marker is ignored" 0 real_label

printf '# Trailing\n\n<!-- checkpoint-label-v1: real_label --> \t\n' > "$WORK/trailing.md"
run_label "$WORK/trailing.md"
expect "trailing whitespace after the marker" 0 real_label

printf '# Twice\n\n<!-- checkpoint-label-v1: real_label -->\n\n```markdown\n<!-- checkpoint-label-v1: example_label -->\n```\n' > "$WORK/twice.md"
run_label "$WORK/twice.md"
expect "two markers are refused" 1 ""
expect_stderr "two markers" "$WORK/twice.md:3:"
expect_stderr "two markers" "$WORK/twice.md:6:"

printf '# Bin\n\n<!-- checkpoint-label-v1: abc -->\n\000\n' > "$WORK/nul.md"
run_label "$WORK/nul.md"
expect "a NUL byte does not turn the plan into a binary match" 0 abc

printf '# Later version\n\n<!-- checkpoint-label-v2: x -->\n' > "$WORK/v2.md"
run_label "$WORK/v2.md"
expect "another marker version is no marker" 3 later_version

printf '# Bullet\n\n- <!-- checkpoint-label-v1: x -->\n' > "$WORK/bullet.md"
run_label "$WORK/bullet.md"
expect "a marker that is not the whole line is no marker" 3 bullet

printf '# Windows\r\n\r\n<!-- checkpoint-label-v1: abc -->\r\n' > "$WORK/crlf.md"
run_label "$WORK/crlf.md"
expect "CRLF line endings" 0 abc

if [ "$(id -u)" -ne 0 ]; then
    printf '# Unreadable\n\n<!-- checkpoint-label-v1: x -->\n' > "$WORK/unreadable.md"
    chmod 000 "$WORK/unreadable.md"
    run_label "$WORK/unreadable.md"
    expect "unreadable plan is refused" 1 ""
else
    echo "SKIP: plan-label - unreadable plan: permission bits do not restrict the superuser"
fi

mkdir -p "$WORK/failing-grep"
printf '#!/bin/sh\nexit 2\n' > "$WORK/failing-grep/grep"
chmod +x "$WORK/failing-grep/grep"
printf '# My Work\n\n<!-- checkpoint-label-v1: real_label -->\n' > "$WORK/read-error.md"
got=$(PATH="$WORK/failing-grep:$PATH" bash "$PLAN_LABEL" "$WORK/read-error.md" 2>"$WORK/stderr")
status=$?
expect "a failed read is refused, not taken as no marker" 1 ""
expect_stderr "a failed read" "could not read plan"

run_label
expect "missing argument" 1 ""
expect_stderr "missing argument" "Usage"

run_label "$WORK/absent.md"
expect "plan not a file" 1 ""
expect_stderr "plan not a file" "$WORK/absent.md"

echo "PASS: plan-label"
