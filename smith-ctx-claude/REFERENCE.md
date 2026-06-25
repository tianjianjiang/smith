# smith-ctx-claude — Reference (Layer 3)

<metadata>

- **Load if**: Configuring hooks, permission modes, agents, model routing, or
  plugins in Claude Code. Read on demand — NOT auto-loaded with
  `smith-ctx-claude/SKILL.md`.
- **Parent**: `@smith-ctx-claude/SKILL.md` (context-management core)

</metadata>

These are reference dumps split out of the parent SKILL.md to keep it under
the SKILL.md token ceiling. Nothing here is needed for routine context
management; read the section you need and unload it.

## Recommended Linting Hooks

**PostToolUse auto-format** — runs formatter after every Edit/Write (strongest enforcement, zero friction):

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{
          "type": "command",
          "command": "input=$(cat) && file=$(printf '%s' \"$input\" | jq -r '.tool_input.file_path // empty') && [ -n \"$file\" ] && { case \"$file\" in *.py) ruff format \"$file\" 2>/dev/null;; *.ts|*.tsx|*.js|*.jsx) npx prettier --write \"$file\" 2>/dev/null;; esac; } || true",
          "timeout": 10
        }]
      }
    ]
  }
}
```

**Prerequisites**: Requires `jq` for JSON parsing (`brew install jq` / `apt install jq`). The `2>/dev/null` and `|| true` suppress errors for non-matching file types; remove them when debugging hook setup.

**Timeout unit**: All hook timeouts are in **seconds** (10 = 10s, default 600s for command hooks).

**Adapt per project**: Replace `ruff format`/`prettier` with project's formatter. Add to project-level `.claude/settings.json`.

**Why not just instructions?** Research shows agents treat "always run lint" as suggestions. PostToolUse hooks are invisible and automatic — the strongest enforcement layer. See [Anthropic best practices](https://www.anthropic.com/engineering/claude-code-best-practices) and [claude-format-hook](https://github.com/ryanlewis/claude-format-hook).

## Hooks Reference

**Hook events** (4 handler types: command, http, prompt, agent):

**Tool lifecycle:**
- PreToolUse — before tool runs; exit 2 = reject
- PostToolUse — after tool succeeds; format, validate
- PostToolUseFailure — after tool fails; recovery

**Session lifecycle:**
- SessionStart — session begins; init, context inject
- SessionEnd — session ends; final cleanup
- Stop — agent finished responding (fires every turn); save state / enforce limits (smith gates at 60% in the handler)
- UserPromptSubmit — user sends message; transform
- InstructionsLoaded — CLAUDE.md/skills loaded
- PreCompact — before context compaction

**Multi-agent:**
- SubagentStart/SubagentStop — subagent lifecycle
- TeammateIdle — teammate awaits task; quality gate
- TaskCompleted — shared task done; exit 2 = reject

**Infrastructure:**
- WorktreeCreate/WorktreeRemove — worktree lifecycle
- Notification — system notification
- PermissionRequest — permission prompt
- ConfigChange — settings.json changed

**Handler types:**
- command — shell script; event JSON on stdin; exit 0=allow, 2=reject
- http — HTTP POST to endpoint; event JSON as body
- prompt — sends text to Claude model (Haiku default)
- agent — spawns subagent with prompt + event JSON

**Config:** `.claude/settings.json` (project) or
`~/.claude/settings.json` (global). Project overrides
global. Matchers filter by tool name. Timeout: command handlers default 600s;
prompt/agent handlers default to shorter limits (values vary by version —
check current docs).

**Reliability caveat — multiple PreToolUse hooks on one tool:** when more than
one PreToolUse hook matches the same tool, an `updatedInput` (and by extension
the permission-decision) response from one hook can be dropped rather than
applied — see anthropics/claude-code [#15897](https://github.com/anthropics/claude-code/issues/15897)
(closed). Don't rely on stacked PreToolUse hooks cooperating on the same
tool's input; consolidate the logic into a single hook when the decision must
stick.

**Matching MCP tools:** MCP server tools appear as regular tools in the tool
events (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`,
`PermissionDenied`), named `mcp__«server»__«tool»`. Match them by name like any
tool; append `.*` to the server prefix (`mcp__«server»__.*`) to match every tool
from one server.

