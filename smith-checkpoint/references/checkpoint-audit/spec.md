# Spec: Checkpoint audit, readback and backup

Source: `intent.md` in this directory.

## Audit (`scripts/audit-checkpoint.sh «body» [plan=«path»] [roots=«dir»[:«dir»…]]`)

Read-only. The body must be a readable regular file; otherwise it prints
`FAIL: body is not a readable file: «path»` and exits 1 with no summary.
For a readable body it prints one `FAIL:` or `WARN:` line per finding and
a closing `Audit: N failure(s), M warning(s)` line, and exits 1 on any
failure.

Search roots, in order, deduplicated by physical path: the current git
top level, the primary checkout, the plan file's directory, each `roots=`
directory, the current directory.

- **§A1 anchors (FAIL).** Every backticked `path:line` or
  `path:start-end` token, skipping URLs, `host:port` (no `.` or `/` in the
  path part) and `IP:port`. `~/` and absolute paths are used as written.
  A relative path resolves at the first root holding `root/path`; failing
  that, at the first git root whose tracked files end in `/path` or equal
  it. FAIL when nothing resolves, or when the last line is past the end of
  every candidate; line numbers are read as decimal, leading zeros
  included. WARN when more than one tracked file matches (the reader after
  `/clear` cannot tell which one is meant).
- **§A2 commits (FAIL).** A 7–40 character hex token after `commit` or
  `SHA` must resolve as a commit in some git root. When no root is a git
  repository the commit cannot be checked: WARN naming it, never a silent
  pass. Hex after `@` is not read as a commit (package pins, mail
  domains).
- **§A3 plan (WARN).** `plan=` names a missing file, or a file without a
  `# ` heading.
- **§A4 plan versus Next (WARN).** The plan has no `- [ ]` but the body's
  `## Next` is not empty, or the plan has `- [ ]` and the body's
  `## Next` is missing or empty.
- **§A5 sections (WARN).** Any of `## Completed`, `## Decisions`,
  `## Next`, `## Related` is missing. §A4 and §A5 match a heading the same
  way, trailing whitespace allowed.
- **§A6 placeholders (WARN).** `«…»`, `TODO` or `TBD` left in the body.

## Integration (`scripts/write-checkpoint.sh`)

- With `body=`, the audit runs after the argument, environment and project
  resolution checks (so a configuration error is reported first) and
  before relocation or any backend call; a failure, or a missing audit
  script, exits 1 with "nothing was written". `audit=skip` bypasses it;
  `plan=` (or, when it is omitted, the plan the ctx-claude plan-state
  file names) and `roots=` are forwarded.
- **Backup.** Before overwriting a backend, its prior document, when there
  is one, is written to
  `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/checkpoint-backups/«label»/«UTC time»-«pid»-«backend».md`.
  UTC names sort in time order to the second, so pruning keeps the newest
  5 per backend; it never removes the backup just written (so a backup
  that sorts outside the newest 5 leaves 6), and warns when a removal
  fails. A backup that cannot be written, or that is gone after pruning,
  aborts that backend's write.
- **Readback and restore.** After each backend write the document is read
  back. The first `## «timestamp»` line must be the new entry's, and the
  number of such lines must equal the prior count plus one. Each backend
  must also read back exactly the document written, leading and trailing
  newlines aside (only newline characters; a line holding spaces or tabs
  still counts): Serena's `memories read` prints the stored file with
  one extra trailing newline, and Basic-Memory's `read-note` returns the
  note body after its frontmatter verbatim, which can open with the blank
  line that separates the two.
- **Restore.** On a failed check, or when the write itself fails, the
  backup is written back and read again. The restore holds only when that
  write succeeded and the document read back equals the backup, leading
  and trailing newlines aside. With no backup (a label's first
  checkpoint) the document this checkpoint created is deleted instead:
  Serena with `memories delete «label»`, Basic-Memory with `tool
  delete-note «permalink»` using the permalink its write returned, and the
  removal is confirmed by reading it back (Basic-Memory by both permalink
  and title, since `delete-note` exits 0 on an identifier it cannot
  find). Basic-Memory is never deleted by title, since title lookup can
  resolve to a same-titled note in another project; without a permalink
  nothing is deleted and the message says so. The script exits 1 naming
  the backend and the outcome: "restored from «backup»", "restore failed;
  its prior document is preserved at «backup»" (that backup is renamed,
  when the rename succeeds, to `…-restore-failed.md` so pruning never
  removes it; a failed rename prints a warning to copy it), "the one this
  checkpoint created was removed", "removal … could not be confirmed",
  or, for Basic-Memory, "no permalink … nothing was deleted".
- **Both backends or neither.** A Serena failure never proceeds to
  Basic-Memory. Any Basic-Memory failure after Serena was written restores
  or removes Serena's document the same way, so a rerun does not leave a
  duplicate entry in Serena.
- The Reload block gains `- Audit: passed | skipped by audit=skip |
  not run (no body)`, `- Verified: serena N entries, basic-memory N
  entries`, and, when a backup was made, `- Prior documents backed up:
  «directory» (last 5 per backend kept)`.
