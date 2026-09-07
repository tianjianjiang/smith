# AI-Native SDLC — Templates and Worked Examples

Full detail supporting `../SKILL.md`. Source: Anthropic, ["The AI-Native
SDLC playbook"](https://claude.com/blog/the-ai-native-sdlc-playbook)
(2026-08-21, retrieved 2026-09-08). Quoted templates and prompts are
Anthropic's own worked examples from that article, reproduced here for
local reference.

## intent.md template

```
# Intent: <short title>
Author: <name> (<team>). Status: draft.

## Problem
<what is broken today, for whom>

## Proposed outcome
<what better looks like>

## Affected users and systems
<who and what this touches>

## Constraints
<hard limits: no new PII, existing auth only, etc.>

## Open questions
<what isn't decided yet>
```

## spec.md prompt (Design stage)

```
Read the attached intent.md and produce a requirements and design spec
for integrating it into our existing codebase. Apply the skills available
to you so the plan conforms to our brand guidelines, security policies
and UX standards. Document the spec fully as spec.md, ready to hand to
the engineering team. Describe clearly any areas of concern, especially
where you cannot satisfy contradicting policies.
```

## spec.md as an EARS+GWT contract (recommended notation, smith addition)

The playbook mandates no internal notation for `spec.md` — this fills that
gap. One requirement per `§section`, in EARS (Easy Approach to Requirements
Syntax) form, each paired with a Given-When-Then acceptance scenario:

```
# <Feature> — Spec (the contract)

> The *why* lives in design.md; the procedure in the relevant skill.

## §<section-name>

**EARS**: While <precondition>, when <trigger>, the system shall <response>.

**GWT**:
- Given <initial context>
- When <event>
- Then <expected outcome>
```

EARS forms: ubiquitous (always true), event-driven (when X), state-driven
(while X), optional-feature (where X is present), unwanted-behaviour (if X,
then). Reference authoritative schemas/code by name rather than restating
their fields — the schema is the source of truth for exact field names.

## design.md as an ADR log (durable cross-cutting knowledge, smith addition)

One per subsystem/component, not per feature — it does not share
`spec.md`'s cardinality or lifecycle, so title it after the subsystem, not
the feature that happened to prompt an entry. Produced during Design-stage
sessions (that's where design decisions get made — see `../SKILL.md`
Stage 2), but shares `CLAUDE.md`'s durable, cross-cutting lifecycle rather
than `spec.md`'s per-cycle one. MADR-minimal (Markdown Architecture
Decision Record) form, append-only:

```
# <Subsystem/component> — Design (ADR log)

> Per-feature contracts live in each change's spec.md; this doc owns the
> *why* for decisions that outlive any single one of them.

## Decision index

- ADR-001 — <title> — accepted — #adr-001

## ADR-001: <title>

**Context and problem**: <what forced a decision>

**Decision drivers**: <constraints that mattered>

**Considered options**:
- Option A — pros / cons
- Option B — pros / cons

**Decision outcome**: <chosen option and why>

**Consequences**: <what this makes easier or harder later>
```

To reverse a decision, append a new ADR that supersedes it and mark the
old entry's status `superseded` — never edit a decided ADR in place.

## plan.md template (Build stage — produced by Claude Code plan mode)

```
# Plan: <short title> (from intent.md <date>)

## Files that change
<file list, new/modified>

## Order of work
1. <step>
2. <step>

## Risks
<what could break, rate limits, migrations, etc.>

## Proof
<what tests/screenshots demonstrate this works>
```

## CLAUDE.md verification block (Test stage)

```
## Verifying your work

- Build: make build (must finish with "Build succeeded")
- Test: make test (all green; never skip or delete a failing test)
- Lint: make lint (zero warnings)

Run all three before reporting any task complete, and paste the output.
If a test fails, fix the code, not the test.
```

## Continuous evals workflow (Test stage)

```yaml
name: Agent evals
on:
  pull_request:
    paths: ['CLAUDE.md', '.claude/**']
  schedule:
    - cron: '0 2 * * *'
jobs:
  evals:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm install -g @anthropic-ai/claude-code
      - name: Run eval suite
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          for eval in evals/*.json; do
            claude -p "$(jq -r '.prompt' $eval)" \
              --allowedTools "Read,Edit,Bash(make test)" \
              --output-format json > result.json
            ./evals/check.sh "$eval" result.json
          done
```

## REVIEW.md template (Deploy stage)

```
# Review instructions

## Passes
Run three passes and tag each finding with its pass:
- Bugs: logic errors, broken edge cases, subtle regressions
- Security: injection risks, authentication gaps, PII in logs
- Compliance: the change matches spec.md, plan.md and our design principles

## What Important means here
Reserve Important for findings that would break behavior, leak data
or breach a policy. Style and naming are nits.

## Cap the nits
Report at most five nits per review; summarize the rest as a count.

## Do not report
Generated files under src/gen/ and anything CI already enforces.
```

## Production-gate hook (Deploy stage)

`.claude/settings.json`:
```json
{
    "hooks": {
      "PreToolUse": [
        {
          "matcher": "Bash",
          "hooks": [
            { "type": "command",
              "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/production-gate.sh" }
          ]
        }
      ]
    }
}
```

`.claude/hooks/production-gate.sh`:
```bash
#!/bin/bash
# Production deploys require a named release authorization
cmd=$(jq -r '.tool_input.command' < /dev/stdin)
if [[ "$cmd" == *"deploy"* && "$cmd" == *"production"* ]]; then
   if [ -z "$RELEASE_APPROVAL" ]; then
     echo "Production deploys need a release authorization." >&2
     exit 2 # exit 2 blocks the action; the message goes to Claude
   fi
fi
exit 0
```

