# Context reset live evals

Recorded results of the live evals that check whether `/clear` can be sent to
Claude Code without a human typing it. Each record holds the tool versions, a
timestamp and the pass or fail of every check; raw streams and screens are not
kept, because they carry local paths.

Every eval here drives a live app or a logged-in `claude` command, and all
except the terminal identity eval call the Anthropic API, so each is skipped
unless `SMITH_LIVE_CONTEXT_RESET_EVAL=1` is set, and none is part of
`run-all.sh`.

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
- Optional parameter: `SMITH_PROBE_RECORD_LABEL` adds a label to the record's
  file name. `orca-clear-reset.outside-send.background-session.json` is the
  outside-send run against a session opened from agent view, which the Claude
  Code supervisor hosts and the terminal only displays; the `/clear` reset it
  too.

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

## Sync between a chat thread and the Claude Code command line

Checks whether a chat thread in T3 Code or in Orca and `claude --resume` on
the command line share one conversation. Unlike the evals above, this one
records observations: its checks only confirm that the probe ran, and the
`observations` block states which directions carried over.

- Script: `../chat-cli-sync.live-eval.mjs`
- Records: `chat-cli-sync.t3.json`, `chat-cli-sync.orca.json`
- Prerequisites: the host app running, a logged-in `claude` on `PATH`, and a
  folder the host already knows (a T3 Code project, or an Orca workspace).
- Replay, T3 Code:
  `SMITH_LIVE_CONTEXT_RESET_EVAL=1 SMITH_PROBE_SYNC_HOST=t3 SMITH_PROBE_SYNC_FOLDER=«project folder» node smith-ctx-claude/scripts/tests/chat-cli-sync.live-eval.mjs`
- Replay, Orca:
  `SMITH_LIVE_CONTEXT_RESET_EVAL=1 SMITH_PROBE_SYNC_HOST=orca SMITH_PROBE_SYNC_FOLDER=«workspace folder» SMITH_PROBE_ORCA_WORKTREE=«workspace selector» node smith-ctx-claude/scripts/tests/chat-cli-sync.live-eval.mjs`
- What it does: the chat is told a code word; the script finds the session
  file the chat wrote under the Claude Code configuration folder and resumes
  it with `claude -p --resume`, asking for the code word and adding a second
  one. For T3 Code it then reads the thread, asks the thread for the second
  code word while adding a third, and resumes from the command line once more
  to list every code word. For Orca it then searches Orca's session index for
  the second code word.
- Recorded result, T3 Code v0.1.9: the command line knows the chat's turns;
  the thread neither shows nor knows the command-line turn; after the thread's
  next turn the command-line turn is no longer part of the conversation the
  command line resumes.
- Recorded result, Orca 1.4.258: the command line knows the chat's turn, and
  the session index links the command-line turn to the same chat session.
- Manual part, Orca: the Orca command line cannot read or send to a chat tab.
  Type this in the chat tab after the script ran: "What is the second code
  word you were asked to remember? If you do not know, reply exactly
  UNKNOWN." Observed by hand on 2026-11-15; the Orca version at that moment
  was not read (1.4.256 earlier that night, 1.4.258 at the scripted run): the chat
  answered with the code word the command line had added; a later
  command-line resume still listed both code words; the chat tab drew a
  command-line turn, labelled "(Continued outside this chat)", only after a
  new message was sent from the tab, not on switching tabs or on resuming the
  session in a new tab.

## What a process in an Orca terminal knows about its terminal

Checks how a process started in an Orca terminal, such as a hook of a Claude
Code session, can learn that it runs there and which terminal is its own.

- Script: `../orca-terminal-identity.live-eval.mjs`
- Record: `orca-terminal-identity.json`
- Prerequisites: Orca running, and a folder Orca already knows as a workspace.
- Replay: `SMITH_LIVE_CONTEXT_RESET_EVAL=1 SMITH_PROBE_ORCA_WORKTREE=path:«workspace folder» node smith-ctx-claude/scripts/tests/orca-terminal-identity.live-eval.mjs`
- What it does: creates a terminal whose startup command writes the names of
  its `ORCA_` variables, the values of `ORCA_TERMINAL_HANDLE`, `ORCA_TAB_ID`
  and `ORCA_PANE_KEY`, and the reply of `orca terminal show` without a handle,
  then closes the terminal. Values of the other variables are not read,
  because one of them is a token.
