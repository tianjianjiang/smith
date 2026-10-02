#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
CENSUS="$HERE/../correction-census.mjs"

TMPD="$(mktemp -d)"
trap 'chmod -R u+rwx "$TMPD" 2>/dev/null; rm -rf "$TMPD"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

mkdir -p "$TMPD/projects/project-one" "$TMPD/projects/project-two"
printf 'not a session\n' > "$TMPD/projects/stray-file.txt"

printf '%s\n' \
  '{"type":"user","timestamp":"2026-01-01T00:00:01Z","origin":{"kind":"human"},"message":{"content":"SECRETWORD please fix the build"}}' \
  '{"type":"attachment","timestamp":"2026-01-01T00:00:02Z","attachment":{"type":"hook_additional_context","content":"Skill router: matches -> @smith-git and @smith-dev and @smith-clientname"}}' \
  '{"type":"assistant","timestamp":"2026-01-01T00:00:03Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"smith-git"}}]}}' \
  '{"type":"assistant","timestamp":"2026-01-01T00:00:04Z","message":{"content":[{"type":"text","text":"Fixed. I have not verified the second test."}]}}' \
  '{"type":"user","timestamp":"2026-01-01T00:00:05Z","origin":{"kind":"human"},"message":{"content":"no loose end, and use smith-review and smith-git"}}' \
  '{"type":"assistant","timestamp":"2026-01-01T00:00:06Z","message":{"content":[{"type":"text","text":"All checks pass."}]}}' \
  '{"type":"user","timestamp":"2026-01-01T00:00:07Z","origin":{"kind":"human"},"message":{"content":"why does the skill contain a date and a PR? remove them"}}' \
  '{"type":"user","timestamp":"2026-01-01T00:00:08Z","isMeta":true,"origin":{"kind":"human"},"message":{"content":"loose end in a meta message"}}' \
  '{"type":"user","timestamp":"2026-01-01T00:00:09Z","origin":{"kind":"task-notification"},"message":{"content":"<task-notification>loose end</task-notification>"}}' \
  '{"type":"user","timestamp":"2026-01-01T00:00:10Z","isSidechain":true,"origin":{"kind":"human"},"message":{"content":"loose end in a subagent"}}' \
  '{"type":"user","timestamp":"2026-01-01T00:00:11Z","message":{"content":[{"type":"tool_result","content":"loose end in a tool result"}]}}' \
  '{"type":"attachment","timestamp":"2026-01-01T00:00:12Z","attachment":{"type":"hook_additional_context","content":"Skill router: matches -> @smith-git"}}' \
  '{"type":"user","timestamp":"2026-01-01T00:00:13Z","origin":{"kind":"human"},"message":{"content":"again"}}' \
  '{"type":"assistant","timestamp":"2026-01-01T00:00:14Z","message":{"content":[{"type":"text","text":"Working on it."}]}}' \
  '{"type":"user","timestamp":"2026-01-01T00:00:15Z","origin":{"kind":"task-notification"},"message":{"content":"<task-notification>done</task-notification>"}}' \
  '{"type":"attachment","timestamp":"2026-01-01T00:00:16Z","attachment":{"type":"queued_command","commandMode":"prompt","origin":{"kind":"human"},"prompt":"again"}}' \
  '{"type":"attachment","timestamp":"2026-01-01T00:00:17Z","attachment":{"type":"hook_additional_context","content":"Skill router: matches -> @smith-dev"}}' \
  '{"type":"user","timestamp":"2026-01-01T00:00:18Z","origin":{"kind":"human"},"message":{"content":"fine"}}' \
  '{"type":"user","timestamp":"2026-01-01T00:00:19Z","message":{"content":[{"type":"tool_result","content":"output"}]}}' \
  '{"type":"attachment","timestamp":"2026-01-01T00:00:20Z","attachment":{"type":"hook_additional_context","content":"Skill router: matches -> @smith-dev"}}' \
  '{"type":"user","timestamp":"2026-01-01T00:00:21Z","origin":{"kind":"human"},"message":{"content":"ok then"}}' \
  '{"type":"attachment","timestamp":"2026-01-01T00:00:22Z","attachment":{"type":"queued_command","commandMode":"task-notification","origin":{"kind":"task-notification"},"prompt":"a task finished"}}' \
  '{"type":"attachment","timestamp":"2026-01-01T00:00:23Z","attachment":{"type":"hook_additional_context","content":"Skill router: matches -> @smith-dev"}}' \
  'this line is not JSON' \
  > "$TMPD/projects/project-one/session-a.jsonl"

