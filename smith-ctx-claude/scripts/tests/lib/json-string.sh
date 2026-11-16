json_string() {
  printf '%s.' "$1" | awk '
    BEGIN {
      for (i = 1; i < 32; i++) escaped[sprintf("%c", i)] = sprintf("\\u%04x", i)
      escaped[sprintf("%c", 8)] = "\\b"
      escaped[sprintf("%c", 9)] = "\\t"
      escaped[sprintf("%c", 12)] = "\\f"
      escaped[sprintf("%c", 13)] = "\\r"
      escaped["\\"] = "\\\\"
      escaped["\""] = "\\\""
    }
    {
      line = ""
      for (i = 1; i <= length($0); i++) {
        character = substr($0, i, 1)
        line = line ((character in escaped) ? escaped[character] : character)
      }
      text = text (NR > 1 ? "\\n" : "") line
    }
    END { printf "\"%s\"", substr(text, 1, length(text) - 1) }
  '
}
