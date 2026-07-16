---
name: smith-slack
description: Slack message/reply drafting discipline — a hard pre-send checklist (draft-not-send, attribution footnote, evidence URLs, no formatting, confirm-before-send). Use when drafting or replying in Slack, invoking any slack_send_message* / slack_* MCP tool, or running a /slack:* command.
---

# Slack Drafting Discipline

**Scope:** Drafting and replying to Slack messages (portable rules)
**Load if:** Drafting/replying in Slack, any `slack_send_message*` / `slack_*`
MCP tool, or a `/slack:*` command
**Prerequisites:** @smith-principles/SKILL.md, @smith-standards/SKILL.md, @smith-guidance/SKILL.md, @smith-ctx/SKILL.md

These are repeat-corrected rules. They get forgotten because they live only in
project-local memory and never fire at draft time. This skill is the trigger.
Project-specific data (team `<@USERID>` table, channel policy, ticket language,
Opik project names) stays in the project's own memory — this skill references it,
never copies it.

## CRITICAL: Pre-Send Gate

**Verify ALL of these BEFORE any `slack_send_message_draft` call. Re-check on
every revision — a single miss is a repeat-correction.**

1. **Draft, never direct-send** — use `slack_send_message_draft` in place of
   `slack_send_message`. Route all communication through channels; drafting or
   sending a DM is off-limits (company policy).
2. **Attribution footnote is the LAST line** — every message body ends with the
   attribution footnote, which includes the `Assisted-by:` line (format in
   `@smith-style`; team-specific footnote parts stay in project memory). This is
   the single most repeat-corrected gate.
3. **Evidence URLs for every reference** — every PR / issue / ticket / Notion
   page / Opik trace is a clickable link, never a bare number (`#3453` alone is
   wrong). Pull a PR's exact title from `gh pr view «n» --json title` and
   hyperlink that exact title.
4. **No formatting** — plain prose with bare identifiers and paths only; no
   bold, italic, backticks, or code blocks. (Links and mentions below are NOT
   formatting and ARE required; the `> ` blockquote used to quote what you're
   replying to is NOT formatting either and IS required when quoting.)
5. **Confirm before send** — present the draft and wait for user confirmation.
   Draft means draft: do not consider it sent until the user says so.
6. **Outbound text stays clean** — keep internal metadata and scratch
   reasoning out of the message body.

## Links & Mentions (required, not "formatting")

- **Links**: Slack mrkdwn `<«url»|«display text»>` — never bare URLs, never
  markdown `[text](url)`.
- **Mentions**: `<@«USERID»>` (resolves + notifies). Use the resolving `<@USERID>`
  form always — display names like `@佐藤` don't notify. Use ONE consistent form
  for all addressees (canonical `<@«USERID»> さん` where a project memory sets it).

## Voice & Structure

- **Concise & fluent** — read like a colleague's note, not a memo. One short
  paragraph per ask; bullets only when genuinely enumerating parallel items.
- **No recap opener** — do not thank or restate what the recipient just did; they
  know. Do not repeat what the thread already says.
- **Quote what you reply to** — lead a reply with the exact passage in a `> `
  blockquote, then respond.
- **Thread vs top-level** — a follow-up on an existing topic defaults to a thread
  reply; before posting top-level, state why it should leave the thread.

## Gather Before Drafting

Have the full picture first — drafts without evidence get rejected:

1. Read the original thread via `slack_read_thread` (+ scan the last 24-72h of the
   likely channel); keyword search alone is insufficient.
2. Pull the source evidence: Notion pages, GitHub PRs/issues, Opik traces.
3. Verify any quote against the primary source, never a subagent summary or
   search excerpt.

## Before You Finish

**Before calling `slack_send_message_draft`, run the gate:**
1. draft tool (not send, not DM)
2. last line = attribution footnote (includes `Assisted-by:` line)
3. every reference = hyperlinked exact title / URL
4. zero bold/italic/backticks; links `<url|text>`, mentions `<@USERID>`
5. concise, fluent, quoted reply, no recap
6. show draft, wait for confirmation

## Related

- @smith-guidance/SKILL.md - Confirm-before-acting, evidence/citation discipline
- @smith-placeholder/SKILL.md - `«token»` placeholders (the `<url|text>` above is
  literal Slack mrkdwn, not a placeholder delimiter)
- Project memory holds team `<@USERID>` IDs, channel policy, ticket language
