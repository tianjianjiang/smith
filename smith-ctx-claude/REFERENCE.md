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

## Curated Skill Catalog (moved from AGENTS.md `<available_skills>`)

The live skill list is injected by the harness every session. This is the
curated, categorized catalog kept for reference (descriptions used to seed
frontmatter / triggers). Keep in sync with `skill-triggers.json` semantics.

```xml
<available_skills>
<!-- Core (always load) -->
<skill name="smith-principles" description="DRY, KISS, YAGNI, SOLID principles">@smith-principles/SKILL.md</skill>
<skill name="smith-standards" description="Universal coding standards">@smith-standards/SKILL.md</skill>
<skill name="smith-guidance" description="AI agent behavior patterns">@smith-guidance/SKILL.md</skill>
<skill name="smith-ctx" description="Context management, proactive recommendations">@smith-ctx/SKILL.md</skill>

<!-- Context (platform-specific) -->
<skill name="smith-ctx-kiro" description="Kiro-specific rules">`@smith-ctx-kiro/SKILL.md`</skill>
<skill name="smith-ctx-claude" description="Claude Code context, hooks, permissions, agents, model routing">`@smith-ctx-claude/SKILL.md`</skill>
<skill name="smith-ctx-cursor" description="Cursor rules">`@smith-ctx-cursor/SKILL.md`</skill>
<skill name="smith-auto_mode" description="Auto-mode classifier denial recovery">`@smith-auto_mode/SKILL.md`</skill>
<skill name="smith-settings" description="settings.json scope/precedence + convention-validator hook recipe">`@smith-settings/SKILL.md`</skill>
<skill name="smith-serena" description="Serena MCP integration">`@smith-serena/SKILL.md`</skill>

<!-- Reasoning -->
<skill name="smith-analysis" description="Problem decomposition, Polya method">`@smith-analysis/SKILL.md`</skill>
<skill name="smith-clarity" description="Cognitive traps, logic fallacies">`@smith-clarity/SKILL.md`</skill>
<skill name="smith-design" description="SOLID principles, architecture">`@smith-design/SKILL.md`</skill>
<skill name="smith-validation" description="Hypothesis testing, adversarial verification of findings, debugging">`@smith-validation/SKILL.md`</skill>
<skill name="smith-postmortem" description="Incident postmortem methodology">`@smith-postmortem/SKILL.md`</skill>
<skill name="smith-dialectic" description="Socratic plan interview against project docs and code">`@smith-dialectic/SKILL.md`</skill>

<!-- Testing -->
<skill name="smith-tests" description="Testing standards, TDD workflow">`@smith-tests/SKILL.md`</skill>
<skill name="smith-playwright" description="Playwright testing, proactive failure monitoring">`@smith-playwright/SKILL.md`</skill>
<skill name="smith-browser_mcp" description="Browser MCP reliability: take each server's default browser, set no override at all">`@smith-browser_mcp/SKILL.md`</skill>

<!-- Languages -->
<skill name="smith-python" description="Python patterns and testing">`@smith-python/SKILL.md`</skill>
<skill name="smith-typescript" description="TypeScript patterns">`@smith-typescript/SKILL.md`</skill>
<skill name="smith-nuxt" description="Nuxt.js framework">`@smith-nuxt/SKILL.md`</skill>

<!-- Git/GitHub -->
<skill name="smith-git" description="Git commits, merges, rebases, worktrees">`@smith-git/SKILL.md`</skill>
<skill name="smith-worktree" description="Claude Code worktree tools: EnterWorktree/ExitWorktree, bgIsolation, baseRef, squash-merge sync">`@smith-worktree/SKILL.md`</skill>
<skill name="smith-gh-pr" description="PR creation, review, automated monitoring">`@smith-gh-pr/SKILL.md`</skill>
<skill name="smith-gh-cli" description="GitHub CLI usage">`@smith-gh-cli/SKILL.md`</skill>
<skill name="smith-style" description="Commit messages and branch naming conventions">`@smith-style/SKILL.md`</skill>

<!-- Workflow -->
<skill name="smith-ralph" description="Ralph Loop iterative development">`@smith-ralph/SKILL.md`</skill>
<skill name="smith-plan" description="Plan tracking protocol (portable)">`@smith-plan/SKILL.md`</skill>
<skill name="smith-plan-claude" description="Plan automation (Claude Code hooks)">`@smith-plan-claude/SKILL.md`</skill>
<skill name="smith-automation" description="Claude Code automation primitives: /loop, ScheduleWakeup, Monitor, /schedule + decision matrix">`@smith-automation/SKILL.md`</skill>
<skill name="smith-subagents" description="Subagent spawning + return discipline: read-only default, findings-not-actions, verify returns, reconcile vs live state">`@smith-subagents/SKILL.md`</skill>

<!-- Communication -->
<skill name="smith-slack" description="Slack drafting discipline: pre-send gate (draft-not-send, attribution footnote, evidence URLs, no formatting, confirm-before-send)">`@smith-slack/SKILL.md`</skill>

<!-- Other -->
<skill name="smith-prompts" description="Prompt engineering">`@smith-prompts/SKILL.md`</skill>
<skill name="smith-xml" description="XML tag patterns for AI">`@smith-xml/SKILL.md`</skill>
<skill name="smith-placeholder" description="Documentation placeholders">`@smith-placeholder/SKILL.md`</skill>
<skill name="smith-tools" description="Development tools, MCP lifecycle">`@smith-tools/SKILL.md`</skill>
<skill name="smith-dev" description="Development workflow">`@smith-dev/SKILL.md`</skill>
<skill name="smith-ide" description="IDE configuration">`@smith-ide/SKILL.md`</skill>
<skill name="smith-research" description="Research methodology">`@smith-research/SKILL.md`</skill>
<skill name="smith-skills" description="Skill authoring">`@smith-skills/SKILL.md`</skill>

<!-- Commands (invoke with /name; also auto-trigger on task match) -->
<skill name="smith-ship" description="/smith-ship — review-to-convergence then atomic commit, push, PR, address review, squash-merge, ff-only sync, cleanup">`@smith-ship/SKILL.md`</skill>
<skill name="smith-review" description="/smith-review — multi-round local worktree review until convergence (no shipping)">`@smith-review/SKILL.md`</skill>
<skill name="smith-preflight" description="/smith-preflight — gate the current change against the invariants; PASS, FAIL, SKIP or N/A per check plus a GO or NO-GO verdict">`@smith-preflight/SKILL.md`</skill>
<skill name="smith-checkpoint" description="/smith-checkpoint — save session state to all 3 memory systems in their formats">`@smith-checkpoint/SKILL.md`</skill>
<skill name="smith-recon" description="/smith-recon — guided, bounded multi-source investigation; asks sources, cross-verifies, evidence-linked brief">`@smith-recon/SKILL.md`</skill>
<skill name="smith-tickets" description="/smith-tickets — create Jira tickets by convention (Job Story, Japanese desc, correct parent Epic)">`@smith-tickets/SKILL.md`</skill>
</available_skills>
```

