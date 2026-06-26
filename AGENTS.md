# Smith AI Agent Skills

AI agent skills for development with progressive disclosure.

<metadata>

- **Always loaded**: @smith-principles/SKILL.md, @smith-standards/SKILL.md, @smith-guidance/SKILL.md, @smith-ctx/SKILL.md
- **Load condition**: Session start (all platforms)
- **Token budget**: per-skill <2000 tokens; keep this always-loaded index minimal

</metadata>

## Platform Context (Load First)

<required>

**Auto-detect platform in order:**
1. **MCP servers**: Check for `cursor-ide-browser` or `cursor-browser-extension` → **Cursor** → Load `@smith-ctx-cursor/SKILL.md`
2. **MCP servers**: Check for `kiro-*` → **Kiro** → Load `@smith-ctx-kiro/SKILL.md`
3. **System prompt**: If mentions "Claude Code" → **Claude Code** → Load `@smith-ctx-claude/SKILL.md`
4. **Default**: Ask user or use Cursor (most common)

</required>

**Manual override** (if auto-detection fails):
- **Cursor**: Load `@smith-ctx-cursor/SKILL.md`
- **Kiro**: Load `@smith-ctx-kiro/SKILL.md`
- **Claude Code**: Load `@smith-ctx-claude/SKILL.md`

## Claude Code Skills Integration

<context>

**Symlink for skill discovery:**
```shell
ln -sf $HOME/.smith $HOME/.claude/skills
```

All skills use "smith-" prefix to avoid conflicts with Claude Code built-in commands (`/context`, `/ide`, `/skills`, etc.).

</context>

## Serena MCP Integration (If Available)

<context>

When Serena MCP is available, prefer Serena tools for file I/O and semantic
edits, and use Serena project memories for durable cross-session context.
See `@smith-serena/SKILL.md` for tool-preference and memory-sync rules.

**Loading protocol** (self-contained — no external memory required):
- On entry, read each workspace `AGENTS.md` / `CLAUDE.md`. Claude Code
  auto-loads `CLAUDE.md` (not a bare `AGENTS.md`) — see `@smith-skills/SKILL.md`.
- Load applicable smith skills via the Semantic Activation triggers below.

</context>

## Always Load

@smith-principles/SKILL.md @smith-standards/SKILL.md @smith-guidance/SKILL.md @smith-ctx/SKILL.md

## Core Principles

DRY, KISS, YAGNI, SOLID, HHH — defined in @smith-principles/SKILL.md
(force-loaded) and @smith-guidance/SKILL.md (HHH). Not restated here, to
avoid duplicating the force-loaded source.

## Skill Loading

<required>

**Skills auto-trigger by their frontmatter `description`** — the native Claude
Code mechanism. The `skill-router` UserPromptSubmit hook
(`@smith-ctx-claude/scripts/skill-router.mjs`, table `skill-triggers.json`)
deterministically surfaces candidate skills from your input every prompt as a
safety net.

**When a trigger fires, invoke the skill via the Skill tool** — that loads its
SKILL.md for you. Read a SKILL.md by hand only to quote or edit it, never as a
substitute for invoking.

No "identify → Read → unload" bookkeeping: it depended on model discipline and
was ~0% executed in practice (smith-* skills almost never loaded; the router
hook replaces it). See `@smith-ctx-claude/SKILL.md`.

</required>

## Skill Notification (optional)

<context>

When a skill materially shapes your approach, one short line suffices:
`using @skill-name (reason)`. The former "ALWAYS notify on every state change"
ceremony is dropped — it was unenforceable (~8% real compliance) and the Skill
tool already records invocation.

</context>

## Proactive Context Management

<required>

- **At warning threshold**: Warn, prepare retention criteria, unload unused skills
- **At critical threshold**: CRITICAL - context reset required (see platform skill for thresholds and command)

</required>

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
<skill name="smith-validation" description="Hypothesis testing, debugging">`@smith-validation/SKILL.md`</skill>
<skill name="smith-postmortem" description="Incident postmortem methodology">`@smith-postmortem/SKILL.md`</skill>
<skill name="smith-dialectic" description="Socratic plan interview against project docs and code">`@smith-dialectic/SKILL.md`</skill>

<!-- Testing -->
<skill name="smith-tests" description="Testing standards, TDD workflow">`@smith-tests/SKILL.md`</skill>
<skill name="smith-playwright" description="Playwright testing, proactive failure monitoring">`@smith-playwright/SKILL.md`</skill>
<skill name="smith-browser_mcp" description="Browser MCP reliability: Chrome for Testing default, non-CfT overrides forbidden">`@smith-browser_mcp/SKILL.md`</skill>

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
<skill name="smith-stacks" description="Stacked PR workflows">`@smith-stacks/SKILL.md`</skill>

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

<!-- Hiring -->
<skill name="smith-hiring" description="Hands-on IC engineer resume/CV screening: 4-gate rubric, evidence-quoting procedure, submission safety">`@smith-hiring/SKILL.md`</skill>

<!-- Commands (invoke with /name; also auto-trigger on task match) -->
<skill name="smith-ship" description="/smith-ship — review-to-convergence then atomic commit, push, PR, address review, squash-merge, ff-only sync, cleanup">`@smith-ship/SKILL.md`</skill>
<skill name="smith-review" description="/smith-review — multi-round local worktree review until convergence (no shipping)">`@smith-review/SKILL.md`</skill>
<skill name="smith-stack" description="/smith-stack — atomic stacked branches in separate worktrees → review each → stacked PRs">`@smith-stack/SKILL.md`</skill>
<skill name="smith-checkpoint" description="/smith-checkpoint — save session state to all 3 memory systems in their formats">`@smith-checkpoint/SKILL.md`</skill>
<skill name="smith-recon" description="/smith-recon — guided, bounded multi-source investigation; asks sources, cross-verifies, evidence-linked brief">`@smith-recon/SKILL.md`</skill>
<skill name="smith-tickets" description="/smith-tickets — create Jira tickets by convention (Job Story, Japanese desc, correct parent Epic)">`@smith-tickets/SKILL.md`</skill>
</available_skills>

