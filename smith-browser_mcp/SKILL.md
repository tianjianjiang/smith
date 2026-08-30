---
name: smith-browser_mcp
description: Browser MCP plugin reliability
---

# Browser MCP Plugin Reliability

**Scope:** chrome-devtools-mcp (`mcp__plugin_chrome-devtools-mcp_chrome-devtools__*`) and Playwright MCP (`mcp__plugin_playwright_playwright__*`)
**Load if:** About to call any browser MCP tool, editing `.mcp.json` / `~/.claude/settings.json` for these plugins, or triaging a browser-launch failure
**Prerequisites:** `@smith-tools/SKILL.md`

## CRITICAL: Browser Selection

- **chrome-devtools-mcp**: omit `--executablePath` AND `--channel`, rather than
  pointing it at `/Applications/Vivaldi.app/...` or any Brave / Arc / Opera /
  Edge binary. Omitting both resolves to Chrome's stable channel — the
  installed Google Chrome — which upstream officially supports: "officially
  supports Google Chrome and Chrome for Testing only". Chrome for Testing is
  the other supported build, but nothing here selects or installs it, so do
  not write a recipe that assumes it.
- **chrome-devtools-mcp**: pass `--isolated` so every run gets a fresh, MCP-owned user-data-dir, rather than reusing a Vivaldi user-data-dir (the one with `VivaldiDirectMatchIcons/`, Vivaldi extension `mpognobbkildjkofajifpdfhcoklimli`). Avoids cross-run profile collisions.
- **Playwright MCP**: take its own default (no `--browser` / `--executable-path` override), or attach to a user-launched instance via `--cdp-endpoint` — not at any other browser. That default is Google Chrome's stable channel, NOT Playwright's bundled Chromium: upstream documents `--browser` as "browser or chrome channel to use" and lists `chrome` as "Google Chrome (default)". The attach flag is `--cdp-endpoint` here; `--browserUrl` is chrome-devtools-mcp's spelling and is not a Playwright MCP option. Note `--browser` accepts `msedge`, so it selects a forbidden browser as readily as an executable path does.
- **Pre-flight** at session start (not just before the first MCP call): inspect all four MCP configuration locations (see "MCP Configuration Locations" below) and confirm NO browser-selecting flag is set on `chrome-devtools-mcp` or `@playwright/mcp` — `--executablePath`, `--executable-path`, `--channel`, and Playwright's `--browser`, in both `--flag value` and `--flag=value` forms. The correct state is no browser override at all, so any of them is the finding, whichever browser it names; `--browser msedge` is as much a violation as an Edge executable path. Run `claude mcp list` first as the authoritative live view; then locate the offending entry when a violation is found — by file via the table, or at the plugin that registers it when it is plugin-installed and so appears in none of the four files.

## MCP Configuration Locations (Pre-flight Scope)

A browser override can live in any of four files, or in a plugin that
registers the server (see below). The
2026-05-21 recurrence was a pair of `*-cft` registrations in `~/.claude.json`
that the previous (settings.json + .mcp.json only) preflight rule never
mentioned. Check all four:

| # | Location | Set by | How to inspect |
| --- | --- | --- | --- |
| 1 | `~/.claude/settings.json#mcpServers` | hand-edit / `/config` | `jq '.mcpServers // {}\|map_values({type,command,args})' ~/.claude/settings.json` |
| 2 | Project `.mcp.json` | hand-edit | `jq '.mcpServers // {}\|map_values({type,command,args})' «project»/.mcp.json` |
| 3 | Project `.claude/settings.json#mcpServers` | hand-edit / `/config` | `jq '.mcpServers // {}\|map_values({type,command,args})' «project»/.claude/settings.json` |
| 4 | `~/.claude.json#mcpServers` | `claude mcp add … -s user` | `jq '.mcpServers // {}\|map_values({type,command,args})' ~/.claude.json` |
| — | live composite of 1–4 + plugin-installed | — | `claude mcp list` |

Project only `type`, `command` and `args` as above. A bare `jq '.mcpServers'`
dumps `env` and `headers` too, which is where MCP servers keep API keys — and
in an agent session that output lands in the transcript. The projection
narrows the exposure without ending it: `args` can itself carry a token or a
credential-bearing URL, and `claude mcp list` prints those same values. Read
the output before pasting any of it. What this check needs is only the
browser-selecting flags, so quoting those alone is always enough.

`claude mcp list` is authoritative — it shows everything currently registered
across scopes, including plugin-installed servers. The file-by-file checks
tell you WHERE to apply the fix once a violation is found. An entry that
`claude mcp list` shows but none of the four files contains is
plugin-installed: fix it at the plugin that registers the server, then rerun
`claude mcp list` to confirm the override is gone.

