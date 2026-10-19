# smith-slack — sources

Dated evidence behind rules in `smith-slack/SKILL.md`. The skill file
states the rules; this document holds when and against what each was
checked.

## Standard Markdown input

- The `slack_send_message_draft` tool description ("standard markdown …
  >blockquotes"): read 2026-10-19.
- https://github.com/slackapi/slack-skills-plugin/blob/main/skills/slack-messaging/SKILL.md
  line 16, the message tools accept standard markdown: retrieved 2026-10-19.
- Lazy continuation: https://spec.commonmark.org/0.31.2/#block-quotes
  ("Laziness").
- A reply line right after a `> ` line rendered inside the quote in a
  draft: observed by the user 2026-10-16.
- Counter-evidence: https://github.com/slackapi/slack-skills-plugin/issues/121
  (open, observed 2026-08-17) recorded `> ` as plain text on the draft
  path; the 2026-10-16 observation shows a rendered quote, so the behavior
  changed or depends on content.

## Checking a draft

- The tool schema documents only `channel_link` as output, and no tool
  reads a draft back: tool description, read 2026-10-19;
  https://github.com/slackapi/slack-skills-plugin/issues/93.
