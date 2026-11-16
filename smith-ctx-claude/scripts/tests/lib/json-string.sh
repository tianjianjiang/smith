json_string() {
  printf '%s.' "$1" | awk '
    BEGIN {
      for (i = 1; i < 32; i++) {
        control[i] = sprintf("%c", i)
        escaped[i] = sprintf("\\u%04x", i)
      }
      escaped[8] = "\\b"; escaped[9] = "\\t"; escaped[12] = "\\f"; escaped[13] = "\\r"
    }
    {
      line = $0
      gsub(/\\/, "\\\\", line)
      gsub(/"/, "\\\"", line)
      for (i = 1; i < 32; i++) if (index(line, control[i])) gsub(control[i], escaped[i], line)
      text = text (NR > 1 ? "\\n" : "") line
    }
    END { printf "\"%s\"", substr(text, 1, length(text) - 1) }
  '
}
