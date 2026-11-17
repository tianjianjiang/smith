---
name: smith-mcp-browser
description: Browser MCP reliability (chrome-devtools-mcp, Playwright MCP). Use before calling any browser MCP tool, when choosing or changing the browser it drives, when a browser launch fails, or when a site needs a user login.
---

# Browser MCP Plugin Reliability

**Scope:** chrome-devtools-mcp (`mcp__plugin_chrome-devtools-mcp_chrome-devtools__*`) and Playwright MCP (`mcp__plugin_playwright_playwright__*`)
**Prerequisites:** `@smith-tools/SKILL.md`

## CRITICAL: Browser Selection

- **The operator picks the browser; this skill does not.** Before the first
  browser MCP call, read the operator's instructions (user rules,
  `CLAUDE.md`, project settings) for a browser choice, which may differ per
  profile or project. With no choice recorded, each server's default
  applies: Google Chrome's stable channel for both.
- **Playwright MCP** selects with `--browser` or the environment variable
  `PLAYWRIGHT_MCP_BROWSER`, values `chrome`, `msedge`, `firefox`, `webkit`.
  Precedence rises from config file to environment variable to command
  line, so a `--browser` flag beats the variable.
  - `chrome` and `msedge` drive the browser installed on the host.
  - `firefox` and `webkit` drive Playwright's own patched builds, not an
    installed app, and need the build matching the server version. Run
    `install-browser` with the package spec the server itself runs, such
    as `npx @playwright/mcp@latest install-browser firefox`.
  - A plugin-installed server has fixed `args`, so set the variable in the
    `env` block of `settings.json`; Claude Code writes those entries into
    its process environment, and a stdio server it spawns inherits that
    environment unless `CLAUDE_CODE_MCP_ALLOWLIST_ENV=1` limits it to a
    baseline plus the server's own `env`. A top-level `env` value reaches
    every MCP server and shell command of that profile, not only this
    one, and most project-scope `env` values apply only once the folder
    is trusted.
  - To attach to a Chromium browser the user launched, pass
    `--cdp-endpoint` or set `PLAYWRIGHT_MCP_CDP_ENDPOINT`; `--browserUrl`
    is chrome-devtools-mcp's spelling and not a Playwright MCP option.
- **chrome-devtools-mcp** "officially supports Google Chrome and Chrome for
  Testing only"; "Other Chromium-based browsers may work, but this is not
  guaranteed, and you may encounter unexpected behavior", and Firefox and
  WebKit are outside its support. When the chosen browser is neither Google
  Chrome nor Chrome for Testing, disable this server instead of pointing
  `--executablePath` at another browser. The one exception is
  the attach escape hatch below, written for Vivaldi, which the operator
  opts into for a Chromium browser they launched. When it runs, pass
  `--isolated` so each run gets a fresh,
  MCP-owned user-data-dir. The plugin-installed server has fixed `args`:
  set the flag through a route its configuration documentation gives, or
  register it by hand with the recipe below and disable the plugin.
- **A change applies only to a newly started server.** Do not assume
  `/reload-plugins` restarts a running MCP server; reconnect it with `/mcp`
  or start a new session, then confirm the launched browser process, not
  the configuration alone. `ps` prints full command lines, which can carry
  a token in an endpoint URL, so read that output before pasting it.
- **Pre-flight** at session start: compare the browser each server will
  launch with the operator's choice. Read the installed server's own
  `--help` and its configuration documentation, and check every option,
  variable and config file they list that picks a browser or attaches to
  one, including config files the server finds without being named, as
  chrome-devtools-mcp does per
  https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/configuration.md.
  The set changes between versions, so take it from those sources rather
  than from this skill. An unwanted selection and a missing one are both
  findings. Run `claude mcp list` first as the live view, locate each
  entry with the section below, then confirm the launched browser
  process: that check catches what the documentation misses.

## MCP Configuration Locations (Pre-flight Scope)

A browser selection can live in any of the four files below, in the
places listed after the table, or in a plugin that registers the
server. Registrations in `~/.claude.json` are the easiest to miss:

| # | Location | Set by | How to inspect |
| --- | --- | --- | --- |
| 1 | `~/.claude/settings.json#mcpServers` | hand-edit / `/config` | `jq '.mcpServers // {}\|map_values({type,command,args})' ~/.claude/settings.json` |
| 2 | Project `.mcp.json` | hand-edit | `jq '.mcpServers // {}\|map_values({type,command,args})' «project»/.mcp.json` |
| 3 | Project `.claude/settings.json#mcpServers` | hand-edit / `/config` | `jq '.mcpServers // {}\|map_values({type,command,args})' «project»/.claude/settings.json` |
| 4 | `~/.claude.json#mcpServers` | `claude mcp add … -s user` | `jq '.mcpServers // {}\|map_values({type,command,args})' ~/.claude.json` |
| — | live composite of 1–4, per-project entries and plugin-installed | — | `claude mcp list` |

