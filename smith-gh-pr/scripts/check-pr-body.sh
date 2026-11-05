#!/bin/sh
if [ "$#" -ne 1 ] || [ ! -r "$1" ]; then
  echo "Usage: check-pr-body.sh «pr-body-file»" >&2
  exit 2
fi
awk '
  function missing(part) { print "MISSING: " part; bad = 1 }
  function duplicate(part, times) { print "DUPLICATE: " part " appears " times " times; it must appear once"; bad = 1 }
  function misplaced(part, where) { print "OUT OF ORDER: " part " must sit " where; bad = 1 }
  /^[[:space:]]*$/ { next }
  {
    count++
    kind = "text"
    if ($0 ~ /^Testing:[[:space:]]*[^[:space:]]/) kind = "testing"
    else if ($0 ~ /^Testing:/) kind = "empty_testing"
    else if ($0 ~ /^(How to revert:|\*\*How to revert\*\*:|\*\*How to revert:\*\*)[[:space:]]*[^[:space:]]/) kind = "revert"
    else if ($0 ~ /^(How to revert:|\*\*How to revert\*\*:|\*\*How to revert:\*\*)/) kind = "empty_revert"
    else if ($0 ~ /^Not touched:/) kind = "not_touched"
    else if ($0 ~ /^(Depends on|Blocks):/) kind = "depends"
    else if ($0 ~ /^Assisted-by:/) kind = "assisted"
    if (after_testing == "" && testing) { after_testing = kind; after_testing_line = NR }
    if (kind == "testing" && !testing) testing = count
    if (kind == "testing" || kind == "empty_testing") testing_count++
    if (kind == "revert" && !revert) revert = count
    if (kind == "revert" || kind == "empty_revert") revert_count++
    if (kind == "not_touched" && !not_touched) not_touched = count
    if (kind == "depends") { if (!depends) depends = count; last_depends = count }
    if (kind == "assisted") { assisted_count++; assisted = count }
    if (kind == "text" && !what_why) what_why = count
    last_kind = kind
  }
  END {
    if (!what_why || (testing && what_why > testing)) missing("What/Why text before the Testing: line")
    if (!testing && testing_count) missing("text after the \"Testing:\" label")
    else if (!testing) missing("a line starting \"Testing:\"")
    if (testing_count > 1) duplicate("Testing:", testing_count)
    if (!revert) missing("a \"How to revert:\" label with text after it")
    else if (testing && revert < testing) misplaced("How to revert", "after the Testing: line")
    if (revert_count > 1) duplicate("How to revert", revert_count)
    if (after_testing == "text")
      { print "EXTRA TEXT: Testing: is one line; line " after_testing_line " holds unlabelled text after it"; bad = 1 }
    else if (testing && revert > testing && after_testing != "revert")
      misplaced("How to revert", "directly after the Testing: line")
    if (!assisted_count) missing("a final line starting \"Assisted-by:\"")
    else if (assisted_count > 1) duplicate("Assisted-by:", assisted_count)
    if (assisted_count && last_kind != "assisted") misplaced("Assisted-by:", "on the last line")
    if (not_touched && ((what_why && not_touched < what_why) || (testing && not_touched > testing)))
      misplaced("Not touched:", "between What/Why and the Testing: line")
    if (depends && ((revert && depends < revert) || (!revert && testing && depends < testing) || (assisted && last_depends > assisted)))
      misplaced("Depends on: / Blocks:", "between How to revert and the Assisted-by: line")
    exit bad
  }
' < "$1"
