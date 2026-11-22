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
- Not measured here: the permission mode of the new session, and what the
  first session should do after the dispatch. A hook that comes from the
  user settings instead of `--settings` is measured in "Conditions of the
  automatic continuation" below.
- Optional parameters: `SMITH_LIVE_CONTEXT_RESET_MODEL` (default `haiku`),
  `SMITH_LIVE_CONTEXT_RESET_TURN_TIMEOUT_MS`,
  `SMITH_LIVE_CONTEXT_RESET_COMMAND_TIMEOUT_MS` (limit of one `claude` call).

## Automatic continuation at the critical threshold (end to end)

The acceptance eval of the automatic continuation of background sessions in
`../../enforce-clear.sh` (on by default; `CTX_AUTO_RESET_DISPATCH=0` turns it
off): a real background
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
  a background session whose `--settings` file leaves the switch unset, lowers
  the threshold, registers this checkout's `enforce-clear.sh` under `Stop`, and
  allows `write-reload-flag.sh`; the session is told to run that script when
  asked to checkpoint. The eval then only watches: for a session named after
  the label, and for its answer. A control run with the switch set to `0`
  follows.
  Sessions, flags and the memory file are removed at the end.
- Passing output: a `stop_hook_summary` of the first session holds an error
  starting with `[SMITH_CTX_AUTO_RESET_BLOCKED] `; a
  session whose name holds «label» appears with another id, reports the
  checkpoint's code word and does not know the first conversation's code
  word; the restore flag is consumed; the control dispatches nothing and
  shows today's reason, with no code. The record's observation
  `ranInTheDefaultProfile` says whether the eval used `~/.claude`.
- The record names the checkout as it was when the eval started:
  `commit`, `treeIsDirty` (whether `git status --porcelain` listed
  anything, `null` when git could not read the tree), and `hookSha256`,
  the SHA-256 of `enforce-clear.sh` alone, so a change to a file it
  sources shows only in `treeIsDirty`; `commit` and `hookSha256` are
  `unknown` when they could not be read, and the run then fails before
  any session starts.
- Only this checkout's copy of the hook answers the stops of the sessions
  the eval starts: they are started with `--setting-sources project,local`,
  which leaves out the user settings and with them an installed copy of
  `enforce-clear.sh`, so a changed hook can be evaluated before it is
  installed. This holds only when the trusted folder's own project and local
  settings register no `enforce-clear.sh`; those two sources are still
  loaded. The eval does not check this: the observation
  `firstSessionTranscriptAlsoHoldsTheUnchangedReason` shows only a copy
  without the dispatch step that also answered, and a copy with the
  dispatch step is not told apart. The new session is started by the hook without that option and
  loads the user settings again. This checkout's hook registered in user
  settings is measured in "Conditions of the automatic continuation"
  below.
- The recorded run of 2026-11-17 ran in the eval profile of that section
  (`CLAUDE_CONFIG_DIR` set to it, `SMITH_PROBE_SESSION_FOLDER` a new folder
  under its `probes`); each Stop hook record of the first session lists one
  hook, although that profile's user settings register this checkout's
  copy too.
- Optional parameters: `SMITH_LIVE_CONTEXT_RESET_MODEL` (default `haiku`),
  `SMITH_LIVE_CONTEXT_RESET_TURN_TIMEOUT_MS`,
  `SMITH_LIVE_CONTEXT_RESET_CONTROL_WAIT_MS`,
  `SMITH_LIVE_CONTEXT_RESET_COMMAND_TIMEOUT_MS` (limit of one `claude` call).

## A Stop hook block as Claude Code writes it in the transcript

