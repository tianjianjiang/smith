# Plan: Checkpoint audit and readback

Source: `spec.md` in this directory.

## Files

- New `smith-checkpoint/scripts/audit-checkpoint.sh` (§A1–§A6).
- New `smith-checkpoint/scripts/tests/audit-checkpoint.test.sh`: a fixture
  repository holding the files the SKILL.md example body names, so the
  example passes with bare file names; one case per check.
- `smith-checkpoint/scripts/write-checkpoint.sh`: `run_audit` after
  project resolution and before any backend call; `backup_prior`,
  `verify_readback` and `restore_serena` / `restore_basic_memory` around
  each write (with no backup, the created document is deleted: Serena by
  label, Basic-Memory only by the permalink its write returned);
  `verify_exact_readback` for both backends (leading and trailing
  newlines aside); `fail_basic_memory_write` rolls Serena back; three
  Reload block lines.
- `smith-checkpoint/scripts/tests/write-checkpoint.test.sh`: the shim gains
  per-backend `SERENA_WRITE_DROPS_HISTORY` / `BM_WRITE_DROPS_HISTORY`
  (`once` loses history on the first write only, so a restore succeeds;
  `always` on every write, so a restore of more than one entry fails);
  cases also cover an unwritable backup aborting before any write, and a
  Basic-Memory failure rolling Serena back to its exact prior document;
  new cases for audit abort with no backend touched, `audit=skip`, a passing
  audit, `plan=` and `roots=` forwarding, readback counts, backups and
  their pruning, each backend's restore, and an unrestorable loss that
  names the preserved backup. Two reads per checkpoint become four.
- New `smith-checkpoint/scripts/tests/run-all.sh` running both suites, as
  other skills' runners do.
- `smith-checkpoint/SKILL.md`: "Audit before writing" Procedure step,
  `audit=` and `roots=` arguments, backup, readback and restore in the
  success criteria.

## Risks

- §A2 reads hex only after `commit` or `SHA`; prose like "commit
  deadbeef0" that is not a commit fails inside git and names the token, so
  the fix is one edit.
- Readback adds one read per backend per checkpoint. On failure only, a
  restore adds one write and one read; a first-checkpoint removal adds
  one delete and one read (two for Basic-Memory, by permalink and by
  title).
- Backups hold prior checkpoint text under the config directory, pruned to
  the newest 5 per label and backend.
