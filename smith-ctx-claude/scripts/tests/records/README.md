# Context reset live evals

Recorded results of the live evals that check whether `/clear` can be sent to
Claude Code without a human typing it. Each record holds the tool versions, a
timestamp and the pass or fail of every check; raw streams and screens are not
kept, because they carry local paths.

Both evals call the Anthropic API through the logged-in `claude` command, so
they are skipped unless `SMITH_LIVE_CONTEXT_RESET_EVAL=1` is set, and they are
not part of `run-all.sh`.

## Host-sent `/clear` (stream-json)

- Script: `../host-clear-reset.live-eval.mjs`
- Record: `host-clear-reset.json`
- Prerequisites: Node.js, a logged-in `claude` on `PATH`.
- Replay: `SMITH_LIVE_CONTEXT_RESET_EVAL=1 node smith-ctx-claude/scripts/tests/host-clear-reset.live-eval.mjs`
- What it does: starts `claude -p --input-format stream-json` in an empty
  temporary folder with no tools and only an inline `SessionStart` hook. A
  control session is told a random code word and asked for it back. A second
  session is told a code word, sent `/clear` as a user turn, then asked.
- Passing output: the control recalls the code word, the cleared session does
  not, the `SessionStart` hook reports source `clear`, and the question turn of
  the cleared session reads fewer input tokens than the control's.
- Optional parameters: `SMITH_LIVE_CONTEXT_RESET_MODEL` (default `haiku`),
  `SMITH_LIVE_CONTEXT_RESET_TURN_TIMEOUT_MS`,
  `SMITH_LIVE_CONTEXT_RESET_CLEAR_SETTLE_MS`.

## `/clear` typed through Orca into an interactive session

Orca is a desktop app that manages agent terminals; its `orca terminal send`
command writes input into a live terminal (`orca terminal send --help`).

- Script: `../orca-clear-reset.live-eval.mjs`
- Hook fixture: `../fixtures/orca-stop-hook-clear.sh`
- Records: `orca-clear-reset.outside-send.json`, `orca-clear-reset.stop-hook.json`
- Prerequisites: Orca running, and an idle interactive Claude Code session in
  an Orca terminal whose handle is known (`orca terminal list --json`). Answer
  any trust or permission-mode menu by hand first.
- Replay, `/clear` sent by the script from outside the session:
  `SMITH_LIVE_CONTEXT_RESET_EVAL=1 SMITH_PROBE_TERMINAL=«handle» node smith-ctx-claude/scripts/tests/orca-clear-reset.live-eval.mjs`
- Replay, `/clear` sent by the session's own Stop hook: start the probed
  session with `SMITH_PROBE_ARM_FILE=«path»`, `SMITH_PROBE_TERMINAL=«handle»`
  and a `--settings` file that registers the hook fixture under `Stop`, then
  run the script with the same two variables and `SMITH_ORCA_RESET_VIA=stop-hook`.
- Set `ORCA_CLI_COMMAND` when `orca` is not on `PATH`.
- Passing output: every step reaches `tui-idle`, Orca accepts the `/clear`
  input, the code word is gone from the screen after the reset, and the
  session answers `UNKNOWN`.
- Limit: this eval has no session without `/clear`; the host eval above holds
  the control that shows the question does recall the code word.

## Fresh context in a T3 Code thread

T3 Code is a desktop and web interface for coding agents
(https://github.com/pingdotgg/t3code); it runs Claude through the Claude Agent
SDK in its own chat threads, and its `t3 thread` command talks to the running
server.

- Script: `../t3-fresh-context.live-eval.mjs`
- Record: `t3-fresh-context.json`
- Prerequisites: the T3 Code server running, `t3` on `PATH`, a Claude provider
  signed in, and a project added with `t3 project add «path»`.
- Replay: `SMITH_LIVE_CONTEXT_RESET_EVAL=1 SMITH_PROBE_T3_PROJECT=«project id» node smith-ctx-claude/scripts/tests/t3-fresh-context.live-eval.mjs`
- What it does: starts a thread with a random code word and asks for it back
  as the control; sends `/clear` with `t3 thread send` and asks again; then
  gives a second code word and tells the thread's own agent to call its
  `t3_thread_send` tool on the same thread with `freshContext` set to true and
  the question as the message.
- Passing output: the control recalls the code word, the answer after the
  command-line `/clear` is `UNKNOWN`, the agent has the send tool, the
  self-sent question arrives as a new turn, and its answer is `UNKNOWN`.
- Optional parameters: `SMITH_PROBE_T3_PROVIDER` (default `claudeAgent`),
  `SMITH_PROBE_T3_MODEL` (default `claude-haiku-5-5`),
  `SMITH_PROBE_T3_SELF_SEND_SETTLE_MS`.

## Integrity

`SHA256SUMS` lists the SHA-256 of each record. Check with
`shasum -a 256 -c SHA256SUMS` from this folder.
