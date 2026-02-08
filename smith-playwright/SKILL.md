---
name: smith-playwright
description: Playwright testing patterns including proactive failure monitoring, artifact inspection, and root cause classification. Use when running Playwright tests or analyzing Playwright test results.
---

# Playwright Testing Standards

<metadata>

- **Load if**: Running Playwright tests, analyzing test results
- **Prerequisites**: `@smith-tests/SKILL.md`

</metadata>

## CRITICAL: Proactive Failure Monitoring (Primacy Zone)

<required>

- MUST check test runner exit code after every run
- MUST inspect failure artifacts before reporting
- MUST read actual error messages (not just "tests failed")
- MUST classify root cause before reporting to user
- MUST proactively detect and report -- do NOT wait for user

</required>

<forbidden>

- NEVER report "tests failed" without reading error messages
- NEVER assume tests passed without verifying exit code
- NEVER skip failure artifact inspection after a run

</forbidden>

## Failure Analysis Protocol

<required>

**After every Playwright test run:**

1. **Check exit code** -- non-zero means failures exist
2. **Inspect failure artifacts** -- Playwright creates per-test
   subdirectories containing page snapshots and screenshots
3. **Read page snapshots** for DOM state at failure time
4. **Read screenshots** for visual confirmation
5. **Open HTML report** for assertion error details
6. **Classify root cause** (see categories below)
7. **Report** with: failed tests, classification, evidence

</required>

## Root Cause Categories

<context>

- **Selector mismatch**: test expects elements or classes
  not present in current component implementation
- **Timing/flakiness**: polling timeout too short,
  race conditions between UI and async operations
- **Backend/dependency**: API or SSE response format changed,
  upstream service unavailable or returning errors
- **Environment**: services not running, auth expired,
  port conflicts, missing configuration
- **Test data/state**: database not seeded, stale
  fixtures, previous test side effects

</context>

## Playwright MCP Tools

<context>

When Playwright MCP plugin (`mcp__plugin_playwright_playwright`)
is available, use it to inspect HTML reports programmatically:

**Tool discovery**: Use ToolSearch with `+playwright` to load
tools before first use.

**Key tools for report inspection:**
- `browser_navigate` -- open report URL
- `browser_snapshot` -- read page as accessibility tree
  (preferred over screenshot for extracting text)
- `browser_click` -- expand failed test details
- `browser_take_screenshot` -- visual capture if needed
- `browser_run_code` -- run JS for complex extraction

**Report inspection workflow:**
1. Start report server (project AGENTS.md has the command)
2. `browser_navigate` to report URL
3. `browser_snapshot` to read test result list
4. `browser_click` on failed tests to expand error details
5. `browser_snapshot` again to read assertion messages

</context>

<related>

- `@smith-tests/SKILL.md` - Testing standards, TDD workflow
- `@smith-validation/SKILL.md` - Root cause analysis
- `@smith-nuxt/SKILL.md` - Nuxt testing patterns

</related>

## ACTION (Recency Zone)

<required>

**Post-test checklist:**
1. Exit code non-zero? Read failure artifacts
2. Read page snapshots + screenshots
3. Classify root cause
4. Report proactively with evidence

</required>
