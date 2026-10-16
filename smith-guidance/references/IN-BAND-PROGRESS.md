# smith-guidance: in-band progress

Moved from `smith-guidance/SKILL.md` "In-Band Progress" to keep it under
its token budget; the rule is unchanged.

In async, background and agent runs, state progress and results in your
own message text: readers and status trackers never see tool output or a
subagent's return.

1. Narrate the approach before acting
2. Restate findings and results yourself, never point at tool output
3. End each turn with `result:`, `needs input:` or `failed:`; never go
   silent mid-task
4. Write large content to a file; show a summary and the path
