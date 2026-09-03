# Hooks Reference — smith-serena

Detailed behavior for the guard hook whose script lives under
`smith-serena/scripts/`. See the repo root `README.md` "Hooks" section for
the cross-skill summary table and registration overview.

## Overview

| Hook | Event (matcher) | Blocks / Advisory |
|---|---|---|
| `uv-tool-health-check.sh` | SessionStart (all sources) | Self-heals a broken `uv tool`-managed venv, reports what it did |

## uv-tool-health-check

**uv-tool-health-check** (`smith-serena/scripts/uv-tool-health-check.sh`) —
SessionStart hook (matcher `""`, all sources) that detects and self-heals a
broken `uv tool`-managed virtual environment.

**Root cause it works around**: `uv tool install` links a persistent venv to
a specific Python interpreter at install time. If that interpreter is later
upgraded or removed — a MacPorts point-upgrade, a pruned uv-managed Python
build, etc. — the venv's `bin/python3` symlink breaks and every entrypoint
fails with "bad interpreter". Verified 2026-08-27: `serena-hooks` failed
exactly this way on every `Read` call until a manual
`uv tool install serena-agent --reinstall`. This is an acknowledged,
closed-as-not-planned upstream limitation, not something `uv` will fix:
[astral-sh/uv#8514](https://github.com/astral-sh/uv/issues/8514) ("Tools
break (understandably) after upgrading system Python" — a user's proposed
`uv tool reinstall-all` was rejected as a duplicate),
[astral-sh/uv#7634](https://github.com/astral-sh/uv/issues/7634) ("uv tool
shouldn't use Python from homebrew version directories" — the same failure
class as this repo's MacPorts `Python.framework/Versions/3.12` path),
[astral-sh/uv#7651](https://github.com/astral-sh/uv/issues/7651),
[astral-sh/uv#8028](https://github.com/astral-sh/uv/issues/8028).

**Detection**: runs `uv tool list`, whose stderr prints a
`Broken symlink at \`.../tools/<name>/bin/python3\`` warning per broken tool
(exit code stays 0 either way — the warning is the only signal). Matches
that path against a small, deliberately narrow allowlist,
`MONITORED_TOOLS` (currently just `serena-agent`) — the tools this repo
actually depends on functioning, not every `uv tool` on the machine.
Broadening that list is a reviewed change, not something this hook should
decide unilaterally.

**Action**: for each monitored tool found broken, runs
`uv tool install <name> --reinstall` — the exact recovery command `uv`
itself prints in the warning's hint. Reports what happened via
`additionalContext`/`systemMessage`: which tools were healed, and — never
silently — which ones FAILED to reinstall (with the manual recovery command
to run by hand). Silent (no output) when nothing is broken, when `uv` isn't
installed, or when only a non-monitored tool is broken.

**Known limitation, accepted**: only guards the tools named in
`MONITORED_TOOLS`. A broken `ruff`/`headroom-ai`/etc. tool venv is not this
hook's concern (surfaces only via `uv tool list`'s own stderr warning, same
as before this hook existed).

Test suite: `smith-serena/scripts/tests/uv-tool-health-check.test.sh` (5
cases, using a fake `uv` on `PATH` to deterministically simulate healthy,
broken-and-healed, broken-and-failed, non-monitored-tool-broken, and
`uv`-not-installed states), run via `smith-serena/scripts/tests/run-all.sh`.