## Worked example: managed settings for a regulated enterprise

Deployed by the platform team via MDM or the admin console; engineers
cannot edit or override any of it.

```json
{
  "permissions": {
    "deny": ["Read(.env*)", "Read(./secrets/**)", "WebFetch", "Bash(curl *)", "Bash(wget *)"],
    "allow": ["Bash(git *)", "Bash(make build)", "Bash(make test)", "Bash(make lint)"],
    "disableBypassPermissionsMode": "disable"
  },
  "allowManagedPermissionRulesOnly": true,
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false,
    "network": { "allowedDomains": ["git.internal.example.com", "registry.npmjs.org"] },
    "credentials": {
      "files": [
        { "path": "~/.ssh", "mode": "deny" },
        { "path": "~/.aws/credentials", "mode": "deny" }
      ],
      "envVars": [{ "name": "GITHUB_TOKEN", "mode": "deny" }]
    }
  },
  "allowManagedHooksOnly": true,
  "disableSideloadFlags": true,
  "allowManagedMcpServersOnly": true,
  "strictKnownMarketplaces": [{ "source": "github", "repo": "example-corp/approved-plugins" }],
  "requiredMinimumVersion": "2.1.193"
}
```

What each line buys: `permissions.deny` keeps secrets out of context and
blocks tool-level network egress; `permissions.allow` pre-approves the
safe inner loop so the deny list doesn't cause prompt fatigue.
`disableBypassPermissionsMode` + `allowManagedPermissionRulesOnly` means no
engineer, project file, or CLI flag can widen the rules. `sandbox` closes
the gap permissions can't — a tool-level deny on WebFetch doesn't stop a
shell command reaching the network; the OS-level domain allowlist does.
`credentials` denies shell-level reads of `~/.ssh`/`~/.aws/credentials`
that a sandboxed command could otherwise still reach. `allowManagedHooksOnly`
means the approval gates in this file are the only hooks that run.
`disableSideloadFlags` + `strictKnownMarketplaces` means every skill,
agent, hook and MCP server arrived through the approved plugin
marketplace, never a home directory. `requiredMinimumVersion` refuses to
start below the assessed floor.

## bands.yaml (Maintain stage — control-band config)

```yaml
metric: ci_test_failure_rate
baseline: rolling_30d
rules: western_electric
tiers:
  1sigma: { action: log }
  2sigma: { action: diagnose,
            tools: "Read,Grep,Bash(gh run view *)" }
  3sigma: { action: propose,
            routes: [pull_request, runbook:rollback-deploy] }
```

Detection stays entirely deterministic (mean/stddev + Western Electric
rules over a rolling window); a model is invoked only once a band is
breached, and the tier that fired sets what it may do.

## Legacy systems and the source of truth

Applies to every artifact the process produces. Existing SDLC processes
likely already track artifacts, just not in markdown — Jira for work
items, a regulatory-traceability tool for requirements, Figma for design,
a change board for approvals. Name one system as the source of truth per
artifact type:

- **The repo as source of truth.** Markdown artifacts are authoritative;
  the legacy system references files within commits. Cleanest for
  engineering-led organizations — one tool, one timestamp authority.
- **The legacy system as source of truth.** Jira/ServiceNow/the
  requirements tool holds the authoritative record; markdown artifacts are
  working copies. Claude reads the record at session start and writes the
  outcome back through an MCP connector in the same session.
- **Linkage as the minimum bar.** Artifacts note the record ID; legacy
  records contain the commit SHA. Good starting point when transitioning,
  accepting two sources of truth for now.

## Recommended tools referenced by the playbook

- **Claude Code** — interactive build/plan sessions, worktrees, subagents
- **Claude Code for Enterprise** — managed settings, sandboxing, hooks
- **Claude Cowork** — collaborative sessions for non-engineers
- **Claude Design** — UI mockups from `intent.md`, exported to Claude Code
- **Claude Security** — scheduled codebase scans, confidence-rated findings
- **Claude Tag** (public beta) — on-call in Slack/Teams, incident response
- **Code Review** (research preview) — managed PR review, or
  `claude-code-action` self-hosted for pipeline control / cloud routing
  (AWS Bedrock, Google Vertex, Microsoft Foundry)

## Documentation the playbook points to

- Admin setup: `code.claude.com/docs/en/admin-setup`
- Settings reference: `code.claude.com/docs/en/settings`
- Server-managed settings: `code.claude.com/docs/en/server-managed-settings`
- Permissions: `code.claude.com/docs/en/permissions`
- Sandboxing: `code.claude.com/docs/en/sandboxing`
- Hooks guide/reference: `code.claude.com/docs/en/hooks-guide`, `.../hooks`
- Skills: `code.claude.com/docs/en/skills`
- Plugin marketplaces: `code.claude.com/docs/en/plugin-marketplaces`
- Managed MCP: `code.claude.com/docs/en/managed-mcp`
- Enterprise deployment: `code.claude.com/docs/en/third-party-integrations`
- Enterprise network config: `code.claude.com/docs/en/network-config`
- Monitoring (OpenTelemetry): `code.claude.com/docs/en/monitoring-usage`
- Analytics dashboard: `code.claude.com/docs/en/analytics`
- Compliance API: `platform.claude.com/docs/en/manage-claude/compliance-api`
- Security model: `code.claude.com/docs/en/security`