- Passing output: `ORCA_TERMINAL_HANDLE` equals the handle Orca returned when
  it created the terminal, `ORCA_TAB_ID` equals its tab, `ORCA_PANE_KEY`
  starts with that tab, and the variables the Orca-installed hook tests are
  present.
- Recorded observations, Orca 1.4.258: `orca terminal show` without a handle
  named the terminal that was active before, not the terminal that called it,
  so it cannot stand in for `ORCA_TERMINAL_HANDLE`. The script itself was run
  from a Claude Code background job attached in an Orca terminal, and its
  process had no `ORCA_TERMINAL_HANDLE`.
- Optional parameter: `SMITH_PROBE_ORCA_SETTLE_TIMEOUT_MS`.

## Conditions around a reset in an Orca terminal session

Measures what a reset design must know about a Claude Code session started
directly in an Orca terminal: what the session's Stop hook can see, whether
the permission mode survives `/clear`, and what `/clear` does when text is
already typed in the input box.

- Script: `../orca-session-reset-conditions.live-eval.mjs`
- Hook fixture: `../fixtures/orca-report-hook-environment.sh`
- Record: `orca-session-reset-conditions.default-launch.json`
- Prerequisites: Orca running, a logged-in `claude` on `PATH`, a folder Orca
  knows as a workspace, and a folder Claude Code already trusts (a new folder
  shows a trust menu, which refuses sent input).
- Replay: `SMITH_LIVE_CONTEXT_RESET_EVAL=1 SMITH_PROBE_ORCA_WORKTREE=path:«workspace folder» SMITH_PROBE_SESSION_FOLDER=«trusted folder» node smith-ctx-claude/scripts/tests/orca-session-reset-conditions.live-eval.mjs`
- What it does: creates a terminal that starts Claude Code with a requested
  permission mode and a `--settings` file registering the hook fixture under
  `Stop`; the fixture writes the names of its `ORCA_` variables and the value
  of `ORCA_TERMINAL_HANDLE`. The script gives a code word, reads the
  permission mode from the screen, sends `/clear`, reads the mode again and
  asks for the code word. It then gives a second code word, types text
  without Enter, sends `/clear` on top of it, and asks again. The terminal is
  closed at the end.
- Passing output: the Stop hook's `ORCA_TERMINAL_HANDLE` is the session's own
  terminal, the plain `/clear` resets the session, and the permission mode
  shown is the same before and after the reset.
- Recorded observation, Orca 1.4.258 with Claude Code 2.1.325: `/clear` sent
  on top of half-typed text did not reset the session; Orca accepted the
  input, the session still recalled the code word, and the typed text was
  still on the screen. A reset sent this way must first deal with text in the
  input box.
- Not measured: a session started through a profile launcher
  (`SMITH_PROBE_CLAUDE_COMMAND` and `SMITH_PROBE_RECORD_NAME` exist for that
  run), and whether allowed tools survive the reset.
- Optional parameters: `SMITH_LIVE_CONTEXT_RESET_MODEL` (default `haiku`),
  `SMITH_PROBE_PERMISSION_MODE` (default `acceptEdits`),
  `SMITH_LIVE_CONTEXT_RESET_TURN_TIMEOUT_MS`.

## Which `claude` launch hosts the session in the terminal

With the `defaultToAgentsView` setting on, checks which ways of starting
`claude` in an Orca terminal make the terminal's own process host the
session. Such a process inherits the terminal's `ORCA_` variables; a session
opened from agent view runs under the Claude Code supervisor instead and has
none of them.

- Script: `../orca-launch-variants.live-eval.mjs`
- Record: `orca-launch-variants.json`
- Prerequisites: Orca running, a logged-in `claude` on `PATH`, a folder Orca
  knows as a workspace, and a folder Claude Code already trusts.
- Replay: `SMITH_LIVE_CONTEXT_RESET_EVAL=1 SMITH_PROBE_ORCA_WORKTREE=path:«workspace folder» SMITH_PROBE_SESSION_FOLDER=«trusted folder» node smith-ctx-claude/scripts/tests/orca-launch-variants.live-eval.mjs`
- What it does: starts `claude` in a new terminal once with no argument and
  once each with only `--model`, only `--permission-mode` and only
  `--settings`; finds the `claude` process whose environment names that
  terminal, reads whether it has child processes, and closes the terminal. No
  prompt is sent.
- Passing output: every launch with an argument shows the session banner and
  its process has child processes.
