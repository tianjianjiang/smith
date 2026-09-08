# smith-checkpoint token budget — Spec (the contract)

## §budget-is-a-guideline

**EARS (Easy Approach to Requirements Syntax)**: While drafting a checkpoint
body, the drafting agent shall treat ~400 tokens as a non-binding starting
aim, not a ceiling.

**GWT (Given-When-Then)**:
- Given a session with more durable content than fits in ~400 tokens
- When the agent drafts the checkpoint body
- Then the agent includes all durable content (decisions, file:line
  anchors, PR/commit references, open follow-ups) even if the body exceeds
  ~400 tokens

## §completeness-takes-precedence

**EARS**: If capturing all durable content would exceed the token
guideline, the system shall treat completeness as the binding requirement
and the token count as secondary.

**GWT**:
- Given a conflict between hitting the ~400-token aim and including a
  durable fact
- When the agent drafts the body
- Then the durable fact is kept and the token aim is exceeded

## §warning-stays-non-blocking

**EARS**: When a checkpoint body exceeds ~1600 bytes, the system shall
print an informational stderr message and shall not truncate, summarize,
or block the write.

**GWT**:
- Given a checkpoint body over 1600 bytes
- When `write-checkpoint.sh` runs `warn_if_body_exceeds_budget`
- Then a stderr note is printed and the full body is still written to both
  backends unmodified

## §durable-scoping-unchanged

**EARS**: The system shall continue to exclude transient chatter and
repo/git-recorded facts from the checkpoint body, unaffected by this
change.

**GWT**:
- Given the existing "Durable only" and "Use references, not content
  duplication" rules (`SKILL.md:18-23`, `SKILL.md:34-40`)
- When this fix is applied
- Then those rules remain textually unchanged and still govern what
  counts as checkpoint content