## Semantic Activation

<required>

**Human-readable mirror of `@smith-ctx-claude/skill-triggers.json` (the
skill-router hook's table — keep the two in sync). On a task match, invoke the
skill via the Skill tool:**

**Languages**: Python → `@smith-python/SKILL.md`, TypeScript → `@smith-typescript/SKILL.md`, Nuxt → `@smith-nuxt/SKILL.md`
**Testing**: Tests/TDD → `@smith-tests/SKILL.md`,
  Playwright → `@smith-playwright/SKILL.md`
**Browser MCP**: chrome-devtools-mcp / @playwright/mcp invocation OR browser MCP launch failure → `@smith-browser_mcp/SKILL.md`
**Workflow**: Ralph Loop → `@smith-ralph/SKILL.md`
**Plan**: Plan execution → `@smith-plan/SKILL.md`,
  Claude Code hooks/`!load-plan` → `@smith-plan-claude/SKILL.md`
**Automation**: `/loop`, `/schedule`, `ScheduleWakeup`, `Monitor`, polling for external state → `@smith-automation/SKILL.md`
**Subagents**: spawning Task/Agent subagents, delegating investigation, parallel orchestration, OR a subagent touching shared state (PR/issue/file/remote) → `@smith-subagents/SKILL.md`
**Git/GitHub**: Commits/branches → `@smith-git/SKILL.md` + `@smith-style/SKILL.md`,
  Worktrees (raw git) → `@smith-git/SKILL.md`,
  Worktrees (Claude Code tools: EnterWorktree/ExitWorktree, bgIsolation, squash-merge sync) → `@smith-worktree/SKILL.md`,
  PRs/reviews/`gh pr*` → `@smith-gh-pr/SKILL.md` + `@smith-gh-cli/SKILL.md` + `@smith-style/SKILL.md`,
  Reviewing or approving a PR/diff/change (`/smith-review`, `/review-pr`) → `@smith-review/SKILL.md` + `@smith-gh-pr/SKILL.md`
**Claude Code**: Hooks/permissions/agents/model routing → `@smith-ctx-claude/SKILL.md`,
  MCP setup/lifecycle → `@smith-tools/SKILL.md` + `@smith-research/SKILL.md` + `@smith-validation/SKILL.md`,
  Auto-mode classifier denial OR classifier-sensitive action (e.g. force-push, push to main, prod deploy, IAM grant, external-content duplication, sandbox network call) → `@smith-auto_mode/SKILL.md`
**Settings**: editing settings.json/.claude config, which scope a key belongs in, OR building a convention-validator/enforcement hook → `@smith-settings/SKILL.md`
**External-dependency recommendation** (proposing any integration/config/tooling mechanism whose success depends on external system behavior — MCP, OAuth/auth flow, provider API, CLI flag, feature/version support): MUST load `@smith-research/SKILL.md` + `@smith-validation/SKILL.md` and verify the mechanism works (official docs + issue tracker) BEFORE proposing it. A proposed mechanism is a claim; claims need evidence.
**Reasoning**: Analysis → `@smith-analysis/SKILL.md`, Design → `@smith-design/SKILL.md`, Debug → `@smith-validation/SKILL.md`,
  Dialectic/grill/stress-test plan → `@smith-dialectic/SKILL.md`
**Slack**: drafting/replying in Slack, any `slack_send_message*` / `slack_*` MCP tool, OR a `/slack:*` command → `@smith-slack/SKILL.md`
**Other**: Prompts → `@smith-prompts/SKILL.md`, XML → `@smith-xml/SKILL.md`
**Hiring**: Resume/CV screening, candidate grading, hands-on/IC vs PM/lead judgment, scout/ATS batch review → `@smith-hiring/SKILL.md`
**Commands** (user types `/smith-X`, or auto-trigger on task match): ship a change end-to-end → `@smith-ship/SKILL.md`; review-to-convergence only → `@smith-review/SKILL.md`; stacked branches → `@smith-stack/SKILL.md`; save all 3 memories → `@smith-checkpoint/SKILL.md`; guided multi-source investigation → `@smith-recon/SKILL.md`; Jira tickets by convention → `@smith-tickets/SKILL.md`

</required>

## Platform Compatibility

**Native AGENTS.md**: Claude Code, OpenAI Codex, Amp, Jules, Kiro, Cursor
**Config required**: Gemini CLI, Aider
**Note**: Cursor also supports `.mdc` format, but AGENTS.md works via MCP integration

## Kiro Terminal (CRITICAL)

<forbidden>

- echo with double quotes (hangs)
- heredoc syntax (fails)
- Complex zsh themes (hangs)

</forbidden>

<required>

- Use Python scripts for file generation
- Prefer Serena MCP tools over Kiro native file operations
- Use single quotes or write to file instead of echo

</required>

<related>

- @smith-principles/SKILL.md - Core principles (DRY, KISS, YAGNI, SOLID)
- @smith-standards/SKILL.md - Universal coding standards
- @smith-guidance/SKILL.md - AI agent behavior patterns
- @smith-ctx/SKILL.md - Context management, proactive recommendations

</related>