- Recorded observation, Orca 1.4.258 with Claude Code 2.1.325 and
  `defaultToAgentsView` on: the launch with no argument had no child process.
  The official page (https://code.claude.com/docs/en/agent-view) documents
  only a prompt argument as the way to a regular session while the setting is
  on; the flags are measured here, not documented there.

## A fresh background session dispatched by a Stop hook

Checks a reset that types into no terminal: the Stop hook of a background
session starts a new background session with `claude --bg`, and the new
session, which has a fresh context, continues from a file.

- Script: `../background-dispatch-fresh-session.live-eval.mjs`
- Hook fixture: `../fixtures/dispatch-background-session-on-stop.sh`
- Record: `background-dispatch-fresh-session.json`
- Prerequisites: Node.js, a logged-in `claude` on `PATH` with background
  sessions enabled, and a folder Claude Code already trusts.
- Replay: `SMITH_LIVE_CONTEXT_RESET_EVAL=1 SMITH_PROBE_SESSION_FOLDER=«trusted folder» node smith-ctx-claude/scripts/tests/background-dispatch-fresh-session.live-eval.mjs`
- What it does: starts a background session with a code word and a
  `--settings` file that registers the hook fixture under `Stop`. When that
  session's first turn ends, the fixture runs `claude --bg` with a prompt
  asking for the code word of the conversation and for a second code word
  written in a file. The script reads the new session's answer from its
  transcript, then stops and removes both sessions.
- Passing output: the hook dispatched a session with another id, and that
  session answered `UNKNOWN` for the conversation's code word and gave the
  code word from the file.
- Recorded observations, Claude Code 2.1.325: the hook ran inside a background
  job; a variable exported by the shell that started the first session did
  not reach its hook; the new session ran in the same folder; the first
  session stayed listed, in state `done`.
- Found while building it: `--add-dir` takes several values, so a prompt
  placed after it is read as one more folder and the session starts idle
  without a prompt; the fixture puts `--` before the prompt.
- Not measured: a session whose hooks come from the user settings instead of
  `--settings`, the permission mode of the new session, and what the first
  session should do after the dispatch.
- Optional parameters: `SMITH_LIVE_CONTEXT_RESET_MODEL` (default `haiku`),
  `SMITH_LIVE_CONTEXT_RESET_TURN_TIMEOUT_MS`.

## Automatic continuation at the critical threshold (end to end)

The acceptance eval of the opt-in automatic continuation in
`../../enforce-clear.sh` (`CTX_AUTO_RESET_DISPATCH=1`): a real background
session crosses a lowered threshold, writes a checkpoint flag, and must be
followed by a new session that restores the checkpoint with no input from
outside.

- Script: `../auto-context-reset.live-eval.mjs`
- Record: `auto-context-reset.json`
- Prerequisites: Node.js, a logged-in `claude` on `PATH` with background
  sessions enabled, and a folder Claude Code already trusts that is a Serena
  project or may hold a `.serena/memories` folder.
- Replay: `SMITH_LIVE_CONTEXT_RESET_EVAL=1 SMITH_PROBE_SESSION_FOLDER=«trusted folder» node smith-ctx-claude/scripts/tests/auto-context-reset.live-eval.mjs`
- What it does: writes a memory file with a random label and code word; starts
  a background session whose `--settings` file sets the switch, lowers the
  threshold, registers this checkout's `enforce-clear.sh` under `Stop`, and
  allows `write-reload-flag.sh`; the session is told to run that script when
  asked to checkpoint. The eval then only watches: for a session named after
  the label, and for its answer. A control run without the switch follows.
  Sessions, flags and the memory file are removed at the end.
- Passing output: the block reason names the background continuation; a
  session named `continue: «label»` with another id appears, reports the
  checkpoint's code word and does not know the first conversation's code
  word; the restore flag is consumed; the control dispatches nothing and
  shows today's reason.
- Limit: an installed copy of `enforce-clear.sh` in the user settings also
  blocks at the lowered threshold with today's reason, so the first session
  sees both reasons; the new reason's presence, and its absence in the
  control, is what tells the runs apart.
- Optional parameters: `SMITH_LIVE_CONTEXT_RESET_MODEL` (default `haiku`),
  `SMITH_LIVE_CONTEXT_RESET_TURN_TIMEOUT_MS`,
  `SMITH_LIVE_CONTEXT_RESET_CONTROL_WAIT_MS`.

## Integrity

`SHA256SUMS` lists the SHA-256 of each record. Check with
`shasum -a 256 -c SHA256SUMS` from this folder.
