#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
AUDIT="$HERE/../audit-checkpoint.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

lines() { awk -v n="$2" 'BEGIN { for (i = 1; i <= n; i++) print "line " i }' > "$1"; }

REPO="$WORK/repo"
mkdir -p "$REPO/src/auth" "$REPO/docs/a" "$REPO/docs/b"
lines "$REPO/src/auth/auth.ts" 600
lines "$REPO/src/auth/refresh.ts" 200
lines "$REPO/SECURITY.md" 50
lines "$REPO/docs/a/notes.md" 10
lines "$REPO/docs/b/notes.md" 10
git -C "$REPO" init -q
git -C "$REPO" add -A
git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -qm init
SHA=$(git -C "$REPO" rev-parse --short HEAD)

PLANS="$WORK/plans"
mkdir -p "$PLANS"
PLAN="$PLANS/plan.md"
{ echo "# Auth plan"; echo; echo "- [x] done"; echo "- [ ] rate limiting"; lines /dev/stdout 300; } > "$PLAN"
DONE_PLAN="$PLANS/done.md"
printf '# Done plan\n\n- [x] all done\n' > "$DONE_PLAN"

OTHER="$WORK/other-repo"
mkdir -p "$OTHER"
lines "$OTHER/elsewhere.sh" 40

run_audit() { (cd "$REPO" && sh -c '"$0" "$@"' "$AUDIT" "$@"); }

