# AI-Native SDLC — Templates and Worked Examples

Full detail supporting `../SKILL.md`. Source: Anthropic, ["The AI-Native
SDLC playbook"](https://claude.com/blog/the-ai-native-sdlc-playbook)
(2026-08-21, retrieved 2026-09-08) and the companion
["AI-Native SDLC Playbook" course](https://academy.claude.com/courses/ai-native-sdlc-playbook)
on Claude Academy (retrieved 2026-09-10). Three provenance tiers, because
the distinction matters when you copy from here:

**Verbatim** — the `spec.md` prompt, `CLAUDE.md` block, evals workflow,
`REVIEW.md` and `bands.yaml` are Anthropic's own worked examples,
reproduced unchanged.

**Adapted** — the production-gate hook and the managed-settings JSON began
as Anthropic's examples and have since been rewritten here. The gate now
matches a structured tool argument rather than substrings of a shell
command, and the managed-settings block narrows its `Bash(git *)` allow
rule, re-roots its `denyRead` paths, and adds `strictAllowlist`,
`allowManagedDomainsOnly`, `allowManagedReadPathsOnly`,
`strictPluginOnlyCustomization`, `allowedMcpServers` and a higher
`requiredMinimumVersion`. Treat them as this repository's guidance, not as
quotations.

**Genericized** — the `intent.md` and `plan.md` "templates" are not
verbatim. Anthropic's actual examples use a specific "claims status
self-service" scenario (author "J. Ortiz," a claims-center problem); the
section headers below match that example exactly, but the content under
each is fillable placeholders for reuse, not quoted.

## intent.md template (section headers verbatim; content genericized)

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
and user experience standards. Document the spec fully as spec.md, ready to hand to
the engineering team. Describe clearly any areas of concern, especially
where you cannot satisfy contradicting policies.
```

## spec.md as an EARS plus Given-When-Then contract (recommended notation, smith addition)

The playbook mandates no internal notation for `spec.md` — this fills that
gap. One requirement per `§section`, in EARS (Easy Approach to Requirements
Syntax) form, each paired with a Given-When-Then (GWT) acceptance scenario:

```
# <Feature> — Spec (the contract)

> The *why* for this feature lives here; the procedure in the relevant
> skill. Only decisions that outlive this cycle move to design.md, which
> is optional — see the ADR-log section below.

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

## design.md as an Architecture Decision Record (ADR) log (durable cross-cutting knowledge, smith addition)

One per subsystem/component, not per feature — it does not share
`spec.md`'s cardinality or lifecycle, so title it after the subsystem, not
the feature that happened to prompt an entry. Produced during Design-stage
sessions (that's where design decisions get made — see `../SKILL.md`
Stage 2), but shares `CLAUDE.md`'s durable, cross-cutting lifecycle rather
than `spec.md`'s per-cycle one. Minimal MADR (Markdown Architectural Decision
Records, a template for writing ADRs as Markdown files —
https://adr.github.io/madr/) form, append-only:

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

## plan.md template (Build stage; section headers verbatim, content genericized)

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
Generated files under src/gen/ and anything continuous integration
already enforces.
```

## Production-gate hook (Deploy stage)

Two rules make this gate meaningful, and both are easy to get wrong:

**Gate a structured tool, not a shell string.** A hook that decides by
searching the raw command text for `deploy` and `production` misses
`make deploy ENV=prod`, `kubectl apply -f prod.yaml`, `helm upgrade prod
./chart` and `./deploy.sh prod` — every ordinary phrasing of the action it
names. Expose deployment as the MCP tools this playbook already recommends
(`deploy`/`status`/`rollback`, tiered by environment) so the gate reads a
named `environment` argument instead of guessing, and gate every tool in
that trio that changes production state — `rollback` is an unreviewed
production change too.

**Do not put the server's name in the matcher.** A tool arrives as
`mcp__«server»__«tool»`, and `«server»` is the label whoever ran
`claude mcp add` chose, not the endpoint. A matcher of
`mcp__deploy__(deploy|rollback)` is therefore satisfied or evaded by
renaming: register the same approved endpoint as `shipping` and its tools
become `mcp__shipping__deploy`, which the hook never sees. `mcp__[^_]+__`
matches whatever the server is called, so the gate keys on the *action*.
Endpoint identity is a separate job, and `allowedMcpServers` with
`serverUrl` entries is what does it — the two controls compose, and
neither substitutes for the other.

The `Bash` denials below raise the cost of going around the tool; they do
not close the door. The permissions documentation says so directly —
"Bash permission patterns that try to constrain command arguments are
fragile" — and any such list is easy to read as more complete than it is.
This one does not cover `aws`, `gcloud`, `az`, `docker`, `argocd`, `flux`
or `ssh`, and `Bash(./deploy.sh *)` matches neither `bash deploy.sh` nor an
absolute path to the same script. Enumerating spellings is a losing game;
the real boundary is the sandbox's network allowlist plus gating the MCP
tool.

**Register it in managed settings.** A gate in `.claude/settings.json` is
a file the agent it gates can edit, and it is switched off entirely by
`allowManagedHooksOnly` (see the managed-settings example below).

Managed settings:
```json
{
  "permissions": {
    "deny": ["Bash(kubectl *)", "Bash(helm *)", "Bash(terraform *)", "Bash(make deploy *)", "Bash(./deploy.sh *)"]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__[^_]+__(deploy|rollback)",
        "hooks": [
          { "type": "command",
            "command": "/opt/org-hooks/production-gate.sh" }
        ]
      }
    ]
  }
}
```

`/opt/org-hooks/production-gate.sh` — blocks anything it cannot positively
classify as authorized, so a malformed payload or a missing dependency
denies the deploy instead of waving it through:
```bash
#!/bin/bash
set -euo pipefail