To remove a user-scope CLI registration: `claude mcp remove «name» -s user`.

**Tool-namespace divergence by install path**: the SAME browser server exposes
different tool names depending on how it was added — plugin-installed gives
`mcp__plugin_«plugin»_«server»__*`; `claude mcp add -s user` gives
`mcp__«name»-cft__*`. The two can also carry DIFFERENT launch arguments (one
bare, one with an explicit `--browser` or `--channel`), so confirm which
registration is live (`claude mcp list`) before assuming a browser variant.

## Failure Signatures → Diagnosis

Treat any of these in MCP stderr as a Vivaldi/non-Chrome misconfiguration:

- `/Applications/Vivaldi.app/Contents/MacOS/Vivaldi` in launch args — `--executablePath` is overridden to Vivaldi
- `VivaldiDirectMatchIcons/...` under the user-data-dir — Vivaldi-specific profile artifacts mixed with MCP profile
- Extension id `mpognobbkildjkofajifpdfhcoklimli` — Vivaldi internal extension loaded
- `gcm/engine/registration_request` errors — Vivaldi GCM registration failing in headless context
- `TimeoutError: async initializeServer: Timeout 180000ms exceeded` shortly after a Vivaldi launch — Vivaldi never finished CDP handshake
- Profile path `ms-playwright/mcp-chrome-*/Default/Vivaldi...` — MCP profile dir contaminated by Vivaldi resources

**Diagnosis**: in every case above, remove the `--executablePath` override from the offending MCP entry and re-run. For chrome-devtools-mcp also add `--isolated`.

## Recipe: chrome-devtools-mcp (default)

In `~/.claude/settings.json` or a project `.mcp.json`, the chrome-devtools-mcp server entry should look like:

```json
{
  "chrome-devtools": {
    "type": "stdio",
    "command": "npx",
    "args": ["chrome-devtools-mcp@latest", "--isolated"]
  }
}
```

No `--executablePath`, no `--channel` — this resolves to Chrome's stable
channel, which upstream officially supports. `claude mcp list` confirms the
configured arguments, which is what an absent override means; it does not
show which browser was installed, selected, or actually launched. To
establish that, inspect the running browser process or the server's own
startup output — and keep the distinction, since assuming a recipe describes
the running system is the error this whole skill was corrected for.

Source: https://github.com/ChromeDevTools/chrome-devtools-mcp (README:
"officially supports Google Chrome and Chrome for Testing only"; `--channel`
"default is the stable channel version"; retrieved 2026-07-12).

## Recipe: Playwright MCP (default)

```json
{
  "playwright": {
    "type": "stdio",
    "command": "npx",
    "args": ["@playwright/mcp@latest"]
  }
}
```

No overrides — this takes Playwright MCP's own default, Google Chrome's stable
channel, the same build chrome-devtools-mcp resolves to. Playwright's bundled
Chromium is NOT that default.

Sources: https://github.com/microsoft/playwright-mcp (`--browser` is "browser or
chrome channel to use") and https://playwright.dev/mcp/configuration/options
(value `chrome` — "Google Chrome (default)") — both retrieved 2026-08-04.

## Interactive Login: Hand Off, Don't Guess

When a page needs interactive authentication (login wall, single sign-on
(SSO) redirect, multi-factor authentication (MFA) prompt, captcha), the
browser is already the right tool — hand the keyboard over instead of asking
abstractly or abandoning the task.

- **Navigate first, then hand off.** Drive the Model Context Protocol (MCP)
  browser to the exact login URL, then say in ONE message: the window is open
  on «page name», complete the login there, tell me when you're done. Never
  ask "do you have an account?" in the abstract, and never report the task
  blocked as "requires authentication" without opening the page.
- **Name the page, don't echo the URL.** Identify it by site and page ("the
  Jira login page"), never by pasting the full URL with its query string or
  fragment — login, magic-link, and password-reset URLs carry single-use
  tokens, and the transcript is the wrong place for them. The user reads the
  address from the browser they are already looking at.
- **Never handle credentials.** Do not ask for a password, token, or one-time
  password (OTP) in chat, and do not fill credential fields on the user's
  behalf even if they offer the values — anything pasted into chat lands in
  the transcript. The user types the credentials themselves, in the MCP-opened
  window (not a separate browser of their own — that session is invisible to
  MCP).
- **Keep it headed.** Both servers are headed by default (chrome-devtools-mcp
  `--headless` "Default: `false`"; Playwright MCP "headed by default"), so the
  user can see the window. Never add `--headless` to a flow that may hit a
  login.
- **Verify, don't assume.** After the user reports done, take a FRESH snapshot
  and confirm the post-login state before continuing — a cached pre-login view
  is a common false positive (`@smith-validation`).
