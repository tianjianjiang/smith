---
name: smith-browser_mcp
description: Browser MCP plugin reliability for chrome-devtools-mcp and @playwright/mcp. Default to Chrome for Testing; Vivaldi/Edge/consumer-Chrome overrides are forbidden. Use when invoking chrome-devtools-mcp or Playwright MCP tools, editing .mcp.json / settings.json, or triaging browser MCP launch failures.
---

# Browser MCP Plugin Reliability

**Scope:** chrome-devtools-mcp (`mcp__plugin_chrome-devtools-mcp_chrome-devtools__*`) and Playwright MCP (`mcp__plugin_playwright_playwright__*`)
**Load if:** About to call any browser MCP tool, editing `.mcp.json` / `~/.claude/settings.json` for these plugins, or triaging a browser-launch failure
**Prerequisites:** `@smith-tools/SKILL.md`

## CRITICAL: Browser Selection

- **chrome-devtools-mcp**: omit `--executablePath` (and `--channel`, which
  defaults to `stable`), rather than pointing it at
  `/Applications/Vivaldi.app/...` or any Brave / Arc / Opera / Edge /
  consumer-Chrome binary. Upstream states it "officially supports Google
  Chrome and Chrome for Testing only" — Chrome for Testing is Google's
  automation-only build, distinct from consumer Chrome — typically not
  flagged by corporate Jamf rules that block consumer Chrome / Edge.
- **chrome-devtools-mcp**: pass `--isolated` so every run gets a fresh, MCP-owned user-data-dir, rather than reusing a Vivaldi user-data-dir (the one with `VivaldiDirectMatchIcons/`, Vivaldi extension `mpognobbkildjkofajifpdfhcoklimli`). Avoids cross-run profile collisions.
- **Playwright MCP**: rely on Playwright's bundled Chromium (no `--browser` / `--executable-path` override), or attach to a user-launched instance via `--browserUrl` — not at other non-bundled browsers.
- **Pre-flight** at session start (not just before the first MCP call): inspect all four MCP configuration locations (see "MCP Configuration Locations" below) and confirm no Vivaldi/Edge/consumer-Chrome `--executablePath` / `--executable-path` is set on `chrome-devtools-mcp` or `@playwright/mcp`. Run `claude mcp list` first as the authoritative live view; then locate the offending entry by file via the table when a violation is found.

## MCP Configuration Locations (Pre-flight Scope)

The Vivaldi / non-Chrome override can live in any of four places. The
2026-05-21 recurrence was a pair of `*-cft` registrations in `~/.claude.json`
that the previous (settings.json + .mcp.json only) preflight rule never
mentioned. Check all four:

| # | Location | Set by | How to inspect |
| --- | --- | --- | --- |
| 1 | `~/.claude/settings.json#mcpServers` | hand-edit / `/config` | `jq '.mcpServers' ~/.claude/settings.json` |
| 2 | Project `.mcp.json` | hand-edit | `jq '.mcpServers' «project»/.mcp.json` |
| 3 | Project `.claude/settings.json#mcpServers` | hand-edit / `/config` | `jq '.mcpServers' «project»/.claude/settings.json` |
| 4 | `~/.claude.json#mcpServers` | `claude mcp add … -s user` | `jq '.mcpServers' ~/.claude.json` |
| — | live composite of 1–4 + plugin-installed | — | `claude mcp list` |

`claude mcp list` is authoritative — it shows everything currently registered
across scopes, including plugin-installed servers. The file-by-file checks
tell you WHERE to apply the fix once a violation is found (e.g. an entry
showing up in `claude mcp list` but absent from #1–#3 is in #4).

To remove a user-scope CLI registration: `claude mcp remove «name» -s user`.

**Tool-namespace divergence by install path**: the SAME browser server exposes
different tool names depending on how it was added — plugin-installed gives
`mcp__plugin_«plugin»_«server»__*`; `claude mcp add -s user` gives
`mcp__«name»-cft__*`. The two can also carry DIFFERENT launch defaults (e.g.
Chrome for Testing vs bundled Chromium), so confirm which registration is live
(`claude mcp list`) before assuming a browser variant.

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

No `--executablePath`, no `--channel` — this defaults to the stable
channel, one of the two browsers upstream officially supports (Google
Chrome or Chrome for Testing).

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

No overrides — bundled Chromium handles all flows. Source: https://github.com/microsoft/playwright-mcp .

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

Upstream calls this "may work but not guaranteed" (chrome-devtools-mcp README: *"Other Chromium-based browsers may work, but this is not guaranteed."*). Use only when the CfT default cannot meet a real need.

## Why This Rule Exists

Incident history (2026-04 → 2026-05): Vivaldi launches via `--executablePath` repeatedly failed CDP handshake — profile contamination, GCM registration errors, 180s timeout. Upstream does not guarantee non-Chrome Chromium. Consumer Chrome / Edge unacceptable per Jamf; Chrome for Testing is the supported alternative.

## Related

- `@smith-playwright/SKILL.md` - Playwright test triage
- `@smith-tools/SKILL.md` - MCP server lifecycle
- `@smith-validation/SKILL.md` - Root cause analysis

## Before You Finish

**At session start (not just before first browser MCP call):**
1. Run `claude mcp list` — reject any non-CfT `--executablePath` / `--executable-path` on chrome-devtools-mcp or @playwright/mcp
2. If a violation is found, locate it in one of the four MCP configuration locations (see table above) and remove the override; for user-scope CLI registrations use `claude mcp remove «name» -s user`
3. Confirm `--isolated` is set on chrome-devtools-mcp
4. Confirm Playwright MCP has no `--executable-path` override

**On browser MCP failure:**
1. Match stderr against the failure signatures above
2. If Vivaldi/non-Chrome detected → recommend removing override + retry
3. If user requires Vivaldi profile → escape hatch via `--browserUrl`
