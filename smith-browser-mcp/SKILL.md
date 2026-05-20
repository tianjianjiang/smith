---
name: smith-browser-mcp
description: Browser MCP plugin reliability for chrome-devtools-mcp and @playwright/mcp. Default to Chrome for Testing; Vivaldi/Edge/consumer-Chrome overrides are forbidden. Use when invoking chrome-devtools-mcp or Playwright MCP tools, editing .mcp.json / settings.json, or triaging browser MCP launch failures.
---

# Browser MCP Plugin Reliability

<metadata>

- **Scope**: chrome-devtools-mcp (`mcp__plugin_chrome-devtools-mcp_chrome-devtools__*`) and Playwright MCP (`mcp__plugin_playwright_playwright__*`)
- **Load if**: About to call any browser MCP tool, editing `.mcp.json` / `~/.claude/settings.json` for these plugins, or triaging a browser-launch failure
- **Prerequisites**: `@smith-tools/SKILL.md`

</metadata>

## CRITICAL: Browser Selection (Primacy Zone)

<forbidden>

- Setting `--executablePath` / `--executable-path` to `/Applications/Vivaldi.app/...`, any Brave / Arc / Opera / Edge / consumer-Chrome binary for `chrome-devtools-mcp`
- Pointing `@playwright/mcp` (`--browser` / `--executable-path`) at any non-bundled browser unless connecting via `--browserUrl` to a user-launched instance
- Reusing a Vivaldi user-data-dir (the one with `VivaldiDirectMatchIcons/`, Vivaldi extension `mpognobbkildjkofajifpdfhcoklimli`) for any MCP launch

</forbidden>

<required>

- **chrome-devtools-mcp**: omit `--executablePath`; let the package resolve **Chrome for Testing** automatically. CfT is Google's automation-only build, distinct from consumer Chrome — typically not flagged by corporate Jamf rules that block consumer Chrome / Edge.
- **chrome-devtools-mcp**: pass `--isolated` so every run gets a fresh user-data-dir. Avoids cross-run profile collisions.
- **Playwright MCP**: rely on Playwright's bundled Chromium (no `--executable-path` override).
- **Pre-flight** before the first browser MCP call in a session: read the active config (`~/.claude/settings.json`, `.mcp.json`, plus any per-project override) and confirm no Vivaldi/Edge/consumer-Chrome path is set. If one is found, recommend removing the override before proceeding.

</required>

## Failure Signatures → Diagnosis

<context>

Treat any of these in MCP stderr as a Vivaldi/non-Chrome misconfiguration:

- `/Applications/Vivaldi.app/Contents/MacOS/Vivaldi` in launch args — `--executablePath` is overridden to Vivaldi
- `VivaldiDirectMatchIcons/...` under the user-data-dir — Vivaldi-specific profile artifacts mixed with MCP profile
- Extension id `mpognobbkildjkofajifpdfhcoklimli` — Vivaldi internal extension loaded
- `gcm/engine/registration_request` errors — Vivaldi GCM registration failing in headless context
- `TimeoutError: async initializeServer: Timeout 180000ms exceeded` shortly after a Vivaldi launch — Vivaldi never finished CDP handshake
- Profile path `ms-playwright/mcp-chrome-*/Default/Vivaldi...` — MCP profile dir contaminated by Vivaldi resources

</context>

**Diagnosis**: in every case above, remove the `--executablePath` override from the offending MCP entry and re-run. For chrome-devtools-mcp also add `--isolated`.

## Recipe: chrome-devtools-mcp (default)

<context>

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

No `--executablePath`, no `--channel`. The package resolves Chrome for Testing on first use; subsequent runs reuse the cached binary.

Source: https://github.com/ChromeDevTools/chrome-devtools-mcp (README `--executablePath`, `--isolated`, `--channel` options).

</context>

## Recipe: Playwright MCP (default)

<context>

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

</context>

## Escape Hatch: Vivaldi via `--browserUrl` (advanced)

<context>

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

</context>

## Why This Rule Exists

<context>

Incident history (2026-04 → 2026-05): Vivaldi launches via `--executablePath` repeatedly failed CDP handshake — profile contamination, GCM registration errors, 180s timeout. Upstream does not guarantee non-Chrome Chromium. Consumer Chrome / Edge unacceptable per Jamf; Chrome for Testing is the supported alternative.

</context>

<related>

- `@smith-playwright/SKILL.md` - Playwright test triage
- `@smith-tools/SKILL.md` - MCP server lifecycle
- `@smith-validation/SKILL.md` - Root cause analysis

</related>

## ACTION (Recency Zone)

<required>

**Before first browser MCP call in a session:**
1. Read active MCP config; reject any non-CfT `--executablePath` for chrome-devtools-mcp
2. Confirm `--isolated` is set on chrome-devtools-mcp
3. Confirm Playwright MCP has no `--executable-path` override

**On browser MCP failure:**
1. Match stderr against the failure signatures above
2. If Vivaldi/non-Chrome detected → recommend removing override + retry
3. If user requires Vivaldi profile → escape hatch via `--browserUrl`

</required>