Project only `type`, `command` and `args` as above. A bare `jq '.mcpServers'`
dumps `env` and `headers` too, which is where MCP servers keep API keys — and
in an agent session that output lands in the transcript. The projection
narrows the exposure without ending it: `args` can itself carry a token or a
credential-bearing URL, and `claude mcp list` prints those same values. Read
the output before pasting any of it. What this check needs is only the
browser-selecting and attach flags, so quoting those alone is always
enough; an attach endpoint can itself carry a token.

The server documentation also names places outside these files:
environment variables, which can sit in the top-level `env` of any
settings file in scope, in a registration's own `env`, or in the
environment Claude Code runs with; config files the server reads when
`--config` names one or that it finds by itself; and per-project
registrations under `.projects["«project path»"].mcpServers` in
`~/.claude.json`, keyed by the folder Claude Code was started in. List
names before reading any value, because an endpoint can carry a token,
then read values only for the keys that pick a browser. For example, to
list the Playwright MCP variable names in a settings file, then the
`env` names of each registration in a file from the table:

```shell
jq '.env // {} | keys | map(select(startswith("PLAYWRIGHT_MCP_")))' «settings file»
```

```shell
jq '.mcpServers // {} | map_values(.env // {} | keys)' «file»
```

`claude mcp list` is authoritative for registrations — it shows every
server currently registered across scopes, including plugin-installed
servers — but not for selections made through `env` or a config file.
The file-by-file checks
tell you WHERE to apply the fix once a mismatch is found; the fix may
remove a selection or add one. An entry that `claude mcp list` shows but
neither the four files nor the per-project entries contain is
plugin-installed: change its selection
through the `env` block or at the plugin that registers it, then confirm
the launched browser process.

To remove a user-scope CLI registration: `claude mcp remove «name» -s user`.

**Tool-namespace divergence by install path**: the SAME browser server exposes
different tool names depending on how it was added — plugin-installed gives
`mcp__plugin_«plugin»_«server»__*`; `claude mcp add -s user` gives
`mcp__«name»__*`. The two can also carry DIFFERENT launch arguments (one
bare, one with an explicit `--browser` or `--channel`), so confirm which
registration is live (`claude mcp list`) before assuming a browser variant.

## Failure Signatures → Diagnosis

Treat any of these in MCP stderr as a Vivaldi or other unsupported
executable-path misconfiguration. Chrome DevTools Protocol (CDP) and
Google Cloud Messaging (GCM) appear in some of them.

- `/Applications/Vivaldi.app/Contents/MacOS/Vivaldi` in launch args — `--executablePath` is overridden to Vivaldi
- `VivaldiDirectMatchIcons/...` under the user-data-dir — Vivaldi-specific profile artifacts mixed with MCP profile
- Extension id `mpognobbkildjkofajifpdfhcoklimli` — Vivaldi internal extension loaded
- `gcm/engine/registration_request` errors — Vivaldi GCM registration failing in headless context
- `TimeoutError: async initializeServer: Timeout 180000ms exceeded` shortly after a Vivaldi launch — Vivaldi never finished CDP handshake
- Profile path `ms-playwright/mcp-chrome-*/Default/Vivaldi...` — MCP profile dir contaminated by Vivaldi resources

**Diagnosis**: in every case above, remove the executable-path override
from the offending MCP entry, spelled `--executablePath`,
`--executable-path` or `PLAYWRIGHT_MCP_EXECUTABLE_PATH`, then follow the
operator's choice: select it through the server's documented option where
the server supports it, or disable chrome-devtools-mcp where it does not.
When chrome-devtools-mcp stays, also add `--isolated`.

A missing Playwright build has its own signature:

- `is not installed; expected executable at
  .../ms-playwright/firefox-«build»/...` — the server version expects a
  build the cache lacks; run `install-browser` for that browser as above

## Recipe: chrome-devtools-mcp (Google Chrome)

Register it in a project `.mcp.json`:

```json
{
  "mcpServers": {
    "chrome-devtools": {
      "type": "stdio",
      "command": "npx",
      "args": ["chrome-devtools-mcp@latest", "--isolated"]
    }
  }
}
```

Or for every project:

```shell
claude mcp add -s user chrome-devtools -- npx chrome-devtools-mcp@latest --isolated
```

