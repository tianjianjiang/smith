function strict(s) { return s ~ /^<a name="[a-z0-9]+(-[a-z0-9]+)*-v[0-9]+"><\/a>$/ }
function is_fence(s) { return s ~ /^[[:space:]]*(```|~~~)/ }
BEGIN { if (tab == "") tab = "\t" }
want == "question" || want == "description" {
  if (FNR == 1) { if ($0 != "---") exit; next }
  if ($0 == "---") exit
  if (want == "question") {
    if ($0 ~ /^metadata:[[:space:]]*$/) { meta = 1; next }
    if (meta && $0 ~ /^[^[:space:]]/) meta = 0
    if (meta && $0 ~ /^[[:space:]]+smith-question:/) {
      value = $0
      sub(/^[[:space:]]+smith-question:[[:space:]]*/, "", value)
      gsub(/["\047[:space:]]/, "", value)
      print value
      exit
    }
    next
  }
  if (in_description && $0 ~ /^[[:space:]]+[^[:space:]]/) { print; next }
  in_description = 0
  if ($0 ~ /^description:/) { print; in_description = 1 }
  next
}
want == "anchors" {
  if (!fence && pending != "") {
    if ($0 ~ /^#+ /) print "ANCHOR" tab file tab pending tab pline tab $0
    else print "PROBLEM" tab "anchor not directly above a heading: " file ":" pline
    pending = ""
  }
  if (is_fence($0)) { fence = !fence; previous = 0; next }
  if (fence) next
  if ($0 ~ /^## /) print "SECTION" tab file tab FNR tab (previous ? "anchored" : "bare")
  if ($0 ~ /^[[:space:]]*<a[[:space:]]/) {
    if (strict($0)) {
      label = $0
      sub(/^<a name="/, "", label)
      sub(/"><\/a>$/, "", label)
      pending = label
      pline = FNR
      previous = 1
      next
    }
    print "PROBLEM" tab "malformed anchor: " file ":" FNR
  }
  previous = 0
}
END { if (want == "anchors" && pending != "") print "PROBLEM" tab "anchor not directly above a heading: " file ":" pline }