EXAMPLE="$WORK/example.md"
cat > "$EXAMPLE" <<EOF
## Completed
- [x] OAuth flow impl (\`auth.ts:234-567\`)
- [x] Token refresh logic (\`refresh.ts:89-156\`)

## Decisions
- Use JWT with 1h TTL (security requirement from \`SECURITY.md:45\`)

## Next
Implement rate limiting (\`plan.md:121-145\`)

## Related
- commit $SHA
- PR #789 (awaiting review)
EOF
out=$(run_audit "$EXAMPLE" "plan=$PLAN") || fail "A1: the SKILL.md example body (bare file names, plan-relative anchor) must pass: $out"
echo "$out" | grep -q '^Audit: 0 failure(s), 0 warning(s)$' || fail "A1: example body must be clean: $out"

STALE="$WORK/stale.md"
printf '## Completed\n- x (`auth.ts:601`)\n' > "$STALE"
out=$(run_audit "$STALE") && fail "A1: a line past the end of the file must fail: $out"
echo "$out" | grep -qF 'FAIL: anchor `auth.ts:601`: line 601 is past the end of' || fail "A1: stale anchor must be named: $out"
echo "$out" | grep -qF "$REPO/src/auth/auth.ts" || fail "A1: stale anchor message must name the resolved file: $out"

MISSING="$WORK/missing.md"
printf '## Completed\n- x (`nope/gone.sh:3`)\n' > "$MISSING"
out=$(run_audit "$MISSING") && fail "A1: an anchor to no file must fail: $out"
echo "$out" | grep -qF 'FAIL: anchor `nope/gone.sh:3`: no file `nope/gone.sh` under' || fail "A1: missing anchor must be named: $out"
echo "$out" | grep -qF 'pass roots=«dir»' || fail "A1: missing anchor must say how to fix it: $out"

CROSS="$WORK/cross.md"
printf '## Completed\n- x (`elsewhere.sh:40`)\n' > "$CROSS"
run_audit "$CROSS" >/dev/null && fail "A1: a file in another repository is not found without roots="
out=$(run_audit "$CROSS" "roots=$OTHER") || fail "A1: roots= must resolve a file in another repository: $out"

ABS="$WORK/abs.md"
printf '## Completed\n- x (`%s:5`)\n- y (`~/%s:1`)\n' "$OTHER/elsewhere.sh" "$(basename "$WORK")/plans/done.md" > "$ABS"
out=$(cd "$REPO" && HOME="$(dirname "$WORK")" "$AUDIT" "$ABS") || fail "A1: absolute and ~/ anchors must resolve directly: $out"

AMBIG="$WORK/ambig.md"
printf '## Completed\n- x (`notes.md:3`)\n' > "$AMBIG"
out=$(run_audit "$AMBIG") || fail "A1: an ambiguous anchor that fits is a warning, not a failure: $out"
echo "$out" | grep -qF 'WARN: anchor `notes.md:3` is ambiguous: 2 tracked files end in `notes.md`' || fail "A1: ambiguous anchor must be warned: $out"
QUALIFIED="$WORK/qualified.md"
printf '## Completed\n- x (`a/notes.md:3`)\n' > "$QUALIFIED"
out=$(run_audit "$QUALIFIED") || fail "A1: a qualified path suffix must resolve: $out"
echo "$out" | grep -q 'ambiguous' && fail "A1: a unique path suffix is not ambiguous: $out"

NOTFILES="$WORK/notfiles.md"
printf '## Completed\n- `https://example.com:443` `localhost:8080` `127.0.0.1:80` `memory_name`\n' > "$NOTFILES"
out=$(run_audit "$NOTFILES") || fail "A1: URLs, host:port and IP:port are not file anchors: $out"

COMMITS="$WORK/commits.md"
printf '## Completed\n- commit %s\n- commit deadbeef0\n' "$SHA" > "$COMMITS"
out=$(run_audit "$COMMITS") && fail "A2: an unresolvable commit must fail: $out"
echo "$out" | grep -qF 'FAIL: commit `deadbeef0` does not resolve' || fail "A2: bad commit must be named: $out"
echo "$out" | grep -qF "\`$SHA\`" && fail "A2: a real commit must not be reported: $out"
out=$(cd "$WORK" && "$AUDIT" "$COMMITS" 2>&1) || fail "A2: outside git, an unverifiable commit is a warning, not a failure: $out"
echo "$out" | grep -qF 'WARN: commit `deadbeef0` was not verified: no git repository among the roots searched' || fail "A2: outside git, an unverifiable commit must be warned, never passed silently: $out"
out=$(cd "$WORK" && "$AUDIT" "$COMMITS" "roots=$REPO" 2>&1) && fail "A2: roots= must make the commit check run outside git: $out"
ATSIGN="$WORK/atsign.md"
printf '## Completed\n- pinned pkg@1234567 and mail ops@deadbeefcafe.example\n' > "$ATSIGN"
out=$(run_audit "$ATSIGN") || fail "A2: hex after @ is not a commit reference: $out"

LEADZERO="$WORK/leadzero.md"
printf '## Completed\n- x (`SECURITY.md:08`)\n- y (`SECURITY.md:09-0050`)\n' > "$LEADZERO"
out=$(run_audit "$LEADZERO") || fail "A1: line numbers with leading zeros are decimal: $out"
STALEZERO="$WORK/stalezero.md"
printf '## Completed\n- x (`SECURITY.md:051`)\n' > "$STALEZERO"
out=$(run_audit "$STALEZERO") && fail "A1: a leading-zero line past the end must still fail: $out"
echo "$out" | grep -qF 'line 51 is past the end' || fail "A1: a leading-zero stale line must be reported in decimal: $out"

out=$(run_audit "$WORK") && fail "a directory is not a body file: $out"
echo "$out" | grep -qF "FAIL: body is not a readable file: $WORK" || fail "a directory body must be named: $out"

NOPLANBODY="$WORK/noplanbody.md"
printf '## Completed\n- x (`auth.ts:1`)\n' > "$NOPLANBODY"
out=$(run_audit "$NOPLANBODY" "plan=$WORK/no-such-plan.md") || fail "A3: a missing plan file stays a warning so a checkpoint is never lost to it: $out"
echo "$out" | grep -qF "WARN: plan file not found: $WORK/no-such-plan.md" || fail "A3: missing plan must be warned: $out"
NOHEAD="$PLANS/nohead.md"
printf -- '- [ ] task\n' > "$NOHEAD"
out=$(run_audit "$EXAMPLE" "plan=$NOHEAD") || fail "A3: a plan without heading is a warning: $out"
echo "$out" | grep -qF "WARN: plan file has no '# ' heading" || fail "A3: headingless plan must be warned: $out"

out=$(run_audit "$EXAMPLE" "plan=$DONE_PLAN") || fail "A4: plan mismatch is a warning: $out"
echo "$out" | grep -qF "WARN: plan has no open '- [ ]' task but the body's '## Next' is not empty" || fail "A4: finished plan with Next items must be warned: $out"
NONEXT="$WORK/nonext.md"
printf '## Completed\n- x\n\n## Decisions\n- y\n\n## Related\n- z\n' > "$NONEXT"
out=$(run_audit "$NONEXT" "plan=$PLAN") || fail "A4: plan mismatch is a warning: $out"
echo "$out" | grep -qF "WARN: plan has 1 open '- [ ]' task(s) but the body's '## Next' is missing or empty" || fail "A4: open plan without Next must be warned: $out"
EMPTYNEXT="$WORK/emptynext.md"
printf '## Completed\n- x\n\n## Decisions\n- y\n\n## Next \n\n## Related\n- z\n' > "$EMPTYNEXT"
out=$(run_audit "$EMPTYNEXT" "plan=$PLAN") || fail "A4: empty Next is a warning: $out"
echo "$out" | grep -qF "'## Next' is missing or empty" || fail "A4: an empty Next section must be warned like a missing one: $out"
echo "$out" | grep -qF "body has no '## Next' section" && fail "A5: a '## Next ' heading with trailing space is present, not missing: $out"

out=$(run_audit "$NONEXT")
echo "$out" | grep -qF "WARN: body has no '## Next' section" || fail "A5: missing section must be warned: $out"

PLACEHOLDER="$WORK/placeholder.md"
printf '## Completed\n- x\n\n## Decisions\n- «decision»\n\n## Next\n- TODO fill\n\n## Related\n- z\n' > "$PLACEHOLDER"
out=$(run_audit "$PLACEHOLDER") || fail "A6: placeholders are a warning: $out"
echo "$out" | grep -qF 'WARN: body still holds a placeholder or TODO/TBD: 5:- «decision» 8:- TODO fill' || fail "A6: placeholders must be listed with line numbers: $out"

echo "PASS: audit-checkpoint"