No `--executablePath`, no `--channel`: this resolves to Chrome's stable
channel. To turn the plugin-installed server off, set its key, as
`enabledPlugins` lists it, to `false` in the `settings.json` of the scope
that enabled it. The key is `chrome-devtools-mcp@«marketplace»`, for
example `"chrome-devtools-mcp@claude-plugins-official": false`.

Sources: https://github.com/ChromeDevTools/chrome-devtools-mcp (README:
"officially supports Google Chrome and Chrome for Testing only") and
https://developer.chrome.com/docs/devtools/agents/get-started/configuration
(`--channel` defaults to `stable`).

## Recipe: Playwright MCP

For the plugin-installed server, select the browser in `settings.json`.
A top-level `env` value reaches every MCP server and shell command of
that profile:

```json
{
  "env": {
    "PLAYWRIGHT_MCP_BROWSER": "firefox"
  }
}
```

For a server registered by hand in a project `.mcp.json`, pass the flag
instead:

```json
{
  "mcpServers": {
    "playwright": {
      "type": "stdio",
      "command": "npx",
      "args": ["@playwright/mcp@latest", "--browser", "msedge"]
    }
  }
}
```

With no selection anywhere, Playwright MCP takes Google Chrome's stable
channel, not its bundled Chromium.

Sources: https://playwright.dev/mcp/configuration/options (`--browser`
values and the environment variables),
https://code.claude.com/docs/en/settings (the `env` block),
https://code.claude.com/docs/en/env-vars ("Claude Code writes each env
entry into the process environment"), and
https://github.com/microsoft/playwright-mcp/blob/main/cli.js, which maps
the `install-browser` subcommand onto Playwright's browser install.

## Interactive Login: Hand Off, Don't Guess

When a page needs interactive authentication (login wall, single sign-on
(SSO) redirect, multi-factor authentication (MFA) prompt, captcha), the
browser is already the right tool — hand the keyboard over instead of asking
abstractly or abandoning the task.

- **Navigate first, then hand off.** Drive the Model Context Protocol (MCP)
  browser to the exact login URL, then say in ONE message: the window is open
  on «page name», complete the login there, reply once it is done. Never
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
  runs and that churn is the real cost, prefer Playwright MCP — without
  its own `--isolated` it stores login state in a persistent profile across
  runs. The profile is kept per browser channel and workspace
  (`mcp-«channel»-«workspace hash»`), so switching
  browsers or workspaces starts logged out. That
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
used by one browser instance at a time").

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

Upstream calls this "may work but not guaranteed" (chrome-devtools-mcp README:
*"Other Chromium-based browsers may work, but this is not guaranteed, and you
may encounter unexpected behavior"*). Use it only when the operator opts in
because a real need, such as an existing logged-in profile, cannot be met
by a browser the server supports.

## Why This Rule Exists

A server left on its default while the operator chose another browser
drives the wrong one, and a browser forced through an executable path that
upstream does not support can fail the Chrome DevTools Protocol (CDP)
handshake: profile contamination, Google Cloud Messaging (GCM)
registration errors, a 180s timeout. Selecting through
each server's documented option, and checking the launched process, keeps
the choice with the operator and the launch on a supported path.

## Related

- `@smith-playwright/SKILL.md` - Playwright test triage
- `@smith-tools/SKILL.md` - MCP server lifecycle
- `@smith-validation/SKILL.md` - Root cause analysis

## Before You Finish

**At session start (not just before first browser MCP call):**
1. Read the operator's browser choice; with none recorded, each server's
   default applies
2. Run `claude mcp list`, then check every place the server's `--help`
   and configuration documentation name, and compare each with that
   choice; fix a mismatch where it lives: a registration from the table
   or a per-project entry, a settings `env` block, a config file, or the
   plugin that registers the server
3. Disable chrome-devtools-mcp when the choice is neither Google Chrome
   nor Chrome for Testing, unless the operator opted into the attach
   escape hatch; otherwise confirm `--isolated`
4. After any change, reconnect the server and confirm the launched
   browser process

**On browser MCP failure:**
1. Match stderr against the failure signatures above
2. An executable path pointed at Vivaldi or another unsupported
   browser → remove that override, select a supported browser
   through the server's documented option, retry
3. Missing Playwright build → `install-browser` for that browser
4. User requires the Vivaldi profile → escape hatch via `--browserUrl`

**On a login wall:** navigate to the login URL → hand off in one message,
naming the page rather than echoing the URL → verify with a fresh snapshot.
Never type credentials; never call it blocked without opening the page.