printf '%s\n' \
  '{"type":"user","timestamp":"2026-02-01T00:00:01Z","promptSource":"sdk","entrypoint":"sdk-cli","message":{"content":"go"}}' \
  '{"type":"user","timestamp":"2026-02-01T00:00:02Z","promptSource":"sdk","entrypoint":"sdk-py","message":{"content":"Review this change for loose ends"}}' \
  '{"type":"user","timestamp":"2026-02-01T00:00:03Z","promptSource":"sdk","entrypoint":"sdk-cli","message":{"content":"Another Claude session says there is a loose end"}}' \
  '{"type":"user","timestamp":"2026-02-01T00:00:04Z","promptSource":"sdk","entrypoint":"sdk-cli","message":{"content":"go"}}' \
  > "$TMPD/projects/project-two/session-b.jsonl"

printf '%s\n' \
  '{"type":"assistant","timestamp":"2026-03-01T00:00:01Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"smith-tests"}}]}}' \
  '{"type":"user","timestamp":"2026-03-02T00:00:01Z","origin":{"kind":"human"},"message":{"content":"keep following smith-tests here"}}' \
  '{"type":"user","origin":{"kind":"human"},"message":{"content":"continue"}}' \
  '{"type":"assistant","timestamp":"2026-03-02T00:00:02Z","message":{"content":[{"type":"text","text":"Here is the chart."}]}}' \
  '{"type":"user","timestamp":"2026-03-02T00:00:03Z","origin":{"kind":"human"},"message":{"content":[{"type":"text","text":"SECRETWORD with an image"}]}}' \
  '{"type":"user","timestamp":"2026-03-02T00:00:04Z","origin":{"kind":"human"},"message":{"content":"thanks"}}' \
  > "$TMPD/projects/project-two/session-c.jsonl"

printf '%s\n' \
  '{"type":"user","origin":{"kind":"human"},"message":{"content":"an opening line without a timestamp"}}' \
  '{"type":"user","timestamp":"2026-04-01T00:00:01Z","origin":{"kind":"human"},"message":{"content":"a later line"}}' \
  '{"type":"assistant","timestamp":"2026-04-01T00:00:02Z","message":{"content":[{"type":"text","text":"Renamed the file."}]}}' \
  '{"type":"user","timestamp":"2026-04-01T00:00:03Z","origin":{"kind":"human"},"message":{"content":"/model"}}' \
  '{"type":"user","timestamp":"2026-04-01T00:00:04Z","origin":{"kind":"human"},"message":{"content":"good"}}' \
  > "$TMPD/projects/project-one/session-d.jsonl"

printf '%s\n' \
  '{"type":"assistant","timestamp":"2026-05-01T00:00:01Z","message":{"content":[{"type":"text","text":"I have not checked the logs."}]}}' \
  '{"type":"user","timestamp":"2026-05-02T00:00:01Z","origin":{"kind":"human"},"message":{"content":"that is a loose end"}}' \
  '{"type":"user","timestamp":"2026-05-03T00:00:01Z","origin":{"kind":"human"},"message":{"content":"/clear loose end"}}' \
  '{"type":"user","timestamp":"2026-05-03T00:00:02Z","origin":{"kind":"human"},"message":{"content":"<pasted>loose end</pasted>"}}' \
  > "$TMPD/projects/project-two/session-e.jsonl"

gap_turn() {
  printf '{"type":"assistant","timestamp":"2026-06-01T00:00:0%sZ","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$1" "$2"
  printf '{"type":"user","timestamp":"2026-06-01T00:00:0%sZ","origin":{"kind":"human"},"message":{"content":"ok"}}\n' "$1"
}
{
  gap_turn 1 'This is unverified.'
  gap_turn 2 'I did not verify the output.'
  gap_turn 3 'Should I check the other file?'
  gap_turn 4 '結果未驗證。'
  gap_turn 5 '尚未確認設定。'
  gap_turn 6 '要不要我再跑一次？'
  gap_turn 7 'Everything was verified.'
  printf '%s\n' \
    '{"type":"assistant","timestamp":"2026-06-01T00:00:08Z","message":{"content":[{"type":"text","text":"All done."}]}}' \
    '{"type":"user","timestamp":"2026-06-01T00:00:09Z","origin":{"kind":"human"},"message":{"content":"there is still a loose end"}}'
} > "$TMPD/projects/project-one/session-f.jsonl"

