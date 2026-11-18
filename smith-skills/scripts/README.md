# Behaviour-eval runner

`behaviour-eval.mjs` runs the behaviour evals in a skill's `evals/` folder
with skillEd (https://github.com/DeadHead04/skillEd, a runner that drives an
agent command-line tool inside docker containers and judges what it did).
Each skill runs twice, once from `--source` and once from `--baseline`, so a
change is compared with the version before it.

## Prerequisites

- Node 24, git, the GitHub command-line tool `gh`, and `trash` on PATH
- Rancher Desktop with the moby engine; `docker` and `rdctl` on PATH
- No other container on the default bridge network while a run is active
- A vendor API key kept for evals only, exported as `ANTHROPIC_API_KEY`

## One command

```shell
ANTHROPIC_API_KEY=«key» node smith-skills/scripts/behaviour-eval.mjs --out «folder outside any git work tree» --source «ref with the change» --baseline «ref of the version before it» «skill»
```

`node smith-skills/scripts/behaviour-eval.mjs --help` lists every flag.

## Local wrapper

Keep the key out of shell history with a wrapper outside this repository,
for example `~/.local/bin/smith-behaviour-eval`. It only reads the key from
the macOS Keychain and fixes the output root:

```shell
#!/bin/sh
set -eu
PATH="$HOME/.rd/bin:$PATH"
export PATH
run_name=$1
shift
ANTHROPIC_API_KEY=$(security find-generic-password -s «keychain item» -w)
export ANTHROPIC_API_KEY
exec node «smith checkout»/smith-skills/scripts/behaviour-eval.mjs --out "${XDG_DATA_HOME:-$HOME/.local/share}/smith-evals/$run_name" "$@"
```

## What a run leaves in `--out`

- `arms.txt`: one line per skill and arm with the ref, its commit and the
  eval file
- `«skill»/«arm»/`: skillEd's raw output, never to be committed
- `egress-status.txt`, `egress-down.txt`: the firewall state at the end
- `leak-scan.txt`: the leak scan report; `LEAK-FOUND` appears on a hit
- `SHA256SUMS.txt`: hashes of every file above

`behaviour-eval-summary.mjs «out»` prints one record per case, arm and
iteration and evaluates the goal and regression rules per case. It refuses a
folder that is marked `LEAK-FOUND`, and a folder whose `leak-scan.txt` is
missing, says the scan did not complete, or holds any line other than a
root, a skip a clean scan writes, and the closing `files-read: yes`. A hit
in the `«out».work` folder alone is therefore refused too, although only
that folder carries the marker.

Without `--skilled`, the runner downloads skillEd with `gh` and runs it only
when the archive matches the SHA-256 pinned in `behaviour-eval.mjs` and the
release's own `.sha256` file and `checksums.txt`. An archive name with no
pinned value is refused; pass `--skilled` on such a host.

## Stopping a run

Each child runs in its own process group. The watchdog, after
`--iterations` times `--seconds-per-iteration` seconds, and a first SIGHUP,
SIGINT or SIGTERM send SIGTERM to that group and SIGKILL ten seconds later; a
second signal sends SIGKILL at once. Cleanup still runs: containers are
removed, egress is taken down and the leak scan runs. A total above
2147483 seconds, the longest timer Node.js keeps, is refused.

## On a leak-scan hit

Revoke the key in the vendor console first. The run folder is left
unchanged, marked and readable by its owner only; after revocation its
files are harmless evidence.

## Limits

- The firewall narrows accidental egress. It does not stop a process that
  encodes the key into DNS lookups or sends it to an allowed host.
- A runner stopped by SIGKILL runs no cleanup, and its children keep
  running, the paid skillEd run included; stop them by hand.
- A process that leaves its process group, for example by starting a new
  session, is not stopped. The runner stops waiting for it ten seconds
  after the child it started has exited.
- The leak scan finds the key raw, JSON-escaped or base64-encoded, not a
  key that was split or re-encoded on purpose.