## Semantic Activation Trigger Table (moved from AGENTS.md)

Human-readable mirror of `@smith-ctx-claude/skill-triggers.json` (the
skill-router hook's table — keep the two in sync). On a task match, invoke the
skill via the Skill tool:

**Languages**: Python → `@smith-python/SKILL.md`, TypeScript → `@smith-typescript/SKILL.md`, Nuxt → `@smith-nuxt/SKILL.md`
**Testing**: Tests/TDD → `@smith-tests/SKILL.md`,
  Playwright → `@smith-playwright/SKILL.md`
**Browser MCP**: chrome-devtools-mcp / @playwright/mcp invocation, browser MCP launch failure, OR browser login / interactive auth (login/sign-in near browser/site/portal wording) → `@smith-browser_mcp/SKILL.md`
**Workflow**: Ralph Loop → `@smith-ralph/SKILL.md`,
  Dev-initiation verbs (implement/develop/fix/add feature/modify/improve/harden/refactor …) → `@smith-dev/SKILL.md` + `@smith-git/SKILL.md` + `@smith-worktree/SKILL.md` (router also emits the branch-first note: dedicated branch+worktree BEFORE the first edit)
**Plan**: Plan execution → `@smith-plan/SKILL.md`,
  Claude Code hooks/`!load-plan` → `@smith-plan-claude/SKILL.md`
**Automation**: `/loop`, `/schedule`, `ScheduleWakeup`, `Monitor`, polling for external state → `@smith-automation/SKILL.md`
**Subagents**: spawning Task/Agent subagents, delegating investigation, parallel orchestration, OR a subagent touching shared state (PR/issue/file/remote) → `@smith-subagents/SKILL.md`
**Git/GitHub**: Commits/branches → `@smith-git/SKILL.md` + `@smith-style/SKILL.md`,
  Worktrees (raw git) → `@smith-git/SKILL.md`,
  Worktrees (Claude Code tools: EnterWorktree/ExitWorktree, bgIsolation, squash-merge sync) → `@smith-worktree/SKILL.md`,
  PRs/reviews/`gh pr*` → `@smith-gh-pr/SKILL.md` + `@smith-gh-cli/SKILL.md` + `@smith-style/SKILL.md`,
  Reviewing or approving a PR/diff/change (`/smith-review`, `/review-pr`) → `@smith-review/SKILL.md` + `@smith-gh-pr/SKILL.md` (router also emits the suggestion-block note below),
  Inline review comments / committable `suggestion` blocks → `@smith-gh-pr/SKILL.md` (router also emits: a mechanical fix MUST carry the block, not prose describing the edit)
  Running or interpreting a CodeRabbit review, GitHub App or `coderabbit` command line → `@smith-gh-pr/SKILL.md` + `@smith-review/SKILL.md` (router also emits: a review that did not run looks identical to a clean one — check status, not the finding count)
**Claude Code**: Hooks/permissions/agents/model routing → `@smith-ctx-claude/SKILL.md`,
  MCP setup/lifecycle → `@smith-tools/SKILL.md` + `@smith-research/SKILL.md` + `@smith-validation/SKILL.md`,
  Auto-mode classifier denial OR classifier-sensitive action (e.g. force-push, push to main, prod deploy, IAM grant, external-content duplication, sandbox network call) → `@smith-auto_mode/SKILL.md`,
  Permission denial wording ("denied", "denial", "blocked by auto-mode/classifier") → `@smith-auto_mode/SKILL.md` (router also emits: do not silently retry a denied action)
**Settings**: editing settings.json/.claude config, which scope a key belongs in, OR building a convention-validator/enforcement hook → `@smith-settings/SKILL.md`
**External-dependency recommendation** (proposing any integration/config/tooling mechanism whose success depends on external system behavior — MCP, OAuth/auth flow, provider API, CLI flag, feature/version support): MUST load `@smith-research/SKILL.md` + `@smith-validation/SKILL.md` and verify the mechanism works (official docs + issue tracker) BEFORE proposing it. A proposed mechanism is a claim; claims need evidence.
**Reasoning**: Analysis → `@smith-analysis/SKILL.md`, Design → `@smith-design/SKILL.md`, Debug → `@smith-validation/SKILL.md`,
  Dialectic/grill/stress-test plan → `@smith-dialectic/SKILL.md` + `@smith-validation/SKILL.md`,
  Investigation / adversarial verification ("investigate X", "verify whether/that/if", "is this true", "prove me wrong", red-team, null hypothesis, refute, disprove, fact-check, falsify) → `@smith-validation/SKILL.md` + `@smith-clarity/SKILL.md` (router also emits: try to disprove a finding before reporting it, carry a durable locator for every claim, and add a separate skeptic when it contradicts a rule or drives an external write, which reporting it is not)
**Slack**: drafting/replying in Slack, any `slack_send_message*` / `slack_*` MCP tool, OR a `/slack:*` command → `@smith-slack/SKILL.md`
**Other**: Prompts → `@smith-prompts/SKILL.md`, XML → `@smith-xml/SKILL.md`
**Commands** (user types `/smith-X`, or auto-trigger on task match): ship a change end-to-end (also "commit and push", "open/create a PR") → `@smith-ship/SKILL.md`; review-to-convergence only → `@smith-review/SKILL.md`; gate a change against the invariants before shipping → `@smith-preflight/SKILL.md`; stacked branches/PRs → `@smith-ship/SKILL.md` stacked mode (`/smith-ship stack`) + `@smith-gh-pr/SKILL.md` Stacked PRs; save all 3 memories → `@smith-checkpoint/SKILL.md`; guided multi-source investigation → `@smith-recon/SKILL.md`; Jira tickets by convention → `@smith-tickets/SKILL.md`

## JSONL State Recall (moved from SKILL.md `/clear` section)

**JSONL state recall (recovery when no memory was saved):** the transcript is
preserved at `~/.claude/projects/«project-slug»/*.jsonl` and survives /clear
and compaction. Prior user prompts, decisions, and errors are recoverable from
it — `ctx_search(sort: "timeline")` indexes it, or grep the JSONL directly.
Use this to reconstruct intent before asking the user to repeat themselves.

## System-Reminder Event Taxonomy (moved from SKILL.md)

Full descriptions of the auto-injected system-reminder events. The parent
SKILL.md keeps only the compact list of event names plus the core rule
(system-reminders are not user input; respond only when action is required).

- **Task tools idle nudge** — `TaskCreate`/`TaskUpdate` present but unused
- **File modification notice** — a touched file changed outside the agent's tool calls
- **Skills available list** — periodic re-enumeration of Skill entries (informational)
- **Plan-mode transitions** — `EnterPlanMode`/`ExitPlanMode`, and post-`/clear` auto-resume flag (see `@smith-plan-claude/SKILL.md`)
- **Background task completion** — a `Bash(run_in_background)` task ended
- **Date change** — local date rolled over
- **Auto mode active** — session is in auto mode (see `@smith-auto_mode/SKILL.md`)
- **bg-isolation guard refusal** — first edit in a bg session without a worktree (see `@smith-worktree/SKILL.md`)
## Skill Descriptions (Full Reference)

Complete skill descriptions archived from frontmatter compression (Task 4.4).
Frontmatter now carries <50-char essence only; full descriptions below for
documentation and router-trigger design.

### Context Management

**smith-ctx**: Universal context-management foundation — proactive context-level checks and reset recommendations. Use when context usage grows high, when deciding whether to /clear or /compact, or when choosing what to retain across a context reset.

**smith-ctx-claude**: Claude Code context management with /clear, /compact mechanics, stop hook enforcement at 60%, JSONL state recall, tool-output hygiene, and system reminders. Reference dumps (hooks, permission modes, agent features, model routing) live in companion REFERENCE.md. Use when operating in Claude Code IDE or when context exceeds 50%.

**smith-ctx-cursor**: Cursor context management with /summarize command, @ mentions for file inclusion, and @codebase discovery. Use when operating in Cursor IDE or when context exceeds 60%. Activate for context optimization in Cursor sessions.

**smith-ctx-kiro**: Kiro-specific context management with terminal limitations, Serena MCP as mandatory tool, and file operation workarounds. Use when operating in Kiro IDE. LOAD FIRST in all Kiro sessions - critical platform constraints that prevent hangs and failures.

### Git & GitHub

**smith-git**: Git workflow gotchas and non-obvious practices. Use when performing Git commits, merges, branch management, rebasing, or raw `git worktree` commands. Covers GPG signing, atomic commits, raw worktree patterns, and safety flags. For the Claude Code worktree tools (EnterWorktree/ExitWorktree) see smith-worktree.

**smith-gh-pr**: GitHub PR workflows including creation, review cycles, merge strategies, stacked PRs (creation, merge order, rebase after parent merges, squash handling), posting review findings, and confirming a CodeRabbit review actually ran. Use when creating PRs, stacked PRs, or dependent PRs, replying to review comments, running or interpreting a CodeRabbit review (GitHub App or `coderabbit` command line), merging branches, or fetching PR threads. Covers rebase decision trees and AI-generated descriptions. For the stacked shipping pipeline see smith-ship (stacked mode).

**smith-gh-cli**: GitHub CLI gotchas and best practices. Use when executing gh commands. Covers token efficiency, pagination limits, and common pitfalls.

**smith-worktree**: Claude Code worktree TOOLS — EnterWorktree/ExitWorktree, the bgIsolation guard, worktree.baseRef, the branch-naming gotcha, and the squash-merge sync protocol. Use when invoking EnterWorktree/ExitWorktree, hitting the bgIsolation guard, or cleaning up after a worktree-based PR merge. For raw `git worktree` commands see smith-git.

### Core Principles

**smith-principles**: Fundamental coding principles (DRY, KISS, YAGNI, SOLID). Use when starting any development task, evaluating implementation approaches, or reviewing code quality. Always active as foundation for all development decisions.

**smith-standards**: Universal coding standards for emoji usage, comments, acronym expansion, datetime formatting, and file conventions. Use when writing code, logs, documentation, or any text output. Always active as universal rules for all development.

**smith-guidance**: Core agent steering with HHH framework (Helpful, Honest, Harmless), exploration-before-implementation workflow, scoped-edit discipline, and anti-sycophancy rules. Use when guiding AI agent behavior, handling disagreements, or establishing interaction patterns. Always active for all agent interactions.

### Development Workflows

**smith-dev**: Development workflow standards and code quality requirements. Use when starting ANY task that will modify repo files (implement, fix, add, refactor, harden), initializing projects, running quality checks, or managing agent tasks. Covers branch-first setup, pre-commit checks, task decomposition, and script organization patterns.

**smith-ship**: Ship pipeline — review a worktree change to convergence, then atomic commit, push, PR, address review, squash-merge, ff-only sync, cleanup. Invoke with /smith-ship for a single change, or /smith-ship stack to split multi-part work into atomic stacked branches and ship them as stacked PRs.

**smith-review**: Multi-round local review loop — review the current worktree change with all relevant smith review skills plus Claude Code review tools (/code-review, /review-pr, CodeRabbit, code-simplifier), iterating until convergence, without shipping. Invoke with /smith-review.

**smith-preflight**: Pre-ship gate — check the current change against the smith invariants (branch-first, secret-scan, pr-ownership, external-write, verify-before-assert, suggestions, subagent-contract) and report PASS, FAIL, SKIP or N/A (not applicable) per check with a GO or NO-GO verdict. Invoke with /smith-preflight; /smith-ship runs it as step 0 and will not push on NO-GO.

### Planning & Analysis

**smith-plan**: Plan tracking protocol (portable). Progress tracking with checkboxes, iteration workflow, completion/blocker signals. Use when executing multi-step plans, tracking task progress, or working from plan files. IMPORTANT - Always update the plan file after completing tasks.

**smith-plan-claude**: ExitPlanMode UI pattern for Claude Code plan mode — explain-first rule and rejection handling. For context/state/hooks see @smith-ctx-claude, for checkpoint see @smith-checkpoint, for Ralph see @smith-ralph.

**smith-recon**: Guided multi-source investigation — asks which sources to sweep (jsonl history, memories, Notion, Slack, Jira, Drive, GitHub) for a topic, reads them bounded and cross-verified, and returns an evidence-linked brief. Invoke with /smith-recon.

**smith-analysis**: Reasoning frameworks and problem decomposition techniques. Use when planning implementation, evaluating arguments, estimating scope, decomposing complex tasks, or applying first principles thinking.

**smith-dialectic**: Socratic interview that stress-tests a plan against project docs and code, one question at a time. Use when user says "grill my plan", "challenge this", "stress-test", or wants to reach shared understanding before implementing.

### Language-Specific

**smith-python**: Python development with uv, pytest, ruff, and type hints. Use when writing Python code, running tests, managing Python packages, or working with virtual environments. Covers import organization, type hints, pytest patterns, and environment variables.

**smith-typescript**: TypeScript development standards for frontend and backend projects. Use when working with TypeScript, configuring path aliases, setting up test runners (Vitest/Jest), or organizing test files. Covers Vite alias configuration and type checking.

**smith-nuxt**: Nuxt 3 development patterns including auto-import stubbing for tests, environment variable conventions, and middleware testing. Use when working with Nuxt projects, testing Nuxt components/middleware, or configuring Nuxt environment variables.

**smith-playwright**: Playwright testing patterns including proactive failure monitoring, artifact inspection, and root cause classification. Use when running Playwright tests or analyzing Playwright test results.

### AI & Prompts

**smith-prompts**: Prompt engineering standards for AI interactions with cache optimization. Use when writing AI prompts, optimizing context usage, or structuring AGENTS.md files. Covers prompt caching, token efficiency, and progressive disclosure patterns.

**smith-subagents**: Subagent spawning and return discipline — read-only by default, return findings not actions, treat every return as a claim to verify, reconcile against live state before mutating shared artifacts. Use when spawning Task/Agent subagents, delegating investigation, orchestrating parallel agents, or when a subagent will read or modify shared state (PRs, issues, files, remotes).

**smith-ralph**: Ralph Loop integration patterns for iterative AI development. Use when starting Ralph loops, managing iterations, or recovering from context resets. Covers TDD, debugging, context management, and memory persistence.

**smith-validation**: Hypothesis testing, adversarial verification of findings, root cause analysis, and debugging techniques. Use when debugging, investigating any question whose answer you will report as fact, verifying whether a claim or finding is true, red-teaming a conclusion, testing hypotheses, validating solutions, proving correctness, or performing root cause analysis on failures.

**smith-automation**: Claude Code scheduling primitives — /loop (interval, dynamic, bare), CronCreate/List/Delete, ScheduleWakeup, Monitor, and /schedule (Routines), with a decision matrix and provider/session-scope caveats. Use when setting up a recurring or scheduled task, polling for external state, self-pacing iterations, or the user mentions /loop, /schedule, cron, ScheduleWakeup, or Monitor.

### Documentation & Style

**smith-skills**: Agent skills authoring guide for AGENTS.md and SKILL.md files. Use when creating or editing agent instructions, rules, or documentation. Covers progressive disclosure, rule loading, Markdown structure, and token budget guidelines.

**smith-style**: File naming, path standards, and conventional commits. Use when naming files, creating branches, writing commit messages, or setting up new projects. Covers underscore vs hyphen conventions, commit format, and branch naming patterns.

**smith-xml**: XML tag standards for runtime prompts that mix instructions with embedded data (subagent prompts, assembled system messages). Use when constructing such a prompt, NOT when authoring a SKILL.md body — see smith-skills for that. Covers tag conventions for Claude, GPT-5.x, Gemini, and Harmony, with source-credibility notes verified 2026-07-11.

**smith-placeholder**: Placeholder syntax standard — guillemets «token» in every context. Use when writing prompts, documentation, usage strings, or any content with user-substitutable values.

**smith-design**: SOLID principles and architecture design patterns. Use when starting new features, refactoring code, conducting architecture reviews, or applying object-oriented design principles.

### Tools & Integration

**smith-tools**: Tool configurations for IDEs, MCP integrations, and development tools. Use when configuring IDE settings, MCP tools, or pytest. Covers conditional tool activation, configuration hierarchy, and synchronization patterns.

**smith-ide**: IDE path variable mappings for VS Code, Cursor, Kiro, and JetBrains. Use when writing or editing IDE config files or using path variables. Covers variable translation between conceptual and IDE-specific syntax.

**smith-serena**: Serena MCP integration for file I/O, semantic code editing, and persistent memory. ALWAYS use Serena for file operations and language server features when available. Proactively sync memories at phase/todo/session boundaries.

**smith-browser_mcp**: Browser MCP plugin reliability for chrome-devtools-mcp and @playwright/mcp. Take each server's own default browser — both resolve to Chrome's stable channel — and set no browser override at all; launching Vivaldi/Brave/Arc/Opera/Edge is forbidden, though attaching to an already-running one over the Chrome DevTools Protocol (CDP) is the documented escape hatch. Use when invoking chrome-devtools-mcp or Playwright MCP tools, editing .mcp.json / settings.json, triaging browser MCP launch failures, or when a site needs an interactive login the user must complete.

**smith-slack**: Slack message/reply drafting discipline — a hard pre-send checklist (draft-not-send, attribution footnote, evidence URLs, no formatting, confirm-before-send). Use when drafting or replying in Slack, invoking any slack_send_message* / slack_* MCP tool, or running a /slack:* command.

### Testing & Quality

**smith-tests**: Testing standards and TDD workflow. Use when writing tests, running test suites, implementing TDD, or organizing test files. Covers unit vs integration test separation, pytest patterns, and test-driven development methodology.

**smith-postmortem**: Incident postmortem methodology and templates. Use when conducting incident postmortems, writing postmortem reports, establishing postmortem processes, or performing post-incident analysis.

**smith-clarity**: Cognitive trap detection and logic fallacy identification. Use when making decisions, evaluating approaches, risk assessment, or detecting faulty reasoning in arguments.

### System & Configuration

**smith-settings**: Claude Code settings files — which config lives where (user / project / project-local / managed, and their precedence) plus a runnable convention-validator hook recipe that blocks actions violating repo rules. Use when editing settings.json or .claude config, deciding which scope a key belongs in, or building a hook that enforces a convention (commit/branch/file rules). For hooks internals see smith-ctx-claude; for permissions/auto-mode see smith-auto_mode.

**smith-auto_mode**: Claude Code auto mode classifier — what gets blocked, how to recover from a denial without silently retrying, and where to configure trusted infrastructure. Use when the agent invokes a classifier-sensitive action (push, deploy, external-content duplication), when a prior turn ended in "auto mode classifier" denial, or when the user mentions auto mode / `defaultMode` / `hard_deny`.

**smith-checkpoint**: Memory checkpoint — save the current session's durable state into both memory systems (Serena memory, Basic-Memory note) in their required formats. Invoke with /smith-checkpoint.

**smith-tickets**: Ticket creation by convention — create Jira issues/sub-tasks in Job Story form, Japanese description, under the correct parent Epic, after reading the relevant context. Invoke with /smith-tickets.

**smith-research**: Proactive research protocol for version queries, APIs, and best practices. Use when answering questions about library versions, API documentation, or technology assessments. Covers research triggers, source citation, and confidence indicators.

**smith-secret_guard.local**: Local-only leak guard for the PUBLIC smith repo — scan staged diff, commit message, branch name, and PR title against the gitignored denylist of internal tokens (Jira keys, codenames, internal services) before any commit/push. Use when committing/pushing in the smith repo, editing a SKILL.md/AGENTS.md, writing a commit message or PR title, or when the user mentions a leak, a Jira key, or internal project names.

### Other