printf '%s\n' \
  '{"type":"attachment","timestamp":"2026-07-01T00:00:01Z","attachment":{"type":"queued_command","commandMode":"prompt","origin":{"kind":"human"},"prompt":"typed meanwhile: another loose end"}}' \
  '{"type":"attachment","timestamp":"2026-07-01T00:00:02Z","attachment":{"type":"queued_command","commandMode":"task-notification","origin":{"kind":"task-notification"},"prompt":"loose end reported by a task"}}' \
  '{"type":"attachment","timestamp":"2026-07-01T00:00:03Z","attachment":{"type":"queued_command","commandMode":"prompt","origin":{"kind":"peer"},"prompt":"loose end from a peer session"}}' \
  '{"type":"attachment","timestamp":"2026-07-01T00:00:04Z","attachment":{"type":"queued_command","commandMode":"prompt","origin":{"kind":"human"},"prompt":"sent once"}}' \
  '{"type":"user","timestamp":"2026-07-01T00:00:05Z","origin":{"kind":"human"},"message":{"content":"sent once"}}' \
  '{"type":"attachment","timestamp":"2026-07-01T00:00:06Z","attachment":{"type":"queued_command","commandMode":"prompt","origin":{"kind":"human"},"prompt":"side text"}}' \
  '{"type":"user","timestamp":"2026-07-01T00:00:07Z","isSidechain":true,"origin":{"kind":"human"},"message":{"content":"side text"}}' \
  > "$TMPD/projects/project-two/session-g.jsonl"

ln -s "$TMPD/nowhere" "$TMPD/projects/dangling-link"
UNREADABLE_ENTRIES=1
if [ "$(id -u)" = 0 ]; then
  echo "  SKIP locked directory (root reads regardless of mode)"
else
  mkdir "$TMPD/projects/locked-directory"
  chmod 000 "$TMPD/projects/locked-directory"
  UNREADABLE_ENTRIES=2
fi

value() { printf '%s' "$1" | jq -r "$2"; }
expect() {
  actual=$(value "$OUT" "$2")
  [ "$actual" = "$3" ] || fail "$1: expected $3, got $actual"
}

OUT=$(node "$CENSUS" --projects-dir "$TMPD/projects") || fail "census crashed"

expect "project directories" '.projectDirectories' 2
expect "session files" '.sessionFiles' 7
expect "owner-typed messages" '.ownerTypedMessages' 27
expect "a message typed while a turn ran is counted once, also when it repeats an earlier one or a subagent repeats it" '.ownerTypedWhileATurnRan' 3
expect "distinct owner-typed messages" '.distinctOwnerTypedMessages' 19
expect "sessions with owner messages" '.sessionsWithOwnerMessages' 7
expect "loose-end messages" '.corrections.looseEnd.messages' 4
expect "loose-end sessions" '.corrections.looseEnd.sessions' 4
expect "naming a loaded skill is not counted" '.corrections.namesUnloadedSkill.messages' 1
expect "unparsable lines are reported" '.excluded.unparsableLines' 1
expect "human messages without plain text are reported" '.excluded.humanMessagesWithBlockContent' 1
expect "without a window, an event before its session's first timestamp is not left out" '.excluded.eventsBeforeAnyTimestamp' 0
expect "entries that cannot be inspected or listed are reported" '.excluded.unreadableEntries' "$UNREADABLE_ENTRIES"
expect "human messages opening with markup or a slash are reported" '.excluded.humanMessagesOpeningWithMarkupOrSlash' 3
expect "text from other sources is reported" '.excluded.textMessagesFromOtherSources' 4
expect "suggestions of skills outside this repository are reported" '.excluded.routerSuggestionsOfUnknownSkills' 1
expect "a skill outside this repository is not named" '.routerBySkill | has("smith-clientname")' false
expect "point-in-time objection" '.corrections.pointInTimeInSkill.messages' 1
expect "turn-final messages followed by the owner: a command in between still counts, a mid-turn message or an image does not" '.turnFinal.followedByOwner' 12
expect "each pattern group of the declared-gap detector fires" '.turnFinal.declaredGap' 8
expect "loose-end replies after a declared gap" '.turnFinal.looseEndRepliesAfterDeclaredGap' 2
expect "loose-end replies to a turn-final message" '.turnFinal.looseEndReplies' 3
expect "router events" '.router.events' 5
expect "router events after an owner-typed prompt, not after a tool result or a queued notification" '.router.eventsAfterOwnerTyped' 2
expect "router suggestions, one per skill per event" '.router.suggestions' 7
expect "a suggestion of a skill already loaded is counted" '.router.suggestionsOfLoadedSkill' 1
expect "router suggested smith-git" '.routerBySkill["smith-git"].sessionsSuggested' 1
expect "smith-git then loaded" '.routerBySkill["smith-git"].ofThoseLoaded' 1
expect "smith-dev never loaded" '.routerBySkill["smith-dev"].ofThoseLoaded' 0

