# smith-ctx-claude — Reference (Layer 3)

<metadata>

- **Read when**: Configuring hooks, permission modes, agents, model routing, or
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

### Tool Output Hygiene Hook

**PostToolUse context reminder** — injects reminder when tool output >5K tokens:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "hooks": [{
          "type": "command",
          "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/tool-output-hygiene.mjs\""
        }]
      }
    ]
  }
}
```

**Triggers**: any tool call whose `tool_response` is present; for `Bash` the
size estimate covers `stdout`+`stderr`, for every other tool it covers the
whole `tool_response` object serialized to JSON (a rough proxy, not an exact
token count — good enough to catch a large Read/Grep/WebFetch result).

**Action**: Injects reminder as `additionalContext` (and `systemMessage`)
suggesting to summarize findings and use file:line references instead of
keeping full output in context.

**Registration**: Add to `~/.claude/settings.json` (user-global) or
`.claude/settings.json` (project-specific). Self-check:
`smith-ctx-claude/scripts/tests/tool-output-hygiene.test.sh` (run via
`smith-ctx-claude/scripts/tests/run-all.sh`).

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

Cross-ref: `@smith-mode-plan-claude/SKILL.md` for plan-specific hooks.

## Permission Modes

**6 permission modes** (`permissions.defaultMode` in settings):
- `default` — approve each tool call individually
- `acceptEdits` — auto-approves file edits/writes + common filesystem Bash (mkdir, touch, rm, mv, cp, sed) inside the working directory; other Bash still prompts
- `plan` — read-only; agent plans but cannot execute
- `auto` — classifier auto-handles prompts; safe runs uninterrupted, destructive routes to classifier deny. Requires v2.1.83+, Max/Team/Enterprise/API plan. `defaultMode: "auto"` is honored only in `~/.claude/settings.json` (ignored in `.claude/settings.json`). See `@smith-ctx-claude-mode-auto/SKILL.md` for the denial-recovery protocol.
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
<skill name="smith-ctx-claude-mode-auto" description="Auto-mode classifier denial recovery">`@smith-ctx-claude-mode-auto/SKILL.md`</skill>
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
<skill name="smith-mcp-browser" description="Browser MCP reliability: take each server's default browser, set no override at all">`@smith-mcp-browser/SKILL.md`</skill>

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
<skill name="smith-mode-plan" description="Plan tracking protocol (portable)">`@smith-mode-plan/SKILL.md`</skill>
<skill name="smith-mode-plan-claude" description="Plan automation (Claude Code hooks)">`@smith-mode-plan-claude/SKILL.md`</skill>
<skill name="smith-sdlc" description="AI-native software development lifecycle artifact chain: intent.md, spec.md (Easy Approach to Requirements Syntax plus Given-When-Then), design.md (Architecture Decision Record log), plan.md, evals-on-config, maintain loop">`@smith-sdlc/SKILL.md`</skill>
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
  Playwright → `@smith-playwright/SKILL.md` + `@smith-mcp-browser/SKILL.md`
**Browser MCP**: chrome-devtools-mcp / @playwright/mcp invocation, browser MCP launch failure, OR browser login / interactive auth (login/sign-in near browser/site/portal wording) → `@smith-mcp-browser/SKILL.md`
**Workflow**: Ralph Loop → `@smith-ralph/SKILL.md`,
  Dev-initiation verbs (implement/develop/fix/add feature/modify/improve/harden/refactor …) → `@smith-dev/SKILL.md` + `@smith-git/SKILL.md` + `@smith-worktree/SKILL.md` (router also emits the branch-first note: dedicated branch+worktree BEFORE the first edit)
**Plan**: "execute/load/run/implement the plan", "plan mode" → `@smith-mode-plan/SKILL.md` + `@smith-mode-plan-claude/SKILL.md` (one rule, both skills)
**SDLC (software development lifecycle)**: `intent.md`/`spec.md`/`design.md`, AI-native or agentic software development lifecycle, the SDLC playbook, an ADR (Architecture Decision Record), Given-When-Then acceptance scenarios, or EARS (Easy Approach to Requirements Syntax) followed by one of `syntax`/`notation`/`form(s)`/`format`/`requirement(s)` — bare `EARS` deliberately does not trigger, because the router matches case-insensitively and would fire on the English word "ears" → `@smith-sdlc/SKILL.md`
**Automation**: `/loop`, `/schedule`, `ScheduleWakeup`, `Monitor`, polling for external state → `@smith-automation/SKILL.md`
**Subagents**: spawning Task/Agent subagents, delegating investigation, parallel orchestration, OR a subagent touching shared state (PR/issue/file/remote) → `@smith-subagents/SKILL.md`
**Git/GitHub**: Commits/branches → `@smith-git/SKILL.md` + `@smith-style/SKILL.md`,
  Worktrees (raw git) → `@smith-git/SKILL.md`,
  Worktrees (Claude Code tools: EnterWorktree/ExitWorktree, bgIsolation, squash-merge sync) → `@smith-worktree/SKILL.md`,
  PRs/reviews/`gh pr*` → `@smith-gh-pr/SKILL.md` + `@smith-gh-cli/SKILL.md` + `@smith-style/SKILL.md`,
  Reviewing or approving a PR/diff/change (`/smith-review`, `/review-pr`) → `@smith-review/SKILL.md` + `@smith-gh-pr/SKILL.md` (router also emits the suggestion-block note below),
  Inline review comments / committable `suggestion` blocks → `@smith-gh-pr/SKILL.md` (router also emits: a mechanical fix MUST carry the block, not prose describing the edit)
  Running or interpreting a CodeRabbit review, GitHub App or `coderabbit` command line → `@smith-gh-pr/SKILL.md` + `@smith-review/SKILL.md` (router also emits: a review that did not run looks identical to a clean one — check status, not the finding count)
**Claude Code**: Hooks/permissions/agents/model routing → `@smith-ctx-claude/SKILL.md` + `@smith-settings/SKILL.md`,
  MCP setup/lifecycle → `@smith-tools/SKILL.md` + `@smith-research/SKILL.md` + `@smith-validation/SKILL.md`,
  Auto-mode classifier denial OR classifier-sensitive action (e.g. force-push, push to main, prod deploy, IAM grant, external-content duplication, sandbox network call) → `@smith-ctx-claude-mode-auto/SKILL.md`,
  Permission denial wording ("denied", "denial", "blocked by auto-mode/classifier") → `@smith-ctx-claude-mode-auto/SKILL.md` (router also emits: do not silently retry a denied action)
**Settings**: editing settings.json/.claude config, which scope a key belongs in, OR building a convention-validator/enforcement hook → `@smith-settings/SKILL.md` + `@smith-ctx-claude/SKILL.md`
**Skill authoring**: `SKILL.md`, `AGENTS.md`, progressive disclosure, "write a skill" → `@smith-skills/SKILL.md`
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
- **Plan-mode transitions** — `EnterPlanMode`/`ExitPlanMode`, and post-`/clear` auto-resume flag (see `@smith-mode-plan-claude/SKILL.md`)
- **Background task completion** — a `Bash(run_in_background)` task ended
- **Date change** — local date rolled over
- **Auto mode active** — session is in auto mode (see `@smith-ctx-claude-mode-auto/SKILL.md`)
- **bg-isolation guard refusal** — first edit in a bg session without a worktree (see `@smith-worktree/SKILL.md`)
## Skill Descriptions (Full Reference)

Complete skill descriptions archived from frontmatter compression (Task 4.4).
Frontmatter now carries <50-char essence only; full descriptions below for
documentation and router-trigger design.

### Context Management

**smith-ctx**: Universal context-management foundation. Always active. Use when context usage grows, when deciding how much of a file or directory to read, or when choosing what to keep or discard across a context reset.

**smith-ctx-claude**: Claude Code context management. Use when context passes the warning threshold in Claude Code, a context hook fires, or choosing between /clear and /compact.

**smith-ctx-cursor**: Cursor context management. Use when working in Cursor and context grows large, or choosing how to pull files into a Cursor chat.

**smith-ctx-kiro**: Kiro platform constraints. Use first in every Kiro session, and when running terminal commands or file operations in Kiro.

### Git & GitHub

**smith-git**: Git workflow gotchas. Use when committing, branching, merging, rebasing, pushing or running raw git worktree commands.

**smith-gh-pr**: GitHub pull request workflows. Use when creating, updating, reviewing or merging a pull request (PR), replying to review comments, or working on stacked PRs.

**smith-gh-cli**: GitHub CLI (gh) gotchas. Use when running any gh command or querying GitHub from the terminal.

**smith-worktree**: Claude Code worktree tools (EnterWorktree, ExitWorktree). Use when entering or leaving a worktree, when an isolation guard refuses an edit or a git command, or cleaning up after a merge.

### Core Principles

**smith-principles**: Fundamental coding principles (DRY, KISS, YAGNI, SOLID). Always active. Use when starting a development task, choosing an approach, or reviewing code quality.

**smith-standards**: Universal coding standards. Always active. Use when writing code, logs, documentation, commit or pull-request text, or any other output.

**smith-guidance**: Core agent steering. Always active. Use for every task, especially before an external write, a disagreement with the user, or a decision request.

### Development Workflows

**smith-dev**: Development workflow standards and quality gates. Use when starting any task that modifies repository files (implement, fix, add, refactor) or running quality checks.

**smith-ship**: Ship pipeline from review to merge. Use when the user runs /smith-ship or asks to ship, land or merge a finished change.

**smith-review**: Multi-round local review loop. Use when the user runs /smith-review or asks to review local changes before a push.

**smith-preflight**: Pre-ship gate with a GO or NO-GO verdict. Use when the user runs /smith-preflight, before any push or pull request, and as the first step of /smith-ship.

### Planning & Analysis

**smith-mode-plan**: Plan mode and plan tracking protocol. ALWAYS load before writing, resuming or updating a plan file. Use when asked for a plan, continuing from a plan file, or logging plan progress.

**smith-mode-plan-claude**: ExitPlanMode pattern for Claude Code. Use when about to call ExitPlanMode, or after the user rejects a plan.

**smith-sdlc**: AI-native software development lifecycle (SDLC) artifacts: intent.md, spec.md, plan.md, a per-subsystem design.md decision log, control-band maintenance. Use when scoping a new feature end to end, setting up a repository's SDLC artifacts or a decision log, or asked about the AI-native SDLC playbook.

**smith-recon**: Guided multi-source investigation. Use when the user runs /smith-recon, asks to resume or reconstruct an earlier work thread, or asks what is known about a topic across sources.

**smith-analysis**: Reasoning frameworks and problem decomposition. Use when planning an implementation, estimating scope, breaking down a complex task, or assessing risk.

**smith-dialectic**: Socratic interview that stress-tests a plan. Use when the user asks to grill, challenge, interrogate or stress-test a plan, to play devil's advocate, or wants shared understanding before implementing.

### Language-Specific

**smith-python**: Python development with uv, pytest and ruff. Use when writing or running Python code, managing packages with uv or Poetry, or running pytest.

**smith-typescript**: TypeScript development standards. Use when working with TypeScript, or configuring path aliases or a test runner.

**smith-nuxt**: Nuxt 3 development patterns. Use when working in a Nuxt project, testing Nuxt components, or configuring Nuxt runtime config.

**smith-playwright**: Playwright testing patterns. Use when running Playwright tests or analysing their failures, screenshots or reports.

### AI & Prompts

**smith-prompts**: Prompt engineering standards. Use when writing or revising a prompt, system prompt or agent instruction file, or optimizing token and cache usage.

**smith-subagents**: Subagent spawning and return discipline. Use when about to spawn an Agent or Task subagent, delegate an investigation, or act on a subagent's report.

**smith-ralph**: Ralph Loop patterns. Use when starting /ralph-loop, managing its iterations, or recovering a loop after a context reset.

**smith-validation**: Hypothesis testing and root cause analysis. Use when debugging, when a bug or test failure is reported, or when verifying a claim before reporting it as fact.

**smith-automation**: Claude Code scheduling primitives (/loop, cron, ScheduleWakeup, Monitor, /schedule). Use when setting up a recurring or scheduled task, polling, or a reminder.

### Documentation & Style

**smith-skills**: Authoring guide for agent skills. Use when creating or editing a SKILL.md, AGENTS.md, CLAUDE.md or other agent instruction file.

**smith-style**: Naming and path standards. Use when naming a file or branch, or writing a commit message.

**smith-xml**: XML tag standards for runtime prompts. Use when constructing a prompt that mixes instructions with embedded data, such as a subagent prompt.

**smith-placeholder**: Placeholder syntax standard («token»). Use when writing prompts, documentation, templates or examples with a value the reader must substitute.

**smith-design**: Architecture and type design principles. Use when designing or reviewing an architecture, refactoring a module or class, or reviewing the design of a type.

### Tools & Integration

**smith-tools**: Tool configuration standards. Use when configuring an IDE, an MCP server, a plugin marketplace or pytest.

**smith-ide**: IDE path variable mappings. Use when editing IDE config files (.vscode/, .kiro/, .cursor/) or translating path variables between IDEs.

**smith-serena**: Serena MCP integration. ALWAYS load before any Serena tool call or memory write. Use when a prompt mentions Serena, and at phase and session boundaries to sync memories.

**smith-mcp-browser**: Browser MCP reliability (chrome-devtools-mcp, Playwright MCP). Use before calling any browser MCP tool, when a browser launch fails, or when a site needs a user login.

**smith-slack**: Slack drafting discipline (draft, never send). Use when drafting or replying to a Slack message, calling any slack_* MCP tool, or running a /slack command.

### Testing & Quality

**smith-tests**: Testing standards and test-driven development (TDD). Use when writing or running tests, fixing a bug with a failing test first, or organizing test files.

**smith-postmortem**: Incident postmortem methodology and templates. Use when conducting a postmortem, writing an incident report, or analysing an outage.

**smith-clarity**: Cognitive trap and logical fallacy detection. Use when making or reviewing a decision, comparing approaches, or checking an argument for faulty reasoning.

### System & Configuration

**smith-settings**: Claude Code settings files and scopes. Use when editing settings.json or .claude config, choosing the scope for a key, or building a hook that enforces a convention.

**smith-ctx-claude-mode-auto**: Claude Code auto mode classifier. Use when an auto-mode denial appeared, before a classifier-sensitive action (force push, production deploy), or when the user mentions auto mode.

**smith-checkpoint**: Memory checkpoint to Serena and Basic-Memory. Use when the user runs /smith-checkpoint, asks to save or hand off session state, and before recommending /clear.

**smith-tickets**: Ticket creation by convention. Use when the user runs /smith-tickets or asks to create, file, split or draft tickets, issues, stories or sub-tasks.

**smith-research**: Proactive research protocol. Use when a question involves library or tool versions, API or CLI behaviour, or current best practices, and before recommending an external dependency.

**local-guard-secret**: Local-only leak guard for the PUBLIC smith repo — scan staged diff, commit message, branch name, and PR title against the gitignored denylist of internal tokens (Jira keys, codenames, internal services) before any commit/push. Use when committing/pushing in the smith repo, editing a SKILL.md/AGENTS.md, writing a commit message or PR title, or when the user mentions a leak, a Jira key, or internal project names.

### Other