The transcript format is not documented
(https://code.claude.com/docs/en/hooks says only that the file "is written
asynchronously and may lag the in-memory conversation"), so
`../../enforce-clear.sh` reads its own earlier block from a recorded shape:
the `stop_hook_summary` entry, or the `hook_blocking_error` attachment of
the same `toolUseID` when the summary was skipped
(https://github.com/anthropics/claude-code/issues/74648).

- Records: `stop-hook-summary.claude-code-2.1.325.jsonl` and
  `hook-blocking-error.claude-code-2.1.325.jsonl`, the first
  `stop_hook_summary` entry and the `hook_blocking_error` attachment of the
  same Stop batch of a real background session on Claude Code 2.1.325,
  taken from a run of the conditions eval below (its folder is
  `probes/zq-run-…/zq-probe-…`), with the home folder replaced by
  `/Users/example`. Their reason predates the
  `[SMITH_CTX_AUTO_RESET_BLOCKED]` code.
- Used by: `../enforce-clear-dispatch.test.sh`, which reads each sample as
  recorded and with the coded reason.
- Refresh after a Claude Code upgrade: run the end-to-end eval above; its check
  `blockRecordedInAStopHookSummaryWithItsCode` fails when the entry changes
  shape. Then copy the new entry with the home folder replaced, under the new
  version's name.

## Conditions of the automatic continuation

Measures these conditions of the version under test, with the hook of this
checkout registered in user settings (not a `--settings` file): a session
is continued after its checkpoint, and a refused launch starts nothing and
keeps the checkpoint. How the model checkpoints and what a restore returns
are not measured here.

- Script: `../auto-context-reset-conditions.live-eval.mjs`
- Record: `auto-context-reset-conditions.json`
- Prerequisites: Node.js, `claude` with background sessions enabled,
  `basic-memory` 1.0 or later, `uvx`, and an eval profile set up once. The
  eval profile is a Claude Code configuration folder of its own
  (`~/.claude-smith-eval`, or `SMITH_EVAL_CONFIG_DIR`), logged in with the
  same account and trusting its `probes` folder:
  `mkdir -p ~/.claude-smith-eval/probes && cd ~/.claude-smith-eval/probes && CLAUDE_CONFIG_DIR=~/.claude-smith-eval command claude`,
  then `/login`, accept the folder trust prompt, and `/exit`. A shell
  function named `claude` that unsets `CLAUDE_CONFIG_DIR` would log the
  default profile in instead; `command claude` bypasses it. The login is
  kept per configuration folder, so it survives later runs.
- Replay: `SMITH_LIVE_CONTEXT_RESET_EVAL=1 node smith-ctx-claude/scripts/tests/auto-context-reset-conditions.live-eval.mjs`
- What it does: every `claude` call runs with `CLAUDE_CONFIG_DIR` set to
  the eval profile, so its sessions, background supervisor, transcripts,
  flags (`plans`) and checkpoint backups stay in that folder. Each run
  links the profile's `skills` to this checkout and writes its
  `settings.json`: the Stop hook is this checkout's `enforce-clear.sh`
  through that link, the allow rules are the default profile's with its
  folder replaced by the eval profile's, and without the allow rules that
  still name the installed copy; each deny rule is kept and also copied
  with the folder replaced; a rule keeps the way it writes the folder
  (`~/.claude`, `$HOME/.claude`, an absolute path); the `ask` rules are
  not copied, and `SERENA_HOME` points at
  the run's own folder. Each measurement starts one background session in
  a new folder under `probes`, outside any repository; the folder lowers
  the threshold, is a Serena project of that `SERENA_HOME`, and names a
  temporary Basic-Memory project (`zq-eval-«id»`) registered for the run.
  The session runs the real `/smith-checkpoint` with no instruction added.
  - Continuation: the eval waits for a second session in the folder and
    reads the hook's restore prompt from its transcript, then stops it.
  - Refused launch: after the first session has started, the eval adds
    `CLAUDE_CODE_DISABLE_AGENT_VIEW` to the folder's settings, so the
    hook's `claude --bg` is refused.
  At the end the sessions, flags, the run folder and the Basic-Memory
  project are removed; the transcripts in the profile's `projects` are
  kept. A run that is interrupted removes nothing: stop and remove the
  eval profile's sessions with `CLAUDE_CONFIG_DIR=~/.claude-smith-eval
  claude stop` and `claude rm`, delete the `zq-run-` folder under
  `probes`, remove the `zq-eval-` project with `basic-memory project
  remove`, and delete the flag files in the profile's `plans`.
- Passing output: the eval profile is logged in, uses its own folder,
  which is not the home folder, above it or inside `~/.claude`, and
  trusts `probes`, and neither its `settings.json` nor its `plans` folder
  is a symbolic link, since the eval writes and deletes there; its skills are this checkout, its Stop hook is this
  checkout's with the dispatch step, and no allow rule names the
  installed copy; a Stop hook record of the first session holds an error
  starting with `[SMITH_CTX_AUTO_RESET_BLOCKED] `, its checkpoint is a
  memory of the folder's Serena project, and a second session in the
  folder starts with the hook's restore prompt. With the launch refused, no
  other session appears, the restore flag stays, the attempt is recorded,
  and a Stop hook notice of the first session, recorded as an attachment
  of type `hook_system_message`, starts with `[SMITH_CTX_DISPATCH_FAILED] `
  and names the switch. The hook's texts
  are matched by these codes, never by their wording.
  No probe session ran a command on a path of the installed copy
  (the `.claude` or `.smith` folder in the home folder, written with `~`, `$HOME`,
  `${HOME}` or the home path), no flag of the runner's own profile
  names the run folder, and the Basic-Memory project is no longer listed.
- A run fails, and is rerun, when a probe session types a path of the
  installed copy itself (`$HOME/.claude/skills/...`) instead of the
  skill's `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`: the check reads the
  command text, which cannot tell a listing from an execution. The
  default inside `${CLAUDE_CONFIG_DIR:-…}` is not read, in commands and
  in allow rules alike, since the eval always sets `CLAUDE_CONFIG_DIR`;
  it is read in a command that runs `env` or `unset`, or names
  `CLAUDE_CONFIG_DIR` outside such a default.
- Seen and not explained: in one run the hook after the checkpoint
  printed nothing and no second session started, while a later run with
  the same settings, and a run of the hook under a shell trace, continued
  the session.
- The record names the Serena version that `uvx` resolved
  (`serenaVersion`, `unknown` when `uvx` fails or prints no version); the
  eval takes the same unpinned Serena that
  `smith-checkpoint/scripts/write-checkpoint.sh` runs, so the probe
  projects match what the checkpoint writes into.
- The record names the checkout as it was when the eval started:
  `commit`, `treeIsDirty` (whether `git status --porcelain` listed
  anything, `null` when git could not read the tree), and `hookSha256`,
  the SHA-256 of `enforce-clear.sh` alone, so a change to a file it
  sources shows only in `treeIsDirty`; `commit` and `hookSha256` are
  `unknown` when they could not be read, and the run then fails before
  any session starts.
- Optional parameters: `SMITH_EVAL_CONFIG_DIR`,
  `SMITH_LIVE_CONTEXT_RESET_MODEL` (default `haiku`),
  `SMITH_LIVE_CONTEXT_RESET_TURN_TIMEOUT_MS`,
  `SMITH_LIVE_CONTEXT_RESET_CONTROL_WAIT_MS`,
  `SMITH_LIVE_CONTEXT_RESET_COMMAND_TIMEOUT_MS` (limit of one `claude` call).

## What a Stop hook receives about background tasks

- Script: `../stop-background-tasks.probe.sh`
- Record: `stop-background-tasks.json`
- Prerequisites: `jq`, `timeout`, a logged-in `claude` on `PATH`.
- Replay: `smith-ctx-claude/scripts/tests/stop-background-tasks.probe.sh smith-ctx-claude/scripts/tests/records/stop-background-tasks.json`
- What it does: runs one headless haiku session in a fresh temporary folder
  with an inline Stop hook that saves its input, and asks the session to start
  a background shell task and reply at once.
- Passing output: every saved Stop input has `has_background_tasks` true; the
  first lists the shell task as `running` in `background_tasks`, and the
  later one lists none.

## Isolated `claude -p` worker: the flags still authenticate

The isolated worker is a `claude -p` child started with the flags in
`../lib/isolated-worker.sh`: `--strict-mcp-config`,
`--no-session-persistence`, `--output-format`, `--model`, `--allowedTools`, a
`--disallowedTools` list, `CLAUDE_JOB_DIR` unset, `CTX_AUTO_RESET_DISPATCH=0`,
and `--` before the prompt, since `--disallowedTools` otherwise takes the
prompt as one of its values.

- Script: `../worker-isolation-auth.probe.sh`
- Record: `worker-isolation-auth.personal.json`, from the personal profile
- Prerequisites: `jq`, `timeout`, a logged-in `claude` on `PATH`.
- Replay: `SMITH_LIVE_CONTEXT_RESET_EVAL=1 smith-ctx-claude/scripts/tests/worker-isolation-auth.probe.sh «record»`
- What it does: asks an isolated worker in an empty temporary folder to echo
  a random word.
- Passing output: exit status 0, `isError` false, `replyMatches` true.
- Optional parameter: `SMITH_LIVE_CONTEXT_RESET_MODEL`, default `haiku`.

## COLD READER: which flags keep it from `git` and from unnamed files

- Script: `../cold-reader-no-git.probe.sh`
- Record: `cold-reader-no-git.personal.json`, from the personal profile
- Prerequisites: `jq`, `timeout`, `git`, a logged-in `claude` on `PATH`.
- Replay: `SMITH_LIVE_CONTEXT_RESET_EVAL=1 smith-ctx-claude/scripts/tests/cold-reader-no-git.probe.sh «record»`
- What it does: writes a named file and an unnamed file with a random code
  word in separate temporary folders, then asks the worker, allowed only
  `Read(//«named file»)`, to run `git` on this repository, read the named
  file, read the unnamed file, read an unnamed file of this repository, and
  search the repository. Each variant adds flags to the isolated worker:
  none; `--tools Read`; `--restricted --tools Read`; `--setting-sources ""`
  with `--tools Read`; `--permission-mode dontAsk --tools Read`; and
  `dontAsk` with `--setting-sources ""` and `--tools Read`; the last two
  settings-free variants run again with the named file outside the working
  folder. The verdicts come from the tool results in the `stream-json`
  stream, never from the reply text.
- Passing output: a variant passes when it exits 0, read the named file, and
  neither ran `git`, read either unnamed file, nor searched;
  `enforcingVariants` lists the variants that pass.
- What the record shows: `git` never ran. While the user settings load,
  their allow rules, such as `Read(//«home»/Projects/**)`, and their auto
  permission mode admit unnamed reads, so the allow rule on the named file
  limits nothing. Without `--tools`, the worker also gets non-built-in tools
  such as `SendMessage`, `Workflow` and `Skill`. With the user settings left
  out, by `--restricted` or by `--setting-sources ""`, and `--tools Read`,
  only the named file is read, also when it lies outside the working folder.
- An absolute path in a rule needs two leading slashes: a single leading
  slash anchors at the primary working directory for a rule given in a CLI
  flag, per "How path patterns match" in
  https://code.claude.com/docs/en/permissions.
- Optional parameter: `SMITH_LIVE_CONTEXT_RESET_MODEL`, default `haiku`.

## Isolated workers end when their runner is signalled

- Script: `../worker-interrupt.probe.sh`
- Records: `worker-interrupt.term.personal.json` and
  `worker-interrupt.int.personal.json`, from the personal profile
- Prerequisites: `jq`, `perl`, `pgrep`, a logged-in `claude` on `PATH`.
- Replay: `SMITH_LIVE_WORKER_SIGNAL=TERM SMITH_LIVE_CONTEXT_RESET_EVAL=1 smith-ctx-claude/scripts/tests/worker-interrupt.probe.sh «record»`,
  and the same with `INT`
- What it does: starts a runner as the leader of its own process group; the
  runner starts both isolated workers in the background, each running a
  script that sleeps in the foreground of its Bash tool, and traps INT and
  TERM by sending TERM to its whole group. Once both tool processes run, the
  probe sends the signal to the runner, waits for it to exit, and counts the
  workers and tool processes still alive. A runner still alive after the wait
  gets TERM, so no run leaves processes behind.
- Passing output: the runner exits within the wait, and no worker or tool
  process is alive afterwards.
- What the records show: TERM passes. INT fails; the inferred cause, which
  the probe does not measure, is that a background job of a non-interactive
  shell starts with INT ignored, so the runner's trap never runs. The tool processes run in process groups of their own, not the
  runner's, so the group kill reaches only the workers, which then end their
  own tool processes.
- Optional parameters: `SMITH_LIVE_WORKER_SIGNAL`, default `TERM`;
  `SMITH_LIVE_CONTEXT_RESET_MODEL`, default `haiku`.

## VERIFIER: which Bash rule keeps `git` to the repository

- Script: `../verifier-bash-scope.probe.sh`
- Record: `verifier-bash-scope.personal.json`, from the personal profile
- Prerequisites: `jq`, `timeout`, `git`, a logged-in `claude` on `PATH`.
- Replay: `SMITH_LIVE_CONTEXT_RESET_EVAL=1 smith-ctx-claude/scripts/tests/verifier-bash-scope.probe.sh «record»`
- What it does: runs the isolated worker in an empty temporary folder with
  `--setting-sources ""`, `--tools Read,Bash` and an allow rule
  `Read(//«repo»/**)`, and asks it to run `git rev-parse` on this
  repository, `cat` an unnamed file holding a random code word, the same
  `cat` chained after `git` with `&&`, `git diff --no-index` against the
  unnamed file, `git init` in the unnamed file's folder, a `git -c
  alias.«name»=!cat «unnamed file»` call inside the allowed prefix, then read a file of
  this repository and the unnamed file. One variant allows `Bash(git *)`,
  the other `Bash(git -C «repo» *)`.
- Passing output: `git` on the repository and the repository read succeed,
  the code word appears in no tool result, and `git init` outside the
  repository is refused; `enforcingVariants` lists the variants that pass.
- What the record shows: no variant passes. Both refused `cat`, the chained
  `cat` and `git diff --no-index`; `Bash(git *)` also let `git init` run
  outside the repository. In both, the `-c alias.«name»=!cat` call ran and
  printed the unnamed file's code word: a prefix rule on `git` does not keep
  a worker from running other programs.
- Optional parameter: `SMITH_LIVE_CONTEXT_RESET_MODEL`, default `haiku`.

## A worker folder: symlinks do not reach outside it

- Script: `../worker-folder-symlink.probe.sh`
- Record: `worker-folder-symlink.personal.json`, from the personal profile
- Prerequisites: `jq`, `timeout`, a logged-in `claude` on `PATH`.
- Replay: `SMITH_LIVE_CONTEXT_RESET_EVAL=1 smith-ctx-claude/scripts/tests/worker-folder-symlink.probe.sh «record»`
- What it does: runs the isolated worker with `--setting-sources ""`,
  `--tools Read` and no allow rule, in a working folder that holds a copied
  file, a symlink to a file outside it and a symlink to a folder outside it,
  each outside file holding a random code word; the worker reads the copied
  file, both links and the outside file by its own path.
- Passing output: the copied file is read and neither outside code word
  appears in a tool result.
- What the record shows: passes; both links are refused like the outside
  path, so inputs placed in a worker folder by link are unreadable and have
  to be copied.
- Optional parameter: `SMITH_LIVE_CONTEXT_RESET_MODEL`, default `haiku`.

## A runner in the foreground Bash tool when its session is interrupted

- Script: `../foreground-runner-interrupt.probe.sh`
- Record: `foreground-runner-interrupt.personal.json`, from the personal profile
- Prerequisites: `jq`, `mkfifo`, a logged-in `claude` on `PATH`.
- Replay: `SMITH_LIVE_CONTEXT_RESET_EVAL=1 smith-ctx-claude/scripts/tests/foreground-runner-interrupt.probe.sh «record»`
- What it does: an outer `claude -p` in `stream-json` mode runs a runner in
  its foreground Bash tool; the runner traps INT, TERM, HUP and QUIT, logs
  the signal and ends its background `sleep`. The session is then
  interrupted, once by the `interrupt` control request on standard input,
  once by SIGINT to the outer `claude` process.
- Passing output: the runner and its child are gone afterwards;
  `signalsTheRunnerTrapped` names what the runner received.
- What the record shows: both variants pass, and in both the runner received
  TERM, so a runner that traps TERM and ends its own jobs needs no process
  group of its own. Both variants interrupt by program and the runner holds
  only a `sleep`; the Escape key and real workers are the next section.
- Optional parameter: `SMITH_LIVE_CONTEXT_RESET_MODEL`, default `haiku`.

## The Escape key in an interactive session stops a runner and its workers

- Script: `../foreground-runner-escape.probe.py`
- Record: `foreground-runner-escape.personal.json`, from the personal profile
- Prerequisites: Python 3, `pgrep`, a logged-in `claude` on `PATH`.
- Replay: `SMITH_LIVE_CONTEXT_RESET_EVAL=1 python3 -I smith-ctx-claude/scripts/tests/foreground-runner-escape.probe.py «record»`
- What it does: starts an interactive `claude` in a pseudo-terminal, in a
  fresh temporary folder the probe created, with `--setting-sources ""`,
  `--strict-mcp-config`, `--tools Bash` and `--allowedTools
  "Bash(./runner.sh)"`, or `"Bash(./start.sh) Bash(./join.sh)"` in the third
  variant; answers the folder trust dialog with "Yes", types
  the request to run `./runner.sh` in the foreground and presses Enter; once
  the runner's jobs run, writes the Escape key byte to the terminal, the
  same input a person's key press gives. The runner traps INT, TERM, HUP and
  QUIT, logs the signal and kills its background jobs. In one variant the
  job is a `sleep`; in another it is both isolated `claude -p` workers of
  `../lib/isolated-worker.sh`, each holding a `sleep` in its own Bash tool.
  In the third, the session runs the wrapper script `./start.sh`, which
  calls `../../worker-job.sh start` on that runner, in one call and the
  wrapper script `./join.sh`, which calls `../../worker-job.sh join`, in the
  next, and the key is pressed during the join. `SMITH_LIVE_ESCAPE_VARIANTS`, default
  `sleep,workers,job`, selects variants.
- Passing output: the runner, its children and the workers' tool processes
  are all gone ten seconds after the key press.
- What the record shows: every variant passes; the runner received TERM in
  each, the job of the third variant ended as `SMITH_JOB_CANCELLED`, and the
  interactive session stayed open.
- Optional parameter: `SMITH_LIVE_CONTEXT_RESET_MODEL`, default `haiku`.

## Raising the Bash tool's timeout ceiling keeps a long command in the foreground

- Script: `../bash-timeout-ceiling.probe.sh`
- Record: `bash-timeout-ceiling.personal.json`, from the personal profile
- Prerequisites: `jq`, a logged-in `claude` on `PATH`; one run takes about
  eleven minutes, its variants running side by side.
- Replay: `SMITH_LIVE_CONTEXT_RESET_EVAL=1 smith-ctx-claude/scripts/tests/bash-timeout-ceiling.probe.sh «record»`
- What it does: an isolated worker with `--setting-sources ""` and `--tools
  Bash` runs a script that sleeps `SMITH_LIVE_HOLD_SECONDS`, default 660,
  then prints a random word, asking for the Bash `timeout` parameter
  `SMITH_LIVE_REQUESTED_TIMEOUT_MS`, default 900000. Variants: no change to
  the ceiling; `BASH_MAX_TIMEOUT_MS` set to `SMITH_LIVE_CEILING_MS`, default
  1200000, in the environment of the `claude` process; the same value in
  `--settings` under `env`, as a `settings.json` entry would give it.
- Passing output: `foregroundVariants` lists the variants whose first tool
  result holds the random word, meaning the command finished in the
  foreground.
- What the record shows: without a change the command moved to the
  background at 600 seconds; with the ceiling raised either way it finished
  in the foreground after 660 seconds. Local paths in the tool result are
  replaced by `«path»`; the record of this run was redacted after the run
  with the same expression the script now applies.
- Background: "When a command reaches its timeout before it finishes,
  Claude Code automatically moves it to the background instead of stopping
  it", https://code.claude.com/docs/en/interactive-mode, and
  `BASH_MAX_TIMEOUT_MS` in https://code.claude.com/docs/en/env-vars.

## A `settings.json` env value reaches commands the Bash tool runs

- Script: `../bash-ceiling-env-visible.probe.sh`
- Record: `bash-ceiling-env-visible.personal.json`, from the personal profile
- Prerequisites: `jq`, `timeout`, a logged-in `claude` on `PATH`.
- Replay: `SMITH_LIVE_CONTEXT_RESET_EVAL=1 smith-ctx-claude/scripts/tests/bash-ceiling-env-visible.probe.sh «record»`
- What it does: with `BASH_MAX_TIMEOUT_MS` removed from the environment of
  the `claude` process, an isolated worker with `--setting-sources ""` and
  `--tools Bash` runs a script that prints that variable; once with no
  setting, once with `SMITH_LIVE_CEILING_MS`, default 1200000, in
  `--settings` under `env`.
- Passing output: `pass` is true: the script sees `unset` without the
  setting and the configured value with it, so a runner can check the
  ceiling it runs under before it starts.
- Optional parameter: `SMITH_LIVE_CONTEXT_RESET_MODEL`, default `haiku`.

## A job started in the background of a Bash call outlives the call and the session

- Script: `../detached-job-survives-call.probe.sh`
- Record: `detached-job-survives-call.personal.json`, from the personal profile
- Prerequisites: `jq`, `perl`, `timeout`, a logged-in `claude` on `PATH`.
- Replay: `SMITH_LIVE_CONTEXT_RESET_EVAL=1 smith-ctx-claude/scripts/tests/detached-job-survives-call.probe.sh «record»`
- What it does: an isolated worker with `--setting-sources ""` and `--tools
  Bash` runs a start script in the foreground that launches a job sleeping
  `SMITH_LIVE_JOB_SECONDS`, default 60, then runs a check script in a second
  call. Launch variants: plain `&`; `nohup … &`; `&` in a new process group
  made with `perl` `setpgrp`.
- Passing output: the job is alive at the second call and finishes.
- What the record shows: every variant passes, and the job is still alive
  after the `claude -p` session has exited, so a detached job needs its own
  rule for ending when no session waits for it.
- Optional parameter: `SMITH_LIVE_CONTEXT_RESET_MODEL`, default `haiku`.

## Integrity

`SHA256SUMS` lists the SHA-256 of each record. Check with
`shasum -a 256 -c SHA256SUMS` from this folder.