**Narrower than `matcher` — the `if` field:** set `if` on an individual hook
handler to filter on tool name AND arguments together using
[permission-rule syntax](https://code.claude.com/docs/en/permissions) — e.g.
`"Bash(git *)"` fires only for `git` subcommands, `"Edit(*.ts)"` only for
TypeScript edits.

Cross-ref: `@smith-plan-claude/SKILL.md` for plan-specific hooks.

## Permission Modes

**6 permission modes** (`permissions.defaultMode` in settings):
- `default` — approve each tool call individually
- `acceptEdits` — auto-approves file edits/writes + common filesystem Bash (mkdir, touch, rm, mv, cp, sed) inside the working directory; other Bash still prompts
- `plan` — read-only; agent plans but cannot execute
- `auto` — classifier auto-handles prompts; safe runs uninterrupted, destructive routes to classifier deny. Requires v2.1.83+, Max/Team/Enterprise/API plan. `defaultMode: "auto"` is honored only in `~/.claude/settings.json` (ignored in `.claude/settings.json`). See `@smith-auto_mode/SKILL.md` for the denial-recovery protocol.
- `dontAsk` — auto-denies prompts; only pre-approved `allow` rules + read-only Bash execute
- `bypassPermissions` — `--dangerously-skip-permissions` flag; skips all checks including protected paths

**Note:** "Yes, don't ask again" is a per-tool approval behavior (remembered per directory/command), not a global mode. Permission rules (`allow`/`ask`/`deny`) are evaluated deny-first.

**When to use:**
- `plan` for research, architecture review
- `acceptEdits` for trusted execution (tests green)
- `auto` for long autonomous tasks where the classifier's deny on destructive actions is acceptable
- `default` for unfamiliar codebases
- `dontAsk` for locked-down CI / scripts with pre-defined allow rules
- `bypassPermissions` for isolated containers / VMs only

## Agent Features

**Subagents** (`Agent` tool):
- Fresh 200k context per subagent
- `run_in_background: true` for async work
- `isolation: "worktree"` for repo isolation
- `model` parameter overrides model per subagent

**Custom agents** (`/agents` or `.claude/agents/*.md`):
- Frontmatter: model, tools, permissions, memory
- Loaded via `subagent_type` parameter
- Project-scoped or user-scoped (`~/.claude/agents/`)

**Agent Teams** (experimental):
- Enable: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
- Team lead + teammates, independent context each
- `SendMessage` for inter-agent communication
- Shared task list with dependency tracking
- See `@smith-ralph/SKILL.md` Pattern C for full workflow

**Agent View (`claude agents`)** (research preview, v2.1.139+):
- One screen for background sessions: dispatch, peek (`Space`), attach (`→`/`Enter`), detach (`←`)
- States: Working / Needs input / Idle / Completed / Failed / Stopped
- Dispatch from shell: `claude --bg "<prompt>"`, with `--agent`, `--name`, `--model`, `--permission-mode`
- Background a current session: `/background` or `/bg`
- Shell-side mgmt: `claude attach`, `claude logs`, `claude stop`, `claude respawn`, `claude rm`
- `claude agents --json` — print live sessions as JSON (pid, cwd, kind, sessionId, name, status, startedAt)
- `claude agents --cwd <path>` — filter by project (v2.1.141+)
- Background sessions auto-isolate edits via worktree under `.claude/worktrees/` (see `@smith-worktree/SKILL.md`)
- Disable via `disableAgentView: true` or `CLAUDE_CODE_DISABLE_AGENT_VIEW`

## Agent Dispatch Protocol

**Default: work in parent context.** Escalate to subagent when:
- Research needs >2 sequential search/read operations on unknown paths
- Exploration breadth exceeds current task scope (broad audit, multi-file comparison)
- Work is parallelizable across independent axes (e.g., review Standards + Content simultaneously)

**Dispatch sizing:**
- Single lookup or known-path read: parent context, no dispatch
- 2-5 reads on a known path: parent context
- Broad exploration (unknown path, >5 reads expected): subagent with `"quick"` breadth by default
- Multi-axis validation: parallel subagents or Agent Team, one axis per agent

**Handoff compaction (dispatching or returning results):**
- Reference artifacts by path/URL, not content (target: 200-500 tokens per handoff)
- Include: goal, relevant file:line refs, decisions already made, suggested skills for next step
- Exclude: verbose tool output, failed exploration paths, full file contents
- Pattern: `Completed: [what]. Key refs: [paths]. Next: [goal]. Budget: [constraint].`

**Explore subagent breadth:**
- `"quick"` (default): single-target lookup, one grep, one file read
- `"medium"`: comparison across 2-5 files, pattern matching
- `"very thorough"`: codebase-wide audit, architecture survey — reserve for genuine unknowns

## /goal — Autonomous Completion Conditions

`/goal <condition>` (v2.1.139+) sets a session-scoped completion condition. After each turn a small fast model (defaults to Haiku) checks whether the condition holds. "No" feeds the reason back as guidance and starts another turn; "yes" clears the goal. Persistent autonomous work without per-turn prompting.

Distinguish from `/loop` and Stop hooks:
- `/goal` — fires after every turn; session-scoped; condition typed once; clears when met
- `/loop` — fires on an interval; session-scoped; re-runs a prompt (see `@smith-automation/SKILL.md`)
- Stop hook — fires after every turn; settings-scoped; deterministic script or model-prompt

**Write conditions Claude's output can demonstrate** — the evaluator reads the conversation, doesn't run tools or read files. Good: "all tests in test/auth pass and lint exits 0". Bad: "the API is well-designed".

**Bound runtime** with a turn/time clause inside the condition (e.g. "or stop after 20 turns"). One goal active per session; `/goal clear` (aliases: `stop`/`off`/`reset`/`none`/`cancel`) cancels; `/clear` also clears. An active goal is restored on `--resume`/`--continue`; turn count, timer, and token baseline reset on resume.

Requires accepted trust dialog; unavailable when `disableAllHooks` or `allowManagedHooksOnly` is set. Non-interactive: `claude -p "/goal ..."`.

## Model Routing

**Model selection guidance:**
- Opus — orchestration, complex reasoning
- Sonnet — focused subagents, code generation
- Haiku — quick lookups, classification

**Commands:**
- `/model` — switch model mid-session
- `/fast` — fast mode toggle; uses the latest **Opus** tier with faster output, NOT a smaller model (distinct from `ANTHROPIC_SMALL_FAST_MODEL`, the Haiku background model)
- `model` param on Agent tool — per-subagent
- `opusplan` alias — Opus for planning

**Cost-aware patterns:**
- Orchestrator (Opus) spawns workers (Sonnet)
- Haiku for repetitive/mechanical subtasks
- Match model to task complexity, not habit

## Tool Search Tool

Substantial token reduction (vendor-cited ~85%) — tools loaded on-demand, not upfront.

- Rely on Tool Search for documentation
- Use specific tool names for better retrieval
- Don't request full tool documentation dumps

## Skills Directory Integration

**Primary method (symlink, recommended for smith):**

```bash
ln -sf $HOME/.smith $HOME/.claude/skills
```

Claude Code discovers skills at `~/.claude/skills/smith-*/SKILL.md`.
All skills prefixed with "smith-" to avoid conflicts.

**Alternative**: `claude --add-dir /path/to/skills-repo` for
cross-repo sharing (see `@smith-tools/SKILL.md` for details).

## Claude Code Features

**Unique capabilities:**
- Web search for current information
- Browser automation for testing
- MCP server integration (including Serena)
- Up to 1M token context window (model-dependent)
- Tool Search for on-demand tool loading

## Plugin Discovery

**Available plugin commands:**
- `/code-review` - Automated PR review with parallel agents
- `/commit` - Auto-commit with message generation
- `/commit-push-pr` - Full PR workflow
- `/clean_gone` - Branch cleanup

**Check installed plugins:** `/plugins` or `cat ~/.claude/plugins/installed_plugins.json`

**Official marketplace:** `anthropics/claude-plugins-official`

## Session-Analytics Surfaces

Two complementary tools for analyzing this Claude Code instance:

- **`/insights`** — Anthropic-side qualitative report (workflow patterns, friction categories, suggestions). ~5-week window. Saves an HTML report under `~/.claude/usage-data/`. Best for "what's slowing me down" / "what should I codify next." Don't search the filesystem to verify it exists — just invoke it (see parent SKILL.md "Slash Command Invocation").
- **`session-report:session-report`** (bundled plugin) — Quantitative report (tokens, cache hits, subagent costs, top prompts) from `~/.claude/projects/*.jsonl`. Default 7-day window; configurable via `--since`. Best for "where are the tokens going" / "which prompts are most expensive."

`/insights` answers WHY; `session-report` answers HOW MUCH. Pair them when reshaping the smith-skills backlog (see `mem:backlog_smith_skills_2026_05_21_post_session_report`).