deny() { printf '%s\n' "$1" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || deny "production-gate: jq unavailable, denying."

payload=$(cat) || deny "production-gate: unreadable payload, denying."
environment=$(jq -er '.tool_input.environment' <<<"$payload") \
    || deny "production-gate: no environment argument, denying."

case "$environment" in
    dev|development|test|staging) exit 0 ;;
esac

verify_release_authorization() {
    local env="$1"
    local ticket="${RELEASE_APPROVAL:-}"
    local token="${RELEASE_VERIFIER_TOKEN:-}"
    [[ -n "$ticket" && -n "$token" ]] || return 1
    curl -sf --max-time 5 -H "Authorization: Bearer $token" \
        "https://releases.internal.example.com/api/authorizations/$ticket" \
        | jq -e --arg e "$env" '.status == "approved" and .environment == $e' >/dev/null
}

verify_release_authorization "$environment" \
    || deny "production-gate: no approved release authorization for '$environment' — file a release ticket, then re-run with RELEASE_APPROVAL set to its id."
exit 0
```

Two spellings of this gate look equivalent and are not.

**Allowlist the environments that may skip the gate; never denylist the one
that may not.** `[[ "$environment" != "production" ]] && exit 0` approves
every string that is not byte-identical to `production` — so `Production`,
`PROD`, `prod`, `prod-us` and `production-eu` all sail through, and so does
any environment name added to the deploy tool after the hook was written.
`environment` comes from model-supplied `tool_input`, so it is exactly the
field not to pattern-match optimistically. The `case` above inverts the
default: an unrecognized environment needs the authorization.

**Prefer `«condition» || «exit»` over `[[ … ]] && exit 0`.** A false `[[ … ]]`
in an `&&` list leaves the list's status at 1. Mid-script that is harmless —
`set -e` exempts an AND-OR list's non-final commands, and does not trigger on
the list itself — but as the script's *last* command it becomes the script's
exit status, and a `PreToolUse` hook exiting 1 is a non-blocking error where
only `exit 2` blocks. A gate is exactly the kind of script that grows a new
branch at the end later, so the `||` spelling is the one that stays correct
when it does.

`exit 2` is what blocks the action; the message on stderr goes to Claude,
which is why each one names the approval route.

**Never let non-emptiness be the check.** The `env` settings key has "Any
file" scope and its values reach every subprocess Claude Code starts, hooks
included, so `{"env": {"RELEASE_APPROVAL": "x"}}` in a settings file
satisfies a `[[ -n … ]]` test — and denying `Edit(.claude/settings.json)`
does not close that, because `.claude/settings.local.json` outranks it (and
is where Claude Code itself writes a "don't ask again" rule), with
`~/.claude/settings.json` outside the repository entirely. Enumerating
files to deny is the losing half of this problem.

The winning half is to stop treating the variable as the credential.
`RELEASE_APPROVAL` above carries a release *identifier*, which the gate
looks up against the release system over an authenticated call; forging the
variable then only names a ticket that has to already exist, be approved,
and match this environment. `RELEASE_VERIFIER_TOKEN` belongs to the machine
the hook runs on, deployed the same way the hook is — if it can be set from
a settings file, you have moved the problem rather than solved it.

## Worked example: managed settings for a regulated enterprise

Deployed by the platform team via mobile device management (MDM) or the
admin console. Engineers cannot override its boolean keys — but "managed"
is not a blanket guarantee: array keys such as `sandbox.excludedCommands`
and `sandbox.filesystem.allowRead` merge entries from every settings scope
the session loads, so a developer can append to them. `allowRead` has a
managed-only lock, `allowManagedReadPathsOnly`, and `network.allowedDomains`
has its own, `allowManagedDomainsOnly` — both set below. `excludedCommands`
has neither, so keep that list narrow and treat it as the seam in this
policy.

```json
{
  "permissions": {
    "deny": ["Read(.env*)", "Read(./secrets/**)", "WebFetch", "Bash(curl *)", "Bash(wget *)", "Bash(git -c *)", "Bash(git --config-env *)", "Bash(git --config-env=*)", "Bash(git --exec-path *)", "Bash(git --exec-path=*)"],
    "allow": ["Bash(git status *)", "Bash(git diff *)", "Bash(git log *)", "Bash(git add *)", "Bash(git commit *)", "Bash(make build)", "Bash(make test)", "Bash(make lint)"],
    "disableBypassPermissionsMode": "disable"
  },
  "allowManagedPermissionRulesOnly": true,
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false,
    "filesystem": {
      "denyRead": ["~/**/.env", "~/**/.env.*", "~/**/secrets/**"],
      "allowManagedReadPathsOnly": true
    },
    "network": {
      "allowedDomains": ["git.internal.example.com", "registry.npmjs.org"],
      "strictAllowlist": true,
      "allowManagedDomainsOnly": true
    },
    "credentials": {
      "files": [
        { "path": "~/.ssh", "mode": "deny" },
        { "path": "~/.aws/credentials", "mode": "deny" }
      ],
      "envVars": [{ "name": "GITHUB_TOKEN", "mode": "deny" }]
    }
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__[^_]+__(deploy|rollback)",
        "hooks": [
          { "type": "command", "command": "/opt/org-hooks/production-gate.sh" }
        ]
      }
    ]
  },
  "allowManagedHooksOnly": true,
  "disableSideloadFlags": true,
  "strictPluginOnlyCustomization": true,
  "allowedMcpServers": [
    { "serverUrl": "https://mcp.internal.example.com/deploy/*" },
    { "serverUrl": "https://mcp.internal.example.com/docs/*" }
  ],
  "allowManagedMcpServersOnly": true,
  "strictKnownMarketplaces": [{ "source": "github", "repo": "example-corp/approved-plugins" }],
  "requiredMinimumVersion": "2.1.257"
}
```

What each line buys, and — just as important — what it does not:

`permissions.deny` binds the `Read` tool, the file commands Claude Code
recognizes in Bash (`cat`, `head`, `sed`, …) and Bash redirection targets.
It does *not* reach a subprocess that opens a file itself, so it is a
prompt-shaping rule, not secret containment; `sandbox.filesystem.denyRead`
is what enforces at the operating-system level. Redirection coverage is
also version-gated — input targets (`< file`) are checked only in v2.1.257
and later, which is why `requiredMinimumVersion` is pinned there rather
than at `strictAllowlist`'s lower floor.

`sandbox.filesystem.denyRead` entries here are `~/`-rooted deliberately. A
`./`-prefixed path resolves to the project root **only in project
settings**; in a managed or user file the same string resolves relative to
`~/.claude`, so `"./secrets/**"` in this file would guard nothing a
developer's checkout contains. Note also that `~/**/.env` matches only the
literal name, hence the separate `~/**/.env.*` entry for `.env.production`
and friends — the `Read(.env*)` rule above covers those, but only for the
tools `permissions` reaches. A checkout outside the home directory needs
its own absolute entry.

`permissions.allow` pre-approves the safe inner loop so the deny list
doesn't cause prompt fatigue — but each entry must name a subcommand.
`Bash(git *)` would allow *every* git command, including
`git -c core.pager='cat .env' log`, because `-c` makes git run a program
you name; that single rule would hand back everything the `Read` denials
above were meant to withhold. Hence the per-subcommand allow list and the
denials of the option spellings that do the same thing — `-c`,
`--config-env` (same effect, value read from an environment variable) and
`--exec-path` (changes which programs git executes). Treat that denylist
as best-effort: it enumerates the spellings known today, and with the
sandbox on and auto-allow at its default, sandboxed Bash runs without a
prompt so the *allow* list shapes prompting rather than enforcement. The
sandbox is the boundary; these rules reduce what has to reach it.
(https://code.claude.com/docs/en/permissions, retrieved 2026-09-08)

`disableBypassPermissionsMode` + `allowManagedPermissionRulesOnly` mean no
engineer, project file, or CLI flag can widen the *permission* rules. That
lock does not extend to the sandbox's array keys, which merge across every
settings scope: `allowManagedDomainsOnly` locks the network list to
managed values and `allowManagedReadPathsOnly` does the same for
`filesystem.allowRead`. Without the latter, a developer adding a narrower
`allowRead` re-opens the part of the denied region it covers.

`failIfUnavailable` + `allowUnsandboxedCommands` make the sandbox a gate:
Claude Code refuses to start when the sandbox cannot initialize, and a
command that fails inside the sandbox cannot be retried outside it.

`network.allowedDomains` on its own only *pre-allows* domains so
sandboxed commands don't prompt for them; an unlisted host still prompts,
and one "don't ask again" widens the list. `strictAllowlist` is what turns
it into deny-by-default, and it needs Claude Code v2.1.219 or later. Pin
`requiredMinimumVersion` to the highest floor any key or claim in the file
depends on, not the first one you look up — here that is the v2.1.257
input-redirect check, not `strictAllowlist`'s v2.1.219.
Even then the boundary is hostname-based: the proxy decides from
the client-supplied hostname without inspecting TLS, so domain fronting
can reach hosts outside the allowlist. A threat model that must prevent
exfiltration needs a TLS-terminating proxy, not this allowlist.
(https://code.claude.com/docs/en/sandboxing, retrieved 2026-09-08)

`credentials` denies shell-level reads of `~/.ssh`/`~/.aws/credentials`
that a sandboxed command could otherwise still reach — sandboxed Bash
commands only.

`allowManagedHooksOnly` blocks user, project, local and plugin hooks. Two
kinds still run alongside the ones deployed in this file: hooks from
plugins force-enabled through managed `enabledPlugins`, and SDK hooks. So
"only what the organization deploys" is accurate, "only what is in this
file" is not — audit `enabledPlugins` as part of the same policy. That is
why the
production gate above is registered here and not in
`.claude/settings.json`: with this flag set and no `hooks` block, a
project-scoped gate is silently disabled — committed, reviewed, believed
to be enforcing, never executed.

`disableSideloadFlags` rejects the CLI flags that sideload plugins,
subagents and MCP servers, and `strictKnownMarketplaces` allowlists the
marketplace sources users may install from. Neither one stops a skill
dropped into `~/.claude/skills/` or an agent in `.claude/agents/`:
`strictPluginOnlyCustomization` is the setting that blocks skills, agents,
hooks and MCP servers from user and project sources, so it is what makes
"everything arrived through the approved marketplace" true.

`allowManagedMcpServersOnly` decides *which* allowlist is honored — the
managed one — and nothing more. It is `allowedMcpServers` that is the
allowlist, and leaving it out means "all servers allowed", so the flag on
its own enforces nothing. Both keys are set above, together.

Two shape rules on that key are easy to get wrong and both fail quietly.
Each entry is an *object* carrying one of `serverUrl`, `serverCommand` or
`serverName` — a bare string like `"deploy"` fails schema validation, and
an invalid entry is stripped rather than rejected loudly. Strip them all
and what remains is `[]`, which means "no servers allowed": every server
silently disappears from `/mcp` and `claude mcp list`, including the
deploy server the gate above exists to guard, so the gate's matcher would
never fire again. And match on `serverUrl` or `serverCommand`, not
`serverName`: the docs state plainly that a `serverName` entry "is not a
security control", because the name is a label the user assigns, so
anyone can call any server `deploy`.

`requiredMinimumVersion` refuses to start below the assessed floor. Pin it
to the highest floor anything in the file needs, and re-check when you add
a key.
(https://code.claude.com/docs/en/settings-reference, retrieved 2026-09-08)

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