- **Know the session lifetime.** `--isolated` (required above) gives
  chrome-devtools-mcp a temporary user-data-dir "automatically cleaned up
  after the browser is closed" — the login survives only while that browser
  lives, so keep it open for the whole task. If the SAME login recurs across
  runs and that churn is the real cost, prefer Playwright MCP — its default
  recipe above stores login state in a persistent profile across runs. That
  profile is single-holder: "A persistent profile can only be used by one
  browser instance at a time, so concurrent MCP clients sharing the same
  workspace will conflict" — so for parallel sessions give each extra client
  `--isolated` or a distinct `--user-data-dir`, and accept that those lose the
  saved login. The Escape Hatch below is NOT the general answer to login
  churn: it applies only when you need the user's existing Vivaldi profile,
  and carries its own "may work but not guaranteed" caveat.

Sources: https://github.com/ChromeDevTools/chrome-devtools-mcp (`--headless`
default `false`; `--isolated` "creates a temporary user-data-dir that is
automatically cleaned up after the browser is closed") and
https://github.com/microsoft/playwright-mcp ("run browser in headless mode,
headed by default"; persistent profile stores login state and "can only be
used by one browser instance at a time") — both retrieved 2026-07-27.

## Escape Hatch: Vivaldi via `--browserUrl` (advanced)

If you need the user's Vivaldi profile (logged-in sessions, cookies), do **not** launch Vivaldi from MCP. Instead:

1. Manually start Vivaldi with a debugging port and a dedicated user-data-dir:
   ```shell
   /Applications/Vivaldi.app/Contents/MacOS/Vivaldi \
     --remote-debugging-port=9222 \
     --user-data-dir="$HOME/.vivaldi-mcp"
   ```
2. Configure chrome-devtools-mcp to attach instead of launch:
   ```json
   { "args": ["chrome-devtools-mcp@latest", "--browserUrl=http://127.0.0.1:9222"] }
   ```

Upstream calls this "may work but not guaranteed" (chrome-devtools-mcp README: *"Other Chromium-based browsers may work, but this is not guaranteed."*). Use only when the default cannot meet a real need.

## Why This Rule Exists

Incident history (2026-04 → 2026-05): Vivaldi launches via `--executablePath` repeatedly failed CDP handshake — profile contamination, GCM registration errors, 180s timeout. Upstream does not guarantee non-Chrome Chromium, and that alone is why the override is forbidden — the rule stands on what upstream supports, not on any one machine's browser policy.

Correction: this skill previously mandated Chrome for Testing and called
consumer Chrome unacceptable, while the recipes above set no `--channel` and
therefore resolved to stable Chrome all along. Chrome for Testing is not
installed here and no registration selects it. The same class of error ran
through the Playwright half: the skill called that server's default "bundled
Chromium" when upstream documents the default as Google Chrome. Both servers
land on the same stable-channel Chrome, and the rule now matches what the
recipes actually do.

Known gap, deliberately not closed here: a browser can also be selected by a
Playwright MCP environment variable (`PLAYWRIGHT_MCP_BROWSER`,
`PLAYWRIGHT_MCP_EXECUTABLE_PATH`, `PLAYWRIGHT_MCP_CONFIG`) or from a `--config`
file, and `~/.claude.json` holds per-project registrations outside the
top-level `mcpServers` this table names. The pre-flight above covers flags
only. Widening it is its own change.

## Related

- `@smith-playwright/SKILL.md` - Playwright test triage
- `@smith-tools/SKILL.md` - MCP server lifecycle
- `@smith-validation/SKILL.md` - Root cause analysis

## Before You Finish

**At session start (not just before first browser MCP call):**
1. Run `claude mcp list` — reject ANY browser-selecting flag on chrome-devtools-mcp or @playwright/mcp: `--executablePath`, `--executable-path`, `--channel`, or Playwright's `--browser`, in both `--flag value` and `--flag=value` forms. The correct state is no browser override at all
2. If a violation is found, locate it in one of the four MCP configuration locations (see table above) and remove the override; for user-scope CLI registrations use `claude mcp remove «name» -s user`. An entry that `claude mcp list` shows but none of the four files contains is plugin-installed: fix it at the plugin that registers it, then rerun `claude mcp list`
3. Confirm `--isolated` is set on chrome-devtools-mcp
4. Confirm Playwright MCP has no `--executable-path` and no `--browser` override

**On browser MCP failure:**
1. Match stderr against the failure signatures above
2. If Vivaldi/non-Chrome detected → recommend removing override + retry
3. If user requires Vivaldi profile → escape hatch via `--browserUrl`

**On a login wall:** navigate to the login URL → hand off in one message,
naming the page rather than echoing the URL → verify with a fresh snapshot.
Never type credentials; never call it blocked without opening the page.