printf '%s' "$OUT" | grep -q 'SECRETWORD' && fail "output leaks message text"
printf '%s' "$OUT" | grep -q "$TMPD" && fail "output leaks a session path"

OUT=$(node "$CENSUS" --projects-dir "$TMPD/projects" --since 2026-02-01T00:00:00Z) || fail "census crashed with --since"
expect "window keeps only later messages" '.ownerTypedMessages' 19
expect "window drops earlier corrections" '.corrections.looseEnd.messages' 3
expect "window drops earlier router events" '.router.events' 0
expect "window drops earlier router suggestions" '.routerBySkill | length' 0
expect "an event before its session's first timestamp is left out and reported" '.excluded.eventsBeforeAnyTimestamp' 1

OUT=$(node "$CENSUS" --projects-dir "$TMPD/projects" --since 2026-03-01T12:00:00Z) || fail "census crashed with a window inside a session"
expect "an event without a timestamp takes the one before it" '.ownerTypedMessages' 17
expect "a skill loaded before the window still counts as loaded" '.corrections.namesUnloadedSkill.messages' 0

OUT=$(node "$CENSUS" --projects-dir "$TMPD/projects" --since 2026-05-01T12:00:00Z --until 2026-05-31T00:00:00Z) || fail "census crashed with both bounds"
expect "an assistant message before the window is still the one answered" '.turnFinal.followedByOwner' 1
expect "its declared gap is still seen" '.turnFinal.looseEndRepliesAfterDeclaredGap' 1

OUT=$(node "$CENSUS" --projects-dir "$TMPD/projects" --until 2026-01-31T00:00:00Z) || fail "census crashed with --until"
expect "window keeps only earlier messages" '.ownerTypedMessages' 7

OUT=$(node "$CENSUS" --projects-dir "$TMPD/projects" --until 2026-01-01T09:00:05+09:00) || fail "census crashed with an offset bound"
expect "a bound with an offset is compared as an instant" '.ownerTypedMessages' 2

node "$CENSUS" --projects-dir "$TMPD/projects" --since yesterday >/dev/null 2>&1 && fail "an unparsable bound must exit non-zero"
node "$CENSUS" --projects-dir "$TMPD/projects" --until >/dev/null 2>&1 && fail "a bound without a value must exit non-zero"
node "$CENSUS" --bogus >/dev/null 2>&1 && fail "unknown argument must exit non-zero"
ERR=$(node "$CENSUS" "$TMPD/projects" 2>&1 >/dev/null) && fail "a directory without its flag must exit non-zero"
printf '%s' "$ERR" | grep -q "$TMPD" && fail "an unknown argument must not be echoed"
ERR=$(node "$CENSUS" --projects-dir "$TMPD/missing" 2>&1 >/dev/null) && fail "missing directory must exit non-zero"
printf '%s' "$ERR" | grep -q "$TMPD" && fail "error output leaks a path"
[ -n "$ERR" ] || fail "missing directory must say why it failed"

echo "PASS: correction-census"
